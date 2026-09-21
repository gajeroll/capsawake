import CapsAwakeCore
import os

/// Diagnostic messages are marked `.public` because they carry no user data.
/// Without it OSLog redacts every interpolated string to `<private>`.
enum Log {
    private static let logger = Logger(subsystem: AppIdentity.osLogSubsystem, category: "app")

    /// Not persisted to disk; use `log stream --level debug` to follow these.
    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
