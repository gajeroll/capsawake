import CapsAwakeCore
import SwiftUI

/// How far CapsAwake goes to keep the Mac awake.
///
/// Worded from the side of staying awake rather than of giving up, because that is
/// what the switch is for: these say what CapsAwake carries on through, and their far
/// ends are where it stands aside. Heat is the one that cannot be chosen, so it is
/// stated rather than offered — a Mac cooking itself is not a preference — but it is
/// stated, because a switch that turns itself off without saying why is a fault.
struct AwakeRangeSection: View {
    let model: AppModel

    @AppStorage(UserPreferenceKey.awakePastSleepTime) private var pastSleepTime = AwakePastSleepTime
        .always.rawValue
    @AppStorage(UserPreferenceKey.awakeBatteryFloor) private var batteryFloor = AwakeBatteryFloor
        .standard

    var body: some View {
        Section {
            Picker(selection: $pastSleepTime) {
                Text("awake_past_sleep_time_always").tag(AwakePastSleepTime.always.rawValue)
                Text("awake_past_sleep_time_lid_closed")
                    .tag(AwakePastSleepTime.whileLidClosed.rawValue)
                Text("awake_past_sleep_time_never").tag(AwakePastSleepTime.never.rawValue)
            } label: {
                Text("awake_past_sleep_time")
            }
            Picker(selection: $batteryFloor) {
                ForEach(AwakeBatteryFloor.offered, id: \.self) { percent in
                    Text(verbatim: "\(percent)%").tag(percent)
                }
                Text("awake_battery_floor_any").tag(0)
            } label: {
                Text("awake_battery_floor")
            }
        } header: {
            Text("settings_section_awake_range")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("awake_past_sleep_time_help")
                SleepTimeNow(model: model)
                Text("awake_battery_floor_help")
                Text("awake_thermal_help")
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// What the Mac's own sleep time currently is, since the setting above is about
/// reaching it and a Mac set never to sleep has none to reach.
struct SleepTimeNow: View {
    let model: AppModel

    var body: some View {
        switch model.sleepAfterMinutes {
        case .none: EmptyView()
        case .some(0): Text("awake_sleep_time_never")
        case .some(let minutes): Text("awake_sleep_time_now \(minutes)")
        }
    }
}
