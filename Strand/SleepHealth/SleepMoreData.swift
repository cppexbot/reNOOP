//  SleepMoreData.swift
//  NOOP · Sleep — the numbers behind "Show More Sleep Data": Stages, Amounts and Comparisons for one
//  night (D) or a window of nights (W / M / 6M), Apple Health style.
//
//  Pure. Every night is decoded by the same `SleepModel.mergeDay` the Sleep tab's day chart uses, so the
//  stage minutes here and the chart above them are one computation. Vitals come from the night's
//  `DailyMetric` row (keyed by the day it ended on, as the rest of the app keys a night) and from the
//  heart-rate buckets that fall inside the night.

import Foundation
import StrandDesign
import StrandAnalytics
import WhoopStore

/// One decoded night: its span, stage totals and hypnogram.
struct SleepNightDetail {
    /// Index into `navDays` (0 = newest night on record).
    let navIndex: Int
    /// Start of the calendar day the night ended on.
    let day: Date
    let onset: Date
    let wake: Date
    let stages: Stages
    /// Seconds from `onset`.
    let intervals: [SleepInterval]

    var dayKey: String { Repository.localDayKey(day) }
    var inBedMin: Double { stages.total }
    var asleepMin: Double { stages.asleep }

    func minutes(_ stage: SleepStage) -> Double {
        switch stage {
        case .awake: return stages.awake
        case .rem: return stages.rem
        case .light: return stages.light
        case .deep: return stages.deep
        }
    }

    /// The same night as a range-chart entry, so the W / M chart draws exactly these nights.
    var entry: SleepNightEntry { SleepNightEntry(day: day, onset: onset, wake: wake, asleepMin: asleepMin) }

    init(navIndex: Int, day: Date, onset: Date, wake: Date, stages: Stages, intervals: [SleepInterval]) {
        self.navIndex = navIndex; self.day = day; self.onset = onset; self.wake = wake
        self.stages = stages; self.intervals = intervals
    }

    init?(night: Night, navIndex: Int, calendar: Calendar = .current) {
        guard night.stages.asleep > 0 else { return nil }
        let wake = Date(timeIntervalSince1970: TimeInterval(night.session.endTs))
        self.init(navIndex: navIndex, day: calendar.startOfDay(for: wake), onset: night.onsetDate,
                  wake: wake, stages: night.stages, intervals: night.intervals)
    }
}

/// The three views under the chart.
enum SleepMoreTab: String, CaseIterable, Identifiable {
    case stages, amounts, comparisons
    var id: String { rawValue }

    var label: String {
        switch self {
        case .stages: return String(localized: "Stages")
        case .amounts: return String(localized: "Amounts")
        case .comparisons: return String(localized: "Comparisons")
        }
    }
}

/// Averages over a set of nights (a single night averages to itself).
struct SleepPeriodSummary: Equatable {
    let nights: Int
    let inBedMin: Double?
    let asleepMin: Double?
    let stageMin: [SleepStage: Double]
    /// Minutes after 18:00 on the evening before each night's day (`SleepNightEntry.onsetOfNightMin`).
    let bedtimeOfNightMin: Double?
    let wakeOfNightMin: Double?

    /// Share of time in bed spent in `stage`, 0…1.
    func share(_ stage: SleepStage) -> Double? {
        guard let inBed = inBedMin, inBed > 0, let m = stageMin[stage] else { return nil }
        return m / inBed
    }

    /// Time asleep over time in bed, 0…1.
    var efficiency: Double? {
        guard let inBed = inBedMin, inBed > 0, let asleep = asleepMin else { return nil }
        return asleep / inBed
    }
}

/// A vital compared against the night(s).
enum SleepComparisonMetric: String, CaseIterable, Identifiable {
    case heartRate, respiratoryRate, hrv, bloodOxygen, skinTemperature
    var id: String { rawValue }

    var label: String {
        switch self {
        case .heartRate: return String(localized: "Heart Rate")
        case .respiratoryRate: return String(localized: "Respiratory Rate")
        case .hrv: return String(localized: "Heart Rate Variability")
        case .bloodOxygen: return String(localized: "Blood Oxygen")
        case .skinTemperature: return String(localized: "Skin Temperature")
        }
    }
}

/// One plotted value of a comparison: a heart-rate bucket (seconds from onset) on the day chart, or a
/// night / week slot on a range chart.
struct SleepComparisonPoint: Equatable {
    let x: Double
    let value: Double
}

enum SleepMoreData {
    /// Nights to decode for the range views: everything that could land in the 6-month window.
    static let lookbackDays = 190

    /// Decodes every night of `navDays` (newest first) whose day falls within `lookbackDays` of `anchor`,
    /// oldest → newest.
    static func nights(navDays: [[CachedSleepSession]], habitualMidsleepSec: Int?,
                       motionByStart: [Int: [Double]], anchor: Date,
                       calendar: Calendar = .current) -> [SleepNightDetail] {
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: calendar.startOfDay(for: anchor)) ?? anchor
        var out: [SleepNightDetail] = []
        for (index, day) in navDays.enumerated() {
            guard let last = day.max(by: { $0.endTs < $1.endTs }),
                  Date(timeIntervalSince1970: TimeInterval(last.endTs)) >= cutoff else { continue }
            guard let night = SleepModel.mergeDay(day, habitualMidsleepSec: habitualMidsleepSec,
                                                  motionByStart: motionByStart),
                  let detail = SleepNightDetail(night: night, navIndex: index, calendar: calendar) else { continue }
            out.append(detail)
        }
        return out.sorted { $0.day < $1.day }
    }

    /// The nights a range view covers: the last 7 or 30 days, or the 26 weeks of the 6-month chart.
    /// Uses the same slot boundaries as `SleepHistory.window`.
    static func nights(in range: SleepRange, _ nights: [SleepNightDetail], anchor: Date,
                       calendar: Calendar = .current) -> [SleepNightDetail] {
        let window = SleepHistory.window(range, entries: [], anchor: anchor, calendar: calendar)
        guard let first = window.slotStarts.first else { return [] }
        let today = calendar.startOfDay(for: anchor)
        return nights.filter { $0.day >= first && $0.day <= today }
    }

    static func summary(_ nights: [SleepNightDetail]) -> SleepPeriodSummary {
        guard !nights.isEmpty else {
            return SleepPeriodSummary(nights: 0, inBedMin: nil, asleepMin: nil, stageMin: [:],
                                      bedtimeOfNightMin: nil, wakeOfNightMin: nil)
        }
        let n = Double(nights.count)
        func mean(_ f: (SleepNightDetail) -> Double) -> Double { nights.map(f).reduce(0, +) / n }
        var stageMin: [SleepStage: Double] = [:]
        for stage in SleepStage.allCases { stageMin[stage] = mean { $0.minutes(stage) } }
        return SleepPeriodSummary(nights: nights.count, inBedMin: mean(\.inBedMin), asleepMin: mean(\.asleepMin),
                                  stageMin: stageMin,
                                  bedtimeOfNightMin: mean { $0.entry.onsetOfNightMin },
                                  wakeOfNightMin: mean { $0.entry.wakeOfNightMin })
    }

    // MARK: - Comparisons

    /// The night's own value of a nightly vital (heart rate is not nightly — it comes from buckets).
    static func nightlyValue(_ metric: SleepComparisonMetric, _ row: DailyMetric?,
                             skinTempPreferred: SkinTempDisplay.Kind) -> Double? {
        guard let row else { return nil }
        switch metric {
        case .heartRate: return nil
        case .respiratoryRate: return row.respRateBpm
        case .hrv: return row.avgHrv
        case .bloodOxygen: return row.spo2Pct
        case .skinTemperature:
            return SkinTempDisplay.leadReading(absC: row.skinTempC, devC: row.skinTempDevC,
                                               prefer: skinTempPreferred)?.value
        }
    }

    /// Heart-rate buckets inside one night, as (seconds from onset, bpm).
    static func heartRatePoints(_ night: SleepNightDetail, buckets: [HRBucket]) -> [SleepComparisonPoint] {
        let from = Int(night.onset.timeIntervalSince1970), to = Int(night.wake.timeIntervalSince1970)
        return buckets.filter { $0.ts >= from && $0.ts <= to && $0.bpm > 0 }
            .map { SleepComparisonPoint(x: Double($0.ts - from), value: $0.bpm) }
    }

    /// Mean sleeping heart rate of each night that has buckets, keyed by the night's day.
    static func nightlyHeartRate(_ nights: [SleepNightDetail], buckets: [HRBucket]) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for night in nights {
            let pts = heartRatePoints(night, buckets: buckets)
            guard !pts.isEmpty else { continue }
            out[night.day] = pts.map(\.value).reduce(0, +) / Double(pts.count)
        }
        return out
    }

    /// Per-slot values for a range chart: each night's value (W / M) or the mean of a week's nights (6M).
    /// Skin temperature is reduced to one scale first (`SkinTempDisplay.dominantKind`), so absolute and
    /// deviation readings are never averaged together.
    static func slotValues(window: SleepRangeWindow, valueByDay: [Date: Double],
                           calendar: Calendar = .current) -> [SleepComparisonPoint] {
        window.slotStarts.enumerated().compactMap { slot, start -> SleepComparisonPoint? in
            let values: [Double]
            if window.range == .sixMonths {
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
                values = valueByDay.filter { $0.key >= start && $0.key < end }.map(\.value)
            } else {
                values = valueByDay[start].map { [$0] } ?? []
            }
            guard !values.isEmpty else { return nil }
            return SleepComparisonPoint(x: Double(slot), value: values.reduce(0, +) / Double(values.count))
        }
    }

    /// Keeps only the skin-temperature readings on the scale of the newest one.
    static func sameScaleSkinTemps(_ byDay: [Date: Double]) -> [Date: Double] {
        let ascending = byDay.sorted { $0.key < $1.key }
        guard let kind = SkinTempDisplay.dominantKind(valuesAscendingByDay: ascending.map(\.value)) else { return [:] }
        return byDay.filter { SkinTempDisplay.kind(of: $0.value) == kind }
    }

    /// The vertical scale an overlaid vital is drawn on: its own min…max, widened to at least 20 % of its
    /// level, so a night-to-night wobble of a few tenths does not fill the chart like a real swing.
    static func overlayDomain(_ points: [SleepComparisonPoint]) -> ClosedRange<Double>? {
        guard let lo = points.map(\.value).min(), let hi = points.map(\.value).max() else { return nil }
        let minSpread = max(abs((lo + hi) / 2) * 0.2, 1)
        guard hi - lo < minSpread else { return lo...hi }
        let mid = (lo + hi) / 2
        return (mid - minSpread / 2)...(mid + minSpread / 2)
    }

    /// The sleep need behind the given nights (mean over them): each night's own imported need where the
    /// export recorded one, else the personal need — the same pair the "Hours vs needed" card measures
    /// against.
    static func needMin(dayKeys: [String], days: [DailyMetric],
                        imported: [String: ImportedSleepFigures]) -> Double? {
        guard !dayKeys.isEmpty else { return nil }
        let fallback = SleepModel.sleepNeedMin(days: days)
        let needs = dayKeys.map { imported[$0]?.needMin ?? fallback }
        return needs.reduce(0, +) / Double(needs.count)
    }
}
