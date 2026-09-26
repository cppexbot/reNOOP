import Foundation
import StrandAnalytics
import WhoopStore

extension Repository {
    /// The combined steps series the steps detail page reads: measured strap, phone import, then strap estimate.
    func resolvedSteps(from: String, to: String) async -> MetricSeriesResolution {
        async let strap = resolvedSeries(key: "steps", source: Self.whoopSource, from: from, to: to)
        async let phone = resolvedSeries(key: "steps", source: "apple-health", from: from, to: to)
        async let estimate = resolvedSeries(key: "steps_est", source: Self.whoopSource, from: from, to: to)
        let resolutions = await [strap, phone, estimate]
        var byDay: [String: ResolvedMetricPoint] = [:]
        for resolution in resolutions {
            for point in resolution.points where byDay[point.day] == nil { byDay[point.day] = point }
        }
        return MetricSeriesResolution(requestedSource: Self.whoopSource,
                                      candidates: resolutions.flatMap(\.candidates),
                                      points: byDay.values.sorted { $0.day < $1.day })
    }
}
