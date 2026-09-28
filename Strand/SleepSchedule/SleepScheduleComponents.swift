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

    @ScaledMetric(relativeTo: .title2) private var timeSize: CGFloat = 24

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: symbol)
                    .foregroundStyle(muted ? StrandPalette.textSecondary : StrandPalette.sleepSchedule)
                    .accessibilityHidden(true)
                Text(label)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(centered ? .center : .leading)
            }
            .font(StrandFont.pro(13, weight: .semibold))
            .textCase(.uppercase)
            Text(verbatim: time)
                .font(StrandFont.pro(centered ? 28 : timeSize, weight: .bold))
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

    /// Bedtime beside wake; one under the other at accessibility sizes.
    static func pairLayout(_ size: DynamicTypeSize) -> AnyLayout {
        size.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

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

    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let locale = AppLanguage.activeLocale
        let pair = SleepScheduleTime.pairLayout(dts)
        let daysText = entry.days.isEmpty ? String(localized: "schedule.noDays", defaultValue: "No Days")
            : SleepSchedule.weekdaySummary(Set(entry.days))
        SleepScheduleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(daysText)
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.sleepSchedule)
                pair {
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
                // Several cards each carry an "Edit": VoiceOver hears which schedule it opens.
                .accessibilityLabel(Text("Edit \(daysText)"))
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

    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let pair = SleepScheduleTime.pairLayout(dts)
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            let now = tick.date
            let next = SleepSchedule.nextWake(inputs, from: now)
            SleepScheduleCard {
                VStack(alignment: .leading, spacing: 10) {
                    if let next {
                        pair {
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
                        // Health's 44 pt circles, narrowing only where seven of them cannot fit the row.
                        .frame(maxWidth: 44, maxHeight: 44)
                        .aspectRatio(1, contentMode: .fit)
                        .background(on ? StrandPalette.accent : Color.clear, in: Circle())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: SleepSchedule.weekdayName(dow, locale: locale)))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        // 9 + 44 + 9 round the 44 pt circles.
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        // Seven fixed circles across the row: the letters follow Dynamic Type only as far as a circle holds one.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(StrandPalette.sleepDialCard,
                    in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
    }
}
