import Foundation

public enum AppIdentity {
    public static let name = "CapsAwake"
    public static let bundleIdentifier = "com.gajeroll.capsawake"
    public static let daemonBundleIdentifier = "com.gajeroll.capsawake.daemon"
    public static let machServiceName = "com.gajeroll.capsawake.daemon"
    /// Where the daemon sits inside the app bundle, which is also what the launch
    /// daemon plist points `BundleProgram` at.
    public static let daemonExecutablePath = "Contents/MacOS/CapsAwakeDaemon"
    public static let osLogSubsystem = bundleIdentifier

    /// The Team ID official CapsAwake releases are signed with.
    ///
    /// Not a secret — `codesign -dv` prints it for any signed binary — and not what a
    /// running copy trusts. The app and the daemon build their XPC requirements from
    /// the team in their own signature (`SelfSigningTeam`), so a fork signed by
    /// another Apple team keeps working without editing this constant. It stays here
    /// so `scripts/release-check.sh` can confirm a release is configured for this team.
    public static let teamIdentifier = "H9DPAP9M7B"

    /// A Team ID is ten uppercase letters or digits. Anything else is refused rather
    /// than interpolated into a requirement string.
    public static func isWellFormedTeamIdentifier(_ team: String) -> Bool {
        team.wholeMatch(of: /^[A-Z0-9]{10}$/) != nil
    }

    /// Who the root daemon will take orders from, for `team`.
    ///
    /// The team is the load-bearing half. `anchor apple generic` only says the
    /// certificate chain leads back to Apple, which is true of *every* Apple-issued
    /// developer certificate, so an identifier on its own is satisfied by anyone who
    /// signs a bundle claiming to be us. Returns nil when `team` is not well formed.
    public static func clientCodeRequirement(team: String) -> String? {
        guard isWellFormedTeamIdentifier(team) else { return nil }
        return """
            identifier "\(bundleIdentifier)" and anchor apple generic \
            and certificate leaf[subject.OU] = "\(team)"
            """
    }

    /// The requirement official releases would use. Tests compile this string; the
    /// running daemon does not. It reads its own signature instead.
    public static let clientCodeRequirement = clientCodeRequirement(team: teamIdentifier) ?? ""

    /// The daemon's code signing identifier, which is deliberately *not* the launchd
    /// label above.
    ///
    /// Left alone, `codesign` derives an identifier from the executable's file name,
    /// and that is the value — `CapsAwakeDaemon` — that every registration so far has
    /// recorded. It is pinned explicitly here so it is a decision rather than an
    /// accident, but it keeps that value on purpose.
    ///
    /// It cannot simply be renamed to something reverse-DNS. launchd records a
    /// Lightweight Code Requirement when the service is registered, and that
    /// requirement names the signing identifier:
    ///
    ///     LWCR = { "reqs" => { "signing-identifier" => "CapsAwakeDaemon", … } }
    ///
    /// Re-registering over the service does *not* update it, so a daemon signed under
    /// a new identifier stops satisfying the recorded requirement and launchd refuses
    /// to spawn it for good — `xpcproxy` exits `EX_CONFIG`, while `SMAppService` goes
    /// on reporting the service as enabled. Every existing install would be left with
    /// a daemon that never starts and nothing saying why. Renaming it would need a
    /// migration that unregisters first, which costs the user a fresh approval prompt.
    public static let daemonSigningIdentifier = "CapsAwakeDaemon"

    /// Who the app will take answers from, for `team`, so the trust runs both ways.
    ///
    /// The identifier is only half of it: paired with the team, this admits our daemon
    /// and nobody else's. Returns nil when `team` is not well formed.
    public static func daemonCodeRequirement(team: String) -> String? {
        guard isWellFormedTeamIdentifier(team) else { return nil }
        return """
            identifier "\(daemonSigningIdentifier)" and anchor apple generic \
            and certificate leaf[subject.OU] = "\(team)"
            """
    }

    /// The requirement official releases would use. The running app does not: it
    /// reads its own signature instead, the same way the daemon does.
    public static let daemonCodeRequirement = daemonCodeRequirement(team: teamIdentifier) ?? ""

    /// Matches nobody. Used when a process has no Team ID — an ad-hoc signature —
    /// so the alternative is not "accept every peer".
    public static let unsatisfiableCodeRequirement =
        "identifier \"\(bundleIdentifier)\" and !(identifier \"\(bundleIdentifier)\")"
}
