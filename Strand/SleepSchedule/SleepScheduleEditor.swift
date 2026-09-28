//  SleepScheduleEditor.swift
//  NOOP · Sleep schedule — Health's "Edit Schedule" sheet: ✕ / ✓, Days Active as circles, the bedtime /
//  wake dial with the span under it, Alarm Options (own-time schedules), Delete Schedule.

import SwiftUI
import StrandDesign

struct SleepScheduleEditor: View {
    let inputs: SleepScheduleInputs
    let onSave: (SleepScheduleStored) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dts

    @State private var edit: SleepScheduleEdit
    @State private var picking: SleepScheduleDial.End?

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
                    SleepScheduleHeader(title: "Bedtime and Wake Up")
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
                            Button(role: .destructive) {
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
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(tint: StrandPalette.accent) {
                        if let result { onSave(result) }
                        dismiss()
                    }
                    .disabled(result == nil || edit.days.isEmpty)
                }
            }
            .sheet(item: $picking) { end in
                SleepScheduleTimeSheet(label: end == .bed ? String(localized: "schedule.bedtime", defaultValue: "Bedtime")
                                                        : String(localized: "schedule.wake", defaultValue: "Wake Up"),
                                       minutes: end == .bed ? edit.bed : edit.wake) { minutes in
                    let moved = SleepScheduleDial.moving(end, to: SleepScheduleDial.snapped(minutes),
                                                         bed: edit.bed, wake: edit.wake)
                    edit.bed = moved.bed
                    edit.wake = moved.wake
                }
            }
        }
    }

    private var dialCard: some View {
        let locale = AppLanguage.activeLocale
        let alarm = edit.isBase ? inputs.alarmOn && inputs.alarmWillArm : inputs.alarmOn && inputs.alarmWillArm && edit.alarm
        let pair = dts.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return VStack(spacing: 18) {
            pair {
                // Each time opens a wheel for that end alone, as Clock and Health do.
                Button { picking = .bed } label: {
                    SleepScheduleTime(kind: .bed, time: SleepSchedule.clock(edit.bed, locale: locale), centered: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { picking = .wake } label: {
                    SleepScheduleTime(kind: .wake(alarm: alarm), time: SleepSchedule.clock(edit.wake, locale: locale), centered: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

extension SleepScheduleDial.End: Identifiable {
    var id: Self { self }
}

/// One end's time on a wheel, confirmed with ✓; swiping the sheet away keeps the old time.
private struct SleepScheduleTimeSheet: View {
    let label: String
    let onDone: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(label: String, minutes: Int, onDone: @escaping (Int) -> Void) {
        self.label = label
        self.onDone = onDone
        _date = State(initialValue: SleepScheduleDial.date(minutes))
    }

    var body: some View {
        NavigationStack {
            DatePicker(label, selection: $date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                #if os(iOS)
                .datePickerStyle(.wheel)
                #endif
                .environment(\.locale, AppLanguage.activeLocale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetConfirmButton(tint: StrandPalette.accent) {
                            onDone(SleepScheduleDial.minutes(of: date))
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.height(300)])
    }
}
