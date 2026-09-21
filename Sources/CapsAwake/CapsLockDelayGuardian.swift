import CapsAwakeCore
import CapsAwakeSystem
import Foundation

/// Takes the delay out of the front of the Caps Lock key, and puts it back.
///
/// macOS ignores a Caps Lock press shorter than the keyboard's `CapsLockDelay`, 75 ms
/// on a stock one. The lock does not move, so no event is generated at all and no tap
/// can see the press: a fast tap of the switch is lost before CapsAwake has any say in
/// it. The delay is there to keep a brush of the key from turning on capitals, which is
/// not what the key is for here.
///
/// It belongs to the keyboard rather than to us, so the value it came with is read
/// before anything is imposed and written back when CapsAwake quits or the preference
/// goes off.
@MainActor
final class CapsLockDelayGuardian {
    /// Read once at launch, off the main actor because reading it walks the I/O
    /// registry.
    private var keyboardDelay: Int?

    /// Learns what this keyboard came with, then imposes what the user asked for.
    func adopt() async {
        keyboardDelay = await offMainActor { CapsLockDelaySettings.deviceDelay() }
        await apply()
    }

    /// Runs when the preference is off as well, which clears an override left behind by
    /// a run that ended without putting it back.
    func apply() async {
        guard let keyboardDelay else { return }
        let delay = UserPreferences.removeCapsLockDelay ? 0 : keyboardDelay
        let applied = await offMainActor { CapsLockDelaySettings.apply(delay: delay) }
        guard applied else {
            Log.error("Could not set the Caps Lock key delay to \(delay)ms")
            return
        }
        Log.info("Caps Lock key delay set to \(delay)ms; this keyboard's own is \(keyboardDelay)ms")
    }

    func restore() async {
        guard let keyboardDelay, UserPreferences.removeCapsLockDelay else { return }
        let restored = await offMainActor { CapsLockDelaySettings.apply(delay: keyboardDelay) }
        if restored {
            Log.info("Caps Lock key delay restored to \(keyboardDelay)ms")
        } else {
            Log.error("Could not restore the Caps Lock key delay to \(keyboardDelay)ms")
        }
    }
}
