import CapsAwakeCore
import CapsAwakeIPC
import Foundation
import os

public actor PrivilegedClient {
    public enum ClientError: Error {
        case connectionFailed
        case operationFailed
    }

    private static let log = Logger(subsystem: AppIdentity.osLogSubsystem, category: "privileged")

    private var connection: NSXPCConnection?

    public init() {}

    public func connect() {
        guard connection == nil else { return }
        let conn = NSXPCConnection(
            machServiceName: CapsAwakeIPC.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: CapsAwakeDaemonProtocol.self)
        // The daemon checks us; check it back, so the trust runs both ways rather than
        // the app handing power settings to whatever answered on the service name.
        // The team is the one in this app's own signature, which matches a daemon
        // signed by the same certificate. An ad-hoc build has no team and is refused.
        if let team = SelfSigningTeam.identifier,
            let requirement = AppIdentity.daemonCodeRequirement(team: team)
        {
            conn.setCodeSigningRequirement(requirement)
        } else {
            Self.log.error(
                """
                No Developer Team ID in this app's signature; refusing the daemon \
                connection. Sign with an Apple Development or Developer ID certificate. \
                An ad-hoc signature cannot change the sleep setting.
                """
            )
            conn.setCodeSigningRequirement(AppIdentity.unsatisfiableCodeRequirement)
        }
        conn.invalidationHandler = { [weak self] in
            Task { await self?.resetConnection() }
        }
        conn.interruptionHandler = { [weak self] in
            Task { await self?.resetConnection() }
        }
        conn.resume()
        connection = conn
    }

    private func resetConnection() {
        connection?.invalidate()
        connection = nil
    }

    public func setSleepDisabled(_ disabled: Bool) async throws {
        let ok = await roundTrip(fallback: false) { proxy, finish in
            proxy.setSleepDisabled(disabled) { finish($0) }
        }
        guard ok else { throw ClientError.operationFailed }
    }

    /// Imposes `plan`, or restores the modes from before CapsAwake changed them
    /// when `plan` is `nil`.
    public func setEnergyMode(_ plan: EnergyModePlan?) async throws {
        let ok = await roundTrip(fallback: false) { proxy, finish in
            guard let plan else {
                proxy.restoreEnergyMode { finish($0) }
                return
            }
            proxy.overrideEnergyMode(
                battery: plan.battery.rawValue,
                adapter: plan.adapter.rawValue
            ) { finish($0) }
        }
        guard ok else { throw ClientError.operationFailed }
    }

    public func currentSleepDisabled() async -> Bool? {
        await roundTrip(fallback: nil) { proxy, finish in
            proxy.currentSleepDisabled { finish($0?.boolValue) }
        }
    }

    /// How long a call waits for the daemon before reporting failure. Generous
    /// against a demand-launch on first use; measured in a suspending clock so a Mac
    /// that sleeps mid-call does not count its nap against the daemon.
    private static let replyTimeout: Duration = .seconds(10)

    /// Performs one XPC round trip.
    ///
    /// The connection error handler has to be able to finish the continuation too.
    /// Passing an empty error handler meant that when the daemon was unreachable no
    /// reply ever arrived, the continuation was never resumed, and the caller hung
    /// forever while holding up everything sequenced behind it.
    ///
    /// The error handler is still not enough on its own. While launchd retries a
    /// spawn that keeps failing — a daemon held to a launch constraint this build
    /// cannot satisfy exits `EX_CONFIG` forever — the message sits queued, no error
    /// is ever delivered, and the same hang comes back by another door. So every
    /// call also carries a watchdog: when no answer arrives in time it reports
    /// failure, which is what lets the icon warn instead of reading green, and drops
    /// the connection so the stale message cannot apply long after being given up on.
    private func roundTrip<T: Sendable>(
        fallback: T,
        _ perform: (CapsAwakeDaemonProtocol, @escaping @Sendable (T) -> Void) -> Void
    ) async -> T {
        connect()
        guard let connection else { return fallback }

        let state = OSAllocatedUnfairLock<(done: Bool, watchdog: Task<Void, Never>?)>(
            initialState: (done: false, watchdog: nil))
        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ value: T) {
                let (first, watchdog) = state.withLock {
                    state -> (Bool, Task<Void, Never>?) in
                    guard !state.done else { return (false, nil) }
                    defer { state = (done: true, watchdog: nil) }
                    return (true, state.watchdog)
                }
                guard first else { return }
                watchdog?.cancel()
                continuation.resume(returning: value)
            }

            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    let reason = error.localizedDescription
                    Self.log.error("Daemon unreachable: \(reason, privacy: .public)")
                    finish(fallback)
                }) as? CapsAwakeDaemonProtocol
            else {
                finish(fallback)
                return
            }
            perform(proxy, finish)

            let watchdog = Task { [weak self] in
                try? await Task.sleep(for: Self.replyTimeout, clock: .suspending)
                guard !Task.isCancelled else { return }
                Self.log.error("Daemon did not answer in time; reporting failure")
                finish(fallback)
                await self?.resetConnection()
            }
            let finishedFirst = state.withLock { state -> Bool in
                guard !state.done else { return true }
                state.watchdog = watchdog
                return false
            }
            if finishedFirst {
                watchdog.cancel()
            }
        }
    }
}
