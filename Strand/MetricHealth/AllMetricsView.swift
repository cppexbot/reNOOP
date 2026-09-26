//  AllMetricsView.swift
//  NOOP · All Metrics — the whole metric catalog as the iOS 26 Health app lays out its data: one section
//  per Health category, one card per data type (tinted icon and name, when it was measured, the latest
//  reading and a week's mini chart), each opening that metric's page. Metrics with no readings collapse
//  into one row at the bottom.

import SwiftUI
import StrandDesign
import StrandAnalytics

/// The Health app's categories the catalog falls into.
enum HealthCategory: String, CaseIterable, Identifiable {
    case activity, bodyMeasurements, heart, mentalWellbeing, nutrition, respiratory, sleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return String(localized: "Activity")
        case .bodyMeasurements: return String(localized: "Body Measurements")
        case .heart: return String(localized: "Heart")
        case .mentalWellbeing: return String(localized: "Mental Wellbeing")
        case .nutrition: return String(localized: "Nutrition")
        case .respiratory: return String(localized: "Respiratory")
        case .sleep: return String(localized: "Sleep")
        }
    }

    /// The glyph every card in the category carries, as Health's category pages draw them.
    var icon: String {
        switch self {
        case .activity: return "flame.fill"
        case .bodyMeasurements: return "figure"
        case .heart: return "heart.fill"
        case .mentalWellbeing: return "brain.head.profile.fill"
        case .nutrition: return "carrot.fill"
        case .respiratory: return "lungs.fill"
        case .sleep: return "bed.double.fill"
        }
    }
}

/// The pure half of All Metrics: which category a metric sits in, which source a metric recorded by
/// several shows, and the order of it all.
enum AllMetricsCatalog {

    static func category(_ metric: MetricDescriptor) -> HealthCategory {
        switch metric.key {
        case "resp_rate", "spo2": return .respiratory
        // Health files wrist temperature under Body Measurements.
        case "weight", "body_fat", "lean_mass", "bmi", "skin_temp": return .bodyMeasurements
        case "stress", "mood": return .mentalWellbeing
        case "energy_kcal": return .activity
        default: break
        }
        switch metric.category {
        case "Heart", "Charge": return .heart
        case "Rest": return .sleep
        case "Effort": return .activity
        case "Nutrition": return .nutrition
        case "Mind": return .mentalWellbeing
        default: return .bodyMeasurements
        }
    }

    /// Which source wins a key recorded by several when their newest readings fall on the same day.
    static let sourcePriority = ["my-whoop", "apple-health", "xiaomi-band"]

    /// One descriptor per key, in the order the keys first appear: the source with the newest reading
    /// (`latestDay`, by metric id), and on a tie — or when none has one — the higher `sourcePriority`.
    static func oneSourcePerKey(_ metrics: [MetricDescriptor], latestDay: [String: String]) -> [MetricDescriptor] {
        func rank(_ m: MetricDescriptor) -> Int { sourcePriority.firstIndex(of: m.source) ?? sourcePriority.count }
        func beats(_ a: MetricDescriptor, _ b: MetricDescriptor) -> Bool {
            let da = latestDay[a.id] ?? "", db = latestDay[b.id] ?? ""
            return da != db ? da > db : rank(a) < rank(b)
        }
        var order: [String] = []
        var best: [String: MetricDescriptor] = [:]
        for m in metrics {
            if let current = best[m.key] {
                if beats(m, current) { best[m.key] = m }
            } else {
                order.append(m.key)
                best[m.key] = m
            }
        }
        return order.compactMap { best[$0] }
    }

    struct Section: Identifiable {
        let category: HealthCategory
        let metrics: [MetricDescriptor]
        var id: HealthCategory { category }
    }

    /// Categories in the order Health lists them — alphabetically in the reader's language — each with
    /// its metrics alphabetically by name. Empty categories are left out.
    static func sections(_ metrics: [MetricDescriptor],
                         title: (HealthCategory) -> String = { $0.title }) -> [Section] {
        let grouped = Dictionary(grouping: metrics, by: category)
        return grouped
            .map { Section(category: $0.key,
                           metrics: $0.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
            .sorted { title($0.category).localizedStandardCompare(title($1.category)) == .orderedAscending }
    }

    /// The name a pinned Summary card gives the metric (the short "HRV"), used when the catalog name does
    /// not fit a card's title row. Never for the estimate and the two calorie series, which share one
    /// Summary card and must stay told apart here.
    static func shortTitle(_ metric: MetricDescriptor) -> String {
        guard !["steps_est", "energy_kcal", "active_kcal"].contains(metric.key) else { return metric.title }
        return MetricHealthStyle.keyMetric(for: metric.key)?.title ?? metric.title
    }

    /// The search field matches a metric's name or its category's, ignoring case and accents.
    static func matches(_ metric: MetricDescriptor, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return shortTitle(metric).range(of: q, options: options) != nil
            || metric.title.range(of: q, options: options) != nil
            || category(metric).title.range(of: q, options: options) != nil
    }
}

struct AllMetricsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""

    /// A metric's card: its newest reading and the week it closes.
    struct Reading {
        let day: String
        let value: Double
        let week: [Double]
        let chart: SummaryMetricReading.ChartStyle
    }

    /// By metric id; only metrics with at least one reading.
    @State private var readings: [String: Reading] = [:]
    @State private var loaded = false
    @State private var query = ""
    @State private var showsEmpty = false

    private var units: MetricHealthStyle.Units {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        return .init(system: system,
                     temperature: UnitPrefs.resolveTemperature(system: system, override: temperatureRaw),
                     effortScale: UnitPrefs.resolveEffortScale(effortScaleRaw))
    }

    private var withData: [MetricDescriptor] {
        AllMetricsCatalog.oneSourcePerKey(MetricCatalog.all.filter { readings[$0.id] != nil },
                                          latestDay: readings.mapValues(\.day))
    }

    private var withoutData: [MetricDescriptor] {
        let shown = Set(withData.map(\.key))
        return AllMetricsCatalog.oneSourcePerKey(MetricCatalog.all.filter { !shown.contains($0.key) }, latestDay: [:])
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var todayKey: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var body: some View {
        let sections = AllMetricsCatalog.sections(withData.filter { AllMetricsCatalog.matches($0, query: query) })
        let empty = loaded ? withoutData.filter { AllMetricsCatalog.matches($0, query: query) } : []
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, NoopMetrics.space8)
                }
                ForEach(sections) { section in
                    SummarySectionHeader(title: "\(section.category.title)")
                    ForEach(section.metrics) { metric in
                        if let reading = readings[metric.id] {
                            NavigationLink(value: TabRoute.metricSourced(key: metric.key, source: metric.source)) {
                                card(metric, reading, category: section.category)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !empty.isEmpty {
                    emptySection(empty, expanded: showsEmpty || !query.isEmpty)
                        .padding(.top, NoopMetrics.space4)
                }
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.bottom, NoopMetrics.space8 + NoopMetrics.tabBarClearance)
            #if os(macOS)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            #endif
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("All Metrics"))
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        #if os(iOS)
        // Under the large title, as Settings and Health's Search page keep it, rather than hidden until a pull.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        #else
        .searchable(text: $query)
        #endif
        .overlay {
            if loaded && sections.isEmpty && empty.isEmpty && !query.isEmpty {
                noResults
            }
        }
        .task(id: "\(repo.refreshSeq)|\(skinTempDisplayRaw)") { await load() }
    }

    // MARK: - Card

    /// The Health data-type card: category glyph and the metric's name in its hue, when it was measured,
    /// the latest figure, and the week at the trailing edge.
    private func card(_ metric: MetricDescriptor, _ reading: Reading, category: HealthCategory) -> some View {
        let tint = MetricHealthStyle.tint(metric)
        let tokens = MetricHealthStyle.tokens(metric, reading.value, units: units)
        return SummaryCard {
            VStack(alignment: .leading, spacing: 10) {
                let stamp = SummaryStamp.text(dayKey: reading.day, todayKey: todayKey)
                ViewThatFits(in: .horizontal) {
                    SummaryCardTitleRow(icon: category.icon, title: metric.title, tint: tint, trailing: stamp)
                    SummaryCardTitleRow(icon: category.icon, title: AllMetricsCatalog.shortTitle(metric), tint: tint,
                                        trailing: stamp)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                            Text(verbatim: token.text)
                                .font(token.isUnit ? StrandFont.subhead.weight(.semibold)
                                                   : StrandFont.number(24, weight: .bold))
                                .foregroundStyle(token.isUnit ? StrandPalette.textSecondary : StrandPalette.textPrimary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    SummaryMiniChart(values: reading.week, style: reading.chart, tint: tint)
                        .frame(width: 72, height: 30)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Metrics without data

    /// One row that opens the plain list of metrics nothing has recorded yet. Always open while searching.
    private func emptySection(_ metrics: [MetricDescriptor], expanded: Bool) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(StrandMotion.interactive) { showsEmpty.toggle() }
            } label: {
                HStack {
                    Text("Metrics Without Data")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Text(verbatim: "\(metrics.count)")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(metrics) { metric in
                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    NavigationLink(value: TabRoute.metricSourced(key: metric.key, source: metric.source)) {
                        HStack {
                            Text(metric.title)
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(StrandPalette.summaryCard,
                    in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
    }

    @ViewBuilder private var noResults: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            ContentUnavailableView.search(text: query)
        } else {
            Text("No Results")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    // MARK: - Load

    /// One pass over the catalog: which metrics hold readings at all, then — for those only, together —
    /// each one's series through the loader its page uses, kept as the newest reading and its week.
    private func load() async {
        let repo = repo
        let prefer = SkinTempDisplay.Kind(rawValue: skinTempDisplayRaw) ?? .absolute
        let nonEmpty = await repo.nonEmptyMetricIDs(MetricCatalog.all)
        let candidates = MetricCatalog.all.filter { nonEmpty.contains($0.id) }
        var found: [String: Reading] = [:]
        await withTaskGroup(of: (String, Reading?).self) { group in
            for metric in candidates {
                group.addTask { @MainActor in
                    guard let loaded = await MetricSeriesLoader.load(metric, repo: repo, skinTemp: prefer,
                                                                     provenance: false),
                          let last = loaded.series.last else { return (metric.id, nil) }
                    let week = MetricHealthSeries.window(series: loaded.series, range: .week, today: Date(),
                                                         calendar: .current).points.map(\.value)
                    let mark = MetricHealthStyle.chart(metric, series: loaded.series).mark
                    let chart: SummaryMetricReading.ChartStyle = mark == .bars ? .bars : .line
                    return (metric.id, Reading(day: last.day, value: last.value, week: week, chart: chart))
                }
            }
            for await (id, reading) in group {
                if let reading { found[id] = reading }
            }
        }
        guard !Task.isCancelled else { return }
        readings = found
        loaded = true
    }
}

