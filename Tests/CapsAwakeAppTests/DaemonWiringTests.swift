import CapsAwakeCore
import Foundation
import Testing

/// Where the daemon lives is written down in four places that have to agree: the
/// launchd plist's `BundleProgram`, the path `scripts/build-app.sh` installs it to,
/// the mach service both ends connect on, and `AppIdentity`, which the app uses to
/// hash the daemon and notice that a registration has gone stale.
///
/// Nothing makes them agree at compile time, and when they drift the symptom is a
/// daemon launchd will not spawn — reported as `.enabled` right up until the first
/// write fails. These read the real files rather than a copy of what they should say.

private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func resource(_ name: String) throws -> String {
    try String(contentsOf: repository.appending(path: name), encoding: .utf8)
}

@Test func theDaemonPlistPointsWhereAppIdentitySaysTheDaemonIs() throws {
    let plist = try resource("resources/\(AppIdentity.daemonBundleIdentifier).plist")
    #expect(plist.contains("<string>\(AppIdentity.daemonExecutablePath)</string>"))
}

@Test func theDaemonPlistLabelsItselfWithTheServiceItVends() throws {
    let plist = try resource("resources/\(AppIdentity.daemonBundleIdentifier).plist")
    #expect(plist.contains("<string>\(AppIdentity.daemonBundleIdentifier)</string>"))
    #expect(plist.contains("<key>\(AppIdentity.machServiceName)</key>"))
}

/// Login Items & Extensions names its approval prompt after this. Without it the user
/// is asked to approve a bare label.
@Test func theDaemonPlistNamesTheAppItBelongsTo() throws {
    let plist = try resource("resources/\(AppIdentity.daemonBundleIdentifier).plist")
    #expect(plist.contains("AssociatedBundleIdentifiers"))
    #expect(plist.contains("<string>\(AppIdentity.bundleIdentifier)</string>"))
}

@Test func theAppBundleIdentifierIsTheOneInInfoPlist() throws {
    let plist = try resource("resources/Info.plist")
    #expect(plist.contains("<string>\(AppIdentity.bundleIdentifier)</string>"))
}

/// `AppIdentity.daemonExecutablePath` is relative to the bundle; the build script
/// installs into `Contents/MacOS`. If one moves, the other has to.
@Test func theBuildScriptInstallsTheDaemonWhereItIsExpected() throws {
    let script = try resource("scripts/build-app.sh")
    let executable = URL(fileURLWithPath: AppIdentity.daemonExecutablePath).lastPathComponent
    #expect(script.contains("\"$MACOS/\(executable)\""))
    #expect(AppIdentity.daemonExecutablePath.hasPrefix("Contents/MacOS/"))
}

/// The daemon is signed with its identifier explicitly, because the code signing
/// requirement the app holds it to names that identifier. Left to itself codesign
/// derives one from the executable's file name.
@Test func theBuildScriptSignsTheDaemonWithItsOwnIdentifier() throws {
    let script = try resource("scripts/build-app.sh")
    #expect(script.contains("--identifier \"$DAEMON_SIGNING_ID\""))
    #expect(script.contains("DAEMON_SIGNING_ID=\"\(AppIdentity.daemonSigningIdentifier)\""))
}
