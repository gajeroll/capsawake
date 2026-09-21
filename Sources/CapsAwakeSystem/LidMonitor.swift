import CoreGraphics
import Foundation
import IOKit

/// Publishes lid and external-display changes without the caller having to poll.
///
/// Interest notifications from `IOPMrootDomain` fire for more than clamshell
/// changes, so every callback re-reads `AppleClamshellState` rather than trying
/// to decode message numbers (the clamshell-specific constant is a C macro that
/// Swift cannot see). Display changes come from
/// `CGDisplayRegisterReconfigurationCallback`.
public final class LidMonitor: @unchecked Sendable {
    public var onClamshellChanged: (@MainActor (Bool?) -> Void)?
    public var onExternalDisplayChanged: (@MainActor (Bool?) -> Void)?

    private let lock = NSLock()
    private var notifyPort: IONotificationPortRef?
    private var interestNotification: io_object_t = 0
    private var displayCallbackRegistered = false
    private var lastClamshell: Bool?
    private var lastExternalDisplay: Bool?

    public init() {}

    deinit {
        tearDown()
    }

    public func start() {
        seed()
        startClamshellInterest()
        startDisplayReconfiguration()
    }

    public func stop() {
        tearDown()
    }

    /// Re-read both sensors and publish only values that changed.
    /// Used as a safety net when interest notifications are missed.
    public func poll() {
        publishClamshell(ClamshellReader.isClosed())
        publishExternalDisplay(ExternalDisplayReader.isConnected())
    }

    private func tearDown() {
        lock.lock()
        defer { lock.unlock() }
        if interestNotification != 0 {
            IOObjectRelease(interestNotification)
            interestNotification = 0
        }
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
        if displayCallbackRegistered {
            CGDisplayRemoveReconfigurationCallback(
                Self.displayCallback, Unmanaged.passUnretained(self).toOpaque())
            displayCallbackRegistered = false
        }
    }

    private func seed() {
        let closed = ClamshellReader.isClosed()
        let external = ExternalDisplayReader.isConnected()
        lock.lock()
        lastClamshell = closed
        lastExternalDisplay = external
        let clamshellHandler = onClamshellChanged
        let displayHandler = onExternalDisplayChanged
        lock.unlock()

        if let clamshellHandler {
            Task { @MainActor in clamshellHandler(closed) }
        }
        if let displayHandler {
            Task { @MainActor in displayHandler(external) }
        }
    }

    private func startClamshellInterest() {
        let port = IONotificationPortCreate(kIOMainPortDefault)
        lock.lock()
        notifyPort = port
        lock.unlock()
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var notification: io_object_t = 0
        let status = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            Self.interestCallback,
            selfPtr,
            &notification
        )
        guard status == KERN_SUCCESS else { return }
        lock.lock()
        interestNotification = notification
        lock.unlock()
    }

    private func startDisplayReconfiguration() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let error = CGDisplayRegisterReconfigurationCallback(Self.displayCallback, selfPtr)
        lock.lock()
        displayCallbackRegistered = error == .success
        lock.unlock()
    }

    private func publishClamshell(_ value: Bool?) {
        lock.lock()
        let changed = value != lastClamshell
        if changed { lastClamshell = value }
        let handler = onClamshellChanged
        lock.unlock()
        guard changed, let handler else { return }
        Task { @MainActor in handler(value) }
    }

    private func publishExternalDisplay(_ value: Bool?) {
        lock.lock()
        let changed = value != lastExternalDisplay
        if changed { lastExternalDisplay = value }
        let handler = onExternalDisplayChanged
        lock.unlock()
        guard changed, let handler else { return }
        Task { @MainActor in handler(value) }
    }

    private static let interestCallback:
        @convention(c) (UnsafeMutableRawPointer?, io_service_t, natural_t, UnsafeMutableRawPointer?)
            -> Void =
            { refcon, _, _, _ in
                guard let refcon else { return }
                let monitor = Unmanaged<LidMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.publishClamshell(ClamshellReader.isClosed())
            }

    private static let displayCallback:
        @convention(c) (CGDirectDisplayID, CGDisplayChangeSummaryFlags, UnsafeMutableRawPointer?)
            -> Void =
            { _, _, refcon in
                guard let refcon else { return }
                let monitor = Unmanaged<LidMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.publishExternalDisplay(ExternalDisplayReader.isConnected())
            }
}
