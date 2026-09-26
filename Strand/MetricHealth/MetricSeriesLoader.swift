//  MetricSeriesLoader.swift
//  NOOP · Metric page — one metric's daily series, read the one way every screen that shows it reads it
//  (the metric's own page and its card in All Metrics), so the two can never disagree.

import Foundation
import StrandAnalytics
import WhoopStore

struct MetricPageSeries {
    /// Ascending by day, all history.
    var series: [(day: String, value: Double)] = []
    /// day → the raw source id that supplied that day's value.
    var sourceByDay: [String: String] = [:]
    /// #1848: why the skin-temp series leads with what it does, when that needs saying.
    var skinTempNote: String?
}

@MainActor
enum MetricSeriesLoader {

    /// The metric's series and per-day provenance. Steps read the store-backed resolver (the full history
    /// when `fullStepsHistory`, since the in-memory explore cache is bounded); every other metric keeps the
    /// explorer's established value path. nil when cancelled.
    ///
    /// `provenance: false` skips the per-day VO₂max estimator lookups, which only "Show All Data" reads.
    static func load(_ metric: MetricDescriptor, repo: Repository, skinTemp: SkinTempDisplay.Kind,
                     fullStepsHistory: Bool = false, provenance: Bool = true) async -> MetricPageSeries? {
        var out = MetricPageSeries()
        let resolution: MetricSeriesResolution
        if MetricHealthStyle.isSteps(metric) {
            if metric.source == MetricCatalog.combinedStepsSource {
                resolution = await repo.resolvedSteps(from: "0000-01-01", to: "9999-12-31")
            } else {
                resolution = await repo.resolvedSeries(key: metric.key, source: metric.source,
                                                       fullHistory: fullStepsHistory)
            }
            out.series = resolution.values
        } else {
            out.series = await repo.exploreSeries(key: metric.key, source: metric.source)
            resolution = await repo.resolvedSeries(key: metric.key, source: metric.source)
        }
        guard !Task.isCancelled else { return nil }
        if metric.key == "vo2max_est" && provenance {
            var attributed: [String: String] = [:]
            for point in resolution.points {
                let tag = await repo.scoreProvenanceTag(
                    resolvedSource: point.source, day: point.day, metricKey: metric.key)
                attributed[point.day] = vo2MaxAttributionSource(tag.flatMap { Vo2MaxEstimator(rawValue: $0) })
            }
            out.sourceByDay = attributed
        } else {
            out.sourceByDay = Dictionary(resolution.points.map { ($0.day, $0.source) },
                                         uniquingKeysWith: { first, _ in first })
        }
        // #103: fill the calibrated SpO₂ series' missing days from the strap candidate, as every other SpO₂
        // surface does when its Experimental toggle is on. Calibrated days always win. WHOOP/Oura only.
        if metric.key == "spo2", metric.source == "my-whoop", PuffinExperiment.spo2CandidateDisplayEnabled {
            let candidateSeries = await repo.exploreSeries(key: "spo2_candidate", source: metric.source)
            if !candidateSeries.isEmpty {
                var byDay = Dictionary(out.series.map { ($0.day, $0.value) }, uniquingKeysWith: { first, _ in first })
                for point in candidateSeries where byDay[point.day] == nil {
                    byDay[point.day] = point.value
                    out.sourceByDay[point.day] = spo2CandidateAttributionSource
                }
                out.series = byDay.sorted { $0.key < $1.key }.map { (day: $0.key, value: $0.value) }
            }
        }
        if metric.key == "skin_temp" { skinTemperature(metric, days: repo.days, prefer: skinTemp, into: &out) }
        return out
    }

    /// #1846/#1848/#1850: the skin-temp series leads with the kind Settings asks for across the whole
    /// history (temperature by default), falls back to the other kind rather than going empty, and says
    /// so when it does. An absolute may sit in either column (#622), so both count.
    private static func skinTemperature(_ metric: MetricDescriptor, days: [DailyMetric],
                                        prefer: SkinTempDisplay.Kind, into out: inout MetricPageSeries) {
        let anyAbsolute = days.contains { row in
            row.skinTempC != nil || row.skinTempDevC.map(VitalBands.isAbsoluteSkinTemp) == true
        }
        let anyDeviation = days.contains { row in
            row.skinTempDevC.map { !VitalBands.isAbsoluteSkinTemp($0) } == true
        }
        guard anyAbsolute || anyDeviation else { return }
        let leadsAbsolute: Bool
        switch prefer {
        case .absolute: leadsAbsolute = anyAbsolute
        case .deviation: leadsAbsolute = !anyDeviation && anyAbsolute
        }
        if leadsAbsolute {
            out.series = days.compactMap { row in
                let v = row.skinTempC ?? row.skinTempDevC.flatMap { VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil }
                return v.map { (day: row.day, value: $0) }
            }.sorted { $0.day < $1.day }
        } else {
            out.series = days.compactMap { row in
                row.skinTempDevC.flatMap { !VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil }.map { (day: row.day, value: $0) }
            }.sorted { $0.day < $1.day }
        }
        out.sourceByDay = Dictionary(out.series.map { ($0.day, metric.source) }, uniquingKeysWith: { first, _ in first })
        let rowsWithEither = days.count { $0.skinTempC != nil || $0.skinTempDevC != nil }
        if shouldExplainSkinTempFallback(prefer: prefer, leadsAbsolute: leadsAbsolute,
                                         anyAbsoluteInWindow: anyAbsolute) {
            out.skinTempNote = String(localized: "No measured temperature for these nights — showing the difference from your baseline instead. A re-score refills temperatures for nights that have one.")
        } else if shouldExplainShortenedSkinTempSeries(leadsAbsolute: leadsAbsolute, shownReadings: out.series.count,
                                                        rowsWithEitherNumber: rowsWithEither) {
            out.skinTempNote = String(localized: "Only nights with a measured temperature are shown — the others only have a baseline difference.")
        }
    }
}
