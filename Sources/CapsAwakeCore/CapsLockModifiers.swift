/// The modifiers that, held with Caps Lock, ask for capitals rather than for
/// CapsAwake.
///
/// Any combination will do, and an empty one means no key switches capitals at all:
/// Caps Lock is then CapsAwake's switch however it is pressed.
public struct CapsLockModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = CapsLockModifiers(rawValue: 1 << 0)
    public static let option = CapsLockModifiers(rawValue: 1 << 1)
    public static let shift = CapsLockModifiers(rawValue: 1 << 2)
    public static let command = CapsLockModifiers(rawValue: 1 << 3)

    /// One entry each, in the order macOS writes a shortcut.
    public static let everyModifier: [CapsLockModifiers] = [.control, .option, .shift, .command]

    /// How macOS draws this modifier, or the whole combination in its usual order.
    public var symbols: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        default: Self.everyModifier.filter(contains).map(\.symbols).joined()
        }
    }

    /// The combination as a shortcut, Caps Lock included.
    public static let capsLockSymbol = "⇪"

    public var shortcutSymbols: String {
        symbols + Self.capsLockSymbol
    }
}
