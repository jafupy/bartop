import AppKit
import Foundation

if let index = CommandLine.arguments.firstIndex(of: "--render"), index + 1 < CommandLine.arguments.count {
    do {
        try renderPreview(directory: CommandLine.arguments[index + 1])
    } catch {
        fputs("Render failed: \(error)\n", stderr)
        exit(1)
    }
} else if CommandLine.arguments.contains("--sample") {
    let sampler = Sampler()
    _ = sampler.read(includeProcesses: true)
    Thread.sleep(forTimeInterval: 1)
    let sample = sampler.read(includeProcesses: true)
    print(String(format: "CPU: %.1f%%", sample.cpu))
    print("GPU: \(sample.gpu.map { String(format: "%.1f%%", $0) } ?? "unavailable")")
    print("Chip: \(sample.chip) · \(sample.cores.count) cores")
    print("Memory: \(bytes(Double(sample.memoryUsed))) / \(bytes(Double(sample.memoryTotal)))")
    print("Network: ↓ \(bytes(sample.download))/s · ↑ \(bytes(sample.upload))/s")
    print("Processes: \(sample.processes.count)")
    for process in sample.processes.sorted(by: { $0.cpu > $1.cpu }).prefix(5) {
        print(String(format: "%6d %6.1f%% %@", process.id, process.cpu, process.name))
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
