import XCTest
@testable import AppUninstaller

final class DiskIOSamplerContinuityTests: XCTestCase {
    func testDeviceReplacementRebasesEvenWhenNewCountersAreHigher() {
        let sampler = DiskIOSampler()
        XCTAssertNil(sampler.sample(counters: .init(read: 100, written: 50), deviceIDs: [1], at: 1))
        XCTAssertEqual(sampler.sample(counters: .init(read: 200, written: 70), deviceIDs: [1], at: 3)?.read, 50)
        XCTAssertNil(sampler.sample(counters: .init(read: 1_000_000, written: 9_000), deviceIDs: [2], at: 5))
        XCTAssertEqual(sampler.sample(counters: .init(read: 1_000_100, written: 9_040), deviceIDs: [2], at: 7)?.written, 20)
    }
    func testUnavailableSampleDoesNotBridgeCountersAcrossTheGap() {
        let sampler = DiskIOSampler()
        _ = sampler.sample(counters: .init(read: 10, written: 10), deviceIDs: [1], at: 1)
        sampler.invalidate()
        XCTAssertNil(sampler.sample(counters: .init(read: 90, written: 90), deviceIDs: [1], at: 20))
        XCTAssertEqual(sampler.sample(counters: .init(read: 110, written: 110), deviceIDs: [1], at: 22)?.read, 10)
    }
    func testMissingDeviceIdentityCannotProduceAnAllDisksRate() {
        let sampler = DiskIOSampler()
        XCTAssertNil(sampler.sample(counters: .init(read: 10, written: 10), deviceIDs: [], at: 1))
        XCTAssertNil(sampler.sample(counters: .init(read: 30, written: 30), deviceIDs: [], at: 2))
    }
}
