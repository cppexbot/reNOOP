import SwiftUI
import StrandDesign

/// Automations — turn the strap's physical inputs (double-tap, wrist on/off) and live biometrics
/// into actions (Shortcuts, and Mac-only screen lock) and haptic coaching. All on-device.
struct AutomationsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var behavior: BehaviorStore
    // PERF: this screen does NOT observe `LiveState`. Its only live-dependent pixel is the "Strap
    // bonded / not connected" row in the double-tap section, which is the `BondStateRow` leaf that owns
    // its own `@EnvironmentObject live`. Observing `live` at this level would re-render the whole
    // automations list on every ~1 Hz strap tick (bond state changes only rarely); scoping it means a
    // tick re-renders just the one row.
    /// Deep-link into the experimental Rhythm visualization (it self-gates on its own consent).
    @EnvironmentObject var router: NavRouter

    /// v5 cycle-awareness opt-in (default OFF — the most sensitive health category, manual-first).
    @AppStorage(AppModel.cycleAwarenessKey) private var cycleAwareness = false
    /// #hide-cycle: the user's "not for me" opt-out (never age-based). Master visibility control lives here
    /// so it stays reachable to un-hide even after the offer is gone from Today + Health.
    @AppStorage(AppModel.cycleAwarenessHiddenKey) private var cycleHidden = false

    /// Whether the cycle-awareness opt-in is offered for this profile (#801). Delegates to the shared
    /// ``ProfileStore/cycleAwarenessApplies`` gate (mirrors HealthView's opt-in gate) so a male profile
    /// can't enable the feature here when it can't see the Health card either.
    private var cycleOptInApplies: Bool { model.profile.cycleAwarenessApplies }
    /// v5 Rhythm experimental gate (the screen still shows its own consent clickwrap when opened).
    @AppStorage(RhythmConsent.enabledKey) private var rhythmEnabled = false
    /// Inactivity reminder (#419) — UI-local store, persisted in UserDefaults. The buzz itself fires
    /// from the BLE offload path (BLEManager.maybeBuzzInactivity → the shipped SedentaryDetector); this
    /// screen only edits the prefs the engine reads.
    @StateObject private var inactivity = InactivityPrefs()
    #if os(iOS)
    /// Wrist-alerts master gate (PR #572). On iOS the NotificationSettingsView (and its store) are
    /// excluded by project.yml, so `notif.masterEnabled` — the key SedentaryDetector + the wrist-buzz
    /// posting read — has no UI to flip and is stuck at its default OFF. Bind the SAME raw key here so
    /// iPhone users can actually turn wrist alerts on. Default OFF, matching the store's default.
    @AppStorage("notif.masterEnabled") private var wristAlertsMaster = false
    #endif

    // #haptics (#1115): per-event toggles for NOOP's IN-SESSION strap buzzes. Default ON (opt-out) — these
    // are feedback to a feature you started, so a fresh install buzzes as before and a user turns off any
    // cue. Ambient cues (inactivity / stress / coaching) keep their own opt-in cards; double-tap is gated by
    // its action picker. Same keys the buzz sites read via HapticPrefs (which also defaults an unset key on).
    @AppStorage(HapticPrefs.breathing) private var breathingHaptic = true
    @AppStorage(HapticPrefs.intervals) private var intervalsHaptic = true
    @AppStorage(HapticPrefs.liveSession) private var liveSessionHaptic = true
    @AppStorage(HapticPrefs.workout) private var workoutHaptic = true

    var body: some View {
        Form {
            #if os(iOS)
            wristAlertsSection
            #endif
            doubleTapSection
            if !model.moments.isEmpty {
                momentsSection
            }
            hapticsSection
            wearSection
            coachingSections
            // #766: the strap's silent wake-alarm used to sit here, which let users conflate it with the
            // wind-down reminder. It's moved to the dedicated Alarms screen (SmartAlarmView) so every
            // wake/wind-down control lives in one place. Automations is just inputs-to-actions now.
            inactivitySection
            illnessSection
            healthInsightsSection
            batterySection
            strainTargetSection
        }
        .settingsPage("Automations")
    }

    // MARK: - Wrist alerts master (iOS only — PR #572)

    #if os(iOS)
    /// The master switch for wrist-buzz notifications. On macOS this lives in its own Notifications
    /// screen; that screen is excluded from the iOS target, so without this the gate is unreachable on
    /// iPhone and every wrist alert (inactivity, app notifications) stays silently off. Binds the same
    /// `notif.masterEnabled` key the SedentaryDetector and the notification posting read.
    private var wristAlertsSection: some View {
        Section {
            Toggle("Enable wrist alerts", isOn: $wristAlertsMaster)
        } header: {
            Text("Wrist alerts")
        }
    }
    #endif

    // MARK: - Haptics (#1115)

    /// Per-event opt-in toggles for NOOP's in-session strap buzzes (all default OFF, existing installs
    /// migrated on). Parity with the Android Automations "Haptics" section. Ambient cues and the
    /// Android-only call/notification buzzes are not shown here (the latter can't exist on Apple).
    private var hapticsSection: some View {
        Section {
            Toggle("Breathing pacer", isOn: $breathingHaptic)
            Toggle("Interval timer", isOn: $intervalsHaptic)
            Toggle("Live Session cues", isOn: $liveSessionHaptic)
            Toggle("Workout start & end", isOn: $workoutHaptic)
        } header: {
            Text("Haptics")
        }
    }

    // MARK: - Double tap

    private var doubleTapSection: some View {
        Section {
            Picker("When I double-tap", selection: $behavior.doubleTapAction) {
                ForEach(doubleTapOptions) { Text($0.label).tag($0) }
            }
            .settingsPicker()
            if behavior.doubleTapAction == .runShortcut {
                TextField("Shortcut name", text: $behavior.doubleTapShortcut)
            }
            Button("Test action") {
                model.runMacAction(behavior.doubleTapAction, shortcut: behavior.doubleTapShortcut)
            }
            .disabled(behavior.doubleTapAction == .none)
            // Live-observing leaf: re-renders on its own when the strap's bond state flips, so a
            // ~1 Hz strap tick doesn't re-render the whole automations list (scroll-stutter isolation).
            BondStateRow()
        } header: {
            Text("Double-tap")
        }
    }

    private var momentsSection: some View {
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
    private static let momentFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        // Keep the "EEE d MMM ·" layout but honor the device's 12-/24-hour clock (#337): the "j"
        // template resolves to a 12-hour pattern (contains "a") only where the user prefers it.
        let uses24h = !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: AppLanguage.activeLocale) ?? "H").contains("a")
        f.dateFormat = "EEE d MMM · " + (uses24h ? "HH:mm" : "h:mm a")
        return f
    }()

    // MARK: - Wear & presence

    private var wearSection: some View {
        Section {
            #if os(macOS)
            Toggle("Lock the Mac when I take the strap off", isOn: $behavior.autoLockOnWristOff)
            #endif
            LabeledContent("Run a Shortcut when taken off") {
                shortcutField(text: $behavior.wristOffShortcut)
            }
            LabeledContent("Run a Shortcut when put back on") {
                shortcutField(text: $behavior.wristOnShortcut)
            }
        } header: {
            Text("Wear & presence")
        }
    }

    // MARK: - Coaching

    @ViewBuilder private var coachingSections: some View {
        Section {
            Toggle("HR-zone coaching", isOn: $behavior.zoneCoaching)
        } header: {
            Text("Haptic coaching")
        }
        // v5 L3 closed-loop check-in (master + sub toggles). Default OFF, manual-first. The keys
        // mirror BiofeedbackPrefs, which the central detector (AppModel.evaluateStress) reads.
        Section {
            Toggle("Stress check-ins (haptic)", isOn: $behavior.stressCheckIn)
            if behavior.stressCheckIn {
                Toggle("Auto-nudge", isOn: $behavior.stressAutoNudge)
                Toggle("Respect quiet hours", isOn: $behavior.stressQuietHours)
                Toggle("Use my resonance pace", isOn: $behavior.stressUseResonancePace)
            }
        }
    }

    // MARK: - Inactivity reminder (#419)

    private var inactivitySection: some View {
        Section {
            Toggle("Enable inactivity reminder", isOn: $inactivity.enabled)
            if inactivity.enabled {
                if !notifMasterOn {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(StrandPalette.settingsOrange)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("Notifications are off, so this can't buzz yet. Turn on the master switch in Notifications to let it through.")
                            .font(.subheadline)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                Stepper(value: $inactivity.thresholdMinutes, in: 15...120, step: 15) {
                    LabeledContent("Sitting for") { Text("\(inactivity.thresholdMinutes) min").monospacedDigit() }
                }
                Stepper(value: $inactivity.reNudgeMinutes, in: 15...120, step: 15) {
                    LabeledContent("Re-nudge every") { Text("\(inactivity.reNudgeMinutes) min").monospacedDigit() }
                }
                Stepper(value: $inactivity.buzzLoops, in: 1...4, step: 1) {
                    LabeledContent("Buzz strength") { Text(verbatim: "\(inactivity.buzzLoops)×").monospacedDigit() }
                }
                Toggle("Only during active hours", isOn: $inactivity.activeHoursEnabled)
                if inactivity.activeHoursEnabled {
                    DatePicker("From", selection: activeStartBinding, displayedComponents: .hourAndMinute)
                        .accessibilityLabel("Active hours start")
                    DatePicker("To", selection: activeEndBinding, displayedComponents: .hourAndMinute)
                        .accessibilityLabel("Active hours end")
                }
            }
        } header: {
            Text("Inactivity reminder")
        }
    }

    /// The reused global notification master (notif.masterEnabled, default OFF) — drives the inert-feature
    /// warning so enabling the reminder while master is off isn't silently a no-op.
    private var notifMasterOn: Bool {
        UserDefaults.standard.object(forKey: "notif.masterEnabled") as? Bool ?? false
    }
    private var activeStartBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: inactivity.activeStartMinutes) },
                set: { inactivity.activeStartMinutes = Self.minutes(from: $0) })
    }
    private var activeEndBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: inactivity.activeEndMinutes) },
                set: { inactivity.activeEndMinutes = Self.minutes(from: $0) })
    }

    // MARK: - Illness early-warning

    private var illnessSection: some View {
        Section {
            Toggle("Watch for early-illness signs", isOn: $behavior.illnessWatch)
                .onChangeCompat(of: behavior.illnessWatch) { _ in
                    model.reevaluateIllness()
                    if behavior.illnessWatch { IllnessNotifier.requestAuthorization() }
                }
        } header: {
            Text("Illness early-warning")
        }
    }

    // MARK: - Health insights (v5: cycle awareness opt-in · experimental Rhythm)

    private var healthInsightsSection: some View {
        Section {
            // #801: cycle awareness reads the MENSTRUAL temperature shift, so the toggle is only
            // offered to profiles it applies to (gated the same way as the Health opt-in card,
            // not shown for male profiles). Keeps the two surfaces consistent: a profile that can't
            // see the Health card can't enable the feature from here either.
            if cycleOptInApplies {
                // #hide-cycle: the master visibility control — a USER opt-out, never age-based. Turning
                // it off hides the cycle-awareness offer on Today + Health AND stops active tracking;
                // turning it back on re-offers it. Reversible, so it is never a one-way door.
                Toggle("Show cycle awareness",
                       isOn: Binding(get: { !cycleHidden },
                                     set: { show in
                                         cycleHidden = !show
                                         if !show {
                                             cycleAwareness = false
                                             model.cycleAwarenessEnabled = false
                                             Task { await model.refreshV5Signals() }
                                         }
                                     }))
                if !cycleHidden {
                    Toggle("Cycle awareness", isOn: $cycleAwareness)
                        .onChangeCompat(of: cycleAwareness) { on in
                            model.cycleAwarenessEnabled = on
                            Task { await model.refreshV5Signals() }
                        }
                }
            }
            Toggle("Rhythm visualization (experimental)", isOn: $rhythmEnabled)
            if rhythmEnabled {
                Button("Open Rhythm") { router.openRhythm() }
            }
        } header: {
            Text("Health insights")
        }
    }

    // MARK: - Strap battery alerts

    private var batterySection: some View {
        Section {
            Toggle("Notify on low and full battery", isOn: $behavior.batteryAlerts)
                .onChangeCompat(of: behavior.batteryAlerts) { on in
                    if on { BatteryNotifier.requestAuthorization() }
                }
            if behavior.batteryAlerts {
                Toggle("Predictive runtime warning", isOn: $behavior.batteryPredictiveAlerts)
            }
        } header: {
            Text("Battery alerts")
        }
    }

    // MARK: - Strain target nudge (#593)

    private var strainTargetSection: some View {
        Section {
            Toggle("Notify when optimal strain is reached", isOn: $behavior.strainTargetNudge)
                .onChangeCompat(of: behavior.strainTargetNudge) { on in
                    if on {
                        StrainTargetNotifier.requestAuthorization()
                        // The repo.$days sink only fires on data changes, so if today's target is
                        // already reached, evaluate now rather than waiting for the next refresh
                        // (the reevaluateIllness idiom).
                        model.evaluateStrainTarget()
                    }
                }
        } header: {
            Text("Strain target")
        }
    }

    // MARK: - Helpers

    /// Double-tap actions offered in the picker. The "Lock the Mac" action can't work on iPhone
    /// (a third-party app can't lock iOS), so it's dropped there.
    private var doubleTapOptions: [MacActionKind] {
        #if os(iOS)
        MacActionKind.allCases.filter { $0 != .lockScreen }
        #else
        MacActionKind.allCases
        #endif
    }

    // `date(fromMinutes:)` / `minutes(from:)` stay: the inactivity active-hours pickers above use them.
    // (The strap-alarm time binding moved to SmartAlarmView with the rest of the alarm UI, #766.)
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// A Shortcut-name field, right-aligned in its row as Settings draws an editable value.
    private func shortcutField(text: Binding<String>) -> some View {
        TextField("Shortcut name", text: text, prompt: Text("Shortcut name"))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Live-observing leaf (scroll-stutter isolation)

/// The strap bond-status row in the double-tap section ("Strap bonded" / "Strap not connected"). It owns
/// its OWN `@EnvironmentObject live` so a ~1 Hz strap publish re-renders only this row, not the whole
/// automations list (the parent `AutomationsView` no longer observes `LiveState`).
private struct BondStateRow: View {
    @EnvironmentObject private var live: LiveState
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(live.bonded ? StrandPalette.settingsGreen : StrandPalette.settingsOrange)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(live.bonded ? LocalizedStringKey("Strap bonded") : LocalizedStringKey("Strap not connected"))
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }
}
