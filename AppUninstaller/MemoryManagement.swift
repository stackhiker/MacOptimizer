import Foundation
import AppKit

/// Kernel pressure levels, not a percentage inferred from free memory.
enum MemoryPressureLevel: Equatable {
    case normal, warning, critical, unknown

    static func fromKernelValue(_ value: UInt32) -> Self {
        switch UInt(value) {
        case DispatchSource.MemoryPressureEvent.normal.rawValue: return .normal
        case DispatchSource.MemoryPressureEvent.warning.rawValue: return .warning
        case DispatchSource.MemoryPressureEvent.critical.rawValue: return .critical
        default: return .unknown
        }
    }

    var isElevated: Bool { self == .warning || self == .critical }

    func title(_ loc: LocalizationManager = .shared) -> String {
        switch self {
        case .normal: return loc.text("正常", "Normal")
        case .warning: return loc.text("较高", "Elevated")
        case .critical: return loc.text("严重", "Critical")
        case .unknown: return loc.text("无法读取", "Unavailable")
        }
    }
}

/// One accounting model for both the monitor and before/after measurements.
struct MemorySnapshot: Equatable {
    let totalBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let pressure: MemoryPressureLevel
    let swapUsedBytes: UInt64?

    var usedBytes: UInt64 { min(totalBytes, appBytes + wiredBytes + compressedBytes) }
    var availableBytes: UInt64 { totalBytes - usedBytes }
    var usage: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }

    init(totalBytes: UInt64, internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
         compressedPages: UInt64, pageSize: UInt64, pressure: MemoryPressureLevel, swapUsedBytes: UInt64? = nil) {
        self.totalBytes = totalBytes
        // Anonymous resident memory excludes reclaimable purgeable pages. File cache
        // is reclaimable and is not labelled as application memory.
        appBytes = min(totalBytes, (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * pageSize)
        wiredBytes = min(totalBytes, wiredPages * pageSize)
        compressedBytes = min(totalBytes, compressedPages * pageSize)
        self.pressure = pressure
        self.swapUsedBytes = swapUsedBytes
    }

    static func readPressure() -> MemoryPressureLevel {
        var value: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return .unknown }
        return .fromKernelValue(value)
    }

    static func read() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        return MemorySnapshot(totalBytes: ProcessInfo.processInfo.physicalMemory,
                              internalPages: UInt64(stats.internal_page_count), purgeablePages: UInt64(stats.purgeable_count),
                              wiredPages: UInt64(stats.wire_count), compressedPages: UInt64(stats.compressor_page_count),
                              pageSize: UInt64(vm_kernel_page_size), pressure: readPressure(),
                              swapUsedBytes: swapOK ? swap.xsu_used : nil)
    }
}

enum MemoryConfirmation: Equatable {
    case pending, confirmed, cancelled
    var permitsTermination: Bool { self == .confirmed }
}

enum GracefulTerminationResult: Equatable { case exited, refused, stillRunning, cancelled }

/// The app gets time to save or ask the user. No timeout ever escalates to force quit.
@MainActor
func requestGracefulTermination(
    request: () -> Bool,
    hasExited: () -> Bool,
    isCancelled: () -> Bool = { Task.isCancelled },
    wait: () async throws -> Void = { try await Task.sleep(nanoseconds: 100_000_000) },
    maximumChecks: Int = 50
) async -> GracefulTerminationResult {
    guard !isCancelled() else { return .cancelled }
    if hasExited() { return .exited }
    guard request() else { return .refused }
    for _ in 0..<maximumChecks {
        if isCancelled() { return .cancelled }
        if hasExited() { return .exited }
        do { try await wait() } catch { return .cancelled }
    }
    return hasExited() ? .exited : .stillRunning
}

@MainActor
func awaitExplicitMemoryConfirmation(
    isPresented: () -> Bool,
    decision: () -> MemoryConfirmation,
    isCancelled: () -> Bool,
    wait: () async throws -> Void = { try await Task.sleep(nanoseconds: 100_000_000) }
) async -> Bool {
    while isPresented() && !isCancelled() {
        do { try await wait() } catch { return false }
    }
    return !isCancelled() && decision().permitsTermination
}
