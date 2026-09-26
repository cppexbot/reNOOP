//  SleepHistory.swift
//  NOOP · Sleep — nights as (bedtime, wake, time asleep), and the week / month / 6-month views of them.
//
//  Pure. Each night is the day's MAIN sleep group, picked by the same `SleepView.mainNightGroup` rule
//  the Sleep tab and the analytics use, so the range charts and the day chart never disagree about
//  which block was "the night".

import Foundation
import WhoopStore

struct SleepNightEntry: Equatable {
    /// Start of the calendar day the night ended on.
    let day: Date
    let onset: Date
    let wake: Date
    let asleepMin: Double

    /// Minutes after 18:00 on the evening before `day` — a clock that runs through the night without
    /// wrapping at midnight, so bedtimes either side of it compare directly.
    var onsetOfNightMin: Double { onset.timeIntervalSince(Self.nightOrigin(day)) / 60 }
    var wakeOfNightMin: Double { wake.timeIntervalSince(Self.nightOrigin(day)) / 60 }

    static func nightOrigin(_ day: Date) -> Date { day.addingTimeInterval(-6 * 3600) }
}

enum SleepRange: String, CaseIterable, Identifiable {
    case day, week, month, sixMonths
    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return String(localized: "sleep.range.day", defaultValue: "D")
        case .week: return String(localized: "sleep.range.week", defaultValue: "W")
        case .month: return String(localized: "sleep.range.month", defaultValue: "M")
        case .sixMonths: return String(localized: "sleep.range.sixMonths", defaultValue: "6M")
        }
    }
}

/// One bar of a range chart: a night (week / month) or a week's average (6 months).
struct SleepRangeBar: Identifiable, Equatable {
    let slot: Int
    let start: Date
    let onsetMin: Double
    let wakeMin: Double
    let asleepMin: Double
    var id: Int { slot }
}

struct SleepRangeWindow: Equatable {
    let range: SleepRange
    /// First day of each slot, oldest → newest.
    let slotStarts: [Date]
    let bars: [SleepRangeBar]

    /// Mean time asleep over the slots that have data; nil when none do.
    var averageAsleepMin: Double? {
        bars.isEmpty ? nil : bars.map(\.asleepMin).reduce(0, +) / Double(bars.count)
    }
}

enum SleepHistory {
    /// Every night with sleep, oldest → newest. `navDays` is `SleepModel.navDays` (newest day first).
    static func entries(navDays: [[CachedSleepSession]], habitualMidsleepSec: Int?,
                        calendar: Calendar = .current) -> [SleepNightEntry] {
        navDays.compactMap { day -> SleepNightEntry? in
            let group = SleepView.mainNightGroup(day, habitualMidsleepSec: habitualMidsleepSec)
            guard let last = group.last else { return nil }
            let onsetTs = SleepModel.nightOnsetTs(group)
            let asleep = group.filter { $0.effectiveStartTs >= onsetTs }
                .map { SleepView.decodedAsleepMinutes($0.stagesJSON, effectiveStartTs: $0.effectiveStartTs) }
                .reduce(0, +)
            guard asleep > 0 else { return nil }
            let wake = Date(timeIntervalSince1970: TimeInterval(last.endTs))
            return SleepNightEntry(day: calendar.startOfDay(for: wake),
                                   onset: Date(timeIntervalSince1970: TimeInterval(onsetTs)),
                                   wake: wake, asleepMin: asleep)
        }
        .sorted { $0.day < $1.day }
    }

    /// The window ending on `anchor`'s day: 7 nights, 30 nights, or 26 weekly averages.
    static func window(_ range: SleepRange, entries: [SleepNightEntry], anchor: Date,
                       calendar: Calendar = .current) -> SleepRangeWindow {
        let today = calendar.startOfDay(for: anchor)
        let byDay = Dictionary(entries.map { ($0.day, $0) }, uniquingKeysWith: { _, newer in newer })
        switch range {
        case .day, .week, .month:
            let count = range == .month ? 30 : 7
            let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            let bars = starts.enumerated().compactMap { slot, day -> SleepRangeBar? in
                guard let e = byDay[day] else { return nil }
                return SleepRangeBar(slot: slot, start: day, onsetMin: e.onsetOfNightMin,
                                     wakeMin: e.wakeOfNightMin, asleepMin: e.asleepMin)
            }
            return SleepRangeWindow(range: range, slotStarts: starts, bars: bars)
        case .sixMonths:
            guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else {
                return SleepRangeWindow(range: range, slotStarts: [], bars: [])
            }
            let starts = (0..<26).reversed().compactMap {
                calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek)
            }
            let bars = starts.enumerated().compactMap { slot, weekStart -> SleepRangeBar? in
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                let nights = entries.filter { $0.day >= weekStart && $0.day < weekEnd }
                guard !nights.isEmpty else { return nil }
                let n = Double(nights.count)
                return SleepRangeBar(slot: slot, start: weekStart,
                                     onsetMin: nights.map(\.onsetOfNightMin).reduce(0, +) / n,
                                     wakeMin: nights.map(\.wakeOfNightMin).reduce(0, +) / n,
                                     asleepMin: nights.map(\.asleepMin).reduce(0, +) / n)
            }
            return SleepRangeWindow(range: range, slotStarts: starts, bars: bars)
        }
    }
}

// MARK: - Highlights

struct SleepHighlight: Identifiable, Equatable {
    /// The two figures a Health highlight sets under its sentence, and the nights behind them.
    enum Detail: Equatable {
        /// Usual bedtime vs last night's, on the night clock (`SleepNightEntry.onsetOfNightMin`); `nights`
        /// are the compared nights then last night, oldest first.
        case bedtime(usualMin: Double, lastMin: Double, nights: [Double])
        /// This week's and the week before's average time asleep; `nights` are this week's, oldest first.
        case duration(averageMin: Double, priorAverageMin: Double, nights: [Double])
    }

    let id: String
    let sentence: String
    var detail: Detail? = nil
}

enum SleepHighlights {
    /// Plain-language reads of the recent nights, Health-style. Each needs enough history to compare
    /// against; with too little it is simply left out.
    static func make(entries: [SleepNightEntry], anchor: Date, calendar: Calendar = .current) -> [SleepHighlight] {
        [bedtime(entries), duration(entries, anchor: anchor, calendar: calendar)].compactMap { $0 }
    }

    /// Last night's bedtime against the mean of up to seven nights before it (needs three).
    static func bedtime(_ entries: [SleepNightEntry]) -> SleepHighlight? {
        guard let last = entries.last else { return nil }
        let before = entries.dropLast().suffix(7)
        guard before.count >= 3 else { return nil }
        let usual = before.map(\.onsetOfNightMin).reduce(0, +) / Double(before.count)
        let diff = Int(((last.onsetOfNightMin - usual) / 5).rounded()) * 5
        let sentence: String
        if abs(diff) < 15 {
            sentence = String(localized: "Last night you went to bed around your usual time.")
        } else if diff > 0 {
            sentence = String(localized: "Last night you went to bed \(diff) min later than usual.")
        } else {
            sentence = String(localized: "Last night you went to bed \(-diff) min earlier than usual.")
        }
        return SleepHighlight(id: "bedtime", sentence: sentence,
                              detail: .bedtime(usualMin: usual, lastMin: last.onsetOfNightMin,
                                               nights: before.map(\.onsetOfNightMin) + [last.onsetOfNightMin]))
    }

    /// The last seven days' average time asleep against the seven before (needs three nights in each).
    static func duration(_ entries: [SleepNightEntry], anchor: Date, calendar: Calendar = .current) -> SleepHighlight? {
        let today = calendar.startOfDay(for: anchor)
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: today),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today) else { return nil }
        let recent = entries.filter { $0.day > weekAgo && $0.day <= today }
        let prior = entries.filter { $0.day > twoWeeksAgo && $0.day <= weekAgo }
        guard recent.count >= 3, prior.count >= 3 else { return nil }
        let avg = recent.map(\.asleepMin).reduce(0, +) / Double(recent.count)
        let priorAvg = prior.map(\.asleepMin).reduce(0, +) / Double(prior.count)
        let diff = Int(((avg - priorAvg) / 5).rounded()) * 5
        let avgText = SleepFormat.duration(minutes: avg)
        let sentence: String
        if abs(diff) < 10 {
            sentence = String(localized: "Over the last 7 days you slept \(avgText) a night on average, about the same as the week before.")
        } else if diff > 0 {
            sentence = String(localized: "Over the last 7 days you slept \(avgText) a night on average, \(SleepFormat.duration(minutes: Double(diff))) more than the week before.")
        } else {
            sentence = String(localized: "Over the last 7 days you slept \(avgText) a night on average, \(SleepFormat.duration(minutes: Double(-diff))) less than the week before.")
        }
        return SleepHighlight(id: "duration", sentence: sentence,
                              detail: .duration(averageMin: avg, priorAverageMin: priorAvg,
                                                nights: recent.map(\.asleepMin)))
    }
}
