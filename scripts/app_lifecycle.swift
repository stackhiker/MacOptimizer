import AppKit
import Foundation

let arguments = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
guard arguments.count == 4 else { fail("Usage: app_lifecycle status|preflight|quit|launch APP BUNDLE_ID") }
let action = arguments[1]
let url = URL(fileURLWithPath: arguments[2]).standardizedFileURL
let bundleID = arguments[3]
func matching() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL == url }
}
func wait(until predicate: () -> Bool, seconds: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return predicate()
}
func rejectOtherCopies() {
    let other = NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == bundleID && $0.bundleURL?.standardizedFileURL != url
    }
    guard other.isEmpty else { fail("Another copy is running. Quit it before installing: \(other.compactMap { $0.bundleURL?.path })") }
}
switch action {
case "status":
    let pids = matching().map { Int($0.processIdentifier) }
    let data = try JSONSerialization.data(withJSONObject: pids)
    print(String(decoding: data, as: UTF8.self))
case "preflight":
    rejectOtherCopies()
case "quit":
    for app in matching() where !app.isTerminated {
        guard app.terminate() else { fail("Application declined to quit; installation stopped.") }
    }
    guard wait(until: { matching().isEmpty }, seconds: 8) else {
        fail("Application did not quit within 8 seconds; no force termination was used.")
    }
case "launch":
    rejectOtherCopies()
    guard matching().isEmpty else { fail("Target application is already running.") }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.createsNewApplicationInstance = true
    var finished = false
    var launched: NSRunningApplication?
    var launchError: Error?
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
        launched = app
        launchError = error
        finished = true
    }
    guard wait(until: { finished }, seconds: 12), launchError == nil,
          let app = launched, app.bundleURL?.standardizedFileURL == url else {
        fail("Failed to launch installed application: \(String(describing: launchError))")
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    guard !app.isTerminated else { fail("Installed application exited immediately.") }
    print(app.processIdentifier)
default:
    fail("Unknown lifecycle action: \(action)")
}
