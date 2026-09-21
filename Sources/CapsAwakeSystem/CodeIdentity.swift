import Foundation
import Security

/// What a binary on disk is, as the system knows it.
///
/// launchd records the daemon's code signature when the service is registered and
/// refuses to spawn a binary that no longer matches. The app therefore has to notice
/// that its daemon has been replaced — by an update, or by a rebuild signed with
/// another identity — and register again, and the signature is the only thing that
/// tells it apart from the copy launchd agreed to.
public enum CodeIdentity {
    /// The code directory hash, as hex, or `nil` for anything unsigned or unreadable.
    public static func hash(at url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else {
            return nil
        }

        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
            let signing = information as? [String: Any],
            let unique = signing[kSecCodeInfoUnique as String] as? Data
        else {
            return nil
        }
        return unique.map { String(format: "%02x", $0) }.joined()
    }
}
