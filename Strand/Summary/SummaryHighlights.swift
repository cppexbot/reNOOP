//  SummaryHighlights.swift
//  NOOP · Summary home — which readiness signals earn a "Highlights" card.
//
//  Pure: `ReadinessEngine.Readiness` in, at most three cards out. A neutral signal is not news, so it is
//  never a highlight; the rest are ordered most-concerning first so a warning cannot sit below a
//  compliment.

import Foundation
import StrandAnalytics

struct SummaryHighlight: Equatable, Identifiable {
    /// The engine's signal key ("hrv" | "rhr" | "respRate" | "acwr" | "monotony").
    let key: String
    let flag: ReadinessEngine.Flag
    let title: String
    /// One full sentence in plain language (`ReadinessCopy.sentence`).
    let sentence: String
    /// Measured-vs-baseline figures, when the engine gave them.
    let evidence: String?
    /// The same figures as numbers, for the card's side-by-side read-out.
    let evidenceData: ReadinessEngine.Evidence?
    /// `MetricCatalog` key the card taps through to.
    let routeKey: String

    var id: String { key }

    static let maxCount = 3

    static func from(_ readiness: ReadinessEngine.Readiness?) -> [SummaryHighlight] {
        guard let readiness, readiness.level != .insufficient else { return [] }
        return readiness.signals
            .filter { $0.flag != .neutral }
            .enumerated()
            .sorted { a, b in
                let ra = rank(a.element.flag), rb = rank(b.element.flag)
                return ra != rb ? ra < rb : a.offset < b.offset   // stable within a severity
            }
            .prefix(maxCount)
            .map { make($0.element) }
    }

    /// Where a signal's card taps through. Training load and variety are both Effort stories.
    static func routeKey(for signalKey: String) -> String {
        switch signalKey {
        case "hrv": return "hrv"
        case "rhr": return "rhr"
        case "respRate": return "resp_rate"
        default: return HeroRingMetric.effort
        }
    }

    private static func rank(_ flag: ReadinessEngine.Flag) -> Int {
        switch flag {
        case .bad: return 0
        case .watch: return 1
        case .good: return 2
        case .neutral: return 3
        }
    }

    private static func make(_ signal: ReadinessEngine.Signal) -> SummaryHighlight {
        let title = ReadinessCopy.label(signal.key)
        return SummaryHighlight(
            key: signal.key,
            flag: signal.flag,
            title: title,
            sentence: ReadinessCopy.sentence(signal),
            evidence: ReadinessCopy.evidence(signal.evidenceData),
            evidenceData: signal.evidenceData,
            routeKey: routeKey(for: signal.key)
        )
    }
}
