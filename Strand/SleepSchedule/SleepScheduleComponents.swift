//  SleepScheduleComponents.swift
//  NOOP · Sleep schedule — the pieces the Health app's Full Schedule is made of: the bold section header,
//  the bedtime / wake pair, a schedule card with its "Edit" link, the next-wake card, the day circles.

import SwiftUI
import StrandDesign

/// Health's grouped-page section header: bold 22 pt SF Pro.
struct SleepScheduleHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(StrandFont.pro(22, weight: .bold))
            .foregroundStyle(StrandPalette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, NoopMetrics.space4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A white card on the grouped canvas, Health's corner radius.
struct SleepScheduleCard<Content: View>: View {
    var padded = true
    /// White on the page; the sheet's grey inside the editor, as Health draws them.
    var fill: Color = StrandPalette.summaryCard
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, padded ? 16 : 0)
            .padding(.vertical, padded ? 14 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
    }
}

/// One of the two times: a small caps label under its glyph, the time in bold, an optional caption.
struct SleepScheduleTime: View {
    enum Kind { case bed, wake(alarm: Bool) }
    let kind: Kind
    let time: String
    var caption: String? = nil
    var centered = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: symbol)
                    .foregroundStyle(muted ? StrandPalette.textSecondary : StrandPalette.sleepSchedule)
                Text(label)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(centered ? .center : .leading)
            }
            .font(StrandFont.pro(13, weight: .semibold))
            .textCase(.uppercase)
            Text(verbatim: time)
                .font(StrandFont.pro(centered ? 28 : 24, weight: .bold))
                .foregroundStyle(muted ? StrandPalette.textSecondary : StrandPalette.textPrimary)
                .monospacedDigit()
            if let caption {
                Text(verbatim: caption)
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityElement(children: .combine)
    }

    private var muted: Bool { if case .wake(let alarm) = kind { return !alarm } else { return false } }

    private var symbol: String {
        switch kind {
        case .bed: return "bed.double.fill"
        case .wake(let alarm): return alarm ? "alarm.waves.left.and.right.fill" : "alarm"
        }
    }

    private var label: String {
        switch kind {
        case .bed: return String(localized: "schedule.bedtime", defaultValue: "Bedtime")
        case .wake(let alarm):
            return alarm ? String(localized: "schedule.wake", defaultValue: "Wake Up")
                : String(localized: "schedule.wakeNoAlarm", defaultValue: "Wake Up — No Alarm")
        }
    }
}

/// A Full Schedule card: the days in purple, bedtime and wake, a hairline, "Edit".
struct SleepScheduleEntryCard: View {
    let entry: SleepScheduleEntry
    let onEdit: () -> Void

    var body: some View {
        let locale = AppLanguage.activeLocale
        SleepScheduleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.days.isEmpty ? String(localized: "schedule.noDays", defaultValue: "No Days")
                     : SleepSchedule.weekdaySummary(Set(entry.days)))
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.sleepSchedule)
                HStack(alignment: .top, spacing: 12) {
                    SleepScheduleTime(kind: .bed, time: SleepSchedule.clock(entry.bed, locale: locale))
                    SleepScheduleTime(kind: .wake(alarm: entry.alarm), time: SleepSchedule.clock(entry.wake, locale: locale))
                }
                Divider().overlay(StrandPalette.hairline).padding(.top, 6)
                Button(action: onEdit) {
                    Text("Edit")
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }
}

/// The next wake: bedtime the evening before and the wake, each with its day, and — only for an armed
/// alarm — how long until it goes off. Every figure comes from ONE `SleepSchedule.nextWake` call against
/// ONE clock tick, re-resolved each minute.
struct SleepNextWakeCard: View {
    let inputs: SleepScheduleInputs
    var trailing: AnyView? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            let now = tick.date
            let next = SleepSchedule.nextWake(inputs, from: now)
            SleepScheduleCard {
                VStack(alignment: .leading, spacing: 10) {
                    if let next {
                        HStack(alignment: .top, spacing: 12) {
                            SleepScheduleTime(kind: .bed, time: Self.clock(next.bed),
                                              caption: Self.dayCaption(next.bed, now: now, evening: true))
                            SleepScheduleTime(kind: .wake(alarm: next.armed), time: Self.clock(next.wake),
                                              caption: Self.dayCaption(next.wake, now: now, evening: false))
                        }
                        if let countdown = SleepSchedule.countdown(next, from: now, locale: AppLanguage.activeLocale) {
                            Divider().overlay(StrandPalette.hairline)
                            Text(verbatim: countdown)
                                .font(StrandFont.pro(15))
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    } else {
                        Text(String(localized: "schedule.none", defaultValue: "No Wake Up Scheduled"))
                            .font(StrandFont.pro(17))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    if let trailing { trailing }
                }
            }
        }
    }

    static func clock(_ date: Date) -> String {
        SleepSchedule.clock(date, locale: AppLanguage.activeLocale)
    }

    /// "Tonight" / "Today" / "Tomorrow", else "Fri, 3 Oct".
    static func dayCaption(_ date: Date, now: Date, evening: Bool, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return evening && calendar.component(.hour, from: date) >= 17
                ? String(localized: "schedule.tonight", defaultValue: "Tonight") : String(localized: "Today")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguage.activeLocale))
    }
}

/// Health's "Days Active" row: seven circles, filled when picked.
struct SleepScheduleDayCircles: View {
    @Binding var days: Set<Int>

    var body: some View {
        let locale = AppLanguage.activeLocale
        HStack(spacing: 0) {
            ForEach(SleepSchedule.weekOrder, id: \.self) { dow in
                let on = days.contains(dow)
                Button {
                    if on { days.remove(dow) } else { days.insert(dow) }
                } label: {
                    Text(verbatim: SleepSchedule.weekdayLetter(dow, locale: locale))
                        .font(StrandFont.pro(17, weight: .medium))
                        .foregroundStyle(on ? Color.white : StrandPalette.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(on ? StrandPalette.accent : Color.clear, in: Circle())
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: SleepSchedule.weekdayName(dow, locale: locale)))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(StrandPalette.sleepDialCard,
                    in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
    }
}
