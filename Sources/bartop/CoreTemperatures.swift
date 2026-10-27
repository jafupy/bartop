import Foundation
import IOKit

func readCoreTemperatures(coreCount: Int) -> [Double?] {
    let reader = CoreTemperatureReader.shared
    return (0..<coreCount).map { index in
        guard index < reader.keys.count, let key = reader.keys[index] else { return nil }
        return reader.temperature(key)
    }
}

private final class CoreTemperatureReader {
    static let shared = CoreTemperatureReader()
    private var connection: io_connect_t = 0
    private var metadata: [String: [UInt8]] = [:]
    let keys: [String?]

    init() {
        // M5 sensor names follow Stats' curated map. PMU die sensors do not
        // identify individual cores, so they must not stand in for missing keys.
        // https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift
        var brand = [CChar](repeating: 0, count: 128)
        var size = brand.count
        let status = sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        guard status == 0, String(cString: brand).contains("Apple M5") else {
            keys = []
            return
        }
        keys = Self.coreSensorKeys()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS {
            connection = 0
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func temperature(_ key: String) -> Double? {
        guard connection != 0 else { return nil }
        var input = [UInt8](repeating: 0, count: 80)
        var code = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        withUnsafeBytes(of: &code) { input.replaceSubrange(0..<4, with: $0) }
        if metadata[key] == nil {
            input[42] = 9 // Read key information; no SMC writes.
            guard let output = call(input) else { return nil }
            metadata[key] = Array(output[28..<40])
        }
        guard let info = metadata[key] else { return nil }
        input.replaceSubrange(28..<40, with: info)
        input[42] = 5 // Read bytes.
        guard let output = call(input) else { return nil }
        let type = info[4..<8].reversed().map { Character(UnicodeScalar($0)) }
        let value: Double
        switch String(type) {
        case "flt ":
            let bits = (0..<4).reduce(UInt32(0)) { $0 | UInt32(output[48 + $1]) << ($1 * 8) }
            value = Double(Float(bitPattern: bits))
        case "sp78":
            let bits = UInt16(output[48]) << 8 | UInt16(output[49])
            value = Double(Int16(bitPattern: bits)) / 256
        default:
            return nil
        }
        return value.isFinite && value > 0 && value < 150 ? value : nil
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: 80)
        var size = output.count
        let result = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                IOConnectCallStructMethod(connection, 2, source.baseAddress, source.count,
                                          destination.baseAddress, &size)
            }
        }
        guard result == KERN_SUCCESS, size == 80, output[40] == 0 else { return nil }
        return output
    }

    private static func coreSensorKeys() -> [String?] {
        let performance = ["Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d",
                           "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
        let superCore = ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K"]
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [] }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var cores: [(id: Int, cluster: UInt8)] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let id = IORegistryEntryCreateCFProperty(entry, "cpu-id" as CFString, nil, 0)?.takeRetainedValue() as? Data,
                  id.count == 4,
                  let cluster = IORegistryEntryCreateCFProperty(entry, "cluster-type" as CFString, nil, 0)?.takeRetainedValue() as? Data,
                  let type = cluster.first else { continue }
            let number = id.withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self)) }
            cores.append((number, type))
        }
        guard let last = cores.map(\.id).max() else { return [] }
        var result = [String?](repeating: nil, count: last + 1)
        var performanceIndex = 0, superIndex = 0
        for core in cores.sorted(by: { $0.id < $1.id }) {
            switch core.cluster {
            case 0x4d: // M: performance cores on M5.
                if performanceIndex < performance.count { result[core.id] = performance[performanceIndex] }
                performanceIndex += 1
            case 0x50: // P: super cores on M5.
                if superIndex < superCore.count { result[core.id] = superCore[superIndex] }
                superIndex += 1
            default:
                break
            }
        }
        return result
    }
}
