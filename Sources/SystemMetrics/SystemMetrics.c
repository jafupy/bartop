#include "SystemMetrics.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <libproc.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/route.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static double gpu_usage(void) {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                    IOServiceMatching("IOAccelerator"), &iterator) != KERN_SUCCESS)
        return -1;
    double usage = -1;
    io_object_t device;
    while ((device = IOIteratorNext(iterator))) {
        CFTypeRef stats = IORegistryEntryCreateCFProperty(device, CFSTR("PerformanceStatistics"),
                                                         kCFAllocatorDefault, 0);
        if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
            CFTypeRef value = CFDictionaryGetValue(stats, CFSTR("Device Utilization %"));
            double current;
            if (value && CFGetTypeID(value) == CFNumberGetTypeID() &&
                CFNumberGetValue(value, kCFNumberDoubleType, &current) && current > usage)
                usage = current;
        }
        if (stats) CFRelease(stats);
        IOObjectRelease(device);
    }
    IOObjectRelease(iterator);
    return usage;
}

MachineSample read_machine(void) {
    MachineSample result = {0};
    host_t host = mach_host_self();
    natural_t count = 0;
    processor_info_array_t info;
    mach_msg_type_number_t info_count;
    if (host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &info_count) == KERN_SUCCESS) {
        result.core_count = count < 128 ? count : 128;
        for (int i = 0; i < result.core_count; i++) {
            int offset = i * CPU_STATE_MAX;
            result.cores[i] = (CoreTicks){info[offset + CPU_STATE_USER],
                info[offset + CPU_STATE_SYSTEM], info[offset + CPU_STATE_NICE], info[offset + CPU_STATE_IDLE]};
        }
        vm_deallocate(mach_task_self(), (vm_address_t)info, info_count * sizeof(integer_t));
    }
    size_t size = sizeof(result.memory_total);
    sysctlbyname("hw.memsize", &result.memory_total, &size, NULL, 0);
    vm_statistics64_data_t vm = {0};
    mach_msg_type_number_t vm_count = HOST_VM_INFO64_COUNT;
    vm_size_t page_size = 0;
    host_page_size(host, &page_size);
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &vm_count) == KERN_SUCCESS) {
        result.memory_compressed = (uint64_t)vm.compressor_page_count * page_size;
        // Active, wired and compressed pages; inactive pages are reclaimable.
        result.memory_used = ((uint64_t)vm.active_count + vm.wire_count + vm.compressor_page_count) * page_size;
    }
    mach_port_deallocate(mach_task_self(), host);
    struct xsw_usage swap = {0};
    size = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0) result.swap_used = swap.xsu_used;
    size = sizeof(result.chip);
    if (sysctlbyname("machdep.cpu.brand_string", result.chip, &size, NULL, 0) != 0) {
        size = sizeof(result.chip);
        sysctlbyname("hw.model", result.chip, &size, NULL, 0);
    }
    result.gpu_percent = gpu_usage();
    return result;
}

int read_processes(ProcessSample *output, int capacity) {
    mach_timebase_info_data_t timebase = {1, 1};
    mach_timebase_info(&timebase);
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return 0;
    int pid_capacity = count + 256;
    pid_t *pids = calloc(pid_capacity, sizeof(pid_t));
    if (!pids) return 0;
    count = proc_listallpids(pids, pid_capacity * sizeof(pid_t));
    if (count > pid_capacity) count = pid_capacity;
    int written = 0;
    for (int i = 0; i < count && written < capacity; i++) {
        struct proc_taskinfo task;
        struct proc_bsdinfo bsd;
        if (pids[i] <= 0 || proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &task, sizeof(task)) != sizeof(task)) continue;
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) continue;
        ProcessSample *sample = &output[written++];
        memset(sample, 0, sizeof(*sample));
        sample->pid = pids[i];
        sample->parent_pid = bsd.pbi_ppid;
        // libproc reports Mach ticks, which are not nanoseconds on Apple Silicon.
        sample->cpu_nanoseconds = (uint64_t)((long double)(task.pti_total_user + task.pti_total_system)
                                            * timebase.numer / timebase.denom);
        sample->resident_bytes = task.pti_resident_size;
        sample->started_seconds = bsd.pbi_start_tvsec;
        sample->started_microseconds = bsd.pbi_start_tvusec;
        proc_name(pids[i], sample->name, sizeof(sample->name));
        char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
        if (proc_pidpath(pids[i], path, sizeof(path)) > 0) {
            // The outer app owns nested helper bundles (Chrome, Codex, etc.).
            char *app_end = strstr(path, ".app/");
            if (app_end) {
                app_end[4] = '\0';
                strlcpy(sample->app_path, path, sizeof(sample->app_path));
            }
        }
    }
    free(pids);
    return written;
}

// Driver-private cumulative GPU nanoseconds, attributed to each accelerator client.
// Missing AppUsage counters remain unavailable rather than inventing an idle reading.
int read_process_gpu(ProcessGPUSample *output, int capacity) {
    io_iterator_t devices = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                    IOServiceMatching("IOAccelerator"), &devices) != KERN_SUCCESS)
        return 0;
    int written = 0;
    io_object_t device;
    while ((device = IOIteratorNext(devices))) {
        io_iterator_t clients = 0;
        if (IORegistryEntryCreateIterator(device, kIOServicePlane, kIORegistryIterateRecursively,
                                          &clients) == KERN_SUCCESS) {
            io_object_t client;
            while ((client = IOIteratorNext(clients))) {
                CFMutableDictionaryRef properties = NULL;
                if (written < capacity && IORegistryEntryCreateCFProperties(client, &properties,
                                                                            kCFAllocatorDefault, 0) == KERN_SUCCESS) {
                    CFTypeRef creator = CFDictionaryGetValue(properties, CFSTR("IOUserClientCreator"));
                    CFTypeRef usage = CFDictionaryGetValue(properties, CFSTR("AppUsage"));
                    char owner[256];
                    int pid;
                    uint64_t client_id;
                    if (creator && CFGetTypeID(creator) == CFStringGetTypeID()
                        && CFStringGetCString(creator, owner, sizeof(owner), kCFStringEncodingUTF8)
                        && sscanf(owner, "pid %d,", &pid) == 1 && pid > 0
                        && usage && CFGetTypeID(usage) == CFArrayGetTypeID()
                        && IORegistryEntryGetRegistryEntryID(client, &client_id) == KERN_SUCCESS) {
                        uint64_t total = 0;
                        int counters = 0;
                        for (CFIndex i = 0; i < CFArrayGetCount(usage); i++) {
                            CFTypeRef entry = CFArrayGetValueAtIndex(usage, i);
                            if (CFGetTypeID(entry) != CFDictionaryGetTypeID()) continue;
                            CFTypeRef value = CFDictionaryGetValue(entry, CFSTR("accumulatedGPUTime"));
                            int64_t nanoseconds;
                            if (value && CFGetTypeID(value) == CFNumberGetTypeID()
                                && CFNumberGetValue(value, kCFNumberSInt64Type, &nanoseconds) && nanoseconds >= 0) {
                                total += (uint64_t)nanoseconds;
                                counters++;
                            }
                        }
                        if (counters) output[written++] = (ProcessGPUSample){client_id, total, pid};
                    }
                    CFRelease(properties);
                }
                IOObjectRelease(client);
            }
            IOObjectRelease(clients);
        }
        IOObjectRelease(device);
    }
    IOObjectRelease(devices);
    return written;
}

int read_network(NetworkSample *output, int capacity) {
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t size = 0;
    if (sysctl(mib, 6, NULL, &size, NULL, 0) != 0 || size == 0) return 0;
    char *buffer = malloc(size);
    if (!buffer) return 0;
    if (sysctl(mib, 6, buffer, &size, NULL, 0) != 0) { free(buffer); return 0; }
    int count = 0;
    for (char *cursor = buffer; cursor < buffer + size && count < capacity;) {
        struct if_msghdr *message = (struct if_msghdr *)cursor;
        if (message->ifm_msglen == 0 || cursor + message->ifm_msglen > buffer + size) break;
        cursor += message->ifm_msglen;
        if (message->ifm_type != RTM_IFINFO2 || !(message->ifm_flags & IFF_UP)) continue;
        char name[IF_NAMESIZE];
        if (!if_indextoname(message->ifm_index, name)) continue;
        // Physical Ethernet/Wi-Fi interfaces avoid counting VPN traffic twice.
        if (strncmp(name, "en", 2) != 0) continue;
        struct if_msghdr2 *info = (struct if_msghdr2 *)message;
        NetworkSample *sample = &output[count++];
        memset(sample, 0, sizeof(*sample));
        strlcpy(sample->name, name, sizeof(sample->name));
        sample->received = info->ifm_data.ifi_ibytes;
        sample->sent = info->ifm_data.ifi_obytes;
    }
    free(buffer);
    return count;
}
