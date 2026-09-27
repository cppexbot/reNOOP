//  StrapSettingsSections.swift
//  NOOP · the strap's own settings. Settings → Devices lists them as one card of rows under the paired
//  devices, as the Watch app keeps a watch's settings under the watch; each row pushes a small page:
//  sync, power saving, double-tap, haptics, heart-rate broadcast. Same keys and the same BLE wiring the
//  old Sync, Power saving, Automations and Data Sources pages had.

import SwiftUI
import StrandDesign

// MARK: - The card on Devices

/// One row per strap setting, with its state in grey on the right.
struct StrapSettingsCard: View {
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage(PuffinExperiment.powerSavingKey) private var powerSavingEnabled = false
    @AppStorage(HrBroadcaster.defaultsKey) private var phoneBroadcast = false
    @AppStorage(PuffinExperiment.broadcastHrKey) private var strapBroadcast = false

    var body: some View {
        Section {
            #if os(iOS)
            SettingsLink(.strapSync, "Sync", icon: "arrow.triangle.2.circlepath", color: StrandPalette.settingsGreen)
            #endif
            SettingsLink(.powerSaving, "Power saving", icon: "battery.75percent", color: StrandPalette.settingsGreen,
                         value: onOff(powerSavingEnabled))
            SettingsLink(.doubleTap, "Double-tap", icon: "hand.tap.fill", color: StrandPalette.settingsBlue,
                         value: behavior.doubleTapAction.label)
            SettingsLink(.haptics, "Haptics", icon: "waveform", color: StrandPalette.settingsOrange)
            SettingsLink(.hrBroadcast, "Heart rate broadcast", icon: "dot.radiowaves.up.forward",
                         color: StrandPalette.settingsRed, value: onOff(phoneBroadcast || strapBroadcast))
        }
    }

    private func onOff(_ on: Bool) -> String { String(localized: on ? "On" : "Off") }
}

// MARK: - Pages

struct StrapSyncPage: View {
    var body: some View { Form { StrapSyncSection() }.settingsPage("Sync") }
}

struct PowerSavingPage: View {
    var body: some View { Form { PowerSavingSection() }.settingsPage("Power saving") }
}

struct DoubleTapPage: View {
    var body: some View { Form { StrapGesturesSection() }.settingsPage("Double-tap") }
}

struct HapticsPage: View {
    var body: some View { Form { StrapHapticsSection() }.settingsPage("Haptics") }
}

/// The phone broadcaster runs while this page is open.
struct HeartRateBroadcastPage: View {
    var body: some View {
        Form { HeartRateBroadcastSection() }
            .settingsPage("Heart rate broadcast")
            .modifier(PhoneHeartRateBroadcastHost())
    }
}

// MARK: - Sync

/// Screen-awake and Live Activity for a strap history sync (iOS only).
struct StrapSyncSection: View {
    /// `SyncKeepAwake` holds the screen awake for as long as a strap history sync runs.
    @AppStorage(ScreenIdle.strapSyncKeepAwakeKey) private var syncKeepScreenOn = false
    /// Strap-sync Live Activity, independent of the live-HR one.
    @AppStorage(UnitPrefs.syncLiveActivityKey) private var syncLiveActivityEnabled = true

    var body: some View {
        #if os(iOS)
        Section {
            Toggle("Keep screen on", isOn: $syncKeepScreenOn)
            Toggle("In Dynamic Island", isOn: $syncLiveActivityEnabled)
        }
        #endif
    }
}

// MARK: - Power saving (#477)

/// The strap-battery levers. The master gates the sub-options: the threshold, "Pause HRV capture" and
/// "Low refresh" only appear (and only apply) while Power saving is on — `AppModel.applyPowerSaving()`
/// ANDs each one with the master.
struct PowerSavingSection: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage(PuffinExperiment.powerSavingKey) private var powerSavingEnabled = false
    @AppStorage(PuffinExperiment.powerSavingBatteryPctKey) private var powerSavingPct = 20
    /// Stored INVERTED so the default (absent = false) reads as "HRV pause on". The toggle shows `!this`.
    @AppStorage(PuffinExperiment.pauseHrvDisabledKey) private var pauseHrvDisabled = false
    @AppStorage(PuffinExperiment.lowRefreshKey) private var lowRefreshEnabled = false

    var body: some View {
        Section {
            Toggle("Power saving mode", isOn: $powerSavingEnabled)
                .onChangeCompat(of: powerSavingEnabled) { _ in model.applyPowerSaving() }
            if powerSavingEnabled {
                Picker("Kick in at", selection: $powerSavingPct) {
                    ForEach(Array(stride(from: 10, through: 35, by: 5)), id: \.self) { pct in
                        Text(verbatim: "\(pct)%").tag(pct)
                    }
                }
                .settingsPicker()
                .onChangeCompat(of: powerSavingPct) { _ in model.applyPowerSaving() }
                Toggle("Pause HRV capture",
                       isOn: Binding(get: { !pauseHrvDisabled }, set: { pauseHrvDisabled = !$0 }))
                    .onChangeCompat(of: pauseHrvDisabled) { _ in model.applyPowerSaving() }
                // Low refresh applies at ANY charge, not just below the threshold.
                Toggle("Low refresh", isOn: $lowRefreshEnabled)
                    .onChangeCompat(of: lowRefreshEnabled) { _ in model.applyPowerSaving() }
            }
        }
    }
}

// MARK: - Double-tap

/// What a strap double-tap does, a test button, the bond state it needs, and the moments it marked.
struct StrapGesturesSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore

    var body: some View {
        Section {
            Picker("Action", selection: $behavior.doubleTapAction) {
                ForEach(doubleTapOptions) { Text($0.label).tag($0) }
            }
            .settingsPicker()
            if behavior.doubleTapAction == .runShortcut {
                TextField("Shortcut", text: $behavior.doubleTapShortcut)
            }
            if behavior.doubleTapAction != .none {
                Button("Test") {
                    model.runMacAction(behavior.doubleTapAction, shortcut: behavior.doubleTapShortcut)
                }
            }
        }

        if !model.moments.isEmpty {
            Section {
                ForEach(Array(model.moments.suffix(5).reversed().enumerated()), id: \.offset) { _, d in
                    Text(Self.momentFormatter.string(from: d))
                        .monospacedDigit()
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Button("Clear", role: .destructive) {
                    model.moments.removeAll()
                    UserDefaults.standard.removeObject(forKey: "moments")
                }
            } header: {
                Text("Recent moments")
            }
        }
    }

    /// The "Lock the Mac" action can't work on iPhone (a third-party app can't lock iOS), so it's dropped.
    private var doubleTapOptions: [MacActionKind] {
        #if os(iOS)
        MacActionKind.allCases.filter { $0 != .lockScreen }
        #else
        MacActionKind.allCases
        #endif
    }

    private static let momentFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        // "EEE d MMM ·" in the device's 12-/24-hour clock (#337): the "j" template resolves to a 12-hour
        // pattern (contains "a") only where the user prefers it.
        let uses24h = !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: AppLanguage.activeLocale) ?? "H").contains("a")
        f.dateFormat = "EEE d MMM · " + (uses24h ? "HH:mm" : "h:mm a")
        return f
    }()
}

// MARK: - Haptics (#1115)

/// Per-event toggles for NOOP's in-session strap buzzes (default ON, the keys `HapticPrefs` reads), plus
/// the HR-zone coaching buzz.
struct StrapHapticsSection: View {
    @EnvironmentObject private var behavior: BehaviorStore

    @AppStorage(HapticPrefs.breathing) private var breathingHaptic = true
    @AppStorage(HapticPrefs.intervals) private var intervalsHaptic = true
    @AppStorage(HapticPrefs.liveSession) private var liveSessionHaptic = true
    @AppStorage(HapticPrefs.workout) private var workoutHaptic = true

    var body: some View {
        Section {
            Toggle("Breathing pacer", isOn: $breathingHaptic)
            Toggle("Interval timer", isOn: $intervalsHaptic)
            Toggle("Live Session cues", isOn: $liveSessionHaptic)
            Toggle("Workout start & end", isOn: $workoutHaptic)
            Toggle("HR zones", isOn: $behavior.zoneCoaching)
        }
    }
}

// MARK: - Heart-rate broadcast

/// Owns the phone's BLE Heart Rate peripheral (0x180D / 0x2A37) for as long as the page it sits on is
/// open, and hands it to `HeartRateBroadcastSection` through the environment. Attached to the whole page,
/// never to the section: a List section appears and disappears as it scrolls, which would drop the radio.
struct PhoneHeartRateBroadcastHost: ViewModifier {
    @EnvironmentObject private var live: LiveState
    @AppStorage(HrBroadcaster.defaultsKey) private var broadcastHrEnabled = false

    /// The broadcaster's diagnostic sink forwards here, pointed at `live` on appear, so its lifecycle lines
    /// (advertised / who subscribed / why the radio refused) land in the same exported strap log.
    private final class LogSink { weak var live: LiveState? }
    private let logSink: LogSink
    @StateObject private var hrBroadcaster: HrBroadcaster

    init() {
        let sink = LogSink()
        self.logSink = sink
        _hrBroadcaster = StateObject(wrappedValue: HrBroadcaster(log: { [weak sink] line in
            // HrBroadcaster is @MainActor, so this closure only runs on the main actor.
            MainActor.assumeIsolated { sink?.live?.append(log: line) }
        }))
    }

    func body(content: Content) -> some View {
        content
            .environmentObject(hrBroadcaster)
            .onAppear {
                logSink.live = live
                hrBroadcaster.bind(to: live)
                if broadcastHrEnabled { hrBroadcaster.start() }
            }
            .onDisappear { hrBroadcaster.stop() }
    }
}

/// Broadcast the live HR from this phone (a local BLE sensor for a treadmill / Zwift / Peloton), or ask
/// the strap to advertise it itself.
struct HeartRateBroadcastSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var hrBroadcaster: HrBroadcaster

    @AppStorage(HrBroadcaster.defaultsKey) private var broadcastHrEnabled = false
    @AppStorage(PuffinExperiment.broadcastHrKey) private var strapBroadcastHrEnabled = false

    var body: some View {
        Section {
            Toggle("From this phone", isOn: $broadcastHrEnabled)
                .accessibilityLabel("Broadcast heart rate as a Bluetooth sensor")
                .onChangeCompat(of: broadcastHrEnabled) { on in
                    if on { hrBroadcaster.start() } else { hrBroadcaster.stop() }
                }
            if broadcastHrEnabled { phoneStatus }
            Toggle("From the strap", isOn: $strapBroadcastHrEnabled)
                .onChangeCompat(of: strapBroadcastHrEnabled) { model.ble.setBroadcastHr($0) }
        }
    }

    /// Honest live status: advertising vs starting, then a radio warning, or who's reading it.
    @ViewBuilder private var phoneStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(hrBroadcaster.advertising ? StrandPalette.settingsGreen : StrandPalette.settingsOrange)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(hrBroadcaster.advertising ? LocalizedStringKey("Broadcasting") : LocalizedStringKey("Starting…"))
        }
        if let note = hrBroadcaster.statusNote {
            Text(note).foregroundStyle(StrandPalette.statusWarning)
        } else if hrBroadcaster.subscriberCount > 0 {
            let n = hrBroadcaster.subscriberCount
            // Whole-phrase variants per count so translators never see a stitched plural.
            Text(n == 1 ? "1 device reading your heart rate" : "\(n) devices reading your heart rate")
                .foregroundStyle(StrandPalette.textSecondary)
        } else if let hr = live.heartRate {
            Text("Sharing \(hr) bpm. Waiting for a device to pair.")
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

// MARK: - Connection

/// Scan again, or drop the link: rows for the Add-a-device card.
struct StrapConnectionRows: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    var body: some View {
        Button("Re-scan") { model.scan() }
        if live.connected || live.bonded {
            Button("Disconnect", role: .destructive) { model.disconnect() }
        }
    }
}

// MARK: - Apple Watch

/// Opens the Apple Watch setup sheet (iOS; the watch reaches NOOP through Apple Health).
struct AppleWatchSetupRow: View {
    @State private var showSetup = false

    var body: some View {
        #if os(iOS)
        Button("Set up Apple Watch") { showSetup = true }
            .sheet(isPresented: $showSetup) {
                AppleWatchSetupView(onClose: { showSetup = false })
            }
        #endif
    }
}
