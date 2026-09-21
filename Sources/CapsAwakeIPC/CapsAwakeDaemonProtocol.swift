import CapsAwakeCore
import Foundation

@objc public protocol CapsAwakeDaemonProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool) -> Void)
    func currentSleepDisabled(reply: @escaping (NSNumber?) -> Void)
    /// Modes are `EnergyMode` raw values. The daemon records what each power source
    /// had before the first override so `restoreEnergyMode` can undo it.
    func overrideEnergyMode(
        battery: String,
        adapter: String,
        reply: @escaping (Bool) -> Void
    )
    /// A no-op when CapsAwake never changed the mode, so callers need not track it.
    func restoreEnergyMode(reply: @escaping (Bool) -> Void)
    func ping(reply: @escaping () -> Void)
}

public enum CapsAwakeIPC {
    public static let machServiceName = AppIdentity.machServiceName
}
