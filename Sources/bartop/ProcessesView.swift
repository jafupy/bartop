import SwiftUI

private struct ProcessGroup: Identifiable {
    let id: String
    let name: String
    let children: [ProcessRow]
    var cpu: Double { children.reduce(0) { $0 + $1.cpu } }
    var gpu: Double? {
        let measured = children.compactMap(\.gpu)
        return measured.isEmpty ? nil : measured.reduce(0, +)
    }
    var memory: UInt64 { children.reduce(0) { $0 + $1.memory } }
    var primaryPID: Int32 {
        let pids = Set(children.map(\.id))
        return children.first(where: { !pids.contains($0.parentPID) })?.id ?? children[0].id
    }
}

private enum ProcessSort { case cpu, gpu, memory }

struct ProcessesView: View {
    let processes: [ProcessRow]
    @State private var expanded = false
    @State private var expandedApps: Set<String> = []
    @State private var filter = ""
    @State private var sort: ProcessSort = .cpu

    private func sortValue(_ process: ProcessRow) -> Double {
        switch sort {
        case .cpu: return process.cpu
        case .gpu: return process.gpu ?? -1
        case .memory: return Double(process.memory)
        }
    }

    private func sortValue(_ group: ProcessGroup) -> Double {
        switch sort {
        case .cpu: return group.cpu
        case .gpu: return group.gpu ?? -1
        case .memory: return Double(group.memory)
        }
    }

    private var groups: [ProcessGroup] {
        Dictionary(grouping: processes) { $0.applicationPath ?? "pid:\($0.id)" }
            .map { key, children in
                ProcessGroup(id: key, name: children[0].applicationName ?? children[0].name,
                             children: children.sorted {
                                 sortValue($0) == sortValue($1) ? $0.id < $1.id : sortValue($0) > sortValue($1)
                             })
            }
            .filter { group in
                filter.isEmpty || group.name.localizedCaseInsensitiveContains(filter)
                    || group.children.contains { $0.name.localizedCaseInsensitiveContains(filter) || String($0.id).contains(filter) }
            }
            .sorted { lhs, rhs in
                let a = sortValue(lhs)
                let b = sortValue(rhs)
                return a == b ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : a > b
            }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold)).frame(width: 10)
                        Text("Processes").font(.system(size: 11, weight: .semibold))
                        Text("\(processes.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain).foregroundStyle(.primary)
                Spacer()
                if expanded {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter app or PID", text: $filter).textFieldStyle(.plain).frame(width: 125)
                }
            }
            if expanded {
                HStack(spacing: 6) {
                    Text("PID").frame(width: 36, alignment: .leading)
                    Text("App / process").frame(maxWidth: .infinity, alignment: .leading)
                    Button("CPU %" + (sort == .cpu ? " ↓" : "")) { sort = .cpu }.frame(width: 42, alignment: .trailing)
                    Button("GPU %" + (sort == .gpu ? " ↓" : "")) { sort = .gpu }.frame(width: 42, alignment: .trailing)
                        .help("GPU execution time per second from available driver counters. Overlapping work can exceed 100%; — means unavailable.")
                    Button("Memory" + (sort == .memory ? " ↓" : "")) { sort = .memory }.frame(width: 55, alignment: .trailing)
                }.font(.system(size: 10)).foregroundStyle(.secondary).buttonStyle(.plain)
                ViewThatFits(in: .vertical) {
                    processRows
                    ScrollView { processRows }
                }.frame(maxHeight: 300)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var processRows: some View {
        VStack(spacing: 0) {
            ForEach(groups) { group in
                groupRow(group)
                if expandedApps.contains(group.id) {
                    ForEach(group.children) { child in
                        row(pid: child.id, name: child.name, cpu: child.cpu, gpu: child.gpu, memory: child.memory, indented: true)
                    }
                }
                Divider().padding(.leading, 42)
            }
        }
    }

    private func groupRow(_ group: ProcessGroup) -> some View {
        Button {
            if expandedApps.contains(group.id) { expandedApps.remove(group.id) }
            else if group.children.count > 1 { expandedApps.insert(group.id) }
        } label: {
            HStack(spacing: 6) {
                Text(String(group.primaryPID)).foregroundStyle(.tertiary).frame(width: 36, alignment: .leading)
                HStack(spacing: 5) {
                    if group.children.count > 1 {
                        Image(systemName: expandedApps.contains(group.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Text(group.name).lineLimit(1)
                    if group.children.count > 1 {
                        Text("\(group.children.count)").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f", group.cpu)).frame(width: 42, alignment: .trailing)
                Text(group.gpu.map { String(format: "%.1f", $0) } ?? "—").frame(width: 42, alignment: .trailing)
                Text(bytes(Double(group.memory))).frame(width: 55, alignment: .trailing)
            }.padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain).help(group.children.count > 1 ? "Show processes in \(group.name)" : group.name)
    }

    private func row(pid: Int32, name: String, cpu: Double, gpu: Double?, memory: UInt64, indented: Bool) -> some View {
        HStack(spacing: 6) {
            Text(String(pid)).foregroundStyle(.tertiary).frame(width: 36, alignment: .leading)
            Text(name).foregroundStyle(.secondary).lineLimit(1)
                .padding(.leading, indented ? 13 : 0).frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1f", cpu)).frame(width: 42, alignment: .trailing)
            Text(gpu.map { String(format: "%.1f", $0) } ?? "—").frame(width: 42, alignment: .trailing)
            Text(bytes(Double(memory))).frame(width: 55, alignment: .trailing)
        }.padding(.vertical, 4)
    }
}
