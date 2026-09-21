import CapsAwakeCore
import CapsAwakeSystem
import Foundation
import Security
import os

/// Decides which XPC peers are allowed to change power settings as root.
enum ClientValidator {
    private static let log = Logger(subsystem: AppIdentity.osLogSubsystem, category: "daemon")

    /// Hands the check to macOS, which makes it against the peer's audit token before
    /// the connection ever reaches the listener delegate.
    ///
    /// This used to be done by hand: ask `SecCodeCopyGuestWithAttributes` about the
    /// peer's process ID, then check that code against a requirement. Two things were
    /// wrong with it. A process ID is the weaker identifier —
    /// `setConnectionCodeSigningRequirement` has been public since macOS 13, uses the
    /// audit token, and is what Apple supports for this. And the requirement itself
    /// named only the bundle identifier under `anchor apple generic`, which every
    /// Apple-issued developer certificate satisfies, so anyone who signed a bundle
    /// claiming to be CapsAwake could drive the daemon. The requirement names the team
    /// in this daemon's own signature, so a fork signed by another team still admits
    /// only its own app. There is no debug bypass: `scripts/build-app.sh` signs the
    /// app and the daemon with the same identity, and an ad-hoc signature — which has
    /// no team — is refused rather than trusted.
    static func requireSignedClients(on listener: NSXPCListener) {
        guard let team = SelfSigningTeam.identifier,
            let requirement = AppIdentity.clientCodeRequirement(team: team),
            compiles(requirement)
        else {
            log.error(
                """
                No Developer Team ID in this daemon's signature; refusing every XPC \
                client. Sign the app and the daemon with the same Apple Development \
                or Developer ID certificate. An ad-hoc signature cannot drive the daemon.
                """
            )
            listener.setConnectionCodeSigningRequirement(AppIdentity.unsatisfiableCodeRequirement)
            return
        }
        log.notice("Accepting XPC clients signed by team \(team, privacy: .public)")
        listener.setConnectionCodeSigningRequirement(requirement)
    }

    private static func compiles(_ requirement: String) -> Bool {
        var compiled: SecRequirement?
        return SecRequirementCreateWithString(requirement as CFString, [], &compiled)
            == errSecSuccess
    }
}
