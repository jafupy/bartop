import Foundation
import SystemMetrics

struct ProcessRow: Identifiable {
    let id: Int32
    let name: String
    let cpu: Double
    let memory: UInt64
    var gpu: Double?
    var parentPID: Int32 = 0
    var applicationPath: String?
    var applicationName: String?
}

struct Metrics {
    var cpu = 0.0
    var gpu: Double?
    var cores: [Double] = []
    var coreTemperatures: [Double?] = []
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var compressed: UInt64 = 0
    var swap: UInt64 = 0
    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var download = 0.0
    var upload = 0.0
    var chip = "Reading system…"
    var processes: [ProcessRow] = []
    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
}

func cString<T>(_ value: T) -> String {
    withUnsafeBytes(of: value) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
}

func bytes(_ value: Double) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var number = max(0, value)
    var unit = 0
    while number >= 1000 && unit < units.count - 1 { number /= 1000; unit += 1 }
    return String(format: number < 10 && unit > 0 ? "%.1f %@" : "%.0f %@", number, units[unit])
}

// Owned by a serial queue. CPU and traffic rates use actual elapsed time.
final class Sampler {
    private var previousCores: [CoreTicks] = []
    private var previousProcesses: [Int32: ProcessSample] = [:]
    private var previousProcessGPU: [UInt64: ProcessGPUSample] = [:]
    private var previousNetwork: [String: NetworkSample] = [:]
    private var previousTime: TimeInterval?
    private var previousProcessTime: TimeInterval?
    private var applicationNames: [String: String] = [:]

    func read(includeProcesses: Bool) -> Metrics {
        var machine = read_machine()
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { max(now - $0, 0.001) } ?? 1
        var result = Metrics()
        let cores = withUnsafePointer(to: &machine.cores) {
            $0.withMemoryRebound(to: CoreTicks.self, capacity: 128) {
                Array(UnsafeBufferPointer(start: $0, count: Int(machine.core_count)))
            }
        }
        var totalBusy = 0.0
        var totalTicks = 0.0
        result.cores = cores.enumerated().map { index, core in
            guard index < previousCores.count else { return 0 }
            let previous = previousCores[index]
            let busy = Double(core.user &- previous.user) + Double(core.system &- previous.system)
                + Double(core.nice &- previous.nice)
            let total = busy + Double(core.idle &- previous.idle)
            totalBusy += busy
            totalTicks += total
            return total > 0 ? busy / total * 100 : 0
        }
        result.cpu = totalTicks > 0 ? totalBusy / totalTicks * 100 : 0
        result.coreTemperatures = readCoreTemperatures(coreCount: result.cores.count)
        result.gpu = machine.gpu_percent >= 0 ? min(100, machine.gpu_percent) : nil
        result.memoryTotal = machine.memory_total
        result.memoryUsed = min(machine.memory_used, machine.memory_total)
        result.compressed = machine.memory_compressed
        result.swap = machine.swap_used
        result.chip = cString(machine.chip)
        if let disk = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = disk[.systemSize] as? NSNumber, let free = disk[.systemFreeSize] as? NSNumber {
            result.diskTotal = total.uint64Value
            result.diskUsed = total.uint64Value - min(free.uint64Value, total.uint64Value)
        }
        var network = [NetworkSample](repeating: NetworkSample(), count: 64)
        let networkCount = read_network(&network, Int32(network.count))
        var currentNetwork: [String: NetworkSample] = [:]
        for sample in network.prefix(Int(networkCount)) {
            let name = cString(sample.name)
            currentNetwork[name] = sample
            if let old = previousNetwork[name] {
                // Skip an interface's reset counters rather than displaying a spike.
                if sample.received >= old.received {
                    result.download += Double(sample.received - old.received) / elapsed
                }
                if sample.sent >= old.sent {
                    result.upload += Double(sample.sent - old.sent) / elapsed
                }
            }
        }
        if includeProcesses {
            var processes = [ProcessSample](repeating: ProcessSample(), count: 8192)
            let count = read_processes(&processes, Int32(processes.count))
            let processElapsed = previousProcessTime.map { max(now - $0, 0.001) } ?? 1
            var current: [Int32: ProcessSample] = [:]
            for process in processes.prefix(Int(count)) { current[process.pid] = process }
            var clients = [ProcessGPUSample](repeating: ProcessGPUSample(), count: 8192)
            let clientCount = read_process_gpu(&clients, Int32(clients.count))
            var currentGPU: [UInt64: ProcessGPUSample] = [:]
            for client in clients.prefix(Int(clientCount)) { currentGPU[client.client_id] = client }
            var gpuByPID: [Int32: Double] = [:]
            // Keep client identities: closing a Metal client must not reset the whole process's counter.
            for client in currentGPU.values {
                if let old = previousProcessGPU[client.client_id], old.pid == client.pid,
                   client.gpu_nanoseconds >= old.gpu_nanoseconds {
                    gpuByPID[client.pid, default: 0] += Double(client.gpu_nanoseconds - old.gpu_nanoseconds)
                        / (processElapsed * 1e9) * 100
                }
            }
            for process in processes.prefix(Int(count)) {
                var cpu = 0.0
                var gpu: Double?
                if let old = previousProcesses[process.pid],
                   old.started_seconds == process.started_seconds,
                   old.started_microseconds == process.started_microseconds,
                   process.cpu_nanoseconds >= old.cpu_nanoseconds {
                    cpu = Double(process.cpu_nanoseconds - old.cpu_nanoseconds) / (processElapsed * 1e9) * 100
                    gpu = gpuByPID[process.pid]
                }
                let app = application(for: process, processes: current)
                result.processes.append(ProcessRow(id: process.pid, name: cString(process.name),
                                                  cpu: cpu, memory: process.resident_bytes,
                                                  gpu: gpu,
                                                  parentPID: process.parent_pid,
                                                  applicationPath: app?.path, applicationName: app?.name))
            }
            previousProcesses = current
            previousProcessGPU = currentGPU
            previousProcessTime = now
        } else {
            previousProcesses.removeAll()
            previousProcessGPU.removeAll()
            previousProcessTime = nil
        }
        previousCores = cores
        previousNetwork = currentNetwork
        previousTime = now
        return result
    }

    private func application(for process: ProcessSample, processes: [Int32: ProcessSample]) -> (path: String, name: String)? {
        var candidate = process
        for _ in 0..<32 {
            let path = cString(candidate.app_path)
            if !path.isEmpty {
                let name: String
                if let cached = applicationNames[path] {
                    name = cached
                } else {
                    let bundle = Bundle(path: path)
                    name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    applicationNames[path] = name
                }
                return (path, name)
            }
            guard candidate.parent_pid > 1, candidate.parent_pid != candidate.pid,
                  let parent = processes[candidate.parent_pid] else { break }
            candidate = parent
        }
        return nil
    }
}
