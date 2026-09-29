//  SleepScore.swift
//  NOOP · Sleep — one night's Rest score split into the parts it is made of, for the Health-style
//  Sleep score ring.
//
//  Pure. The score is the one every other surface shows (`SleepModel.performanceSeries`: an imported
//  WHOOP figure when the export carried one, else `AnalyticsEngine.Rest.composite`). Its parts come from
//  `AnalyticsEngine.Rest.components`, the same function the composite is built from, and are rounded so
//  the points on the rows add up to the number in the ring. An imported score has no known parts, so it
//  is shown whole.

import Foundation
import StrandAnalytics
import WhoopStore

struct SleepScore: Equatable {
    enum Part: String, CaseIterable, Identifiable {
        case duration, interruptions, restorative, regularity
        var id: String { rawValue }

        /// Points this part is worth out of 100 (the composite's weights).
        var maxPoints: Int {
            switch self {
            case .duration: return Int((AnalyticsEngine.Rest.wDuration * 100).rounded())
            case .interruptions: return Int((AnalyticsEngine.Rest.wEfficiency * 100).rounded())
            case .restorative: return Int((AnalyticsEngine.Rest.wRestorative * 100).rounded())
            case .regularity: return Int((AnalyticsEngine.Rest.wConsistency * 100).rounded())
            }
        }

        var label: String {
            switch self {
            case .duration: return String(localized: "Duration")
            case .interruptions: return String(localized: "Interruptions")
            case .restorative: return String(localized: "Deep & REM")
            case .regularity: return String(localized: "Regularity")
            }
        }
    }

    struct PartScore: Equatable, Identifiable {
        let part: Part
        /// Share of this part's points earned, 0…1.
        let fraction: Double
        /// Whole points earned; the parts' points sum to `SleepScore.value`. nil for an imported score,
        /// whose own make-up is unknown.
        let points: Int?
        var id: String { part.id }
    }

    /// 0…100, rounded for display.
    let value: Int
    /// True when the score is WHOOP's own imported figure (its make-up is unknown).
    let imported: Bool
    /// How the night did on each part. For an imported score these are the night's own figures without
    /// points, and regularity (a neutral constant for one night) is left out.
    let parts: [PartScore]

    /// The night's score from its `DailyMetric` row and the imported figure for the same wake-day.
    static func make(daily: DailyMetric?, importedPct: Double?) -> SleepScore? {
        let c = daily.flatMap { AnalyticsEngine.Rest.components(daily: $0) }
        if let importedPct {
            let parts = c.map { c in
                [(Part.duration, c.duration), (.interruptions, c.efficiency), (.restorative, c.restorative)]
                    .map { PartScore(part: $0.0, fraction: $0.1, points: nil) }
            } ?? []
            return SleepScore(value: Int(importedPct.rounded()), imported: true, parts: parts)
        }
        guard let daily, let c, let composite = AnalyticsEngine.Rest.composite(daily: daily) else { return nil }
        let fractions: [(Part, Double)] = [(.duration, c.duration), (.interruptions, c.efficiency),
                                           (.restorative, c.restorative), (.regularity, c.consistency)]
        let total = Int(composite.rounded())
        let points = apportion(fractions.map { Double($0.0.maxPoints) * $0.1 }, total: total)
        let parts = zip(fractions, points).map { PartScore(part: $0.0, fraction: $0.1, points: $1) }
        return SleepScore(value: total, imported: false, parts: parts)
    }

    /// Whole-number shares of `raw` that sum to `total` (largest remainder), so the rows never add up
    /// to a different number than the ring shows.
    static func apportion(_ raw: [Double], total: Int) -> [Int] {
        var out = raw.map { Int($0.rounded(.down)) }
        let short = total - out.reduce(0, +)
        guard short != 0 else { return out }
        let order = raw.indices.sorted { (raw[$0] - Double(out[$0])) > (raw[$1] - Double(out[$1])) }
        if short > 0 {
            for i in order.prefix(short) { out[i] += 1 }
        } else {
            for i in order.reversed().prefix(-short) where out[i] > 0 { out[i] -= 1 }
        }
        return out
    }

    /// The same banding the Rest word has always used.
    static func word(_ value: Int) -> String {
        switch value {
        case ..<50: return String(localized: "Poor")
        case ..<70: return String(localized: "Fair")
        case ..<85: return String(localized: "Good")
        default: return String(localized: "Optimal")
        }
    }
}

extension SleepScore.Part {
    /// The name on the Sleep Score card: Health's own word where Health has the part.
    var cardLabel: String {
        self == .duration ? String(localized: "sleep.score.duration", defaultValue: "Duration") : label
    }
}

extension SleepScore {
    /// The line under the Sleep Score card's parts: the night in one sentence, naming the part that cost it
    /// the most points, or saying it cost almost none.
    var sentence: String {
        guard !imported else { return String(localized: "WHOOP scored this night \(value).") }
        let lost = parts.map { ($0.part, Double($0.part.maxPoints) * (1 - $0.fraction)) }
        guard let worst = lost.max(by: { $0.1 < $1.1 }), lost.reduce(0, { $0 + $1.1 }) >= 10 else {
            return String(localized: "You slept soundly through to morning, and your score was \(value). Excellent!")
        }
        switch worst.0 {
        case .duration: return String(localized: "A longer night would have lifted your score of \(value).")
        case .interruptions: return String(localized: "Waking in the night held your score to \(value).")
        case .restorative: return String(localized: "Less deep and REM sleep held your score to \(value).")
        case .regularity: return String(localized: "Going to bed at an unusual time held your score to \(value).")
        }
    }
}
