//  NotificationsSettingsPage.swift
//  NOOP · Settings → Notifications: every alert NOOP can raise, on the wrist or on the phone. The wrist
//  master, the inactivity reminder, stress check-ins, the illness early-warning, strap battery alerts and
//  the strain-target nudge. Same keys and side effects the old Automations page had.

import SwiftUI
import StrandDesign

struct NotificationsSettingsPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore

    /// Inactivity reminder (#419) prefs. The buzz fires from the BLE offload path
    /// (BLEManager.maybeBuzzInactivity → SedentaryDetector); this page only edits what it reads.
    @StateObject private var inactivity = InactivityPrefs()
    /// Wrist-alerts master gate (#572), the key SedentaryDetector and the wrist-buzz posting read. On macOS
    /// it lives on the Notifications sidebar screen; on iOS this is its only switch. Default OFF.
    @AppStorage("notif.masterEnabled") private var wristAlertsMaster = false

    var body: some View {
        Form {
            #if os(iOS)
            Section {
                Toggle("Wrist alerts", isOn: $wristAlertsMaster)
            }
            #endif
            Section {
                inactivityRows
                stressRows
            } header: {
                Text("Reminders")
            }
            Section {
                Toggle("Illness signs", isOn: $behavior.illnessWatch)
                    .onChangeCompat(of: behavior.illnessWatch) { _ in
                        model.reevaluateIllness()
                        if behavior.illnessWatch { IllnessNotifier.requestAuthorization() }
                    }
                Toggle("Strain target", isOn: $behavior.strainTargetNudge)
                    .onChangeCompat(of: behavior.strainTargetNudge) { on in
                        if on {
                            StrainTargetNotifier.requestAuthorization()
                            // The repo.$days sink only fires on data changes: if today's target is already
                            // reached, evaluate now rather than at the next refresh.
                            model.evaluateStrainTarget()
                        }
                    }
                Toggle("Strap charge", isOn: $behavior.batteryAlerts)
                    .onChangeCompat(of: behavior.batteryAlerts) { on in
                        if on { BatteryNotifier.requestAuthorization() }
                    }
                if behavior.batteryAlerts {
                    Toggle("Charge forecast", isOn: $behavior.batteryPredictiveAlerts)
                }
            } header: {
                Text("Alerts")
            }
        }
        .settingsPage("Notifications")
    }

    // MARK: - Inactivity reminder (#419)

    @ViewBuilder private var inactivityRows: some View {
        Toggle("Movement reminder", isOn: $inactivity.enabled)
        if inactivity.enabled {
            if !wristAlertsMaster {
                // The reminder buzzes through the wrist-alerts gate; say so instead of failing silently.
                HStack(spacing: 8) {
                    Circle()
                        .fill(StrandPalette.settingsOrange)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("Wrist alerts are off")
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            Stepper(value: $inactivity.thresholdMinutes, in: 15...120, step: 15) {
                LabeledContent("After sitting") { Text("\(inactivity.thresholdMinutes) min").monospacedDigit() }
            }
            Stepper(value: $inactivity.reNudgeMinutes, in: 15...120, step: 15) {
                LabeledContent("Repeat every") { Text("\(inactivity.reNudgeMinutes) min").monospacedDigit() }
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
    }

    // MARK: - Stress check-ins

    /// v5 closed-loop check-in (master + sub toggles), default OFF. The keys mirror BiofeedbackPrefs, which
    /// the central detector (`AppModel.evaluateStress`) reads.
    @ViewBuilder private var stressRows: some View {
        Toggle("Stress check-ins", isOn: $behavior.stressCheckIn)
        if behavior.stressCheckIn {
            Toggle("Auto-nudge", isOn: $behavior.stressAutoNudge)
            Toggle("Respect quiet hours", isOn: $behavior.stressQuietHours)
            Toggle("Use my resonance pace", isOn: $behavior.stressUseResonancePace)
        }
    }

    // MARK: - Helpers

    private var activeStartBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: inactivity.activeStartMinutes) },
                set: { inactivity.activeStartMinutes = Self.minutes(from: $0) })
    }
    private var activeEndBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: inactivity.activeEndMinutes) },
                set: { inactivity.activeEndMinutes = Self.minutes(from: $0) })
    }
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
