import Foundation
import Darwin

/// Called on the monitor's serial queue; no child processes are needed.
final class SystemMetricsSampler {
    private var previousTicks: [UInt32]?
    private var previousNetwork: [String: (received: UInt64, sent: UInt64)] = [:]
    private var previousNetworkTime: TimeInterval?

    func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return nil }
        let deltas = zip(ticks, previous).map { UInt64($0 &- $1) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(deltas[Int(CPU_STATE_IDLE)]) / Double(total)))
    }

    func networkUsage() -> (download: Double, upload: Double, received: UInt64, sent: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &bytes, &length, nil, 0) == 0 else { return nil }
        var counters: [String: (received: UInt64, sent: UInt64)] = [:]
        bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let size = Int(header.ifm_msglen)
                guard size >= MemoryLayout<if_msghdr>.size, offset + size <= length else { break }
                if header.ifm_type == RTM_IFINFO2, size >= MemoryLayout<if_msghdr2>.size {
                    let info = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(info.ifm_index), &name) != nil,
                       info.ifm_flags & IFF_UP != 0, info.ifm_flags & IFF_LOOPBACK == 0 {
                        let interface = String(cString: name)
                        // Physical Ethernet/Wi-Fi interfaces share the en prefix.
                        // Exclude virtual tunnels to avoid counting VPN traffic twice.
                        if interface.hasPrefix("en") {
                            counters[interface] = (info.ifm_data.ifi_ibytes, info.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += size
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousNetworkTime.map { now - $0 } ?? 0
        var receivedDelta: UInt64 = 0
        var sentDelta: UInt64 = 0
        for (name, current) in counters {
            if let old = previousNetwork[name] {
                receivedDelta += current.received >= old.received ? current.received - old.received : 0
                sentDelta += current.sent >= old.sent ? current.sent - old.sent : 0
            }
        }
        previousNetwork = counters
        previousNetworkTime = now
        return (elapsed > 0 ? Double(receivedDelta) / elapsed : 0,
                elapsed > 0 ? Double(sentDelta) / elapsed : 0,
                counters.values.reduce(0) { $0 + $1.received },
                counters.values.reduce(0) { $0 + $1.sent })
    }
}
