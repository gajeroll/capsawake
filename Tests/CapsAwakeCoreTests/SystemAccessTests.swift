import Testing

@testable import CapsAwakeCore

/// The warning icon and the rows that explain it are rendered from this one list, so
/// the rule that matters is that the two cannot come apart: an icon that turns into a
/// warning with nothing saying why is the failure this type exists to prevent.

@Test func onlyWhatTheUserCanActOnNeedsAttention() {
    #expect(!SystemAccessItem(kind: .accessibility, status: .granted).needsAttention)
    #expect(!SystemAccessItem(kind: .accessibility, status: .notNeeded).needsAttention)
    #expect(SystemAccessItem(kind: .accessibility, status: .awaitingApproval).needsAttention)
    #expect(SystemAccessItem(kind: .backgroundDaemon, status: .failing).needsAttention)
}

/// Every item that needs attention has a reason the icon can draw, and every item that
/// does not has none. This is the invariant behind "no warning icon without a row".
@Test func needingAttentionAndHavingAReasonAreTheSameThing() {
    for kind in SystemAccessKind.allCases {
        for status in [
            SystemAccessStatus.granted, .notNeeded, .awaitingApproval, .failing,
        ] {
            let item = SystemAccessItem(kind: kind, status: status)
            #expect(
                item.needsAttention == (item.errorReason != nil),
                "\(kind) while \(status)"
            )
        }
    }
}

/// The daemon fails in two different ways and they send the user to different places:
/// one is a switch to turn on in Login Items, the other is a daemon that is already
/// approved and still cannot write, where the answer is a relaunch.
@Test func theDaemonsTwoFailuresAreToldApart() {
    #expect(
        SystemAccessItem(kind: .backgroundDaemon, status: .awaitingApproval).errorReason
            == .daemonApproval
    )
    #expect(
        SystemAccessItem(kind: .backgroundDaemon, status: .failing).errorReason == .privileged
    )
}

/// Accessibility has only the one failure: the grant is missing.
@Test func accessibilityHasOneWayToBeWrong() {
    #expect(
        SystemAccessItem(kind: .accessibility, status: .awaitingApproval).errorReason
            == .dedicatedPermission
    )
    #expect(
        SystemAccessItem(kind: .accessibility, status: .failing).errorReason
            == .dedicatedPermission
    )
}

/// Identity is the kind, so a list of these can be diffed by SwiftUI without two rows
/// for the same permission appearing while its status changes.
@Test func anItemIsIdentifiedByWhatItIsAboutNotByItsStatus() {
    let granted = SystemAccessItem(kind: .accessibility, status: .granted)
    let missing = SystemAccessItem(kind: .accessibility, status: .awaitingApproval)
    #expect(granted.id == missing.id)
    #expect(granted != missing)
}
