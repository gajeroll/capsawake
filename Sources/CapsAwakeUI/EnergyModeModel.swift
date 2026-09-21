import CapsAwakeCore
import Observation

/// Which Energy Modes this Mac offers, resolved by the app layer.
///
/// The Settings window reads this so it never offers a mode the hardware lacks —
/// High Power exists on only some Macs, and is listed as not recommended because
/// it works against keeping a closed Mac cool.
@MainActor
@Observable
public final class EnergyModeModel {
    public var supportedModes: Set<EnergyMode> = []

    public init() {}

    public var isSupported: Bool {
        !supportedModes.isEmpty
    }

    /// The supported modes in the order System Settings lists them.
    public var offeredModes: [EnergyMode] {
        EnergyMode.allCases.filter { supportedModes.contains($0) }
    }
}
