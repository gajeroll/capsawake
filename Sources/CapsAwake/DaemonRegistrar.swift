import CapsAwakeCore
import CapsAwakeSystem
import Foundation
import ServiceManagement

/// Keeps the privileged daemon registered with launchd, and says when the user has to
/// do something about it.
///
/// Nothing can change the sleep setting until the daemon is running, so every outcome
/// here is worth recording. Silently returning on an unexpected status once left the
/// app showing a bare error icon with no way to tell why.
@MainActor
final class DaemonRegistrar {
    /// What the user would have to do, if anything.
    enum Approval {
        case granted
        case required
    }

    private static let plistName = "\(AppIdentity.daemonBundleIdentifier).plist"

    /// launchd keeps the executable it was handed when the service was registered, not
    /// whatever is in the bundle now. An app that replaced itself in place — an update,
    /// or a move to another folder — therefore leaves behind a daemon that no longer
    /// matches the app and may not launch at all, while `status` still cheerfully
    /// reports `.enabled`.
    private static let registeredDaemonKey = "RegisteredDaemonBuild"

    private var service: SMAppService { SMAppService.daemon(plistName: Self.plistName) }

    /// Registers the daemon if it is missing, or re-registers it if the app it points
    /// at has changed. Returns whether the user still has to approve it.
    @discardableResult
    func synchronize() -> Approval {
        let daemon = service
        switch daemon.status {
        // `.notFound` is also worth a registration attempt: it is what macOS reports
        // for a service it has no record of, and the thrown error says why.
        case .notRegistered, .notFound:
            return register(daemon)
        case .requiresApproval:
            Log.info("Daemon is waiting for approval in Login Items & Extensions")
            return .required
        case .enabled where registrationIsStale:
            Log.info("The app changed since the daemon was registered; registering again")
            return register(daemon)
        case .enabled:
            return .granted
        @unknown default:
            Log.error("Unknown daemon status: \(daemon.status.rawValue)")
            return currentApproval()
        }
    }

    /// Approval happens in System Settings, out of our sight, so this is asked again on
    /// every reconcile rather than only at launch.
    func currentApproval() -> Approval {
        service.status == .requiresApproval ? .required : .granted
    }

    /// Registers again even though nothing about the app has changed.
    ///
    /// `synchronize()` notices a *changed* app. It cannot notice a registration that
    /// has gone away underneath one that did not change: macOS goes on reporting
    /// `.enabled` from its Background Task Management record while launchd has no
    /// service left to spawn, and the build stamp still matches, so the ordinary path
    /// concludes there is nothing to do. The app then fails every privileged call for
    /// the rest of its life, and the relaunch it offers takes that same path again.
    ///
    /// So when the daemon is supposed to be there and writes keep failing anyway,
    /// register over it regardless of the stamp. Rate-limited, because a failing write
    /// may mean something else entirely and registering in a loop would be its own bug.
    func repairIfStuck(now: Date = Date()) {
        if let lastRepair, now.timeIntervalSince(lastRepair) < Self.repairInterval { return }
        lastRepair = now
        Log.info(
            "Sleep settings keep failing while the daemon reads as registered; registering again"
        )
        _ = register(service)
    }

    /// Long enough that a daemon which is merely slow to come up is not registered over
    /// repeatedly, short enough that the user is not left broken for a session.
    private static let repairInterval: TimeInterval = 60
    private var lastRepair: Date?

    /// Registering over the service that is already there, and deliberately not
    /// unregistering it first as Apple's advice for a changed executable would have it.
    /// Unregistering is not the clean slate it sounds like: it switches the daemon off
    /// in Login Items & Extensions, and macOS then declines to register it again — for
    /// a while with a bare `EPERM`, and afterwards by minting a fresh approval record
    /// while launchd keeps the one that was there when the registration began. Either
    /// way the user is asked to approve a daemon they never knowingly turned off, and
    /// can be asked again on the next update.
    ///
    /// Registering over it asks nothing of them, and puts back whatever launchd is
    /// missing.
    private func register(_ daemon: SMAppService) -> Approval {
        do {
            try daemon.register()
            UserDefaults.standard.set(Self.buildStamp, forKey: Self.registeredDaemonKey)
            Log.info("Registered CapsAwake daemon")
        } catch {
            Log.error("Daemon registration failed: \(error)")
            if Self.isRefusedByTheUser(error) {
                Log.info("The daemon is switched off in Login Items & Extensions")
                return .required
            }
        }
        return currentApproval()
    }

    /// Whether macOS refused to register the daemon because the user has switched it
    /// off, rather than because anything is wrong with it.
    ///
    /// It comes back as a bare `EPERM`, and `status` afterwards is `.notRegistered`
    /// like any other failure, so without telling the two apart the app reports a
    /// daemon that cannot write and offers a relaunch — which will fail the same way
    /// for as long as the switch in Login Items & Extensions is off.
    private static func isRefusedByTheUser(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == "SMAppServiceErrorDomain" && error.code == EPERM
    }

    private var registrationIsStale: Bool {
        UserDefaults.standard.string(forKey: Self.registeredDaemonKey) != Self.buildStamp
    }

    /// The version and the path are not enough to tell one daemon from another: what
    /// launchd holds the registration against is the signature, and a daemon rebuilt or
    /// re-signed at the same version and place is exactly the case it refuses to spawn
    /// ("needs LWCR update", `xpcproxy` exiting `EX_CONFIG`). The app is then left with
    /// a service that will never start and a status that says it is fine until the
    /// first write fails.
    private static var buildStamp: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let daemon = Bundle.main.bundleURL.appending(path: AppIdentity.daemonExecutablePath)
        let signature = CodeIdentity.hash(at: daemon) ?? "unsigned"
        return "\(build)@\(Bundle.main.bundlePath)#\(signature)"
    }
}
