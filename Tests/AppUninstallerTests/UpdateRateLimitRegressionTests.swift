import XCTest
@testable import AppUninstaller

final class UpdateRateLimitRegressionTests: XCTestCase {
    private let info: [String: Any] = ["CFBundleShortVersionString": "5.0", "CFBundleVersion": "13", "UpdateRepository": "stackhiker/MacOptimizer"]
    private let timestamp = Date(timeIntervalSince1970: 1_794_840_000)
    private let apiURL = "https://api.github.com/repos/stackhiker/MacOptimizer/releases/latest"
    private let latestURL = "https://github.com/stackhiker/MacOptimizer/releases/latest"
    private let releasesURL = "https://github.com/stackhiker/MacOptimizer/releases"
    private let cooldownKey = "MacOptimizer.UpdateAPIRetryAt.stackhiker/macoptimizer"

    private struct Reply {
        var status = 200
        var url: String?
        var headers: [String: String] = [:]
        var body = Data()
        var wait = false
    }
    private actor Transport {
        var requests: [URLRequest] = []
        private var replies: [Reply]
        private let entered: XCTestExpectation?
        init(_ replies: [Reply], entered: XCTestExpectation? = nil) {
            self.replies = replies; self.entered = entered
        }
        func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            guard !replies.isEmpty else { throw URLError(.resourceUnavailable) }
            let reply = replies.removeFirst()
            if reply.wait {
                entered?.fulfill()
                try await Task.sleep(nanoseconds: 10_000_000_000)
                throw URLError(.timedOut)
            }
            let url = reply.url.flatMap(URL.init(string:)) ?? request.url!
            return (reply.body, HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!)
        }
    }
    private func html(repository: String = "stackhiker/MacOptimizer", empty: Bool = true) -> Data {
        Data("""
        <!DOCTYPE html><html><head>
        <meta property="og:site_name" content="GitHub" />
        <meta name="octolytics-dimension-repository_nwo" content="\(repository)" />
        <meta name="route-controller" content="releases" />
        </head><body>\(empty ? "<h2>There aren’t any releases here</h2>" : "<h1>v5.0</h1>")</body></html>
        """.utf8)
    }
    private func page(url: String? = nil, body: Data? = nil) -> Reply {
        Reply(url: url ?? releasesURL, headers: ["Content-Type": "text/html; charset=utf-8"], body: body ?? html())
    }
    private func limit(headers: [String: String] = [:], status: Int = 403) -> Reply {
        var fields = ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1794844074"]
        fields.merge(headers) { _, new in new }
        return Reply(status: status, headers: fields, body: Data(#"{"message":"API rate limit exceeded"}"#.utf8))
    }
    private func release() -> Reply {
        Reply(body: Data(#"{"tag_name":"v5.0-build14","html_url":"https://github.com/stackhiker/MacOptimizer/releases/tag/v5.0-build14"}"#.utf8))
    }
    private func makeService(_ transport: Transport, defaults: UserDefaults? = nil) -> UpdateCheckerService {
        UpdateCheckerService(info: info, load: { request in try await transport.load(request) }, now: { [timestamp] in timestamp }, defaults: defaults)
    }
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "MacOptimizer.UpdateRateLimitTests." + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }

    @MainActor func testAPIRequestIncludesRequiredHeadersAndHonestSource() async {
        let transport = Transport([release()])
        let service = makeService(transport)
        await service.checkForUpdates()
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.absoluteString, apiURL)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "User-Agent"), "MacOptimizer/5.0 (Build 13)")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(service.lastCheckSource, .api)
        XCTAssertEqual(service.state, .updateAvailable)
    }

    @MainActor func testRateLimitUsesVerifiedPublicPageAndPersistsCooldownAcrossLaunches() async {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let transport = Transport([limit(), page(), page()])
        let service = makeService(transport, defaults: defaults)
        await service.checkForUpdates()
        XCTAssertEqual(service.state, .noPublishedRelease)
        XCTAssertFalse(service.hasUpdate)
        XCTAssertNil(service.errorMessage)
        XCTAssertEqual(service.checkedAt, timestamp)
        XCTAssertEqual(service.lastCheckSource, .publicReleasePage)
        XCTAssertEqual(service.apiRetryAt, Date(timeIntervalSince1970: 1_794_844_074))
        XCTAssertEqual(defaults.double(forKey: cooldownKey), 1_794_844_074)
        await service.checkForUpdates()
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.absoluteString }, [apiURL, latestURL, latestURL])
        let relaunchedTransport = Transport([page()])
        let relaunched = makeService(relaunchedTransport, defaults: defaults)
        await relaunched.checkForUpdates()
        let relaunchedRequests = await relaunchedTransport.requests
        XCTAssertEqual(relaunchedRequests.map { $0.url!.absoluteString }, [latestURL])
        XCTAssertEqual(relaunched.state, .noPublishedRelease)
    }

    @MainActor func testExpiredCooldownIsRemovedAndAPIIsAllowed() async {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(timestamp.timeIntervalSince1970 - 1, forKey: cooldownKey)
        let transport = Transport([release()])
        let service = makeService(transport, defaults: defaults)
        XCTAssertNil(service.apiRetryAt)
        await service.checkForUpdates()
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.absoluteString, apiURL)
        XCTAssertNil(defaults.object(forKey: cooldownKey))
    }

    func testRateLimitHeaderPrecedenceAndHTTPDate() {
        func retry(_ status: Int, _ headers: [String: String], _ message: String = "") -> Date? {
            let response = HTTPURLResponse(url: URL(string: apiURL)!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return UpdateCheckerService.rateLimitRetryDate(response: response, data: Data("{\"message\":\"\(message)\"}".utf8), now: timestamp)
        }
        XCTAssertEqual(retry(403, ["Retry-After": "120", "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1794844074"]), timestamp.addingTimeInterval(120))
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        XCTAssertEqual(retry(429, ["Retry-After": dateFormatter.string(from: timestamp.addingTimeInterval(240))]), timestamp.addingTimeInterval(240))
        XCTAssertEqual(retry(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1794844074"]), Date(timeIntervalSince1970: 1_794_844_074))
        XCTAssertEqual(retry(403, [:], "You have exceeded a secondary rate limit"), timestamp.addingTimeInterval(60))
        XCTAssertEqual(retry(429, ["Retry-After": "invalid"]), timestamp.addingTimeInterval(60))
        XCTAssertEqual(retry(429, ["Retry-After": "-1", "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1"]), timestamp.addingTimeInterval(60))
        XCTAssertNil(retry(403, [:], "Resource not accessible by integration"))
        XCTAssertNil(retry(200, ["X-RateLimit-Remaining": "0"]))
    }

    @MainActor func testNonRateLimit403RemainsAnErrorWithoutPublicFallback() async {
        let transport = Transport([Reply(status: 403, body: Data(#"{"message":"Forbidden"}"#.utf8))])
        let service = makeService(transport)
        await service.checkForUpdates()
        XCTAssertEqual(service.state, .failed)
        XCTAssertTrue(service.errorMessage?.contains("403") == true)
        XCTAssertNil(service.checkedAt)
        XCTAssertNil(service.apiRetryAt)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    @MainActor func testAPI404RequiresVerifiedPublicRepositoryBeforeNoReleaseConclusion() async {
        let transport = Transport([Reply(status: 404), page()])
        let service = makeService(transport)
        await service.checkForUpdates()
        XCTAssertEqual(service.state, .noPublishedRelease)
        XCTAssertNil(service.errorMessage)
        XCTAssertNil(service.apiRetryAt)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let unavailable = makeService(Transport([Reply(status: 404), Reply(status: 404)]))
        await unavailable.checkForUpdates()
        XCTAssertEqual(unavailable.state, .failed)
        XCTAssertNil(unavailable.checkedAt)
    }

    @MainActor func testPublicTagBuildComparisonAndMissingBuildRemainHonest() async {
        let cases: [(String, UpdateCheckerService.CheckState)] = [
            ("v5.0-build14", .updateAvailable), ("v5.0-build13", .upToDate),
            ("v5.0", .unverifiable), ("v5.1", .updateAvailable), ("v5.1-beta1", .failed)
        ]
        for (tag, state) in cases {
            let url = releasesURL + "/tag/" + tag
            let service = makeService(Transport([limit(), page(url: url, body: html(empty: false))]))
            await service.checkForUpdates()
            XCTAssertEqual(service.state, state, tag)
            XCTAssertEqual(service.hasUpdate, state == .updateAvailable, tag)
            if state != .failed { XCTAssertEqual(service.lastCheckSource, .publicReleasePage) }
        }
    }

    @MainActor func testPublicFallbackRejectsCrossRepositoryAndUnsafeFinalURLs() async {
        let malicious = [
            "https://github.com/other/project/releases", "https://example.com/stackhiker/MacOptimizer/releases",
            "http://github.com/stackhiker/MacOptimizer/releases", "https://user@github.com/stackhiker/MacOptimizer/releases",
            releasesURL + "?next=evil", releasesURL + "#release", "https://github.com:444/stackhiker/MacOptimizer/releases",
            releasesURL + "/tag/v5.0%2F..", releasesURL + "/tag/v5.0%252F..", releasesURL + "//tag/v5.0-build14",
            releasesURL + "/tag/../v5.0", releasesURL + "/tag/v5.0%5Cother"
        ]
        for url in malicious {
            let service = makeService(Transport([limit(), page(url: url)]))
            await service.checkForUpdates()
            XCTAssertEqual(service.state, .failed, url)
            XCTAssertNil(service.checkedAt, url)
            XCTAssertNil(service.downloadURL, url)
        }
    }

    @MainActor func testPublicFallbackRejectsEmptyProxyAndUnverifiedPages() async {
        let bodies = [Data(), Data("<html>Proxy OK</html>".utf8), html(repository: "other/project"), html(empty: false)]
        for body in bodies {
            let service = makeService(Transport([limit(), page(body: body)]))
            await service.checkForUpdates()
            XCTAssertEqual(service.state, .failed)
            XCTAssertNil(service.checkedAt)
            XCTAssertNil(service.lastCheckSource)
        }
        let wrongMIME = Reply(url: releasesURL, headers: ["Content-Type": "text/plain"], body: html())
        let service = makeService(Transport([limit(), wrongMIME]))
        await service.checkForUpdates()
        XCTAssertEqual(service.state, .failed)
    }

    @MainActor func testAPIResponseFromAnotherRepositoryIsRejected() async {
        var reply = release()
        reply.url = "https://api.github.com/repos/other/project/releases/latest"
        let service = makeService(Transport([reply]))
        await service.checkForUpdates()
        XCTAssertEqual(service.state, .failed)
        XCTAssertNil(service.checkedAt)
    }

    @MainActor func testCancelDuringPublicFallbackCancelsWholeCheckAndRetainsCooldown() async {
        let entered = expectation(description: "fallback entered")
        let transport = Transport([limit(), Reply(wait: true)], entered: entered)
        let service = makeService(transport)
        let task = Task { await service.checkForUpdates() }
        await fulfillment(of: [entered], timeout: 2)
        service.cancelCheck()
        await task.value
        XCTAssertEqual(service.state, .cancelled)
        XCTAssertFalse(service.isChecking)
        XCTAssertNil(service.errorMessage)
        XCTAssertNil(service.checkedAt)
        XCTAssertNotNil(service.apiRetryAt)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testPublicTagsRequireStableVersionAndOptionalExplicitBuild() {
        XCTAssertEqual(ReleaseVersion.parsePublicTag("v5.0-build14")?.build, 14)
        XCTAssertNil(ReleaseVersion.parsePublicTag("v5.0")?.build)
        for tag in ["latest", "5.0-beta1", "5.0-rc.1", "5.0/build14", "5.0-build14.txt"] {
            XCTAssertNil(ReleaseVersion.parsePublicTag(tag), tag)
        }
    }
}
