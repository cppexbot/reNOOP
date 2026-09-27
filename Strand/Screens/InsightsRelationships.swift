//  InsightsRelationships.swift
//  NOOP · the correlation half of What Moves You: how the body's metrics move together, and what
//  tracks the logged mood. Moved here from the old Insights screen and its Mind card when the
//  journal became its own screen; the logic and copy are unchanged.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// A curated metric relationship plus its computed correlation.
struct MetricRelationship: Identifiable {
    let id: String
    let title: String        // "Sleep → Recovery"
    let blurb: String        // what the pairing probes
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
                             blurb: String(localized: "How closely a good night tracks next-morning charge."),
                             corr: c))
        }
        // HRV ↔ recovery (same day).
        if let c = CorrelationEngine.pearson(
            CorrelationEngine.alignByDay(series("hrv"), series("recovery"))) {
            out.append(.init(id: "hrv-rec",
                             title: String(localized: "HRV ↔ Charge"),
                             blurb: String(localized: "Heart-rate variability as the engine behind your charge score."),
                             corr: c))
        }
        // Resting HR ↔ recovery (same day), expected to be negative.
        if let c = CorrelationEngine.pearson(
            CorrelationEngine.alignByDay(series("rhr"), series("recovery"))) {
            out.append(.init(id: "rhr-rec",
                             title: String(localized: "Resting HR ↔ Charge"),
                             blurb: String(localized: "A lower resting heart rate usually means a higher charge."),
                             corr: c))
        }
        // Today's recovery ↔ NEXT-day recovery (1-day lag) as a strain/carry-over proxy.
        // (Strain series isn't in the outcome set; recovery→next-day recovery shows
        //  how much yesterday carries into today.)
        if let c = CorrelationEngine.lagged(x: series("recovery"), y: series("recovery"), lagDays: 1) {
            out.append(.init(id: "rec-lag",
                             title: String(localized: "Charge → Next-day charge"),
                             blurb: String(localized: "How much one day's charge carries into the next."),
                             corr: c))
        }

        return out
    }

}

/// "Metric Relationships": the curated pairs as rows with a centred r bar.
struct MetricRelationshipsSection: View {
    let relationships: [MetricRelationship]

    var body: some View {
        let rels = relationships
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Metric Relationships", overline: "Pearson r")

            if rels.isEmpty {
                NoopCard {
                    Text("Not enough overlapping history to correlate your metrics yet.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                NoopCard(tint: DomainTheme.charge.color) {
                    VStack(spacing: 0) {
                        ForEach(Array(rels.enumerated()), id: \.element.id) { idx, rel in
                            relationshipRow(rel)
                            if idx < rels.count - 1 {
                                Divider().overlay(StrandPalette.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func relationshipRow(_ rel: MetricRelationship) -> some View {
        let r = rel.corr.r
        let strength = correlationColor(r)
        // Build the reading sentence ONCE and reuse it for the visible copy and
        // the accessibility label (was computed twice per row).
        let sentence = relationshipSentence(rel)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Liquid magnitude accent: a small filling vessel showing |r| in the correlation's
                // strength colour, the same leading-gauge idiom Today's card rows + vitals use. Static
                // (a small gauge doesn't need live slosh); decorative, the exact r + a11y read below.
                LiquidVessel(value: min(1, abs(r)), tint: strength, animated: false)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text(rel.title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Text(String(format: "r = %+.2f", r))
                    .font(StrandFont.number(16))
                    .foregroundStyle(strength)
                StatePill(rel.corr.pApprox < 0.05 ? "p < 0.05" : "n.s.",
                          tone: rel.corr.pApprox < 0.05 ? .accent : .neutral,
                          showsDot: false)
            }

            // r bar, visual magnitude/direction (hover reveals the exact value).
            RBar(r: r, color: strength, label: rel.title)

            Text(sentence)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(rel.blurb)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sentence)
    }

    /// |r| → strength word.
    private func strengthWord(_ r: Double) -> String {
        switch abs(r) {
        case ..<0.1:  return String(localized: "no")
        case ..<0.3:  return String(localized: "a weak")
        case ..<0.5:  return String(localized: "a moderate")
        case ..<0.7:  return String(localized: "a strong")
        default:      return String(localized: "a very strong")
        }
    }

    /// Tint a correlation by strength, keyed on the recovery gradient so strong
    /// positive reads mint and strong negative reads red.
    private func correlationColor(_ r: Double) -> Color {
        // Map r∈[-1,1] → 0…1 of the recovery scale (−1 red, 0 gold, +1 mint).
        StrandPalette.sample(stops: StrandPalette.recoveryStops, at: (r + 1) / 2)
    }

    private func relationshipSentence(_ rel: MetricRelationship) -> String {
        let r = rel.corr.r
        let dir = r > 0 ? String(localized: "positive") : (r < 0 ? String(localized: "negative") : String(localized: "flat"))
        let strength = strengthWord(r)
        return String(localized: "\(strength.capitalizedFirst) \(dir) relationship (r = \(String(format: "%.2f", r)), n = \(rel.corr.n)).")
    }
}

/// What tracks the logged mood: up to three body signals whose correlation with mood clears the gate.
/// Self-loading, as the Mind card it came from.
struct MoodLinksSection: View {
    @EnvironmentObject var repo: Repository
    @State private var lines: [MoodLine] = []
    @State private var moodDayCount = 0

    /// Minimum mood days AND minimum paired observations before any line shows.
    private static let minDays = 7
    /// Minimum correlation magnitude worth a sentence.
    private static let minAbsR = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            if !lines.isEmpty { insightsCard }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    // MARK: - Insights card

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            Text("What tracks your mood (\(moodDayCount) check-ins)")
                .strandOverline()
            // Each correlation as its own frosted Rest-tinted insight card. The indigo wash is
            // calm and carries no valence — a link is just a link, never framed as good or bad.
            ForEach(lines) { line in
                NoopCard(tint: StrandPalette.restColor) {
                    HStack(alignment: .top, spacing: 12) {
                        // A small liquid vessel filled to the link's strength (|r|) marks the row and reads
                        // its magnitude at a glance — the leading-gauge idiom Insights' effect cards use.
                        // Rest-tinted so it carries no valence (a link is just a link, never good or bad).
                        LiquidVessel(value: line.strength, tint: StrandPalette.restBright, animated: false)
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.text)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(line.caption)
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// One rendered correlation sentence.
    private struct MoodLine: Identifiable {
        let id: String
        let text: String
        let caption: String
        /// Correlation magnitude 0...1 (|r|), for the leading strength vessel.
        let strength: Double
    }

    // MARK: - Load

    private func load() async {
        let mood = await repo.moodSeries()
        let days = repo.days
        func bodySeries(_ pick: (DailyMetric) -> Double?) -> [(day: String, value: Double)] {
            days.compactMap { d in pick(d).map { (day: d.day, value: $0) } }
        }
        let candidates: [(id: String, name: String, series: [(day: String, value: Double)])] = [
            ("mind-hrv", "HRV", bodySeries { $0.avgHrv }),
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
        moodDayCount = mood.count
        lines = built
    }

    /// Plain-English sentence + factual caption for one mood↔metric correlation.
    /// Descriptive, never predictive or prescriptive ("tend to be", not "will be").
    private static func moodLine(id: String, metric: String, corr: Correlation) -> MoodLine {
        let strength: String = {
            switch abs(corr.r) {
            case ..<0.5: return String(localized: "Moderate")
            case ..<0.7: return String(localized: "Strong")
            default:     return String(localized: "Very strong")
            }
        }()
        let text = corr.r > 0
            ? String(localized: "Days with higher \(metric) tend to be your better-mood days.")
            : String(localized: "Days with higher \(metric) tend to be your lower-mood days.")
        let caption = String(localized: "\(strength) link · r = \(String(format: "%+.2f", corr.r)) · n = \(corr.n) days")
        // |r| capped at 1 for the leading strength vessel's fill.
        return MoodLine(id: id, text: text, caption: caption, strength: min(1, abs(corr.r)))
    }
}

/// A centred correlation bar (zero in the middle, fills left/negative or
/// right/positive by |r|). On hover it shows the locked ChartTooltip with the exact
/// r value, matching the hover affordance every other Strand chart provides.
private struct RBar: View {
    let r: Double
    let color: Color
    let label: String

    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let mag = CGFloat(min(abs(r), 1.0)) * half
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.surfaceInset)
                // centre tick
                Rectangle()
                    .fill(StrandPalette.hairlineStrong)
                    .frame(width: 1)
                    .position(x: half, y: geo.size.height / 2)
                // value fill
                Capsule()
                    .fill(color)
                    .frame(width: mag, height: geo.size.height)
                    .offset(x: r >= 0 ? half : half - mag)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        // Tooltip floats above the bar without affecting layout (overlays aren't
        // clipped), so the exact r value reads on hover, same affordance as charts.
        .overlay(alignment: .center) {
            if hovering {
                ChartTooltip(
                    value: String(format: "r = %+.2f", r),
                    label: label,
                    accent: color
                )
                .fixedSize()
                .offset(y: -26)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active: hovering = true
            case .ended:  hovering = false
            }
        }
        .animation(StrandMotion.fade, value: hovering)
        .accessibilityHidden(true)
    }
}

private extension String {
    /// Capitalise only the first letter (keeps "a weak" → "A weak").
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
