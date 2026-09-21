import CapsAwakeCore
import Foundation
import Security
import Testing

/// The requirements are strings handed to macOS, so a typo in one is not a compile
/// error — it is a daemon that refuses every client, or an app that cannot reach its
/// daemon, discovered at runtime on someone else's Mac.

private func compiles(_ requirement: String) -> Bool {
    var compiled: SecRequirement?
    return SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess
        && compiled != nil
}

@Test func bothCodeRequirementsCompile() {
    #expect(compiles(AppIdentity.clientCodeRequirement))
    #expect(compiles(AppIdentity.daemonCodeRequirement))
}

/// The team is the half that does the work. `anchor apple generic` only says the
/// certificate leads back to Apple, which is true of every Apple-issued developer
/// certificate — so without the team, anyone who signs a bundle claiming our
/// identifier can drive the root daemon.
@Test func theRequirementsNameTheTeamAndNotJustTheIdentifier() {
    let team = "certificate leaf[subject.OU] = \"\(AppIdentity.teamIdentifier)\""
    for requirement in [AppIdentity.clientCodeRequirement, AppIdentity.daemonCodeRequirement] {
        #expect(requirement.contains(team))
        #expect(requirement.contains("anchor apple generic"))
    }
}

/// A fork builds the requirement from whatever team signed it. The string must name
/// that team, and a team that is not ten letters or digits must not become a requirement
/// — interpolating it would be a way to break out of the quoted OU.
@Test func aRequirementCanBeBuiltForAnyWellFormedTeam() {
    let other = "ABCDEFGHIJ"
    let client = AppIdentity.clientCodeRequirement(team: other)
    let daemon = AppIdentity.daemonCodeRequirement(team: other)
    #expect(compiles(client ?? ""))
    #expect(compiles(daemon ?? ""))
    #expect(client?.contains("certificate leaf[subject.OU] = \"\(other)\"") == true)
    #expect(daemon?.contains("certificate leaf[subject.OU] = \"\(other)\"") == true)
    #expect(client?.contains(AppIdentity.teamIdentifier) == false)
}

@Test func anIllFormedTeamIsRefused() {
    for team in ["", "h9dpap9m7b", "H9DPAP9M7", "H9DPAP9M7BB", "H9DPAP9M7B\" or true"] {
        #expect(AppIdentity.isWellFormedTeamIdentifier(team) == false)
        #expect(AppIdentity.clientCodeRequirement(team: team) == nil)
        #expect(AppIdentity.daemonCodeRequirement(team: team) == nil)
    }
}

/// What an ad-hoc signature gets instead of "accept everyone".
@Test func theFallbackRequirementMatchesNobody() {
    #expect(compiles(AppIdentity.unsatisfiableCodeRequirement))
    #expect(AppIdentity.unsatisfiableCodeRequirement.contains("!("))
}

/// The app and the daemon are different programs and each requirement must name its
/// own, or the check is satisfied by the wrong side of the connection.
@Test func eachRequirementNamesItsOwnProgram() {
    #expect(
        AppIdentity.clientCodeRequirement
            .contains("identifier \"\(AppIdentity.bundleIdentifier)\"")
    )
    #expect(
        AppIdentity.daemonCodeRequirement
            .contains("identifier \"\(AppIdentity.daemonSigningIdentifier)\"")
    )
    #expect(AppIdentity.bundleIdentifier != AppIdentity.daemonSigningIdentifier)
}

/// The launchd label and the mach service are the same string; the daemon's *signing*
/// identifier is deliberately a third, different one. launchd records a code
/// requirement naming the signing identifier when the service is registered and never
/// updates it, so renaming it would refuse to spawn on every existing install. See
/// `AppIdentity.daemonSigningIdentifier`.
@Test func theDaemonLabelAndServiceAgreeButTheSigningIdentifierIsItsOwn() {
    #expect(AppIdentity.machServiceName == AppIdentity.daemonBundleIdentifier)
    #expect(AppIdentity.daemonSigningIdentifier != AppIdentity.daemonBundleIdentifier)
}

/// The value launchd already holds. Changing it is a migration, not an edit.
@Test func theDaemonSigningIdentifierIsTheOneAlreadyRegistered() {
    #expect(AppIdentity.daemonSigningIdentifier == "CapsAwakeDaemon")
}
