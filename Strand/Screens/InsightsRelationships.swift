//  InsightsRelationships.swift
//  NOOP · the correlation half of What Moves You: how the body's metrics move together, and what
//  tracks the logged mood, as Highlights cards on What Moves You.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// A curated metric relationship plus its computed correlation.
struct MetricRelationship: Identifiable {
    let id: String
    let title: String        // "Rest ↔ Charge"
    let corr: Correlation

    static func compute(_ byKey: [String: [String: Double]]) -> [MetricRelationship] {
        func series(_ key: String) -> [(day: String, value: Double)] {
            (byKey[key] ?? [:]).sorted { $0.key < $1.key }.map { (day: $0.key, value: $0.value) }
        }
        var out: [MetricRelationship] = []

        // Sleep performance ↔ recovery (same day).
        if let c = CorrelationEngine.pearson(
            CorrelationEngine.alignByDay(series("sleep_performance"), series("recovery"))) {
            out.append(.init(id: "sleep-rec",
                             title: String(localized: "Rest ↔ Charge"),
                             corr: c))
        }
        // HRV ↔ recovery (same day).
        if let c = CorrelationEngine.pearson(
            CorrelationEngine.alignByDay(series("hrv"), series("recovery"))) {
            out.append(.init(id: "hrv-rec",
                             title: String(localized: "HRV ↔ Charge"),
                             corr: c))
        }
        // Resting HR ↔ recovery (same day), expected to be negative.
        if let c = CorrelationEngine.pearson(
            CorrelationEngine.alignByDay(series("rhr"), series("recovery"))) {
            out.append(.init(id: "rhr-rec",
                             title: String(localized: "Resting HR ↔ Charge"),
                             corr: c))
        }
        // Today's recovery ↔ NEXT-day recovery (1-day lag) as a strain/carry-over proxy.
        // (Strain series isn't in the outcome set; recovery→next-day recovery shows
        //  how much yesterday carries into today.)
        if let c = CorrelationEngine.lagged(x: series("recovery"), y: series("recovery"), lagDays: 1) {
            out.append(.init(id: "rec-lag",
                             title: String(localized: "Charge → Next-day charge"),
                             corr: c))
        }

        return out
    }

}

/// What tracks the logged mood: up to three body signals whose correlation with mood clears the gate.
/// Self-loading, as the Mind card it came from.
struct MoodLinksSection: View {
    @EnvironmentObject var repo: Repository
    @State private var lines: [MoodLine] = []

    /// Minimum mood days AND minimum paired observations before any line shows.
    private static let minDays = 7
    /// Minimum correlation magnitude worth a sentence.
    private static let minAbsR = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !lines.isEmpty { insightsCard }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    // MARK: - Cards

    /// "Mood" and one Highlights card per link: the sentence and the strength bar, no coefficient.
    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Mood")
            ForEach(lines) { line in
                SummaryCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SummaryCardTitleRow(icon: "face.smiling", title: line.metric, tint: StrandPalette.healthMind,
                                            chevron: false)
                        Text(verbatim: line.text)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        RBar(r: line.r, color: StrandPalette.healthMind)
                            .padding(.top, 4)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// One rendered correlation sentence.
    private struct MoodLine: Identifiable {
        let id: String
        let metric: String
        let text: String
        let r: Double
    }

    // MARK: - Load

    private func load() async {
        let mood = await repo.moodSeries()
        let days = repo.days
        func bodySeries(_ pick: (DailyMetric) -> Double?) -> [(day: String, value: Double)] {
            days.compactMap { d in pick(d).map { (day: d.day, value: $0) } }
        }
        let candidates: [(id: String, name: String, series: [(day: String, value: Double)])] = [
            ("mind-hrv", KeyMetric.hrv.title, bodySeries { $0.avgHrv }),
            ("mind-recovery", String(localized: "recovery"), bodySeries { $0.recovery }),
            ("mind-sleep", String(localized: "sleep duration"), bodySeries { $0.totalSleepMin }),
        ]
        var built: [MoodLine] = []
        if mood.count >= Self.minDays {
            var scored: [(id: String, name: String, corr: Correlation)] = []
            for c in candidates {
                guard let corr = CorrelationEngine.pearson(
                        CorrelationEngine.alignByDay(c.series, mood)),
                      corr.n >= Self.minDays,
                      abs(corr.r) >= Self.minAbsR else { continue }
                scored.append((c.id, c.name, corr))
            }
            built = scored
                .sorted { abs($0.corr.r) > abs($1.corr.r) }
                .prefix(3)
                .map { Self.moodLine(id: $0.id, metric: $0.name, corr: $0.corr) }
        }
        lines = built
    }

    /// Plain-English sentence for one mood↔metric correlation. Descriptive, never predictive or
    /// prescriptive ("tend to be", not "will be").
    private static func moodLine(id: String, metric: String, corr: Correlation) -> MoodLine {
        let text = corr.r > 0
            ? String(localized: "Days with higher \(metric) tend to be your better-mood days.")
            : String(localized: "Days with higher \(metric) tend to be your lower-mood days.")
        return MoodLine(id: id, metric: metric.capitalizedFirst, text: text, r: corr.r)
    }
}

private extension String {
    /// Capitalise only the first letter (keeps "a weak" → "A weak").
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
