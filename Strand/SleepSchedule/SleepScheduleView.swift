//  SleepScheduleView.swift
//  NOOP · Sleep schedule — the strap alarm and the bedtime reminder as the iOS 26 Health app's Full
//  Schedule: the alarm switch on top, one card per schedule with "Edit" (a sheet with the dial), the next
//  wake, and Additional Details (the bedtime reminder). Opened from the Sleep tab's "Your Schedule".
//
//  Behaviour is the old Alarms screen's: the same stored keys, the same strap commands through
//  `AppModel.applySmartAlarm`, the same rejected-alarm (#34) and 5/MG (#864) warnings.

import SwiftUI
import StrandDesign
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SleepScheduleView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore

    /// #34: consecutive times the strap reported back a different alarm time than was sent (FrameRouter).
    @AppStorage("alarm.rejectStreak") private var alarmRejectStreak = 0

    @State private var reminderOn = WindDownNudge.isEnabled
    @State private var lead = WindDownNudge.leadMinutes
    /// Bumped after a write so the `WindDownNudge` values (UserDefaults, not observed) are read again.
    @State private var revision = 0
    @State private var editing: EditItem?
    @State private var showNotifDeniedAlert = false

    struct EditItem: Identifiable {
        let id = UUID()
        let edit: SleepScheduleEdit
    }

    private var inputs: SleepScheduleInputs {
        _ = revision
        return SleepScheduleStore.inputs(behavior: behavior, model: model)
    }

    var body: some View {
        let inputs = inputs
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                alarmSection
                SleepScheduleHeader(title: "Full Schedule")
                ForEach(SleepSchedule.entries(inputs)) { entry in
                    SleepScheduleEntryCard(entry: entry) { open(entry, inputs: inputs) }
                }
                addButton(inputs)
                SleepScheduleHeader(title: "Next Wake Up")
                SleepNextWakeCard(inputs: inputs)
                SleepScheduleHeader(title: "Additional Details")
                detailsCard
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, NoopMetrics.space3)
            .padding(.bottom, NoopMetrics.tabBarClearance)
            #if os(macOS)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            #endif
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("Full Schedule"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { item in
            SleepScheduleEditor(edit: item.edit, inputs: inputs) { stored in
                SleepScheduleStore.write(stored, over: inputs, behavior: behavior, model: model)
                revision += 1
            }
        }
        .onChangeCompat(of: behavior.smartAlarmEnabled) { _ in model.applySmartAlarm(userInitiated: true) }
        .alert(String(localized: "Notifications are off"), isPresented: $showNotifDeniedAlert) {
            Button(String(localized: "Open Settings")) { Self.openNotificationSettings() }
            Button(String(localized: "Not now"), role: .cancel) {}
        } message: {
            Text("Turn on notifications for NOOP in Settings to get your wind-down reminder.")
        }
        .onAppear(perform: openDemoEditor)
    }

    // MARK: - Strap alarm

    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SleepScheduleCard {
                Toggle(isOn: $behavior.smartAlarmEnabled) {
                    Text("Strap Alarm").font(StrandFont.pro(17))
                }
                .tint(StrandPalette.settingsGreen)
            }
            footnote(String(localized: "schedule.silentNote",
                            defaultValue: "The strap buzzes silently. For a loud alarm, use the Clock app."))
            // #864: a WHOOP 5/MG keeps the time but arms nothing until Experimental is on.
            if behavior.smartAlarmEnabled && model.whoop5Detected && !PuffinExperiment.isEnabled {
                warning(String(localized: "Alarm isn't armed on the strap"),
                        detail: String(localized: "WHOOP 5/MG needs Experimental mode on. Keep a backup alarm."))
            }
            // #34: only when the strap keeps refusing the alarm, never for a one-off readback quirk.
            if behavior.smartAlarmEnabled && alarmRejectStreak >= 2 {
                warning(String(localized: "Your strap isn't accepting the alarm"),
                        detail: String(localized: "Reset or recharge the strap, and use the Clock app until it takes."))
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(verbatim: text)
            .font(StrandFont.pro(13))
            .foregroundStyle(StrandPalette.textSecondary)
            .padding(.horizontal, 16)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func warning(_ title: String, detail: String? = nil) -> some View {
        NoticeCard(title: Text(verbatim: title), message: detail.map { Text(verbatim: $0) },
                   systemImage: "exclamationmark.triangle.fill", tone: .warning)
    }

    // MARK: - Schedules

    private func open(_ entry: SleepScheduleEntry, inputs: SleepScheduleInputs) {
        editing = EditItem(edit: SleepScheduleEdit(original: entry, days: Set(entry.days), bed: entry.bed,
                                                   wake: entry.wake,
                                                   alarm: entry.days.allSatisfy(SleepSchedule.effectiveAlarmDays(inputs.alarmDays).contains)))
    }

    private func addButton(_ inputs: SleepScheduleInputs) -> some View {
        Button {
            editing = EditItem(edit: SleepScheduleEdit(original: nil, days: [],
                                                       bed: SleepSchedule.wrap(inputs.baseWake - inputs.sleepGoal),
                                                       wake: inputs.baseWake, alarm: true))
        } label: {
            SleepScheduleCard {
                Text("Add Schedule")
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Additional details

    private var detailsCard: some View {
        SleepScheduleCard(padded: false) {
            VStack(spacing: 0) {
                row {
                    Toggle(isOn: $reminderOn) { Text("Bedtime Reminder").font(StrandFont.pro(17)) }
                        .tint(StrandPalette.settingsGreen)
                        .onChangeCompat(of: reminderOn) { on in
                            WindDownNudge.setEnabled(on) { outcome in
                                // Denied at the OS level: the reminder can never fire, so revert the switch.
                                if outcome == .denied {
                                    reminderOn = false
                                    showNotifDeniedAlert = true
                                }
                            }
                        }
                }
                if reminderOn {
                    divider
                    row {
                        HStack {
                            Text("Wind Down").font(StrandFont.pro(17))
                            Spacer()
                            // Health's value in the accent, opening a menu of lead times.
                            Menu {
                                Picker(selection: $lead) {
                                    ForEach([15, 30, 45, 60], id: \.self) { m in
                                        Text(verbatim: SleepSchedule.duration(m, locale: AppLanguage.activeLocale)).tag(m)
                                    }
                                } label: { EmptyView() }
                                .pickerStyle(.inline)
                            } label: {
                                Text(verbatim: SleepSchedule.duration(lead, locale: AppLanguage.activeLocale))
                                    .font(StrandFont.pro(17))
                                    .foregroundStyle(StrandPalette.accent)
                            }
                        }
                        .onChangeCompat(of: lead) { WindDownNudge.setLeadMinutes($0) }
                    }
                }
                // #1706: asks the strap what alarm it has stored; the answer lands in the strap log. Not on
                // a 5/MG, whose alarm readback is unconfirmed.
                if !model.whoop5Detected {
                    divider
                    row {
                        Button { model.ble.getStrapAlarm() } label: {
                            Text("Check what the strap has stored")
                                .font(StrandFont.pro(17))
                                .foregroundStyle(StrandPalette.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(minHeight: 52)
            .padding(.horizontal, 16)
    }

    private var divider: some View {
        Divider().overlay(StrandPalette.hairline).padding(.leading, 16)
    }

    // MARK: - Helpers

    /// The system permission dialog only appears once, so Settings is the only way back after a denial.
    private static func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// DEBUG screenshot runs open the first schedule's editor with `--schedule-edit` (`new` = a new one).
    private func openDemoEditor() {
        #if DEBUG
        let args = CommandLine.arguments
        guard editing == nil, let i = args.firstIndex(of: "--schedule-edit") else { return }
        let inputs = inputs
        if i + 1 < args.count, args[i + 1] == "new" {
            editing = EditItem(edit: SleepScheduleEdit(original: nil, days: [7, 1],
                                                       bed: SleepSchedule.wrap(inputs.baseWake + 90 - inputs.sleepGoal),
                                                       wake: inputs.baseWake + 90, alarm: true))
        } else if let first = SleepSchedule.entries(inputs).first {
            open(first, inputs: inputs)
        }
        #endif
    }
}
