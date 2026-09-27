//  HealthTrendLoader.swift
//  NOOP · Trends — every metric's trend, read from the same series its page draws (`MetricSeriesLoader`)
//  and one source per metric, as All Metrics picks it, so a card and the page it opens always agree.

import Foundation
import StrandAnalytics

struct HealthTrendItem: Identifiable {
    let metric: MetricDescriptor
    let trend: HealthTrend
    var id: String { metric.id }
}

struct HealthTrendsSnapshot {
    /// Only the metrics with a trend, in `HealthTrendDetector.precedes` order.
    var items: [HealthTrendItem] = []
    /// Whether any metric had enough recent readings to be judged at all: tells "no trends" apart from
    /// "not enough data yet".
    var anyJudged = false
}

@MainActor
enum HealthTrendLoader {

    /// nil when cancelled.
    static func load(repo: Repository, skinTemp: SkinTempDisplay.Kind, today: Date = Date()) async -> HealthTrendsSnapshot? {
        let nonEmpty = await repo.nonEmptyMetricIDs(MetricCatalog.all)
        let candidates = MetricCatalog.all.filter { nonEmpty.contains($0.id) }
        var series: [String: [(day: String, value: Double)]] = [:]
        await withTaskGroup(of: (String, [(day: String, value: Double)]).self) { group in
            for metric in candidates {
                group.addTask { @MainActor in
                    let loaded = await MetricSeriesLoader.load(metric, repo: repo, skinTemp: skinTemp, provenance: false)
                    return (metric.id, loaded?.series ?? [])
                }
            }
            for await (id, values) in group where !values.isEmpty {
                series[id] = values
            }
        }
        guard !Task.isCancelled else { return nil }
        let chosen = AllMetricsCatalog.oneSourcePerKey(candidates.filter { series[$0.id] != nil },
                                                       latestDay: series.compactMapValues { $0.last?.day })
        let todayKey = Repository.localDayKey(today)
        var snapshot = HealthTrendsSnapshot()
        for metric in chosen {
            switch HealthTrendDetector.detect(series: series[metric.id] ?? [], today: todayKey,
                                              higherIsBetter: metric.higherIsBetter) {
            case .trend(let trend):
                snapshot.anyJudged = true
                snapshot.items.append(HealthTrendItem(metric: metric, trend: trend))
            case .steady:
                snapshot.anyJudged = true
            case .insufficient:
                break
            }
        }
        snapshot.items.sort { HealthTrendDetector.precedes($0.trend, $1.trend) }
        return snapshot
    }
}
