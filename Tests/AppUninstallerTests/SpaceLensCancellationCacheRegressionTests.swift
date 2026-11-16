import XCTest
@testable import AppUninstaller

final class SpaceLensCancellationCacheRegressionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceLensCache-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    @MainActor func testLazyExpansionReusesInitialDirectorySizeUntilExplicitInvalidation() async throws {
        let folder = root.appendingPathComponent("a/b/c/d")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("data")
        try Data(repeating: 1, count: 4096).write(to: file)
        let scanner = SpaceLensScanner()
        await scanner.scan(targetURL: root)
        let a = try XCTUnwrap(scanner.rootNode?.children.first)
        let b = try XCTUnwrap(a.children.first)
        let c = try XCTUnwrap(b.children.first)
        XCTAssertFalse(c.childrenLoaded)
        let originalSize = c.size
        try Data(repeating: 2, count: 1024 * 1024).write(to: file)
        await scanner.loadChildren(for: c)
        let cachedD = try XCTUnwrap(c.children.first)
        XCTAssertEqual(cachedD.size, originalSize, "Expansion should reuse the initial scan's directory size")
        scanner.invalidateCachedSizes()
        let freshC = FileNode(url: c.url, name: c.name, size: 0, isDirectory: true, childrenLoaded: false)
        await scanner.loadChildren(for: freshC)
        XCTAssertGreaterThan(try XCTUnwrap(freshC.children.first?.size), cachedD.size)
    }

    @MainActor func testCancelledInitialScanNeverPublishesCompletedTree() async throws {
        let folder = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1]).write(to: folder.appendingPathComponent("file"))
        let scanner = SpaceLensScanner()
        let task = Task { await scanner.scan(targetURL: root) }
        task.cancel()
        await task.value
        XCTAssertNil(scanner.rootNode)
        XCTAssertFalse(scanner.isScanning)
        XCTAssertLessThan(scanner.scanProgress, 1)
    }
}
