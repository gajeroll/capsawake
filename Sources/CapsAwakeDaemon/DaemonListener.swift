import CapsAwakeCore
import CapsAwakeIPC
import CapsAwakeSystem
import Foundation

final class CapsAwakeDaemonDelegate: NSObject, NSXPCListenerDelegate, CapsAwakeDaemonProtocol {
    private var bootReconcileTimer: DispatchSourceTimer?
    private var abandonTimer: DispatchSourceTimer?
    private let lock = NSLock()
    private var liveConnections = 0

    /// How long to wait for a reconnect before restoring the baseline sleep setting.
    /// Short XPC interruptions must not put a still-running app's Mac to sleep.
    private let abandonGraceSeconds: Double = 5

    /// The peer's signature was already checked by macOS, against its audit token,
    /// before this was called — see `ClientValidator.requireSignedClients(on:)`.
    func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: CapsAwakeDaemonProtocol.self)
        newConnection.exportedObject = self

        // Count only invalidation: interruption is recoverable and must not
        // abandon SleepDisabled while the app is still alive.
        newConnection.invalidationHandler = { [weak self] in
            self?.clientDisconnected()
        }

        // Counted before it is resumed, and before the handler above can run. XPC
        // delivers invalidation on the connection's own queue, so a peer that died
        // between `resume()` and the count would have decremented first — clamping at
        // zero and arming the abandon timer — and the increment that followed would
        // then have left a client that can never disconnect, with SleepDisabled held
        // for as long as the daemon lived.
        clientConnected()
        newConnection.resume()
        cancelBootReconcileTimer()
        return true
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void) {
        reply(PrivilegedPowerController.shared.setSleepDisabled(disabled))
    }

    func currentSleepDisabled(reply: @escaping (NSNumber?) -> Void) {
        if let value = PrivilegedPowerController.shared.readSleepDisabled() {
            reply(NSNumber(value: value))
        } else {
            reply(nil)
        }
    }

    func overrideEnergyMode(
        battery: String,
        adapter: String,
        reply: @escaping (Bool) -> Void
    ) {
        guard let battery = EnergyMode(rawValue: battery),
            let adapter = EnergyMode(rawValue: adapter)
        else {
            reply(false)
            return
        }
        let plan = EnergyModePlan(battery: battery, adapter: adapter)
        reply(PrivilegedPowerController.shared.overrideEnergyMode(plan))
    }

    func restoreEnergyMode(reply: @escaping (Bool) -> Void) {
        reply(PrivilegedPowerController.shared.restoreEnergyMode())
    }

    func ping(reply: @escaping () -> Void) {
        reply()
    }

    func startBootReconcile() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 120)
        timer.setEventHandler { [weak self] in
            // A client accepted just as the timer fired would otherwise be dropped.
            guard self?.hasNoClients ?? true else { return }
            PrivilegedPowerController.shared.restoreBaselineIfNoClient()
            // Nothing has asked for anything since launch, so there is no state to
            // serve. Wait for the next demand as a fresh process.
            exit(EXIT_SUCCESS)
        }
        // Under the same lock as the rest of the shared state: this is set on the main
        // thread at launch and cancelled from whichever queue accepts the first
        // connection.
        lock.lock()
        bootReconcileTimer = timer
        lock.unlock()
        timer.resume()
    }

    private func cancelBootReconcileTimer() {
        lock.lock()
        let timer = bootReconcileTimer
        bootReconcileTimer = nil
        lock.unlock()
        timer?.cancel()
    }

    private var hasNoClients: Bool {
        lock.lock()
        defer { lock.unlock() }
        return liveConnections == 0
    }

    private func clientConnected() {
        lock.lock()
        liveConnections += 1
        abandonTimer?.cancel()
        abandonTimer = nil
        lock.unlock()
    }

    private func clientDisconnected() {
        lock.lock()
        liveConnections = max(0, liveConnections - 1)
        let shouldAbandon = liveConnections == 0
        if shouldAbandon {
            abandonTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + abandonGraceSeconds)
            timer.setEventHandler { [weak self] in
                self?.abandonIfStillAlone()
            }
            timer.resume()
            abandonTimer = timer
        }
        lock.unlock()
    }

    /// Restores the machine and exits once the last client is really gone.
    ///
    /// Exiting matters beyond tidiness: launchd relaunches the daemon on the next
    /// XPC demand, so an app update takes effect without a reboot. A daemon that
    /// stays resident keeps serving the previous build's code.
    private func abandonIfStillAlone() {
        lock.lock()
        let alone = liveConnections == 0
        abandonTimer = nil
        lock.unlock()
        guard alone else { return }
        PrivilegedPowerController.shared.abandonClientRequest()
        exit(EXIT_SUCCESS)
    }
}
