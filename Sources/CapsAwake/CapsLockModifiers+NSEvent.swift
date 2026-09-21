import AppKit
import CapsAwakeCore

extension CapsLockModifiers {
    /// The modifiers held alongside Caps Lock, as an `NSEvent` reports them.
    ///
    /// `CapsLockFilterPolicy.heldModifiers` does the same job for `CGEventFlags`, and
    /// the two look like one function written twice. They are not: the event tap and
    /// the `NSEvent` monitors are given different Apple types, and no refactor collapses
    /// the bodies. This one lives here rather than beside the other because the other
    /// is in `CapsAwakeSystem`, which the root daemon links — and AppKit has no business
    /// in a root daemon's dependency graph.
    ///
    /// Both are covered by the same test table, so they cannot quietly disagree.
    init(_ flags: NSEvent.ModifierFlags) {
        var held: CapsLockModifiers = []
        if flags.contains(.control) { held.insert(.control) }
        if flags.contains(.option) { held.insert(.option) }
        if flags.contains(.shift) { held.insert(.shift) }
        if flags.contains(.command) { held.insert(.command) }
        self = held
    }
}
