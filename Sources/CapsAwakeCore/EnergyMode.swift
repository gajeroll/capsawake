import Foundation

/// The macOS Energy Mode, shown in System Settings as Automatic, Low Power, and
/// High Power. High Power only exists on some Macs.
public enum EnergyMode: String, CaseIterable, Sendable {
    case automatic
    case low
    case high
}

/// Energy Mode is stored per power source, and the two routinely disagree — a
/// laptop often sits at Low Power on battery and Automatic on the adapter — so
/// every read, write, and restore is scoped to one source.
public enum PowerSource: String, CaseIterable, Sendable {
    case battery
    case adapter
}

/// The mode CapsAwake imposes on each power source while sleep prevention is on.
public struct EnergyModePlan: Equatable, Sendable {
    public var battery: EnergyMode
    public var adapter: EnergyMode

    public init(battery: EnergyMode, adapter: EnergyMode) {
        self.battery = battery
        self.adapter = adapter
    }

    /// The same mode on both power sources, which is the default.
    public init(_ shared: EnergyMode) {
        self.init(battery: shared, adapter: shared)
    }

    public func mode(for source: PowerSource) -> EnergyMode {
        switch source {
        case .battery: battery
        case .adapter: adapter
        }
    }
}
