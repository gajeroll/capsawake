import Foundation
import IOKit
import IOKit.hidsystem

public enum CapsLockHID {
    public static func openConnection() -> io_connect_t? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching(kIOHIDSystemClass)
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard
            IOServiceOpen(
                service,
                mach_task_self_,
                UInt32(kIOHIDParamConnectType),
                &connection
            ) == KERN_SUCCESS
        else {
            return nil
        }
        return connection
    }

    public static func readState(connection: io_connect_t) -> Bool? {
        var state = false
        guard
            IOHIDGetModifierLockState(
                connection,
                Int32(kIOHIDCapsLockState),
                &state
            ) == KERN_SUCCESS
        else {
            return nil
        }
        return state
    }

    public static func setState(_ state: Bool, connection: io_connect_t) -> Bool {
        IOHIDSetModifierLockState(
            connection,
            Int32(kIOHIDCapsLockState),
            state
        ) == KERN_SUCCESS
    }
}

public actor CapsLockController {
    private var connection: io_connect_t = 0

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    public init() {}

    public func currentState() -> Bool? {
        ensureConnection()
        guard connection != 0 else { return nil }
        if let state = CapsLockHID.readState(connection: connection) {
            return state
        }
        IOServiceClose(connection)
        connection = CapsLockHID.openConnection() ?? 0
        guard connection != 0 else { return nil }
        return CapsLockHID.readState(connection: connection)
    }

    public func setState(_ target: Bool) async -> Bool {
        ensureConnection()
        guard connection != 0 else { return false }
        guard CapsLockHID.setState(target, connection: connection) else { return false }

        for _ in 0..<25 {
            if CapsLockHID.readState(connection: connection) == target {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return CapsLockHID.readState(connection: connection) == target
    }

    private func ensureConnection() {
        if connection == 0 {
            connection = CapsLockHID.openConnection() ?? 0
        }
    }
}
