//  SleepVitals.swift
//  NOOP · Sleep — one night's overnight vitals against their typical ranges, as Health's Vitals reads
//  them: heart rate, respiratory rate, skin temperature, blood oxygen and sleep duration.
//
//  Pure. A metric's typical range comes from the nights before the one read (up to `window` of them): the
//  mean of those readings ± two standard deviations, never narrower than the metric's own resolution. Until
//  `nightsNeeded` earlier nights carry a reading, there is no range and the night reports how many are
//  still to come, as Health does while it learns a person.

import Foundation
import WhoopStore

struct SleepVitals: Equatable {
    enum Metric: String, CaseIterable, Identifiable {
        case heartRate, respiratory, temperature, oxygen, sleepDuration
        var id: String { rawValue }

        /// The MetricCatalog key its page opens on.
        var catalogKey: String {
            switch self {
            case .heartRate: return "rhr"
            case .respiratory: return "resp_rate"
            case .temperature: return "skin_temp"
            case .oxygen: return "spo2"
            case .sleepDuration: return "sleep_total_min"
            }
        }

        var symbol: String {
            switch self {
            case .heartRate: return "heart.fill"
            case .respiratory: return "lungs.fill"
            case .temperature: return "thermometer.medium"
            case .oxygen: return "drop.fill"
            case .sleepDuration: return "bed.double.fill"
            }
        }

        var title: String {
            switch self {
            case .heartRate: return String(localized: "Resting Heart Rate")
            case .respiratory: return String(localized: "Respiratory Rate")
            case .temperature: return String(localized: "Skin Temperature")
            case .oxygen: return String(localized: "Blood Oxygen")
            case .sleepDuration: return String(localized: "vitals.sleepDuration", defaultValue: "Sleep Duration")
            }
        }

        /// The narrowest half-range a reading's spread may give: the metric's own resolution, so a run of
        /// identical nights does not turn the next tiny wobble into an outlier.
        var minHalfWidth: Double {
            switch self {
            case .heartRate: return 2
            case .respiratory: return 0.5
            case .temperature: return 0.3
            case .oxygen: return 1
            case .sleepDuration: return 30
            }
        }

        /// This metric's reading for one day's row, if it has one. Skin temperature reads the deviation
        /// or the absolute figure (`deviation`), the same one for the night and its history.
        func value(_ row: DailyMetric, deviation: Bool = false) -> Double? {
            switch self {
            case .heartRate: return row.restingHr.map(Double.init)
            case .respiratory: return row.respRateBpm
            case .temperature: return deviation ? row.skinTempDevC : row.skinTempC
            case .oxygen: return row.spo2Pct
            case .sleepDuration: return row.totalSleepMin
            }
        }
    }

    struct Reading: Equatable, Identifiable {
        let metric: Metric
        let value: Double
        let range: ClosedRange<Double>
        var id: String { metric.id }

        /// Where the reading sits: 0 at the range's low edge, 1 at its high edge, outside 0…1 beyond it.
        var position: Double {
            let span = range.upperBound - range.lowerBound
            return span > 0 ? (value - range.lowerBound) / span : 0.5
        }

        var isOutlier: Bool { !range.contains(value) }
    }

    static let nightsNeeded = 7
    static let window = 28

    /// The night's readings that have a range, in `Metric` order.
    let readings: [Reading]
    /// Earlier nights with a vital still needed before the ranges exist; 0 once they do.
    let nightsRemaining: Int
    /// Earlier nights that already carry a vital (at most `nightsNeeded`), for the waiting state.
    var nightsRecorded: Int { Self.nightsNeeded - nightsRemaining }

    var outliers: Int { readings.filter(\.isOutlier).count }

    /// The night that ended on `day` read against the nights before it. `rows` are the daily rows in any
    /// order; only those before `day` form the ranges.
    static func make(rows: [DailyMetric], day: String) -> SleepVitals {
        guard let tonight = rows.last(where: { $0.day == day }) else {
            return SleepVitals(readings: [], nightsRemaining: nightsNeeded)
        }
        let prior = rows.filter { $0.day < day }.sorted { $0.day < $1.day }.suffix(window)
        let nightsWithVitals = prior.filter { row in
            Metric.allCases.contains { $0.value(row) != nil || $0.value(row, deviation: true) != nil }
        }.count
        let remaining = max(0, nightsNeeded - nightsWithVitals)
        guard remaining == 0 else { return SleepVitals(readings: [], nightsRemaining: remaining) }

        // The strap's deviation where the night carries one, else the absolute reading.
        let deviation = tonight.skinTempDevC != nil
        let readings = Metric.allCases.compactMap { metric -> Reading? in
            guard let value = metric.value(tonight, deviation: deviation) else { return nil }
            let history = prior.compactMap { metric.value($0, deviation: deviation) }
            guard history.count >= nightsNeeded, let range = typicalRange(history, minHalfWidth: metric.minHalfWidth)
            else { return nil }
            return Reading(metric: metric, value: value, range: range)
        }
        return SleepVitals(readings: readings, nightsRemaining: 0)
    }

    /// Mean ± two standard deviations, at least `minHalfWidth` either side.
    static func typicalRange(_ values: [Double], minHalfWidth: Double) -> ClosedRange<Double>? {
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let half = max(2 * variance.squareRoot(), minHalfWidth)
        return (mean - half)...(mean + half)
    }
}
