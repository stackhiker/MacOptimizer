import Foundation

struct MaintenanceCommandResult {
    let success: Bool
    let output: String
}

/// No shell interpolation and no success inferred from merely starting a process.
func runCheckedMaintenanceCommand(_ executable: String, _ arguments: [String]) -> MaintenanceCommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return MaintenanceCommandResult(success: process.terminationStatus == 0,
                                        output: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    } catch {
        return MaintenanceCommandResult(success: false, output: error.localizedDescription)
    }
}
