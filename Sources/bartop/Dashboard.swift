import AppKit
import SwiftUI

// Layout follows serverBar: flat sections, dividers, and a small footer.
struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @State private var coresExpanded = false
    private var m: Metrics { monitor.metrics }

    init(monitor: Monitor, coresExpanded: Bool = false) {
        self.monitor = monitor
        _coresExpanded = State(initialValue: coresExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            processor
            Divider()
            memory.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            network.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ProcessesView(processes: m.processes)
            Divider()
            footer
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .font(.system(size: 11))
        .monospacedDigit()
        .tint(.primary)
    }

    private var processor: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("CPU & GPU")
            SplitGraph(upper: monitor.cpuHistory, lower: monitor.gpuHistory,
                       upperLabel: "CPU \(String(format: "%.1f%%", m.cpu))",
                       lowerLabel: "GPU \(m.gpu.map { String(format: "%.1f%%", $0) } ?? "Unavailable")")
            Button { coresExpanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: coresExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 10)
                    Text("\(m.cores.count) CPU cores")
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.primary)
            if coresExpanded {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<2, id: \.self) { column in
                        VStack(alignment: .leading, spacing: 4) {
                            let count = (m.cores.count + 1) / 2
                            ForEach(min(column * count, m.cores.count)..<min((column + 1) * count, m.cores.count), id: \.self) { index in
                                coreRow(index)
                            }
                        }.font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.top, 3)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Memory & storage")
            stat("RAM", "\(bytes(Double(m.memoryUsed))) / \(bytes(Double(m.memoryTotal)))")
            Meter(fraction: m.memoryFraction, color: Theme.memory)
            HStack {
                Text("Compressed \(bytes(Double(m.compressed)))")
                Spacer()
                Text("Swap \(bytes(Double(m.swap)))")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            stat("Disk", "\(bytes(Double(m.diskUsed))) / \(bytes(Double(m.diskTotal)))")
            Meter(fraction: m.diskTotal > 0 ? Double(m.diskUsed) / Double(m.diskTotal) : 0, color: Theme.disk)
        }
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Network")
            SplitGraph(upper: monitor.uploadHistory, lower: monitor.downloadHistory.map { Optional($0) },
                       maximum: max(1000, (monitor.downloadHistory + monitor.uploadHistory).max() ?? 0),
                       upperColor: Theme.gpu, lowerColor: Theme.memory,
                       upperLabel: "↑ \(bytes(m.upload))/s", lowerLabel: "↓ \(bytes(m.download))/s")
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { monitor.togglePause() } label: {
                Image(systemName: monitor.paused ? "play.fill" : "pause.fill")
            }.help(monitor.paused ? "Resume monitoring" : "Pause monitoring")
            Spacer()
            Button("Activity Monitor") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Button("Quit") { NSApp.terminate(nil) }
        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func coreRow(_ index: Int) -> some View {
        let history = monitor.coreHistory.indices.contains(index) ? monitor.coreHistory[index] : []
        let temperature = m.coreTemperatures.indices.contains(index) ? m.coreTemperatures[index] : nil
        return HStack(spacing: 3) {
            Text("C\(index)").fixedSize().frame(width: 20, alignment: .leading)
            Text(String(format: "%.0f%%", m.cores[index])).fixedSize().frame(width: 26, alignment: .trailing)
            Text(temperature.map { String(format: "%.0f°C", $0) } ?? "—°C")
                .foregroundStyle(.secondary).fixedSize().frame(width: 26, alignment: .trailing)
            BrailleRow(text: BrailleGraph.lines(history.map { Optional($0) }, columns: 10, rows: 1)[0])
        }.lineLimit(1)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value) }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold))
    }
}
