import AppKit
import CapsAwakeCore
import CapsAwakeSystem
import Foundation

/// What the Mac is running on and how hard it is finding it: the power source, the
/// battery level, the thermal state, and waking from sleep.
///
/// Everything here is reported rather than acted on. What to do about a hot Mac or a
/// low battery is the reducer's decision, and this only has to notice.
@MainActor
final class PowerEnvironmentMonitor {
    var onPowerChanged: ((PowerSourceReading) -> Void)?
    /// The power source itself changed, rather than just the level. Energy Mode
    /// capabilities and the Mac's sleep time are both kept per source.
    var onPowerSourceChanged: ((PowerSource) -> Void)?
    var onThermalChanged: ((ThermalLevel) -> Void)?
    /// Which Energy Modes this Mac offers, accumulated rather than replaced.
    var onSupportedModesChanged: ((Set<EnergyMode>) -> Void)?
    var onSystemWake: (() -> Void)?
    var onDisplayWake: (() -> Void)?

    private var batteryTimer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private var lastOnBattery: Bool?
    private var supportedModes: Set<EnergyMode> = []

    private let interval: TimeInterval

    /// A tolerance, because a timer with none asks macOS to wake the Mac exactly on the
    /// second — a strange thing to ask for repeatedly in an app about staying awake.
    private let tolerance: TimeInterval = 5

    init(interval: TimeInterval = 30) {
        self.interval = interval
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayWoke),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWoke),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // Unlike the rest, this one is posted from whatever queue macOS noticed the
        // temperature on, and a selector on a main-actor object called from there traps
        // the moment it touches anything. So: delivered on the main queue.
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportThermalState() }
        }

        batteryTimer = repeatingTimer(every: interval, tolerance: tolerance) { [weak self] in
            self?.readPower()
        }
        readPower()
        refreshSupportedModes()
    }

    func stop() {
        batteryTimer?.invalidate()
        batteryTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
    }

    /// Learns which Energy Modes this Mac offers.
    ///
    /// `pmset` reports the capabilities of the power source in use, so the modes are
    /// accumulated rather than replaced: High Power can be missing from the reading
    /// taken while running on battery, and a menu that gained and lost entries as the
    /// adapter came and went would be worse than one that is slightly generous. The
    /// reading forks `pmset`, so it stays off the main actor.
    func refreshSupportedModes() {
        Task { [weak self] in
            let modes = await offMainActor { EnergyModeSettings.supportedModes() }
            guard let self else { return }
            let merged = self.supportedModes.union(modes)
            guard merged != self.supportedModes else { return }
            self.supportedModes = merged
            self.onSupportedModesChanged?(merged)
        }
    }

    private func readPower() {
        guard let reading = PowerSourceReader.read() else { return }
        if reading.onBattery != lastOnBattery {
            lastOnBattery = reading.onBattery
            refreshSupportedModes()
            onPowerSourceChanged?(reading.onBattery ? .battery : .adapter)
        }
        onPowerChanged?(reading)
    }

    private func reportThermalState() {
        let level: ThermalLevel
        switch ProcessInfo.processInfo.thermalState {
        case .critical: level = .critical
        case .serious: level = .serious
        case .fair: level = .fair
        default: level = .nominal
        }
        onThermalChanged?(level)
    }

    @objc private func systemWoke() {
        onSystemWake?()
    }

    @objc private func displayWoke() {
        onDisplayWake?()
    }
}
