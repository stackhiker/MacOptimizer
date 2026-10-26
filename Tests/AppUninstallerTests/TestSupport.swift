import Foundation
import XCTest
@testable import AppUninstaller

extension XCTestCase {
    func makeTemporaryCachePersistence() throws -> CachePersistence {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOptimizerCacheTests-\(UUID().uuidString)", isDirectory: true)
        let persistence = try CachePersistence(cacheDirectory: directory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return persistence
    }
}
