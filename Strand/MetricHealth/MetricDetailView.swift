//  MetricDetailView.swift
//  NOOP · Metric page — the one page every metric opens on, laid out like a data type's page in the
//  iOS 26 Health app (Browse → Heart → Heart Rate Variability, Cardio Fitness, Steps…).
//
//  One grouped canvas, cards on it as on the Summary: the W / M / 6M / Y picker, then a card with
//  "AVERAGE", the period's figure and dates (ⓘ explains the metric), the metric's own chart (press and
//  drag to read one mark) and its latest reading; a Highlights card (the latest reading against the
//  two-week average); and Options (all data, pin to Summary, data sources). Every figure comes from
//  `MetricHealthSeries`.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

struct MetricDetailView: View {
    let metric: MetricDescriptor

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    /// #1846/#1848: lead the skin-temp page with a temperature (default) or with the ±baseline move.
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""
    @AppStorage(KeyMetricPrefs.layoutKey) private var keyMetricsRaw = ""

    @State private var range: MetricHealthRange = Self.initialRange
    @State private var selection: MetricHealthPoint?
    /// Full ascending series for this metric — all history.
    @State private var series: [(day: String, value: Double)] = []
    /// day → the raw source id that supplied that day's value, for "Show All Data" and the VO₂max breaks.
    @State private var sourceByDay: [String: String] = [:]
    @State private var loaded = false
    /// #1848: why the skin-temp series leads with what it does, when that needs saying.
    @State private var skinTempNote: String?
    @State private var refreshing = false
    @State private var showAbout = false

    // MARK: Derived

    private var units: MetricHealthStyle.Units {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        return .init(system: system,
                     temperature: UnitPrefs.resolveTemperature(system: system, override: temperatureRaw),
                     effortScale: UnitPrefs.resolveEffortScale(effortScaleRaw))
    }
    private var tint: Color { MetricHealthStyle.tint(metric) }
    private var isSteps: Bool { MetricHealthStyle.isSteps(metric) }
    private var skinTempPreferred: SkinTempDisplay.Kind { SkinTempDisplay.Kind(rawValue: skinTempDisplayRaw) ?? .absolute }
    private var calendar: Calendar { .current }
    private var locale: Locale { AppLanguage.activeLocale }

    /// A daily sum rather than a level: its picked day reads "TOTAL", not "AVERAGE".
    private var isTotal: Bool {
        metric.unit == "min" || metric.unit == "kcal" || metric.unit == "g" || isSteps
    }

    private var loadTaskID: String {
        "\(metric.id)|\(repo.refreshSeq)|\(skinTempDisplayRaw)|\(isSteps && range == .year)"
    }

    private var todayKey: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: Body

    var body: some View {
        let window = MetricHealthSeries.window(series: series, range: range, today: Date(), calendar: calendar)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $range) {
                    ForEach(MetricHealthRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.bottom, 4)
                chartCard(window)
                canvas
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, NoopMetrics.space2)
            .padding(.bottom, NoopMetrics.space8 + NoopMetrics.tabBarClearance)
            #if os(macOS)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            #endif
        }
        #if os(iOS)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        #endif
        // The cards grow once the series lands; without a top anchor the page could open scrolled down.
        .modifier(TopScrollAnchor())
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text(metric.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: loadTaskID) { await load() }
    }

    // MARK: - Chart card

    /// The first card: the figure and its dates, the chart, and the latest reading under a hairline.
    private func chartCard(_ window: MetricHealthWindow) -> some View {
        SummaryCard {
            VStack(alignment: .leading, spacing: 0) {
                header(window)
                Group {
                    if loaded {
                        MetricHealthChart(window: window, spec: MetricHealthStyle.chart(metric, series: series),
                                          tint: tint, segments: segments(window),
                                          axisLabel: { v in
                                              MetricHealthStyle.axisLabel(metric, v, units: units,
                                                                          span: window.points.map(\.value).max() ?? 0)
                                          },
                                          selection: $selection)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 240)
                .padding(.top, NoopMetrics.space4)

                ForEach(notes(window), id: \.self) { note in
                    Text(note)
                        .font(StrandFont.pro(13))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoopMetrics.space2)
                }

                if let latest = series.last {
                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                        .padding(.top, NoopMetrics.space4)
                    latestRow(latest)
                        .padding(.top, NoopMetrics.space3)
                }
            }
            .padding(.top, 4)
        }
        .animation(StrandMotion.interactive, value: range)
    }

    /// "AVERAGE" · figure · dates — or, while a mark is held, that mark's figure and date.
    private func header(_ window: MetricHealthWindow) -> some View {
        let picked = selection
        // A picked day of a level has no aggregate to name; a blank keeps the header from jumping.
        let caption = picked != nil && range.bucket == .day
            ? (isTotal ? String(localized: "TOTAL") : " ")
            : String(localized: "AVERAGE")
        let value = picked?.value ?? window.average
        let dates = picked.map { MetricHealthSeries.pointLabel($0, range: range, calendar: calendar, locale: locale) }
            ?? MetricHealthSeries.spanLabel(window, calendar: calendar, locale: locale)
        return VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(StrandFont.pro(13, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(alignment: .firstTextBaseline) {
                if let value {
                    figure(MetricHealthStyle.tokens(metric, value, units: units), size: 34)
                } else {
                    Text(loaded ? String(localized: "No Data") : " ")
                        .font(StrandFont.pro(34, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                Spacer(minLength: 8)
                if let about = MetricHealthStyle.about(metric) {
                    Button { showAbout = true } label: {
                        Image(systemName: "info")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(StrandPalette.summaryCanvas, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("About"))
                    .popover(isPresented: $showAbout, arrowEdge: .top) { aboutPopover(about) }
                }
            }
            Text(dates)
                .font(StrandFont.pro(17, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// What the number is, one tap away instead of a section of its own (Health's ⓘ).
    private func aboutPopover(_ text: String) -> some View {
        Text(text)
            .font(StrandFont.pro(15))
            .foregroundStyle(StrandPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(NoopMetrics.space4)
            .frame(width: 320)
            .modifier(PopoverOnPhone())
    }

    /// Numbers large and primary, units smaller and secondary, on one baseline.
    private func figure(_ tokens: [MetricHealthStyle.Token], size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, t in
                if t.isUnit {
                    Text(verbatim: t.text)
                        .font(StrandFont.pro(size * 0.58, weight: .semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Text(verbatim: t.text)
                        .font(StrandFont.pro(size, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// "Latest: Yesterday ······ 52 bpm" — the last line of the chart card.
    private func latestRow(_ latest: (day: String, value: Double)) -> some View {
        let stamp = SummaryStamp.text(dayKey: latest.day, todayKey: todayKey) ?? latest.day
        return HStack(alignment: .firstTextBaseline) {
            Text("Latest: \(stamp)")
                .font(StrandFont.pro(15))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            figure(MetricHealthStyle.tokens(metric, latest.value, units: units), size: 17)
        }
        .accessibilityElement(children: .combine)
    }

    /// The explanations a chart can need: why the skin-temp series leads as it does (#1848), and why a
    /// VO₂max line breaks where the estimator changed (#1662).
    private func notes(_ window: MetricHealthWindow) -> [String] {
        var out: [String] = []
        if let skinTempNote { out.append(skinTempNote) }
        if metric.key == "vo2max_est",
           vo2MaxTrendHasBreak(days: window.days.map(\.day), sourceByDay: sourceByDay) {
            out.append(String(localized: "The line breaks where the estimation method changed or was not recorded."))
        }
        return out
    }

    /// Each VO₂max mark's estimator run, so the line never joins two methods; one run for anything else.
    private func segments(_ window: MetricHealthWindow) -> [Date: String] {
        guard metric.key == "vo2max_est" else { return [:] }
        let ids = vo2MaxTrendSegmentIds(days: window.days.map(\.day), sourceByDay: sourceByDay)
        let byDay = Dictionary(zip(window.days.map(\.day), ids), uniquingKeysWith: { a, _ in a })
        var out: [Date: String] = [:]
        for p in window.points { out[p.start] = byDay[p.lastDay] }
        return out
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loaded && series.isEmpty {
                emptyState
            }
            if let highlight = MetricHealthSeries.highlight(series: series, calendar: calendar) {
                sectionHeader("Highlights")
                highlightCard(highlight)
            }
            sectionHeader("Options")
            optionsCard
        }
    }

    /// Health's section title on the grouped canvas: SF Pro bold, flush with the cards' inset.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(StrandFont.pro(22, weight: .bold))
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, 4)
            .padding(.top, NoopMetrics.space4)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var emptyState: some View {
        if metric.key == "fitness_age" {
            // Fitness Age is computed on-device from resting HR + activity, not imported: say how many more
            // nights it needs, and offer to recompute now from what is stored.
            SummaryCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text(verbatim: fitnessReadyLeadCopy(rhrDays: repo.days.suffix(7).compactMap { $0.restingHr }.count,
                                                        hasAge: profile.age > 0, hasSex: !profile.sex.isEmpty))
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if refreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            refreshing = true
                            Task {
                                _ = await intelligence.recomputeFitnessAgeOnly()
                                await load()
                                refreshing = false
                            }
                        } label: {
                            Label("Refresh Fitness Age", systemImage: "arrow.clockwise")
                                .font(StrandFont.pro(17))
                                .foregroundStyle(StrandPalette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            SummaryCard {
                Text("Import your history first. A WHOOP export in Data Sources fills every metric you can explore here in about a minute.")
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The average's hue in a highlight, set against the metric's own (Health pairs teal with the category hue).
    private var averageTint: Color {
        metric.key == "resp_rate" ? StrandPalette.healthOxygen : StrandPalette.healthRespiratory
    }

    /// Health's highlight on a data type's page: the category line, one sentence, the average and the latest
    /// figure, then the fortnight's readings as grey bars with the latest in the metric's hue and the
    /// average drawn across them.
    private func highlightCard(_ h: MetricHealthHighlight) -> some View {
        let sentence: String
        switch h.direction {
        case .above: sentence = String(localized: "Your latest reading was above your two-week average.")
        case .below: sentence = String(localized: "Your latest reading was below your two-week average.")
        case .close: sentence = String(localized: "Your latest reading was close to your two-week average.")
        }
        // The latest reading in the hue its bar has on the chart above (Charge by its state), so the two agree.
        let latestTint = MetricHealthStyle.chart(metric, series: series).barTint?(h.latest) ?? tint
        return SummaryCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: metric.icon)
                        .font(.system(size: 14, weight: .semibold))
                    Text(metric.title)
                        .font(StrandFont.pro(17, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(tint)
                Text(sentence)
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                HStack(alignment: .top) {
                    highlightFigure(String(localized: "Two-Week Average"), h.average, color: averageTint, trailing: false)
                    Spacer(minLength: 8)
                    highlightFigure(String(localized: "Latest"), h.latest, color: latestTint, trailing: true)
                }
                highlightBars(h, latestTint: latestTint)
                    .frame(height: 96)
                    .padding(.top, 6)
                HStack {
                    Text(verbatim: shortDate(h.firstDay))
                    Spacer()
                    Text(verbatim: shortDate(h.lastDay))
                }
                .font(StrandFont.pro(13))
                .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func highlightFigure(_ title: String, _ value: Double, color: Color, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.pro(15, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                ForEach(Array(MetricHealthStyle.tokens(metric, value, units: units).enumerated()), id: \.offset) { _, t in
                    Text(verbatim: t.text)
                        .font(t.isUnit ? StrandFont.pro(17, weight: .semibold) : StrandFont.pro(30, weight: .semibold))
                        .foregroundStyle(t.isUnit ? StrandPalette.textSecondary : color)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    /// Grey bars for the fortnight, the latest in the metric's hue, the average as a line across. The scale
    /// starts below the lowest reading so day-to-day movement shows, as on Health's highlight charts.
    private func highlightBars(_ h: MetricHealthHighlight, latestTint: Color) -> some View {
        let lo0 = h.values.min() ?? 0, hi = max(h.values.max() ?? 1, h.average)
        let lo = hi > lo0 ? max(0, lo0 - (hi - lo0) * 0.6) : hi * 0.5
        let span = max(hi - lo, 1e-9)
        return GeometryReader { geo in
            let slot = geo.size.width / CGFloat(max(h.values.count, 1))
            let barWidth = min(18, slot * 0.55)
            ZStack(alignment: .bottomLeading) {
                ForEach(Array(h.values.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(i == h.values.count - 1 ? latestTint : StrandPalette.textTertiary.opacity(0.35))
                        .frame(width: barWidth, height: max(3, geo.size.height * CGFloat((v - lo) / span)))
                        .offset(x: slot * CGFloat(i) + (slot - barWidth) / 2)
                }
                Capsule()
                    .fill(averageTint)
                    .frame(height: 3)
                    .offset(y: -geo.size.height * CGFloat((h.average - lo) / span) + 1.5)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        .accessibilityHidden(true)
    }

    private func shortDate(_ key: String) -> String {
        MetricHealthSeries.date(key, calendar: calendar)
            .map { $0.formatted(.dateTime.day().month(.abbreviated).locale(locale)) } ?? key
    }

    // MARK: Options

    private var pinnable: KeyMetric? {
        guard let card = MetricHealthStyle.keyMetric(for: metric.key), ![.charge, .effort, .rest].contains(card) else {
            return nil
        }
        return card
    }

    private var optionsCard: some View {
        VStack(spacing: 0) {
            if !series.isEmpty {
                NavigationLink {
                    MetricAllDataView(metric: metric, series: series, sourceByDay: sourceByDay, units: units)
                } label: {
                    optionRow(String(localized: "Show All Data"), accent: false, chevron: true)
                }
                .buttonStyle(.plain)
                optionDivider
            }
            if metric.key == "avg_hr" {
                // The day's heart rate at full resolution (#575), one level below the daily averages.
                NavigationLink {
                    FullDayChartView()
                } label: {
                    optionRow(String(localized: "Full Day by the Second"), accent: false, chevron: true)
                }
                .buttonStyle(.plain)
                optionDivider
            }
            if let card = pinnable {
                let pinned = KeyMetricPrefs.decodeEnabled(keyMetricsRaw).contains(card)
                Button {
                    var list = KeyMetricPrefs.decodeEnabled(keyMetricsRaw)
                    if pinned { list.removeAll { $0 == card } } else { list.append(card) }
                    keyMetricsRaw = KeyMetricPrefs.encode(list)
                } label: {
                    optionRow(pinned ? String(localized: "Unpin from Summary") : String(localized: "Pin in Summary"),
                              accent: true, chevron: false)
                }
                .buttonStyle(.plain)
                optionDivider
            }
            NavigationLink {
                DataSourcesView()
            } label: {
                optionRow(String(localized: "Data Sources"), accent: false, chevron: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .background(StrandPalette.summaryCard,
                    in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
    }

    private func optionRow(_ title: String, accent: Bool, chevron: Bool) -> some View {
        HStack {
            Text(title)
                .font(StrandFont.pro(17))
                .foregroundStyle(accent ? StrandPalette.accent : StrandPalette.textPrimary)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var optionDivider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    /// W, or the range named by the DEBUG launch argument `--metric-range week|month|sixMonths|year`
    /// (simulator screenshots).
    private static var initialRange: MetricHealthRange {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--metric-range"), i + 1 < args.count,
           let range = MetricHealthRange(rawValue: args[i + 1]) {
            return range
        }
        #endif
        return .week
    }

    // MARK: - Load

    /// This metric's own series and per-day provenance, read through the loader the All Metrics card
    /// shares, so the card and this page show the same latest reading.
    private func load() async {
        guard let result = await MetricSeriesLoader.load(metric, repo: repo, skinTemp: skinTempPreferred,
                                                         fullStepsHistory: range == .year) else { return }
        series = result.series
        sourceByDay = result.sourceByDay
        skinTempNote = result.skinTempNote
        loaded = true
    }
}

/// A real popover (not a sheet) on iPhone as well, where the OS allows it.
private struct PopoverOnPhone: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, macOS 13.3, *) {
            content.presentationCompactAdaptation(.popover)
        } else {
            content
        }
    }
}

/// Opens the page at its top whatever the content does while it loads (iOS 17 / macOS 14 and later).
private struct TopScrollAnchor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.defaultScrollAnchor(.top)
        } else {
            content
        }
    }
}

/// The Fitness Age not-ready lead: a concrete countdown of nights-of-wear still needed (from the shared
/// `nightsUntilReady`), noting the profile basics only when they're actually missing. File-scope so the
/// Fitness Age metric page's empty state reads it from one source. Kept WORD-FOR-WORD identical to the Android
/// `fitnessReadyLead` so the two platforms match.
func fitnessReadyLeadCopy(rhrDays: Int, hasAge: Bool, hasSex: Bool) -> String {
    let remaining = FitnessAgeEngine.nightsUntilReady(rhrDays: rhrDays)
    let needsBasics = !hasAge || !hasSex
    switch (remaining, needsBasics) {
    case (0, false): return String(localized: "A few more days and we can show your Fitness Age.")
    case (0, true):  return String(localized: "Add your age and sex below and we can show your Fitness Age.")
    case (1, false): return String(localized: "1 more night of wear and we can show your Fitness Age.")
    case (1, true):  return String(localized: "1 more night of wear, plus your age and sex below, and we can show your Fitness Age.")
    case (let n, false): return String(localized: "\(n) more nights of wear and we can show your Fitness Age.")
    case (let n, true):  return String(localized: "\(n) more nights of wear, plus your age and sex below, and we can show your Fitness Age.")
    }
}
