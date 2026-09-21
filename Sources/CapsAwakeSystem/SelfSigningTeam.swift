import CapsAwakeCore
import Foundation
import Security

/// The Developer Team ID in *this* process's code signature, read once at startup.
///
/// The XPC requirements are built from this rather than from `AppIdentity.teamIdentifier`,
/// so a fork signed with another Apple team satisfies its own check. An ad-hoc signature
/// has no team; callers then fail closed instead of accepting every peer. Reading our own
/// signature is not circular: a process that can rewrite the daemon binary is already
/// root, which is the privilege the daemon exists to hold.
public enum SelfSigningTeam {
    /// nil for unsigned, ad-hoc, or a team that is not ten letters or digits.
    public static let identifier: String? = read()

    private static func read() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
            let signing = information as? [String: Any],
            let team = signing[kSecCodeInfoTeamIdentifier as String] as? String,
            AppIdentity.isWellFormedTeamIdentifier(team)
        else {
            return nil
        }
        return team
    }
}
