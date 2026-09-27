//  SleepScheduleEditor.swift
//  NOOP · Sleep schedule — Health's "Edit Schedule" sheet: ✕ / ✓, Days Active as circles, the bedtime /
//  wake dial with the span under it, Alarm Options (own-time schedules), Delete Schedule.

import SwiftUI
import StrandDesign

struct SleepScheduleEditor: View {
    let inputs: SleepScheduleInputs
    let onSave: (SleepScheduleStored) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var edit: SleepScheduleEdit

    init(edit: SleepScheduleEdit, inputs: SleepScheduleInputs, onSave: @escaping (SleepScheduleStored) -> Void) {
        self.inputs = inputs
        self.onSave = onSave
        _edit = State(initialValue: edit)
    }

    private var isNew: Bool { edit.original == nil }
    private var result: SleepScheduleStored? { SleepSchedule.applying(edit, to: inputs) }

    /// Whether this schedule's alarm may be switched off: not when its days are the last ones ringing,
    /// since an empty alarm-day set is how "every day" is stored. The top switch turns the alarm off.
    private var alarmToggleEnabled: Bool {
        var off = edit
        off.alarm = false
        return !edit.alarm || SleepSchedule.applying(off, to: inputs) != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SleepScheduleHeader(title: "Days Active")
                    SleepScheduleDayCircles(days: $edit.days)
                    Text("Bedtime and Wake Up")
                        .font(StrandFont.pro(17, weight: .semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.top, NoopMetrics.space4)
                    dialCard
                    if !edit.isBase {
                        SleepScheduleHeader(title: "Alarm Options")
                        SleepScheduleCard(fill: StrandPalette.sleepDialCard) {
                            Toggle(isOn: $edit.alarm) {
                                Text("Alarm").font(StrandFont.pro(17))
                            }
                            .tint(StrandPalette.settingsGreen)
                            .disabled(!alarmToggleEnabled)
                        }
                        if !isNew {
                            Button {
                                var gone = edit
                                gone.delete = true
                                if let stored = SleepSchedule.applying(gone, to: inputs) { onSave(stored) }
                                dismiss()
                            } label: {
                                Text("Delete Schedule")
                                    .font(StrandFont.pro(17))
                                    .foregroundStyle(StrandPalette.settingsRed)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(StrandPalette.sleepDialCard,
                                                in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, NoopMetrics.space4)
                        }
                    }
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.bottom, NoopMetrics.space6)
            }
            .navigationTitle(Text(isNew ? "New Schedule" : "Edit Schedule"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { WorkoutSheetCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SleepScheduleConfirmButton {
                        if let result { onSave(result) }
                        dismiss()
                    }
                    .disabled(result == nil || edit.days.isEmpty)
                }
            }
        }
    }

    private var dialCard: some View {
        let locale = AppLanguage.activeLocale
        let alarm = edit.isBase ? inputs.alarmOn && inputs.alarmWillArm : inputs.alarmOn && inputs.alarmWillArm && edit.alarm
        return VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 8) {
                SleepScheduleTime(kind: .bed, time: SleepSchedule.clock(edit.bed, locale: locale), centered: true)
                SleepScheduleTime(kind: .wake(alarm: alarm), time: SleepSchedule.clock(edit.wake, locale: locale), centered: true)
            }
            SleepScheduleDial(bed: $edit.bed, wake: $edit.wake)
                .padding(.horizontal, 8)
            Text(verbatim: SleepSchedule.duration(SleepSchedule.goal(bed: edit.bed, wake: edit.wake), locale: locale))
                .font(StrandFont.pro(20, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(StrandPalette.sleepDialCard,
                    in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
    }
}
