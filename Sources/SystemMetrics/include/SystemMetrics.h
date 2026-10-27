#pragma once
#include <stdint.h>

typedef struct {
    uint32_t user, system, nice, idle;
} CoreTicks;

typedef struct {
    int core_count;
    CoreTicks cores[128];
    uint64_t memory_total, memory_used, memory_compressed, swap_used;
    double gpu_percent; // -1 when the driver does not expose a counter.
    char chip[128];
} MachineSample;

typedef struct {
    int pid;
    int parent_pid;
    uint64_t cpu_nanoseconds, resident_bytes, started_seconds, started_microseconds;
    char name[128];
    char app_path[1024];
} ProcessSample;

typedef struct {
    uint64_t client_id, gpu_nanoseconds;
    int pid;
} ProcessGPUSample;

typedef struct {
    char name[32];
    uint64_t received, sent;
} NetworkSample;

MachineSample read_machine(void);
int read_processes(ProcessSample *output, int capacity);
int read_process_gpu(ProcessGPUSample *output, int capacity);
int read_network(NetworkSample *output, int capacity);
