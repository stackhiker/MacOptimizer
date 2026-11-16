import XCTest
@testable import AppUninstaller

final class UpdateCheckerTruthfulnessTests: XCTestCase {
    private let info: [String: Any] = ["CFBundleShortVersionString": "5.0", "CFBundleVersion": "13", "UpdateRepository": "stackhiker/MacOptimizer"]
    private let releaseURL = "https://github.com/stackhiker/MacOptimizer/releases/tag/v5.0"
    private func payload(tag: String = "v5.0", extra: [String: Any] = [:]) throws -> Data {
        var json: [String: Any] = ["tag_name": tag, "html_url": releaseURL, "body": "fixture release notes"]
        json.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: json)
    }
    private func response(_ request: URLRequest, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testBuildComparisonAndVersionComponents() throws {
        let local = ReleaseVersion(version: "5.0", build: 13)!
        XCTAssertEqual(ReleaseVersion(version: "5.0.0", build: 14)!.compare(to: local), .newer)
        XCTAssertEqual(ReleaseVersion(version: "5.0", build: 13)!.compare(to: local), .sameOrOlder)
        XCTAssertEqual(ReleaseVersion(version: "5.0", build: nil)!.compare(to: local), .unknown)
        XCTAssertEqual(ReleaseVersion(version: "5.1", build: nil)!.compare(to: local), .newer)
        XCTAssertEqual(ReleaseVersion(version: "4.99", build: 999)!.compare(to: local), .sameOrOlder)
        XCTAssertNil(ReleaseVersion(version: "release latest", build: 1))
    }

    func testBuildExtractionFromTagAssetsAndMetadata() throws {
        let variants: [Data] = [
            try payload(tag: "5.0-build14"),
            try payload(extra: ["assets": [["name": "MacOptimizer_5.0_build14.zip"]]]),
            try payload(extra: ["build_number": "14"]),
            try payload(extra: ["metadata": ["build": 14]]),
            try payload(extra: ["body": "Release notes\nBuild: 14"])
        ]
        for data in variants {
            XCTAssertEqual(ReleaseVersion.parse(release: try JSONDecoder().decode(GitHubRelease.self, from: data))?.build, 14)
        }
        let ambiguous = try payload(extra: ["assets": [["name": "app_build13.zip"], ["name": "app_build14.zip"]]])
        XCTAssertNil(ReleaseVersion.parse(release: try JSONDecoder().decode(GitHubRelease.self, from: ambiguous))?.build)
    }

    @MainActor func testInitialStateAndSameVersionMissingBuildAreHonest() async throws {
        let data = try payload()
        let service = UpdateCheckerService(info: info, load: { [self] request in (data, response(request)) })
        XCTAssertEqual(service.state, .notChecked)
        XCTAssertNil(service.checkedAt)
        XCTAssertEqual(service.currentVersionDisplay, "5.0 (Build 13)")
        await service.checkForUpdates()
        XCTAssertEqual(service.state, .unverifiable)
        XCTAssertFalse(service.hasUpdate)
        XCTAssertNotNil(service.checkedAt)
    }

    @MainActor func testNewBuildUsesConfiguredChannelAndRealTimestamp() async throws {
        let data = try payload(tag: "v5.0-build14")
        let timestamp = Date(timeIntervalSince1970: 12345)
        let service = UpdateCheckerService(info: info, load: { [self] request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/stackhiker/MacOptimizer/releases/latest")
            XCTAssertEqual(request.timeoutInterval, 5)
            return (data, response(request))
        }, now: { timestamp })
        await service.checkForUpdates()
        XCTAssertTrue(service.hasUpdate)
        XCTAssertEqual(service.state, .updateAvailable)
        XCTAssertEqual(service.checkedAt, timestamp)
        XCTAssertEqual(service.downloadURL?.absoluteString, releaseURL)
    }

    @MainActor func testHTTPFailureNeverClaimsUpToDateOrSuccessfulCheck() async {
        let service = UpdateCheckerService(info: info, load: { [self] request in (Data(), response(request, status: 404)) })
        await service.checkForUpdates()
        XCTAssertEqual(service.state, .failed)
        XCTAssertTrue(service.errorMessage?.contains("404") == true)
        XCTAssertNil(service.checkedAt)
        XCTAssertNil(service.downloadURL)
    }

    @MainActor func testWrongRepositoryLinkIsRejected() async throws {
        let data = try payload(extra: ["html_url": "https://github.com/other/project/releases/tag/5.0"])
        let service = UpdateCheckerService(info: info, load: { [self] request in (data, response(request)) })
        await service.checkForUpdates()
        XCTAssertEqual(service.state, .failed)
        XCTAssertNil(service.downloadURL)
        XCTAssertNil(service.checkedAt)
    }

    @MainActor func testSimultaneousChecksShareOneOwnerAndCancellationReleasesIt() async throws {
        let entered = expectation(description: "request entered")
        var requests = 0
        let service = UpdateCheckerService(info: info, load: { _ in
            requests += 1
            entered.fulfill()
            try await Task.sleep(nanoseconds: 10_000_000_000)
            throw URLError(.timedOut)
        })
        let first = Task { await service.checkForUpdates() }
        await fulfillment(of: [entered], timeout: 2)
        let second = Task { await service.checkForUpdates() }
        await Task.yield()
        XCTAssertEqual(requests, 1)
        service.cancelCheck()
        await first.value; await second.value
        XCTAssertEqual(service.state, .cancelled)
        XCTAssertFalse(service.isChecking)
        XCTAssertNil(service.checkedAt)
    }

    func testRepositoryValidationRejectsURLInjection() {
        XCTAssertTrue(UpdateCheckerService.validRepository("stackhiker/MacOptimizer"))
        for value in ["owner/project/extra", "https://example.com", "../project", "owner/project?token=x"] {
            XCTAssertFalse(UpdateCheckerService.validRepository(value))
        }
        let service = UpdateCheckerService(info: [:], load: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertEqual(service.repository, "stackhiker/MacOptimizer")
    }
}
