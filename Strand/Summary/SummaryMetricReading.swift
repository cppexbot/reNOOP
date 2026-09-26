//  SummaryMetricReading.swift
//  NOOP · Summary home — what a pinned metric card says.
//
//  Pure: the day's already-loaded inputs in, one card's value / unit / caption / route out. The value
//  precedence for every metric is the one the Liquid Today tiles used (measured → imported → estimate,
//  today-first carries for the overnight vitals), so moving a metric onto the Summary never changes the
//  number it shows. Charge, Effort and Rest are not pinned cards: they live in the rings.

import Foundation
import StrandAnalytics
import WhoopStore

/// Everything the pinned cards read for one selected day. Built once per load by `SummaryLoader`.
struct SummaryMetricInputs {
    /// The selected day's own row.
    var day: DailyMetric?
    /// Today-only carries for when the morning row has no vitals yet (nil on a past day).
    var vitalsDay: DailyMetric?
    var respDay: DailyMetric?
    var hrvDay: DailyMetric?
    var restingHrDay: DailyMetric?
    var skinTempReading: SkinTempDisplay.Reading?
    /// The unvalidated strap SpO₂ estimate — non-nil only when its Experimental toggle is on.
    var spo2Candidate: Double?
    var importedSteps: Int?
    var stepsEstimate: Double?
    var importedActiveKcal: Double?
    /// Apple Health weight for the day (or its most recent reading before it).
    var healthWeightKg: Double?
    var profileWeightKg: Double
    var unitSystem: UnitSystem
    var fahrenheit: Bool
    /// The selected day's key ("yyyy-MM-dd"): the stamp for values that belong to it outright.
    var dayKey: String? = nil
    /// The day the Apple Health weight was recorded on.
    var healthWeightDay: String? = nil
    /// The day the skin-temperature reading came from (the day itself or a carry).
    var skinTempDay: String? = nil
}

struct SummaryMetricReading: Equatable {
    enum ChartStyle: Equatable { case line, bars }

    /// Formatted number, or `noValue`.
    let value: String
    /// Trailing unit drawn smaller and secondary; empty when the value already carries it.
    let unit: String
    let caption: String?
    /// Key into the loader's 7-day series (`SummarySnapshot.series`).
    let seriesKey: String
    let chart: ChartStyle
    let route: TabRoute
    /// The day ("yyyy-MM-dd") the value was measured on — the card's Health-style recency stamp. nil when
    /// the value has no day of its own (a profile weight, a missing reading).
    var stampDay: String? = nil

    static let noValue = "–"

    var hasValue: Bool { value != Self.noValue }

    /// nil for the ring metrics (charge / effort / rest), which are never pinned cards.
    static func resolve(_ metric: KeyMetric, _ i: SummaryMetricInputs) -> SummaryMetricReading? {
        switch metric {
        case .charge, .effort, .rest:
            return nil
        case .hrv:
            let row = i.day?.avgHrv != nil ? i.day : i.hrvDay
            return reading(int(row?.avgHrv), String(localized: "ms"), key: "hrv", day: row?.day)
        case .restingHr:
            let row = i.day?.restingHr != nil ? i.day : i.restingHrDay
            return reading(int(row?.restingHr.map(Double.init)), String(localized: "bpm"), key: "rhr", day: row?.day)
        case .bloodOxygen:
            let row = i.day?.spo2Pct != nil ? i.day : i.vitalsDay
            let real = row?.spo2Pct
            let candidate = real == nil ? i.spo2Candidate : nil
            let key = candidate != nil ? "spo2_candidate" : "spo2"
            return reading(int(real ?? candidate), "%", key: key,
                           caption: candidate != nil ? String(localized: "strap estimate (unverified)") : nil,
                           day: real != nil ? row?.day : i.dayKey)
        case .respiratory:
            let row = [i.day, i.vitalsDay, i.respDay].compactMap { $0 }.first { $0.respRateBpm != nil }
            return reading(decimal(row?.respRateBpm), String(localized: "br/min"), key: "resp_rate", day: row?.day)
        case .steps:
            let count = i.day?.steps.map(Double.init) ?? i.importedSteps.map(Double.init) ?? i.stepsEstimate
            let detail = MetricCatalog.todayStepsMetric(hasMeasuredSteps: i.day?.steps != nil,
                                                        hasImportedSteps: i.importedSteps != nil)
            let key = detail?.key ?? "steps_est"
            return SummaryMetricReading(value: grouped(count), unit: "", caption: nil,
                                        seriesKey: "steps",
                                        chart: .bars, route: route(key: key, source: detail?.source),
                                        stampDay: count == nil ? nil : i.dayKey)
        case .calories:
            let kcal = i.importedActiveKcal ?? i.day?.activeKcalEst
            let detail = MetricCatalog.todayCaloriesMetric(hasImportedKcal: i.importedActiveKcal != nil,
                                                           hasOnDeviceKcal: i.day?.activeKcalEst != nil)
            return SummaryMetricReading(value: int(kcal), unit: kcal == nil ? "" : String(localized: "kcal"),
                                        caption: nil, seriesKey: "energy_kcal", chart: .bars,
                                        route: route(key: detail?.key ?? "energy_kcal", source: detail?.source),
                                        stampDay: kcal == nil ? nil : i.dayKey)
        case .weight:
            let unit = i.unitSystem == .imperial ? String(localized: "lb") : String(localized: "kg")
            let mass = { (kg: Double) in decimal(i.unitSystem == .imperial ? UnitFormatter.kgToPounds(kg) : kg) }
            if let kg = i.healthWeightKg {
                return reading(mass(kg), unit, key: "weight", day: i.healthWeightDay)
            }
            // A profile figure was typed in, not measured: it has no day, so it says where it came from.
            return reading(mass(i.profileWeightKg), unit, key: "weight", caption: String(localized: "from profile"))
        case .skinTemp:
            return reading(TodayView.skinTempCardValue(reading: i.skinTempReading, fahrenheit: i.fahrenheit),
                           "", key: "skin_temp", day: i.skinTempReading == nil ? nil : i.skinTempDay)
        }
    }

    // MARK: - Helpers

    private static func reading(_ value: String, _ unit: String, key: String,
                                caption: String? = nil, day: String? = nil) -> SummaryMetricReading {
        let has = value != noValue
        return SummaryMetricReading(value: value, unit: has ? unit : "", caption: caption,
                                    seriesKey: key, chart: .line, route: .metric(key),
                                    stampDay: has ? day : nil)
    }

    private static func route(key: String, source: String?) -> TabRoute {
        source.map { .metricSourced(key: key, source: $0) } ?? .metric(key)
    }

    static func int(_ v: Double?) -> String {
        v.map { String(Int($0.rounded())) } ?? noValue
    }

    /// One decimal in the app language's own separator ("79,9" in Russian, "79.9" in English).
    static func decimal(_ v: Double?) -> String {
        guard let v, v.isFinite else { return noValue }
        return v.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.activeLocale))
    }

    static func grouped(_ v: Double?) -> String {
        guard let v else { return noValue }
        return Int(v).formatted(.number.grouping(.automatic).locale(AppLanguage.activeLocale))
    }
}

/// A Health card's recency stamp: "Today", "Yesterday", or the short date the value was measured on.
/// Pure over two day keys so the words never depend on when the view happens to redraw.
enum SummaryStamp {
    static func text(dayKey: String?, todayKey: String, calendar: Calendar = .current) -> String? {
        guard let dayKey else { return nil }
        if dayKey == todayKey { return String(localized: "Today") }
        guard let day = date(dayKey, calendar), let today = date(todayKey, calendar) else { return nil }
        let back = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if back == 1 { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.activeLocale))
    }

    private static func date(_ key: String, _ calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// Clamped ring fill. Never below 0 or past one full lap; a missing value is an empty ring.
enum RingFraction {
    static func of(_ value: Double?, max: Double) -> Double {
        guard let value, max > 0, value.isFinite else { return 0 }
        return Swift.max(0, Swift.min(1, value / max))
    }
}
