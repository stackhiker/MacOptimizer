import Foundation
import IOKit

struct DiskIOCounters { let read: UInt64; let written: UInt64 }
struct DiskIORates { let read: Double; let written: Double }

/// Registry counters represent physical storage drivers, not directory sizes.
final class DiskIOSampler {
    private var deviceIDs = Set<UInt64>()
    private var previous: (DiskIOCounters, TimeInterval)?
    func sample(counters: DiskIOCounters, at time: TimeInterval) -> DiskIORates? {
        defer { previous = (counters, time) }
        guard let (old, timestamp) = previous, time > timestamp,
              counters.read >= old.read, counters.written >= old.written else { return nil }
        return DiskIORates(read: Double(counters.read - old.read) / (time - timestamp),
                           written: Double(counters.written - old.written) / (time - timestamp))
    }
    func sample(counters: DiskIOCounters, deviceIDs currentIDs: Set<UInt64>, at time: TimeInterval) -> DiskIORates? {
        guard !currentIDs.isEmpty else { invalidate(); return nil }
        if currentIDs != deviceIDs { previous = nil; deviceIDs = currentIDs }
        return sample(counters: counters, at: time)
    }
    func invalidate() { previous = nil; deviceIDs = [] }
    func read() -> DiskIORates? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { invalidate(); return nil }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, written: UInt64 = 0
        var found = false
        var currentIDs = Set<UInt64>()
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let value = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let r = value["Bytes (Read)"] as? NSNumber,
                  let w = value["Bytes (Write)"] as? NSNumber else { invalidate(); return nil }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { invalidate(); return nil }
            currentIDs.insert(registryID)
            read &+= r.uint64Value; written &+= w.uint64Value; found = true
        }
        guard found else { invalidate(); return nil }
        return sample(counters: DiskIOCounters(read: read, written: written), deviceIDs: currentIDs, at: ProcessInfo.processInfo.systemUptime)
    }
}
