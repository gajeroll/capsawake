import AppKit
import CapsAwakeCore
import CapsAwakeSystem
import CapsAwakeUI
import Foundation
import ServiceManagement

/// Wires the app together and turns the state machine's effects into system calls.
///
/// Everything that watches the Mac or talks to it lives in a collaborator beside this
/// file; what is left here is the wiring, the app lifecycle, and `apply(_:)`. The rule
/// the collaborators are built around is that none of them change state: an observation
/// becomes an intent, the reducer decides, and the effects come back here.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    /// Observable state the SwiftUI scenes render.
    let model = AppModel()

    private lazy var store = SleepPreventionStore { [weak self] effects in
        self?.apply(effects)
    }

    private let privileged = PrivilegedClient()
    private let filter = CapsLockEventFilter()
    private let lidMonitor = LidMonitor()
    private let assertions = SleepAssertions()

    private lazy var capsLockSwitch = CapsLockSwitch(
        capsLock: CapsLockController(),
        filter: filter
    )
    private lazy var dedicatedMode = DedicatedModeSupervisor(filter: filter)
    private let settingsWindow = SettingsWindowPresenter()
    private let daemon = DaemonRegistrar()
    private let notifier = UserNotifier()
    private let capsLockDelay = CapsLockDelayGuardian()
    private let preferences = PreferenceWatcher()
    private let sleepTimer = SleepTimerCache()
    private let power = PowerEnvironmentMonitor()
    private let session = SessionAccessibilityMonitor()

    private var reconcileTimer: Timer?
    private var pendingDisplaySleepTask: Task<Void, Never>?
    private var capitalsRecordingTask: Task<Void, Never>?
    private var isTerminating = false
    /// `applicationShouldTerminate` may answer only once. The completion task and the
    /// grace-period task both want to, and AppKit does not document a second reply.
    private var terminationReplied = false
    private var lastEnvironmentSnapshot = ""

    /// How long Settings waits for the press that sets the capitals combination. The
    /// wait is bounded because while it lasts the key switches nothing, so a Settings
    /// window left open must not leave it dead.
    private static let capitalsRecordingTimeout: Duration = .seconds(10)
    private static let reconcileInterval: TimeInterval = 5
    /// The daemon may still be coming up, so quitting does not wait on it forever.
    private static let terminationGrace: Duration = .seconds(3)

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserPreferences.registerDefaults()
        NSApp.setActivationPolicy(.accessory)

        wireModel()
        wireCapsLockSwitch()
        wireFilter()
        wireLidMonitor()
        wireDedicatedMode()
        wireSleepTimer()
        wirePreferences()
        settingsWindow.install()
        settingsWindow.onClose = { [weak self] in
            // Nothing is left to show that a press is being waited for.
            self?.listenForCapitalsCombination(false)
        }

        wirePowerEnvironment()
        wireSessionAccessibility()
        capsLockSwitch.start()

        applyLaunchAtLoginPreference()
        dedicatedMode.refresh(prompt: UserPreferences.dedicatedMode)

        // Seed the reducer with the stored preferences: state defaults match the
        // preference defaults, so without this a customised setting would not be
        // honoured until the user changed something.
        store.dispatch(.preferenceChanged(preferencesSnapshot()))
        store.dispatch(.startup)
        startReconcileTimer()

        Task {
            await capsLockDelay.adopt()
            await reconcileAtStartup()
        }

        Log.info("CapsAwake started")
    }

    /// Wait for sleep prevention to clear before quitting so a crash-style exit cannot
    /// leave `SleepDisabled` stuck on disk.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true
        stopWatchingTheEnvironment()
        pendingDisplaySleepTask?.cancel()
        capitalsRecordingTask?.cancel()
        filter.stop()
        lidMonitor.stop()
        assertions.hold(false)

        Task {
            // The lit lock is CapsAwake's sleep-prevention indicator, and with the
            // app gone nothing strips the capitals it implies — quitting must not
            // leave the user typing capitals with no way to switch them off. A
            // crash still leaves it lit, and the next launch adopts that.
            if store.state.dedicatedModeEnabled, store.state.capsLockLEDOn != false {
                await capsLockSwitch.clearLock()
            }
            // Next, because the delay is the one thing here that belongs to the
            // keyboard rather than to us and a hung daemon must not cost the user
            // their setting.
            await capsLockDelay.restore()
            try? await privileged.setSleepDisabled(false)
            try? await privileged.setEnergyMode(nil)
            finishTerminating()
        }
        // Bound the wait so a hung daemon cannot strand the quit.
        Task {
            try? await Task.sleep(for: Self.terminationGrace)
            finishTerminating()
        }
        return .terminateLater
    }

    /// Answers the deferred termination exactly once. Both tasks run on the main actor,
    /// so the flag needs no lock. `isTerminating` cannot serve this: it is already true
    /// before either task starts.
    private func finishTerminating() {
        guard !terminationReplied else { return }
        terminationReplied = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    /// Stops everything that watches the Mac and can put work back on the main actor.
    ///
    /// Quitting is not instant: the reply is deferred while the daemon is asked to put
    /// `SleepDisabled` back. A reconcile tick landing inside that window would read the
    /// setting we had just cleared, find it disagreeing with a state where `desired` is
    /// still true, and write it straight back on — leaving the Mac unable to sleep after
    /// CapsAwake had gone. Each handler checks `isTerminating` as well, because they hop
    /// to the main actor and one can be in flight when its timer is invalidated.
    private func stopWatchingTheEnvironment() {
        reconcileTimer?.invalidate()
        reconcileTimer = nil
        power.stop()
        session.stop()
        capsLockSwitch.stop()
        dedicatedMode.stop()
        preferences.stop()
        sleepTimer.stop()
        settingsWindow.stop()
    }

    /// Opens Settings when the app is launched again while already running.
    ///
    /// This is the way back for anyone who hid the menu bar icon: with the icon gone
    /// the app has no visible interface at all, and reopening it from Finder is the
    /// only gesture left.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        Log.debug("Reopen requested; hasVisibleWindows=\(flag)")
        openSettings()
        return true
    }

    // MARK: - Wiring

    private func wireModel() {
        model.onToggleRequested = { [weak self] in
            self?.toggleFromUser()
        }
        model.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        model.onRecordCapitalsShortcut = { [weak self] listen in
            self?.listenForCapitalsCombination(listen)
        }
        model.onSetCapitalsLocked = { [weak self] locked in
            // The capitals switch in the menu and in Settings is the capitals
            // combination by another route, so it ends in the same place: the request
            // the filter answers by adding capitals to what is typed.
            self?.filter.setCapsLockTyping(locked)
        }
        model.onOpenAccessibilitySettings = {
            SystemSettingsLink.openAccessibility()
        }
        model.onOpenLoginItemsSettings = {
            SMAppService.openSystemSettingsLoginItems()
        }
        model.onRestart = { [weak self] in
            self?.restart()
        }
        model.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func wireCapsLockSwitch() {
        capsLockSwitch.isFilterActive = { [weak self] in self?.filter.isActive ?? false }
        capsLockSwitch.desiredLock = { [weak self] in
            guard let self else { return false }
            return SleepPreventionReducer.capsLockLEDTarget(self.store.state)
        }
        capsLockSwitch.knownLock = { [weak self] in self?.store.state.capsLockLEDOn }
        capsLockSwitch.onSwitchPressed = { [weak self] lockOn in
            self?.store.dispatch(.externalCapsLockChanged(lockOn))
        }
        capsLockSwitch.onLockObserved = { [weak self] lockOn in
            self?.store.dispatch(.capsLockLEDObserved(lockOn))
        }
        capsLockSwitch.onPressWithoutMovement = { [weak self] in
            guard let self else { return }
            self.store.dispatch(.userToggled(!self.store.state.desired))
        }
        capsLockSwitch.onCombinationRecorded = { [weak self] held in
            self?.recordCapitalsCombination(held)
        }
        capsLockSwitch.onInputSourceChanged = { [weak self] in
            self?.store.dispatch(.inputSourceChanged)
        }
    }

    private func wireFilter() {
        filter.capitalsModifiers = UserPreferences.capitalsModifiers
        filter.shiftTypesSmallLetters = UserPreferences.shiftTypesSmallLetters
        // The tap callback already runs on the main actor.
        filter.onUserCapsLockKeyPress = { [weak self] lockOn in
            self?.store.dispatch(.externalCapsLockChanged(lockOn))
        }
        filter.onCapsLockTypingChanged = { [weak self] requested in
            Log.debug("Capitals combination: locked to capitals \(requested ? "on" : "off")")
            // The press flipped the hardware lock on its way in. The reducer writes it
            // back at once; this only keeps the poll from reading that as the switch.
            self?.capsLockSwitch.expectLockEcho()
            self?.store.dispatch(.capsLockTypingChanged(requested))
        }
        filter.onCombinationRecorded = { [weak self] held in
            self?.recordCapitalsCombination(held)
        }
    }

    private func wireLidMonitor() {
        lidMonitor.onClamshellChanged = { [weak self] closed in
            guard let self else { return }
            self.store.dispatch(.clamshellChanged(closed))
            self.refreshClamshellSleepPolicy()
        }
        lidMonitor.onExternalDisplayChanged = { [weak self] connected in
            guard let self else { return }
            self.store.dispatch(.externalDisplayChanged(connected))
            self.refreshClamshellSleepPolicy()
        }
        lidMonitor.start()
        refreshClamshellSleepPolicy()
    }

    private func wireDedicatedMode() {
        dedicatedMode.onStatusChanged = { [weak self] ready, enabled in
            self?.store.dispatch(.dedicatedFilterChanged(ready: ready, enabled: enabled))
        }
    }

    private func wireSleepTimer() {
        sleepTimer.onChange = { [weak self] minutes in
            self?.model.sleepAfterMinutes = minutes
        }
    }

    private func wirePreferences() {
        preferences.onChange = { [weak self] changes in
            self?.preferencesChanged(changes)
        }
        preferences.start()
    }

    /// Wired and seeded before `.startup`, so the reducer knows whether the session
    /// can be reached before it adopts anything — a lit lock read at launch behind a
    /// locked screen may be someone's own caps for their password, not the switch.
    private func wireSessionAccessibility() {
        session.onChange = { [weak self] snapshot in
            guard let self, !self.isTerminating else { return }
            self.store.dispatch(.sessionAccessibilityChanged(snapshot))
        }
        session.start()
        store.dispatch(.sessionAccessibilityChanged(session.current))
    }

    // MARK: - Reconciling

    private func startReconcileTimer() {
        reconcileTimer?.invalidate()
        reconcileTimer = repeatingTimer(every: Self.reconcileInterval, tolerance: 1) {
            [weak self] in
            guard let self, !self.isTerminating else { return }
            self.reconcileEnvironment()
            self.store.dispatch(.reconcileTick)
        }
    }

    private func reconcileEnvironment() {
        // Safety net only: LidMonitor owns the live path. Always go through intents.
        lidMonitor.poll()
        session.poll()
        refreshClamshellSleepPolicy()
        verifySleepDisabled()
        reportDaemonApproval()
        reportIdleTime()
        dedicatedMode.poll()
        logEnvironmentIfChanged()
    }

    /// Measures how long the keyboard has gone untouched against the Mac's own sleep
    /// time, for the user who asked to be let go of at the moment the Mac would have
    /// slept by itself.
    ///
    /// Only while there is something to let go of and someone who asked. The decision
    /// itself belongs to the reducer, which is why the reading is sent on rather than
    /// acted on here.
    private func reportIdleTime() {
        guard store.state.desired else { return }
        guard UserPreferences.awakePastSleepTime != .always else { return }
        guard let idle = InputIdleTime.seconds() else { return }
        let source: PowerSource = store.state.onBattery ? .battery : .adapter
        store.dispatch(
            .idleObserved(
                seconds: Int(idle),
                sleepAfterMinutes: sleepTimer.minutes(for: source),
                displayAsleep: DisplayPowerReader.isAsleep()
            )
        )
    }

    /// Checks the machine rather than what we remember writing.
    ///
    /// `sleepDisabledApplied` was only ever set from our own writes, so anything that
    /// put the setting back went unnoticed: the daemon exiting with the last client,
    /// being replaced by an update, another tool, a crash. The Mac would then sleep at
    /// the next idle timeout or as soon as the lid closed while CapsAwake still showed
    /// itself as on — a failure that only appears after a long stretch of nothing
    /// happening, which is exactly when nobody is watching.
    ///
    /// Only the one direction is worth policing. A machine that says sleep is disabled
    /// while we are off may simply have been set that way by its owner, and correcting
    /// that would fight the baseline the daemon is keeping for them.
    private func verifySleepDisabled() {
        guard store.state.sleepDisabledApplied else { return }
        guard PowerSettingsReader.sleepDisabled() == false else { return }
        Log.error("Sleep prevention was lost underneath us; re-applying")
        store.dispatch(.sleepDisabledObserved(false))
    }

    private func reportDaemonApproval() {
        let needsApproval = daemon.currentApproval() == .required
        // Approved, and still nothing can be written: the registration may have gone
        // away under an app that never changed, which the staleness check cannot see.
        if !needsApproval, store.state.privilegedError {
            daemon.repairIfStuck()
        }
        guard needsApproval != store.state.daemonNeedsApproval else { return }
        store.dispatch(.daemonApprovalChanged(needsApproval: needsApproval))
    }

    private func refreshClamshellSleepPolicy() {
        store.dispatch(.clamshellSleepPolicyChanged(ClamshellReader.causesSleep()))
        model.render(store.state)
    }

    /// Logged on change only. A heartbeat every 5 seconds buried the transitions that
    /// are actually worth reading.
    private func logEnvironmentIfChanged() {
        let snapshot = """
            led=\(store.state.capsLockLEDOn.map(String.init) ?? "nil") \
            desired=\(store.state.desired) trusted=\(AccessibilityPermission.isTrusted) \
            tap=\(filter.isActive) \
            lid=\(store.state.clamshellClosed.map(String.init) ?? "nil") \
            external=\(store.state.externalDisplayConnected.map(String.init) ?? "nil")
            """
        guard snapshot != lastEnvironmentSnapshot else { return }
        lastEnvironmentSnapshot = snapshot
        Log.debug("env \(snapshot)")
    }

    /// Adopts the two things that outlive the process: the Caps Lock LED and the system
    /// `SleepDisabled` setting.
    ///
    /// Order matters. The LED is the user's switch, so it is read first and a lit LED
    /// means sleep prevention should be on. Only then is `SleepDisabled` compared, which
    /// clears a value orphaned by a previous crash. Running these concurrently let them
    /// race to opposite conclusions.
    private func reconcileAtStartup() async {
        if let led = await capsLockSwitch.adoptLockAtLaunch() {
            if led {
                Log.info("Caps Lock was already on at launch; adopting it as the switch")
                store.dispatch(.externalCapsLockChanged(true))
            } else {
                store.dispatch(.capsLockLEDObserved(false))
            }
        }

        // The work below exists to clear orphans. Once the LED has turned the switch
        // on, the sync above is already driving the writes, and reading the settings
        // back would race those writes and duplicate them.
        guard !store.state.desired else { return }

        // A crash can leave an Energy Mode we imposed in place. The daemon kept the
        // baseline on disk, and no-ops when there is nothing to undo.
        try? await privileged.setEnergyMode(nil)

        guard let disabled = await privileged.currentSleepDisabled(), disabled else { return }
        Log.info("Observed SleepDisabled=true at launch; reconciling against desired=false")
        store.dispatch(.sleepDisabledObserved(true))
    }

    // MARK: - The environment

    private func wirePowerEnvironment() {
        power.onPowerChanged = { [weak self] reading in
            guard let self, !self.isTerminating else { return }
            self.store.dispatch(
                .batteryChanged(percent: reading.percent, onBattery: reading.onBattery)
            )
        }
        power.onPowerSourceChanged = { [weak self] source in
            // The Mac's sleep time is kept per power source and the two often differ.
            self?.sleepTimer.refresh(source: source)
        }
        power.onThermalChanged = { [weak self] level in
            self?.store.dispatch(.thermalChanged(level))
        }
        power.onSupportedModesChanged = { [weak self] modes in
            guard let self else { return }
            self.model.energy.supportedModes = modes
            self.store.dispatch(.preferenceChanged(self.preferencesSnapshot()))
        }
        power.onDisplayWake = { [weak self] in
            // Do not trust the polled store value: lid-open wakes the display before
            // the safety poll would notice, and a stale `clamshellClosed == true` would
            // re-request display sleep on an open lid.
            guard ClamshellReader.isClosed() == true else { return }
            self?.store.dispatch(.displayWokeWhileLidClosed)
        }
        power.onSystemWake = { [weak self] in
            // A keyboard can come back from sleep as a new service, holding the delay
            // it shipped with, so impose ours again rather than assume it survived.
            Task { await self?.capsLockDelay.apply() }
        }
        power.start()
    }

    /// The stored preferences, minus what this Mac cannot do. Macs without an Energy
    /// Mode must never have `pmset powermode` written to them.
    private func preferencesSnapshot() -> PreferencesSnapshot {
        var snapshot = UserPreferences.snapshot()
        if !model.energy.isSupported {
            snapshot.energyModePlan = nil
        }
        return snapshot
    }

    // MARK: - The user

    private func toggleFromUser() {
        Task {
            guard let current = await capsLockSwitch.currentLock() else { return }
            store.dispatch(.userToggled(!current))
        }
    }

    private func openSettings() {
        // Settings quotes the Mac's sleep time back at the user, so read it again
        // rather than showing whatever it was when the window last had a reason to.
        sleepTimer.refresh(source: store.state.onBattery ? .battery : .adapter)
        settingsWindow.open()
    }

    /// Waits for the user to press the combination they want for capitals, rather than
    /// asking them to describe it.
    ///
    /// Whichever path is watching the keyboard does the listening — the event tap while
    /// it is running, the `NSEvent` monitors otherwise — so the combination is recorded
    /// from a real press and works without Accessibility permission.
    private func listenForCapitalsCombination(_ listen: Bool) {
        capitalsRecordingTask?.cancel()
        capitalsRecordingTask = nil
        model.isRecordingCapitalsShortcut = listen
        filter.isRecording = listen
        capsLockSwitch.isRecording = listen
        guard listen else { return }
        capitalsRecordingTask = Task { [weak self] in
            try? await Task.sleep(for: Self.capitalsRecordingTimeout)
            guard !Task.isCancelled else { return }
            Log.debug("Capitals combination: gave up waiting for a press")
            self?.listenForCapitalsCombination(false)
        }
    }

    /// The press that was recorded belonged to neither switch, but it still flipped the
    /// hardware lock on its way in, so the lock is put back where sleep prevention wants
    /// it.
    private func recordCapitalsCombination(_ held: CapsLockModifiers) {
        defer { capsLockSwitch.putLockBack() }
        guard !held.isEmpty else {
            // Caps Lock on its own is CapsAwake's switch and cannot also be capitals,
            // so nothing is recorded and the wait carries on rather than ending in a
            // setting the user did not ask for.
            Log.debug("Capitals combination: Caps Lock on its own is not a combination")
            return
        }
        Log.info("Capitals combination recorded: \(held.shortcutSymbols)")
        UserPreferences.capitalsModifiers = held
        filter.capitalsModifiers = held
        listenForCapitalsCombination(false)
    }

    private func preferencesChanged(_ changes: Set<PreferenceChange>) {
        if changes.contains(.launchAtLogin) || changes.contains(.dedicatedMode) {
            applyLaunchAtLoginPreference()
        }
        if changes.contains(.capitalsModifiers) {
            filter.capitalsModifiers = UserPreferences.capitalsModifiers
        }
        if changes.contains(.shiftTypesSmallLetters) {
            filter.shiftTypesSmallLetters = UserPreferences.shiftTypesSmallLetters
        }
        if changes.contains(.dedicatedMode) {
            dedicatedMode.refresh(prompt: UserPreferences.dedicatedMode)
        }
        if changes.contains(.reducerInput) {
            store.dispatch(.preferenceChanged(preferencesSnapshot()))
            sleepTimer.refresh(source: store.state.onBattery ? .battery : .adapter)
        }
        if changes.contains(.capsLockDelay) {
            Task { await capsLockDelay.apply() }
        }
    }

    private func applyLaunchAtLoginPreference() {
        if daemon.synchronize() == .required {
            store.dispatch(.daemonApprovalChanged(needsApproval: true))
        } else {
            reportDaemonApproval()
        }
        do {
            if UserPreferences.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.error("Launch at login error: \(error.localizedDescription)")
        }
    }

    /// Relaunches the app, which is the reliable way to pick up a code signature or
    /// permission change that macOS only reads at process start.
    private func restart() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Effects

    /// Effects run independently. Awaiting them in order meant a slow privileged call
    /// delayed the status update that the reducer emitted after it, so the menu bar
    /// could sit on a stale icon indefinitely.
    private func apply(_ effects: [Effect]) {
        // A reconcile that changed nothing still re-emits `showStatus`, so only a list
        // with real work in it is worth a log line.
        if effects.contains(where: { if case .showStatus = $0 { false } else { true } }) {
            Log.debug(
                """
                desired=\(store.state.desired) \
                capitals=\(store.state.capsLockTypingRequested) effects=\(effects)
                """
            )
        }

        // The assertions follow the switch, not the effect list.
        //
        // They used to be taken on `.setSleepDisabled`, which the reducer emits only
        // when the applied flag disagrees with what is wanted. While the daemon is
        // unreachable that flag never becomes true, so turning the switch *off* agreed
        // with it, emitted nothing, and left the assertions held — CapsAwake going on
        // keeping the Mac awake with its own switch off and its icon reading idle.
        // They are ours, they cost nothing, and `hold` is idempotent, so the honest
        // thing is to mirror the state on every pass.
        assertions.hold(SleepPreventionReducer.effectiveDesired(store.state))

        for effect in effects {
            switch effect {
            case .showStatus(let presentation):
                model.render(store.state)
                notifier.warnIfBlockedWhileHidden(presentation)

            case .setSleepDisabled(let disabled):
                // Not awaited: the assertions above already stand, so sleep prevention
                // does not wait on the daemon to answer.
                Task { await applySleepDisabled(disabled) }

            case .setCapsLockLED(let on):
                capsLockSwitch.write(lock: on)

            case .requestDisplaySleep(let afterSeconds):
                scheduleDisplaySleep(afterSeconds: afterSeconds)

            case .setEnergyMode(let plan):
                Task { await applyEnergyMode(plan) }

            case .notifyUser(let kind):
                Task { await notifier.notify(kind) }
            }
        }
    }

    private func applySleepDisabled(_ disabled: Bool) async {
        do {
            try await privileged.setSleepDisabled(disabled)
            store.dispatch(.sleepDisabledConfirmed(disabled))
        } catch {
            Log.error("setSleepDisabled failed: \(error.localizedDescription)")
            store.dispatch(.sleepDisabledFailed)
        }
    }

    /// A failed Energy Mode write is logged rather than surfaced: sleep prevention
    /// itself is unaffected, and the reducer stops retrying on its own.
    private func applyEnergyMode(_ plan: EnergyModePlan?) async {
        do {
            try await privileged.setEnergyMode(plan)
            store.dispatch(.energyModeConfirmed(plan))
        } catch {
            Log.error("setEnergyMode failed: \(error.localizedDescription)")
            store.dispatch(.energyModeFailed(plan))
        }
    }

    private func scheduleDisplaySleep(afterSeconds: Double) {
        pendingDisplaySleepTask?.cancel()
        pendingDisplaySleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(afterSeconds))
            guard !Task.isCancelled else { return }
            await self?.applyDisplaySleep()
        }
    }

    private func applyDisplaySleep() async {
        // Needs no root, so it does not go through the daemon: display sleep on lid
        // close keeps working even while the daemon cannot be spawned.
        let slept = await offMainActor { DisplaySleeper.requestNow() }
        store.dispatch(slept ? .displaySleepCompleted : .displaySleepFailed)
    }
}
