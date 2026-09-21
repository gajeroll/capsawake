import Foundation

/// Runs a command-line tool to completion and collects what it printed.
enum SystemCommand {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ path: String, _ arguments: [String]) -> Result {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: "\(error)")
        }

        // Drained before waiting, not after. A pipe holds about 64 KB; a child that
        // fills one blocks writing to it, and a parent waiting for that child to exit
        // before it reads would then be waiting forever. Today's callers print far
        // less than that, so this has never happened — but the deadlock would be in
        // the daemon, as root, with the sleep setting half-applied.
        let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errors = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            stdout: text(from: output),
            stderr: text(from: errors)
        )
    }

    private static func text(from data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
