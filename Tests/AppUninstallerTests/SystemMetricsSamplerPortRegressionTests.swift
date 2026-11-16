import Darwin
import XCTest
@testable import AppUninstaller

final class SystemMetricsSamplerPortRegressionTests: XCTestCase {
    @MainActor
    func testRepeatedCPUSamplingReleasesHostPortReferences() throws {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let sampler = SystemMetricsSampler()
        _ = sampler.cpuUsage()

        func referenceCount() throws -> mach_port_urefs_t {
            var references: mach_port_urefs_t = 0
            let result = mach_port_get_refs(mach_task_self_, host,
                                           mach_port_right_t(MACH_PORT_RIGHT_SEND), &references)
            XCTAssertEqual(result, KERN_SUCCESS)
            guard result == KERN_SUCCESS else { throw NSError(domain: NSMachErrorDomain, code: Int(result)) }
            return references
        }

        let before = try referenceCount()
        for _ in 0..<100 {
            let usage = try XCTUnwrap(sampler.cpuUsage())
            XCTAssertTrue((0...1).contains(usage))
        }
        let after = try referenceCount()
        XCTAssertEqual(after, before, "CPU polling must release each host send right, even when no ticks elapsed")
    }
}
