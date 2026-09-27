import SwiftUI
import StrandDesign

// MARK: - Power saving (#477)
//
// Lifted out of Settings into its own screen: on iPhone it is a first-class More row (between Test
// Centre and Settings) and on macOS its own sidebar item, so the strap-battery levers are one tap away
// instead of buried in the middle of the Settings scroll. The controls, their prefs and their wiring are
// UNCHANGED — `AppModel.applyPowerSaving()` still reads every value from `PuffinExperiment`, so moving
// the surface cannot alter behaviour.
//
// The master gates the sub-options: the threshold, "Pause HRV capture" and "Low refresh" only
// appear (and only apply) while Power saving is on — `applyPowerSaving` ANDs each one with the master.
struct PowerSavingView: View {
    @EnvironmentObject var model: AppModel

    @AppStorage(PuffinExperiment.powerSavingKey) private var powerSavingEnabled = false
    @AppStorage(PuffinExperiment.powerSavingBatteryPctKey) private var powerSavingPct = 20
    /// Stored INVERTED so the default (absent = false) reads as "HRV pause on". The toggle shows `!this`.
    @AppStorage(PuffinExperiment.pauseHrvDisabledKey) private var pauseHrvDisabled = false
    @AppStorage(PuffinExperiment.lowRefreshKey) private var lowRefreshEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Power saving mode", isOn: $powerSavingEnabled)
                    .onChangeCompat(of: powerSavingEnabled) { _ in model.applyPowerSaving() }
            }

            if powerSavingEnabled {
                Section {
                    // 10…35 in 5s. 35 buys one more step of strap life than the old 30 ceiling:
                    // the levers engage ~5% earlier in the discharge, at the cost of a slightly
                    // longer stretch of quieter syncing.
                    Picker("Kick in at (strap battery)", selection: $powerSavingPct) {
                        ForEach(Array(stride(from: 10, through: 35, by: 5)), id: \.self) { pct in
                            Text(verbatim: "\(pct)%").tag(pct)
                        }
                    }
                    .settingsPicker()
                    .onChangeCompat(of: powerSavingPct) { _ in model.applyPowerSaving() }
                }

                Section {
                    // HRV pause: a sub-option, ON by default when the master is on (stored inverted).
                    Toggle("Pause HRV capture",
                           isOn: Binding(get: { !pauseHrvDisabled }, set: { pauseHrvDisabled = !$0 }))
                        .onChangeCompat(of: pauseHrvDisabled) { _ in model.applyPowerSaving() }
                }

                Section {
                    // Low refresh: a sub-option that applies at ANY charge, not just below the threshold.
                    Toggle("Low refresh", isOn: $lowRefreshEnabled)
                        .onChangeCompat(of: lowRefreshEnabled) { _ in model.applyPowerSaving() }
                }
            }
        }
        .settingsPage("Power saving")
    }
}
