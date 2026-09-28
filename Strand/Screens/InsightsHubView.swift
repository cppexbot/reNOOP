import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - What Moves You
//
// The n-of-1 "what actually moves YOUR numbers" surface, laid out as Health's Highlights: one card per
// finding — the thing on the title row, one short sentence, a small chart — each opening its details.
// Everything is pure association on the user's own logged days, never advice, diagnosis or cause; the
// method lives behind ⓘ.
//
//  1. Habits — the LAG-AWARE EffectRanker feed for the selected outcome: each journal behaviour at its
//     strongest honest lag ({0,+1,+2} days), with/without means as the card's figure pair.
//  2. Alcohol / caffeine — the personal DoseResponseEngine curve, shrunk toward a documented population
//     prior; a card shows only once the user's own nights, not the prior, carry the curve.
//  3. Metrics and mood — the curated metric-pair correlations and what tracks the logged mood.
//
// All maths lives in StrandAnalytics (EffectRanker / DoseResponseEngine / DoseResponsePriors); this view
// loads the series, shapes the engine inputs, and presents honestly.

struct InsightsHubView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @StateObject private var model = InsightsHubViewModel()
    /// Journal question keys → the names the Journal shows (renames, translated built-ins).
    @StateObject private var catalog = JournalCatalogStore()

    /// The outcome the habit feed is ranked against (Charge / HRV / Rest / RHR).
    @State private var outcome: InsightsHubViewModel.Outcome = .recovery

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !model.loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if model.ranked.isEmpty && model.doseCards.isEmpty && model.relationships.isEmpty {
                    EmptyStateView(title: Text("No Patterns Yet"), systemImage: "sparkles",
                                   description: Text("Keep logging your journal.")) {
                        openJournal
                    }
                    .padding(.top, 60)
                } else {
                    habitsSection
                    doseSection
                    relationshipsSection
                    MoodLinksSection()
                }
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, NoopMetrics.space2)
            .padding(.bottom, NoopMetrics.space8 + NoopMetrics.tabBarClearance)
            #if os(macOS)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            #endif
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("What Moves You"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InfoButton(label: "How to read this") { methodNote }
            }
        }
        .navigationDestination(for: InsightRoute.self) { route in
            switch route {
            case .effect(let behavior):
                if let r = model.ranked.first(where: { $0.behavior == behavior }) {
                    EffectDetailView(effect: r, outcome: outcome, title: catalog.displayName(for: r.behavior))
                }
            case .dose(let id):
                if let card = model.doseCards.first(where: { $0.id == id }) {
                    DoseDetailView(card: card)
                }
            }
        }
        .task(id: repo.refreshSeq) { await model.load(repo: repo) }
        .onChangeCompat(of: outcome) { model.rankFor($0) }
    }

    /// The empty state's way on: the Journal, pushed as Browse pushes it on iPhone; the sidebar row on the Mac.
    @ViewBuilder private var openJournal: some View {
        #if os(iOS)
        NavigationLink(value: MoreDestination.journal) { Text("Open Journal") }
        #else
        Button("Open Journal") { router.openJournal() }
        #endif
    }

    // MARK: Habits (ranked, lag-aware)

    @ViewBuilder private var habitsSection: some View {
        Picker("Outcome", selection: $outcome) {
            ForEach(InsightsHubViewModel.Outcome.allCases) { Text(verbatim: $0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if model.ranked.isEmpty {
            SummaryCard {
                Text("Not enough journal days yet.")
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        } else {
            ForEach(model.ranked, id: \.behavior) { r in
                NavigationLink(value: InsightRoute.effect(r.behavior)) {
                    SummaryCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SummaryCardTitleRow(icon: "checklist", title: catalog.displayName(for: r.behavior),
                                                tint: StrandPalette.healthMind)
                            insightSentence(InsightCopy.effectSentence(r, outcome: outcome))
                            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                            InsightCopy.figures(r.effect, outcome: outcome)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Alcohol / caffeine

    @ViewBuilder private var doseSection: some View {
        if !model.doseCards.isEmpty {
            SummarySectionHeader(title: "Alcohol and Caffeine")
            ForEach(model.doseCards) { card in
                NavigationLink(value: InsightRoute.dose(card.id)) {
                    SummaryCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SummaryCardTitleRow(icon: card.symbol, title: card.title, tint: card.tint)
                            insightSentence(card.sentence)
                            DoseCurveChart(points: card.response.curve, accent: card.tint)
                                .frame(height: 56)
                                .padding(.top, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Metric relationships

    @ViewBuilder private var relationshipsSection: some View {
        if !model.relationships.isEmpty {
            SummarySectionHeader(title: "Metrics")
            ForEach(model.relationships) { rel in
                SummaryCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SummaryCardTitleRow(icon: "arrow.left.arrow.right", title: rel.title,
                                            tint: KeyMetric.charge.healthTint, chevron: false)
                        insightSentence(InsightCopy.relationshipSentence(rel.corr.r))
                        RBar(r: rel.corr.r, color: KeyMetric.charge.healthTint)
                            .padding(.top, 4)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func insightSentence(_ text: String) -> some View {
        Text(verbatim: text)
            .font(StrandFont.headline)
            .foregroundStyle(StrandPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// ⓘ: how to read every card on this page.
    @ViewBuilder private var methodNote: some View {
        Text("Association, not cause")
            .font(StrandFont.headline)
        Text("Everything here is a pattern in your own logged days: an association with an effect size and confidence, never a cause or a diagnosis. Population patterns are shown as \u{201C}typical\u{201D} and are always overridden by your own data once you have enough of it. Approximations, not WHOOP\u{2019}s scores; not a medical device.")
            .foregroundStyle(StrandPalette.textSecondary)
    }
}

/// A pushed finding. Values, not closures, so the Browse stack's path can pop them (#198).
enum InsightRoute: Hashable {
    case effect(String)
    case dose(String)
}


// MARK: - Copy

/// The one place a finding becomes words and figures, shared by its card and its details page so the two
/// cannot disagree.
enum InsightCopy {
    /// "Charge is 8 % lower the next day." — whole-sentence variants per direction and lag.
    static func effectSentence(_ r: RankedEffect, outcome: InsightsHubViewModel.Outcome) -> String {
        let e = r.effect
        let name = outcome.label
        guard e.delta != 0 else { return String(localized: "\(name) is no different.") }
        let size = magnitude(e, outcome: outcome)
        let lower = e.delta < 0
        switch (r.lag, lower) {
        case (0, true):  return String(localized: "\(name) is \(size) lower the same day.")
        case (0, false): return String(localized: "\(name) is \(size) higher the same day.")
        case (1, true):  return String(localized: "\(name) is \(size) lower the next day.")
        case (1, false): return String(localized: "\(name) is \(size) higher the next day.")
        case (_, true):  return String(localized: "\(name) is \(size) lower \(r.lag) days later.")
        case (_, false): return String(localized: "\(name) is \(size) higher \(r.lag) days later.")
        }
    }

    /// "~8 %" when the engine gives a relative change, the outcome's own unit otherwise.
    static func magnitude(_ e: BehaviorEffect, outcome: InsightsHubViewModel.Outcome) -> String {
        if let pct = e.pctChange {
            return "~" + (abs(pct) / 100).formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.activeLocale))
        }
        return "~" + outcome.format(abs(e.delta))
    }

    /// With vs Without, as the card and the details page both draw it.
    static func figures(_ e: BehaviorEffect, outcome: InsightsHubViewModel.Outcome) -> HighlightFigures {
        HighlightFigures(leftTitle: String(localized: "Yes"), left: outcome.number(e.meanWith),
                         rightTitle: String(localized: "No"), right: outcome.number(e.meanWithout),
                         unit: outcome.unit, leftValue: e.meanWith, rightValue: e.meanWithout,
                         tint: outcome.tint)
    }

    static func relationshipSentence(_ r: Double) -> String {
        switch (abs(r), r >= 0) {
        case (..<0.1, _):     return String(localized: "No link.")
        case (..<0.3, true):  return String(localized: "Weak link: they rise together.")
        case (..<0.3, false): return String(localized: "Weak link: when one rises, the other falls.")
        case (..<0.5, true):  return String(localized: "Moderate link: they rise together.")
        case (..<0.5, false): return String(localized: "Moderate link: when one rises, the other falls.")
        case (..<0.7, true):  return String(localized: "Strong link: they rise together.")
        case (..<0.7, false): return String(localized: "Strong link: when one rises, the other falls.")
        case (_, true):       return String(localized: "Very strong link: they rise together.")
        case (_, false):      return String(localized: "Very strong link: when one rises, the other falls.")
        }
    }

    /// Cohen's d → conventional magnitude word.
    static func effectMagnitudeWord(_ d: Double) -> String {
        switch abs(d) {
        case ..<0.2: return String(localized: "Negligible")
        case ..<0.5: return String(localized: "Small")
        case ..<0.8: return String(localized: "Moderate")
        default:     return String(localized: "Large")
        }
    }

    static func confidenceWord(_ c: ScoreConfidence) -> String {
        switch c {
        case .solid:       return String(localized: "Solid")
        case .building:    return String(localized: "Building")
        case .calibrating: return String(localized: "Calibrating")
        }
    }

    static func lagWord(_ lag: Int) -> String {
        switch lag {
        case 0:  return String(localized: "Same day")
        case 1:  return String(localized: "Next day")
        default: return String(localized: "\(lag) days later")
        }
    }
}

extension InsightsHubViewModel.Outcome {
    /// The Health hue and glyph of the metric the outcome is.
    var tint: Color {
        switch self {
        case .recovery: return KeyMetric.charge.healthTint
        case .hrv:      return KeyMetric.hrv.healthTint
        case .sleep:    return KeyMetric.rest.healthTint
        case .rhr:      return KeyMetric.restingHr.healthTint
        }
    }
    /// The figure without its unit, and the unit alone (the figure pair sets them in two weights).
    func number(_ v: Double) -> String { "\(Int(v.rounded()))" }
    var unit: String {
        switch self {
        case .recovery, .sleep: return "%"
        case .hrv:              return String(localized: "ms")
        case .rhr:              return String(localized: "bpm")
        }
    }
}

// MARK: - Details

/// One habit finding: the sentence and figures from its card, then how the reading was made.
private struct EffectDetailView: View {
    let effect: RankedEffect
    let outcome: InsightsHubViewModel.Outcome
    /// The behaviour as the Journal names it.
    let title: String

    var body: some View {
        let e = effect.effect
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: InsightCopy.effectSentence(effect, outcome: outcome))
                        .font(StrandFont.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    InsightCopy.figures(e, outcome: outcome)
                }
                .padding(.vertical, 6)
            }
            Section {
                LabeledContent("Days With", value: "\(e.nWith)")
                LabeledContent("Days Without", value: "\(e.nWithout)")
                LabeledContent("Shows Up", value: InsightCopy.lagWord(effect.lag))
                LabeledContent("Effect Size", value: InsightCopy.effectMagnitudeWord(e.cohensD))
                LabeledContent("Confidence", value: InsightCopy.confidenceWord(effect.confidence))
            }
        }
        // The name is already resolved (a rename, or a translated built-in), so it is not looked up again.
        .settingsForm()
        .navigationTitle(Text(verbatim: title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Alcohol or caffeine: the personal curve and how sure the reading is. No forecast: an association on
/// past nights is not a prediction for tomorrow.
private struct DoseDetailView: View {
    let card: InsightsHubViewModel.DoseCard

    var body: some View {
        let r = card.response
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: card.sentence)
                        .font(StrandFont.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    DoseCurveChart(points: r.curve, accent: card.tint)
                        .frame(height: 120)
                }
                .padding(.vertical, 6)
            } footer: {
                if card.timingProxy {
                    Text("Dose here is timing: later in the day counts as more.")
                }
            }
            Section {
                LabeledContent("Confidence", value: InsightCopy.confidenceWord(r.confidence))
            }
        }
        .settingsPage(LocalizedStringKey(card.title))
    }
}

// MARK: - Small charts

/// The prior-shrunk dose curve: dose on x, the modelled change on y around a dashed zero line.
struct DoseCurveChart: View {
    let points: [DoseCurvePoint]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxAbs = max(1.0, points.map { abs($0.outcomeDelta) }.max() ?? 1.0)
            let yFor: (Double) -> CGFloat = { d in h - CGFloat((d / maxAbs + 1) / 2) * h }
            let n = max(1, points.count - 1)
            let xFor: (Int) -> CGFloat = { i in CGFloat(i) / CGFloat(n) * w }
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: yFor(0)))
                    p.addLine(to: CGPoint(x: w, y: yFor(0)))
                }
                .stroke(StrandPalette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let point = CGPoint(x: xFor(i), y: yFor(pt.outcomeDelta))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                ForEach(points.indices, id: \.self) { i in
                    Circle()
                        .strokeBorder(accent, lineWidth: 2)
                        .background(Circle().fill(StrandPalette.summaryCard))
                        .frame(width: 8, height: 8)
                        .position(x: xFor(i), y: yFor(points[i].outcomeDelta))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A correlation as a centred bar: zero in the middle, filling left (inverse) or right by |r|.
struct RBar: View {
    let r: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let mag = CGFloat(min(abs(r), 1.0)) * half
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.textTertiary.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: max(mag, 4), height: geo.size.height)
                    .offset(x: r >= 0 ? half : half - mag)
                Rectangle()
                    .fill(StrandPalette.textTertiary)
                    .frame(width: 1.5)
                    .position(x: half, y: geo.size.height / 2)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - View-model
//
// Self-contained: loads the journal (behaviour → days), dose rows (under the dedicated
// noop-journal-dose source), and the outcome series (imported metricSeries ∪ DailyMetric
// fallback, exactly as InsightsView), then runs EffectRanker for the ranked feed and
// DoseResponseEngine for each dosed behaviour the user has data for. No edits to AppModel.

@MainActor
final class InsightsHubViewModel: ObservableObject {

    // MARK: Outcome

    enum Outcome: String, CaseIterable, Identifiable {
        case recovery, hrv, sleep, rhr
        var id: String { rawValue }
        /// The metric's name as Summary's tiles print it (`KeyMetric.title`), so one metric reads one way.
        var label: String {
            switch self {
            case .recovery: return KeyMetric.charge.title
            case .hrv:      return KeyMetric.hrv.title
            case .sleep:    return KeyMetric.rest.title
            case .rhr:      return KeyMetric.restingHr.title
            }
        }
        /// metricSeries key.
        var key: String {
            switch self {
            case .recovery: return "recovery"
            case .hrv:      return "hrv"
            case .sleep:    return "sleep_performance"
            case .rhr:      return "rhr"
            }
        }
        /// The engine's outcome label (carried onto each RankedEffect).
        var outcomeName: String {
            switch self {
            case .recovery: return String(localized: "Charge")
            case .hrv:      return "HRV"
            case .sleep:    return String(localized: "Rest")
            case .rhr:      return String(localized: "Resting HR")
            }
        }
        var higherIsBetter: Bool { self != .rhr }
        func format(_ v: Double) -> String {
            switch self {
            case .recovery, .sleep: return "\(Int(v.rounded()))%"
            case .hrv:              return "\(Int(v.rounded())) ms"
            case .rhr:              return "\(Int(v.rounded())) bpm"
            }
        }
    }

    // MARK: Published state

    @Published private(set) var loaded = false
    @Published private(set) var ranked: [RankedEffect] = []
    @Published private(set) var doseCards: [DoseCard] = []
    /// The curated metric-pair correlations over the same outcome series.
    @Published private(set) var relationships: [MetricRelationship] = []

    // MARK: Loaded inputs (kept so the outcome segmented control can re-rank cheaply)

    private var behaviours: [String: Set<String>] = [:]
    /// Per behaviour, the days it was logged NO — the only legitimate control group.
    private var controls: [String: Set<String>] = [:]
    private var outcomeByKey: [String: [String: Double]] = [:]
    private var currentOutcome: Outcome = .recovery

    /// The source id dose rows are parked under (mirrors MoodStore's noop-mood isolation).
    static let doseSource = "noop-journal-dose"

    private let outcomeKeys = ["recovery", "hrv", "sleep_performance", "rhr"]

    // MARK: Load

    func load(repo: Repository) async {
        // Journal → behaviour → days (only "yes" answers count as the behaviour occurring).
        let entries = await repo.journalEntries()
        // Yes days and NO days, kept apart. A day with no journal row for the question lands in
        // neither, so an unanswered day is never counted as a No (BehaviorInsights.effect).
        var byBehaviour: [String: Set<String>] = [:]
        var controlsByBehaviour: [String: Set<String>] = [:]
        for e in entries {
            if e.answeredYes { byBehaviour[e.question, default: []].insert(e.day) }
            else { controlsByBehaviour[e.question, default: []].insert(e.day) }
        }

        // Outcome series: imported metricSeries ∪ the DailyMetric column fallback so an
        // account-free (strap-only) user still gets effects — the exact contract InsightsView uses.
        let mergedDays = repo.days
        var byKey: [String: [String: Double]] = [:]
        for key in outcomeKeys {
            let s = await repo.series(key: key, source: "my-whoop")
            var dict: [String: Double] = [:]
            for row in s { dict[row.day] = row.value }
            for d in mergedDays where dict[d.day] == nil {
                if let v = Self.dailyOutcome(key: key, day: d) { dict[d.day] = v }
            }
            byKey[key] = dict
        }

        // Dose rows per dosed behaviour, under the dedicated dose source, keyed by the
        // behaviour's storage key. A logged "yes" with no dose row reads as dose = 1
        // (back-compatible), so we union the behaviour's logged days at dose 1 with any
        // explicit dose rows (explicit wins).
        var doseByBehaviour: [DosedBehavior: [String: Int]] = [:]
        for behavior in DosedBehavior.allCases {
            let key = Self.doseKey(for: behavior)
            let rows = await repo.series(key: key, source: Self.doseSource)
            var doses: [String: Int] = [:]
            // Back-compat: any logged "yes" day for a matching journal question starts at dose 1.
            for (question, days) in byBehaviour where Self.matches(behavior, question: question) {
                for day in days { doses[day] = max(doses[day] ?? 0, 1) }
            }
            // Explicit dose rows override.
            for row in rows { doses[row.day] = Int(row.value.rounded()) }
            if !doses.isEmpty { doseByBehaviour[behavior] = doses }
        }

        // Build the dose cards from the engine (alcohol first, then caffeine).
        var cards: [DoseCard] = []
        for behavior in DosedBehavior.allCases {
            guard let doses = doseByBehaviour[behavior] else { continue }
            let outcomeName = DoseResponsePriors.defaultOutcome(for: behavior)
            let outcomeKey = Self.outcomeKey(forEngineName: outcomeName)
            let outcomeDays = byKey[outcomeKey] ?? [:]
            guard let response = DoseResponseEngine.estimate(behavior: behavior,
                                                             doseByDay: doses,
                                                             outcomeByDay: outcomeDays) else { continue }
            // A curve still carried by the population prior is not the user's pattern: no card.
            guard !response.priorDominated else { continue }
            cards.append(DoseCard(behavior: behavior, response: response))
        }

        self.behaviours = byBehaviour
        self.controls = controlsByBehaviour
        self.outcomeByKey = byKey
        self.doseCards = cards
        self.relationships = MetricRelationship.compute(byKey)
        self.loaded = true
        rankFor(currentOutcome)
    }

    /// Re-rank the mover feed for a (possibly new) outcome selection — cheap, no DB.
    func rankFor(_ outcome: Outcome) {
        currentOutcome = outcome
        let outcomeDays = outcomeByKey[outcome.key] ?? [:]
        ranked = EffectRanker.rank(behaviors: behaviours,
                                   controls: controls,
                                   outcomeByDay: outcomeDays,
                                   outcome: outcome.outcomeName)
    }

    // MARK: Static shaping helpers

    /// The merged DailyMetric column backing an outcome key (strap-only fallback). sleep_performance
    /// has no daily column, so it stays import-only — never seeded here (matches InsightsView).
    private static func dailyOutcome(key: String, day d: DailyMetric) -> Double? {
        switch key {
        case "recovery": return d.recovery
        case "hrv":      return d.avgHrv
        case "rhr":      return d.restingHr.map(Double.init)
        default:         return nil
        }
    }

    /// The metricSeries key a DoseResponsePriors outcome NAME maps to ("Charge"→recovery, "HRV"→hrv).
    static func outcomeKey(forEngineName name: String) -> String {
        switch name {
        case "Charge": return "recovery"
        case "HRV":    return "hrv"
        case "Rest":   return "sleep_performance"
        case "Resting HR": return "rhr"
        default:       return "recovery"
        }
    }

    /// The dose storage key for a behaviour (its raw enum value — the stable, cross-platform key).
    static func doseKey(for behavior: DosedBehavior) -> String { "dose_\(behavior.rawValue)" }

    /// Whether a journal question is the dosed behaviour (so its yes-days back-fill dose = 1).
    static func matches(_ behavior: DosedBehavior, question: String) -> Bool {
        let q = question.lowercased()
        switch behavior {
        case .alcohol:  return q.contains("alcohol") || q.contains("drink")
        case .caffeine: return q.contains("caffeine") || q.contains("coffee")
        }
    }

    // MARK: Dose card view-data

    struct DoseCard: Identifiable {
        let behavior: DosedBehavior
        let response: DoseResponse

        var id: String { behavior.rawValue }
        var outcomeName: String { response.outcome }

        var title: String {
            switch behavior {
            case .alcohol:  return String(localized: "Alcohol")
            case .caffeine: return String(localized: "Caffeine")
            }
        }
        var symbol: String {
            switch behavior {
            case .alcohol:  return "wineglass"
            case .caffeine: return "cup.and.saucer.fill"
            }
        }
        var timingProxy: Bool { behavior == .caffeine }

        /// The engine's outcome name ("Charge" / "HRV") in the reader's language.
        var outcomeLabel: String { String(localized: String.LocalizationValue(outcomeName)) }
        var tint: Color { outcomeName == "HRV" ? KeyMetric.hrv.healthTint : KeyMetric.charge.healthTint }

        /// "Next-day Charge is usually lower after drinking." — the card's and the details page's one
        /// sentence: which way the outcome tends to sit, never how much one more causes.
        var sentence: String {
            let name = outcomeLabel
            guard (abs(response.perUnit) * 10).rounded() > 0 else {
                return String(localized: "\(name) doesn\u{2019}t move with it.")
            }
            switch (behavior, response.perUnit < 0) {
            case (.alcohol, true):   return String(localized: "Next-day \(name) is usually lower after drinking.")
            case (.alcohol, false):  return String(localized: "Next-day \(name) is usually higher after drinking.")
            case (.caffeine, true):  return String(localized: "Next-day \(name) is usually lower after late caffeine.")
            case (.caffeine, false): return String(localized: "Next-day \(name) is usually higher after late caffeine.")
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func hubPreviewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    repo.loaded = true
    return repo
}

#Preview("Insights Hub") {
    InsightsHubView()
        .environmentObject(hubPreviewRepo())
        .environmentObject(NavRouter())
        .frame(width: 920, height: 980)
        .preferredColorScheme(.dark)
}
#endif
