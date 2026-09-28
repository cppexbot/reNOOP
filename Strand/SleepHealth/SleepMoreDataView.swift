//  SleepMoreDataView.swift
//  NOOP · Sleep — "Show More Sleep Data", laid out like the sheet of the same name in the iOS 26 Health app.
//
//  D / W / M / 6M picker, time in bed beside time asleep, the stage chart (day) or stage-coloured
//  bedtime→wake bars (week / month), then Stages · Amounts · Comparisons on the grouped canvas. Picking a
//  stage fades the rest of the chart; picking a vital draws it over the chart. Numbers come from
//  `SleepMoreData`, which decodes the nights with the same `SleepModel.mergeDay` as the Sleep tab.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

struct SleepMoreDataView: View {
    let navDays: [[CachedSleepSession]]
    let habitualMidsleepSec: Int?
    let motionByStart: [Int: [Double]]
    /// Typical minutes per stage across history (`SleepModel.typical…Min`), for "usually" on the day view.
    let typicalStageMin: [SleepStage: Double]
    /// The running sleep-debt estimate as of the newest night (`SleepModel.sleepDebtLedger`).
    let sleepDebtLedger: SleepDebtLedger?

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dts
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""

    @State private var range: SleepRange
    @State private var nightOffset: Int
    @State private var tab: SleepMoreTab
    @State private var selectedStage: SleepStage?
    /// The vital the reader picked; until they pick, Comparisons draws the first one it can.
    @State private var pickedComparison: SleepComparisonMetric?
    @State private var comparisonPicked = false

    @State private var nights: [SleepNightDetail] = []
    @State private var dayNight: SleepNightDetail?
    @State private var hrBuckets: [HRBucket] = []
    @State private var anchor = Date()

    init(navDays: [[CachedSleepSession]], habitualMidsleepSec: Int?, motionByStart: [Int: [Double]],
         typicalStageMin: [SleepStage: Double] = [:], sleepDebtLedger: SleepDebtLedger? = nil,
         range: SleepRange, nightOffset: Int, tab: SleepMoreTab = .stages) {
        self.navDays = navDays
        self.habitualMidsleepSec = habitualMidsleepSec
        self.motionByStart = motionByStart
        self.typicalStageMin = typicalStageMin
        self.sleepDebtLedger = sleepDebtLedger
        _range = State(initialValue: range)
        _nightOffset = State(initialValue: nightOffset)
        _tab = State(initialValue: tab)
    }

    /// Stage rows run top-down in the chart's order.
    private static let stageOrder: [SleepStage] = SleepStagesChart.rowOrder

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    chartSection
                        .padding(.horizontal, NoopMetrics.screenHPadding)
                        .padding(.bottom, NoopMetrics.space5)
                        .background(alignment: .top) {
                            StrandPalette.healthSleepPage.padding(.top, -1000)
                        }
                    detailSection
                        .padding(.horizontal, NoopMetrics.screenHPadding)
                        .padding(.top, NoopMetrics.space5)
                        .padding(.bottom, NoopMetrics.space8)
                }
                #if os(macOS)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                #endif
            }
            .background(StrandPalette.summaryCanvas.ignoresSafeArea())
            .navigationTitle(Text("Sleep"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetConfirmButton(tint: StrandPalette.accent) { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 720)
        #endif
        .task(id: navDays.count) { load() }
        .task(id: hrKey) { await loadHeartRate() }
        .onChangeCompat(of: nightOffset) { _ in updateDayNight() }
        .onChangeCompat(of: range) { _ in selectedStage = nil; comparisonPicked = false; pickedComparison = nil }
    }

    // MARK: - Chart (plain page)

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $range) {
                ForEach(SleepRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.top, NoopMetrics.space2)
            .padding(.bottom, NoopMetrics.space4)

            header

            Group {
                if range == .day {
                    dayChart
                        .contentShape(Rectangle())
                        .gesture(nightSwipe)
                } else {
                    SleepRangeChart(window: window,
                                    stagesBySlot: range == .sixMonths ? [:] : stagesBySlot,
                                    highlight: tab == .stages && range != .sixMonths ? selectedStage : nil,
                                    overlay: rangeOverlay,
                                    overlayColor: selectedComparison.map(Self.color) ?? StrandPalette.healthHeart)
                }
            }
            .frame(height: 300)
            .padding(.top, NoopMetrics.space3)
            .animation(StrandMotion.interactive, value: selectedStage)
            .animation(StrandMotion.interactive, value: selectedComparison)
        }
    }

    private var header: some View {
        let s = summary
        let average = range != .day
        let figures = dts.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopMetrics.space2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: NoopMetrics.space6))
        return VStack(alignment: .leading, spacing: 2) {
            figures {
                headerFigure(average ? String(localized: "AVG. TIME IN BED") : String(localized: "TIME IN BED"),
                             minutes: s.inBedMin)
                headerFigure(average ? String(localized: "AVG. TIME ASLEEP") : String(localized: "TIME ASLEEP"),
                             minutes: s.asleepMin)
            }
            Text(periodLabel)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func headerFigure(_ title: String, minutes: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(dts.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let minutes, minutes > 0 {
                    let p = SleepFormat.parts(minutes: minutes)
                    if p.hours > 0 {
                        Text(verbatim: "\(p.hours)").font(StrandFont.number(34, weight: .semibold))
                        Text(String(localized: "sleep.unit.hr", defaultValue: "hr")).font(StrandFont.rounded(20, weight: .medium))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Text(verbatim: "\(p.minutes)").font(StrandFont.number(34, weight: .semibold))
                    Text(String(localized: "sleep.unit.min", defaultValue: "min")).font(StrandFont.rounded(20, weight: .medium))
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Text(verbatim: "–").font(StrandFont.number(34, weight: .semibold))
                }
            }
            .foregroundStyle(StrandPalette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private var dayChart: some View {
        if let dayNight, !dayNight.intervals.isEmpty {
            SleepStagesChart(intervals: dayNight.intervals, onset: dayNight.onset,
                             highlight: tab == .stages ? selectedStage : nil,
                             overlay: dayOverlay,
                             overlayColor: StrandPalette.healthHeart)
        } else {
            Text("No sleep data")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Right = an older night, left = a newer one; clamped to the nights on record.
    private var nightSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 50, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                let next = min(max(0, nightOffset + (dx > 0 ? 1 : -1)), max(0, navDays.count - 1))
                if next != nightOffset { withAnimation(StrandMotion.interactive) { nightOffset = next } }
            }
    }

    // MARK: - Stages · Amounts · Comparisons (grouped canvas)

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Picker("", selection: $tab) {
                ForEach(SleepMoreTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, NoopMetrics.space2)

            switch tab {
            case .stages: stageRows
            case .amounts: amountRows
            case .comparisons: comparisonRows
            }
        }
    }

    @ViewBuilder private var stageRows: some View {
        let s = summary
        if s.nights == 0 {
            emptyRow
        } else {
            ForEach(Self.stageOrder, id: \.self) { stage in
                let selected = selectedStage == stage
                Button {
                    withAnimation(StrandMotion.interactive) { selectedStage = selected ? nil : stage }
                } label: {
                    SleepMoreRow(dot: stage.healthColor, title: stageTitle(stage),
                                 subtitle: range == .day ? typicalStageMin[stage].map {
                                     String(localized: "usually \(SleepFormat.duration(minutes: $0))")
                                 } : nil,
                                 detail: s.share(stage).map(Self.percent),
                                 value: s.stageMin[stage].map { SleepFormat.duration(minutes: $0) } ?? "–",
                                 selected: selected)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(range != .sixMonths)   // weekly averages carry no stage bands to pick
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var amountRows: some View {
        let s = summary
        if s.nights == 0 {
            emptyRow
        } else {
            let average = range != .day
            SleepMoreRow(dot: StrandPalette.healthSleepRem,
                         title: average ? String(localized: "Average Time in Bed") : String(localized: "Time in Bed"),
                         value: s.inBedMin.map { SleepFormat.duration(minutes: $0) } ?? "–")
            SleepMoreRow(dot: StrandPalette.healthSleepCore,
                         title: average ? String(localized: "Average Time Asleep") : String(localized: "Time Asleep"),
                         value: s.asleepMin.map { SleepFormat.duration(minutes: $0) } ?? "–")
            if let need = sleepNeedMin {
                SleepMoreRow(dot: StrandPalette.healthSleepDeep, title: String(localized: "Sleep Need"),
                             value: SleepFormat.duration(minutes: need))
            }
            if let eff = s.efficiency {
                SleepMoreRow(dot: nil,
                             title: average ? String(localized: "Average Sleep Efficiency") : String(localized: "Sleep Efficiency"),
                             value: Self.percent(eff))
            }
            if let bed = s.bedtimeOfNightMin, let wake = s.wakeOfNightMin {
                SleepMoreRow(dot: nil,
                             title: average ? String(localized: "Average Bedtime") : String(localized: "Bedtime"),
                             value: Self.clock(minutesOfNight: bed))
                SleepMoreRow(dot: nil,
                             title: average ? String(localized: "Average Wake-Up") : String(localized: "Wake-Up"),
                             value: Self.clock(minutesOfNight: wake))
            }
            if let ledger = sleepDebtLedger, !ledger.nights.isEmpty {
                SleepDebtNightsCard(ledger: ledger)
                    .padding(.top, NoopMetrics.space2)
            }
        }
    }

    @ViewBuilder private var comparisonRows: some View {
        let rows = comparisons
        if rows.isEmpty {
            emptyRow
        } else {
            ForEach(rows, id: \.metric) { row in
                let selected = selectedComparison == row.metric
                Button {
                    withAnimation(StrandMotion.interactive) {
                        comparisonPicked = true
                        pickedComparison = selected ? nil : row.metric
                    }
                } label: {
                    SleepMoreRow(dot: Self.color(row.metric), title: row.metric.label, value: row.value,
                                 selected: selected)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(row.plottable)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Text(range == .day
                 ? String(localized: "Heart rate is drawn over the night's stages. The other vitals are one reading per night.")
                 : String(localized: "Choose a vital to see it night by night beside your sleep."))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyRow: some View {
        SleepMoreRow(dot: nil, title: String(localized: "No sleep data"), value: "")
    }

    private func stageTitle(_ stage: SleepStage) -> String {
        range == .day ? stage.label : String(localized: "Average \(stage.label)")
    }

    // MARK: - Derived

    private var today: Date { Calendar.current.startOfDay(for: anchor) }

    private var rangeNights: [SleepNightDetail] {
        SleepMoreData.nights(in: range, nights, anchor: anchor)
    }

    /// The nights the page describes: the picked night (D) or the range's nights.
    private var shownNights: [SleepNightDetail] {
        range == .day ? (dayNight.map { [$0] } ?? []) : rangeNights
    }

    private var summary: SleepPeriodSummary { SleepMoreData.summary(shownNights) }

    private var window: SleepRangeWindow {
        SleepHistory.window(range, entries: nights.map(\.entry), anchor: anchor)
    }

    private var stagesBySlot: [Int: [SleepInterval]] {
        let byDay = Dictionary(nights.map { ($0.day, $0.intervals) }, uniquingKeysWith: { _, newer in newer })
        var out: [Int: [SleepInterval]] = [:]
        for (slot, start) in window.slotStarts.enumerated() { out[slot] = byDay[start] }
        return out
    }

    private var periodLabel: String {
        if range == .day {
            return dayNight.map {
                $0.day.formatted(.dateTime.day().month(.abbreviated).year().locale(AppLanguage.activeLocale))
            } ?? " "
        }
        return SleepHealthView.rangeLabel(window)
    }

    private var dayMetrics: [String: DailyMetric] {
        Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { _, newer in newer })
    }

    private var skinTempPreferred: SkinTempDisplay.Kind {
        SkinTempDisplay.Kind(rawValue: skinTempDisplayRaw) ?? .absolute
    }

    private var fahrenheit: Bool {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                     override: temperatureRaw) == .fahrenheit
    }

    /// The night's own need where an import recorded one, else the personal need — the same pair the
    /// "Hours vs needed" card measures against.
    private var sleepNeedMin: Double? {
        SleepMoreData.needMin(dayKeys: shownNights.map(\.dayKey), days: repo.days, imported: repo.importedSleep)
    }

    // MARK: Comparisons

    private struct ComparisonRow {
        let metric: SleepComparisonMetric
        let value: String
        let plottable: Bool
    }

    /// Per-night values of a vital over the range's nights, keyed by the night's day.
    private func valuesByDay(_ metric: SleepComparisonMetric) -> [Date: Double] {
        let nights = rangeNights
        if metric == .heartRate { return SleepMoreData.nightlyHeartRate(nights, buckets: hrBuckets) }
        let rows = dayMetrics
        var out: [Date: Double] = [:]
        for night in nights {
            if let v = SleepMoreData.nightlyValue(metric, rows[night.dayKey], skinTempPreferred: skinTempPreferred) {
                out[night.day] = v
            }
        }
        return metric == .skinTemperature ? SleepMoreData.sameScaleSkinTemps(out) : out
    }

    private var comparisons: [ComparisonRow] {
        SleepComparisonMetric.allCases.compactMap { metric -> ComparisonRow? in
            if range == .day {
                guard let night = dayNight else { return nil }
                if metric == .heartRate {
                    let pts = SleepMoreData.heartRatePoints(night, buckets: hrBuckets)
                    guard let lo = pts.map(\.value).min(), let hi = pts.map(\.value).max() else { return nil }
                    return ComparisonRow(metric: metric, value: Self.bpmRange(lo, hi), plottable: pts.count >= 2)
                }
                guard let v = SleepMoreData.nightlyValue(metric, dayMetrics[night.dayKey],
                                                         skinTempPreferred: skinTempPreferred) else { return nil }
                return ComparisonRow(metric: metric, value: Self.format(metric, v, fahrenheit: fahrenheit), plottable: false)
            }
            let values = Array(valuesByDay(metric).values)
            guard !values.isEmpty else { return nil }
            if metric == .heartRate, let lo = values.min(), let hi = values.max() {
                return ComparisonRow(metric: metric, value: Self.bpmRange(lo, hi), plottable: true)
            }
            return ComparisonRow(metric: metric, value: Self.format(metric, values.reduce(0, +) / Double(values.count), fahrenheit: fahrenheit),
                                 plottable: true)
        }
    }

    private var dayOverlay: [SleepComparisonPoint] {
        guard selectedComparison == .heartRate, let dayNight else { return [] }
        return SleepMoreData.heartRatePoints(dayNight, buckets: hrBuckets)
    }

    private var rangeOverlay: [SleepComparisonPoint] {
        guard let metric = selectedComparison else { return [] }
        return SleepMoreData.slotValues(window: window, valueByDay: valuesByDay(metric))
    }

    /// The vital drawn over the chart: the reader's pick, else the first that can be drawn (heart rate
    /// when the night has it), as Health does. Only while Comparisons is showing.
    private var selectedComparison: SleepComparisonMetric? {
        guard tab == .comparisons else { return nil }
        let plottable = comparisons.filter(\.plottable).map(\.metric)
        if comparisonPicked { return pickedComparison.flatMap { plottable.contains($0) ? $0 : nil } }
        return plottable.first
    }

    static func format(_ metric: SleepComparisonMetric, _ v: Double, fahrenheit: Bool) -> String {
        switch metric {
        case .heartRate: return bpmRange(v, v)
        case .respiratoryRate:
            return String(localized: "\(v.formatted(.number.precision(.fractionLength(1)))) br/min")
        case .hrv: return String(localized: "\(Int(v.rounded())) ms")
        case .bloodOxygen: return percent(v / 100)
        case .skinTemperature: return SkinTempDisplay.format(v, fahrenheit: fahrenheit)
        }
    }

    static func color(_ metric: SleepComparisonMetric) -> Color {
        switch metric {
        case .heartRate, .hrv: return StrandPalette.healthHeart
        case .respiratoryRate: return StrandPalette.healthRespiratory
        case .bloodOxygen: return StrandPalette.healthOxygen
        case .skinTemperature: return StrandPalette.healthTemperature
        }
    }

    static func bpmRange(_ lo: Double, _ hi: Double) -> String {
        let l = Int(lo.rounded()), h = Int(hi.rounded())
        return l == h ? String(localized: "\(l) BPM") : String(localized: "\(l)–\(h) BPM")
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.activeLocale))
    }

    /// Minutes after 18:00 (the night clock of `SleepNightEntry`) as a wall-clock time.
    static func clock(minutesOfNight: Double) -> String {
        let reference = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-6 * 3600)
        return reference.addingTimeInterval(minutesOfNight * 60)
            .formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale))
    }

    // MARK: - Loading

    private func load() {
        anchor = Date()
        nights = SleepMoreData.nights(navDays: navDays, habitualMidsleepSec: habitualMidsleepSec,
                                      motionByStart: motionByStart, anchor: anchor)
        updateDayNight()
    }

    private func updateDayNight() {
        if let n = nights.first(where: { $0.navIndex == nightOffset }) {
            dayNight = n
        } else {
            dayNight = SleepModel.decodedNight(at: nightOffset, navDays: navDays, habitualMidsleepSec: habitualMidsleepSec,
                                               motionByStart: motionByStart)
                .flatMap { SleepNightDetail(night: $0, navIndex: nightOffset) }
        }
    }

    private var hrKey: String { "\(range.rawValue)|\(nightOffset)|\(nights.count)|\(dayNight?.onset.timeIntervalSince1970 ?? 0)" }

    /// Heart-rate buckets spanning the shown nights: fine for one night, coarser for longer windows.
    private func loadHeartRate() async {
        let span = shownNights
        guard let first = span.first, let last = span.last else { hrBuckets = []; return }
        let bucket = range == .day ? 180 : (range == .sixMonths ? 1200 : 600)
        hrBuckets = await repo.hrBuckets(from: Int(first.onset.timeIntervalSince1970),
                                         to: Int(last.wake.timeIntervalSince1970), bucketSeconds: bucket)
    }
}

/// One row card: a coloured dot and title on the left, a secondary figure and the value on the right.
private struct SleepMoreRow: View {
    let dot: Color?
    let title: String
    /// A second line under the title ("usually 1 h 41 min").
    var subtitle: String? = nil
    var detail: String? = nil
    let value: String
    var selected = false

    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 10

    var body: some View {
        // The figures move under the title at accessibility sizes.
        let stacked = dts.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            HStack(spacing: 10) {
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: dotSize, height: dotSize)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(stacked ? nil : 2)
                        .minimumScaleFactor(0.85)
                    if let subtitle {
                        Text(subtitle)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
            if !stacked { Spacer(minLength: 8) }
            HStack(spacing: 10) {
                if let detail {
                    Text(detail)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .monospacedDigit()
                }
                Text(value)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                if selected {
                    Image(systemName: "checkmark")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius,
                                                                    style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The sleep-debt estimate night by night: each counted night's time asleep against need, above the line
/// when it met the need and below when it fell short, with the running estimate it adds up to.
private struct SleepDebtNightsCard: View {
    let ledger: SleepDebtLedger

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        let nights = Array(ledger.nights.suffix(14))
        let peak = max(60, nights.map { abs($0.deltaMin) }.max() ?? 60)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep Debt")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Text(ledger.isDebt ? SleepFormat.duration(minutes: ledger.magnitudeMin) : String(localized: "No debt"))
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            let half = geo.size.height / 2
                            let h = max(2, half * CGFloat(min(1, abs(night.deltaMin) / peak)))
                            ZStack(alignment: .top) {
                                Rectangle().fill(StrandPalette.hairline).frame(height: 1).offset(y: half)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(night.deltaMin >= 0 ? StrandPalette.healthSleepCore
                                                              : StrandPalette.healthSleepAwake)
                                    .frame(width: min(geo.size.width, 10), height: h)
                                    .offset(y: night.deltaMin >= 0 ? half - h : half)
                            }
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        }
                        Text(Self.dayLabel(night.day))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(height: 80)
            .accessibilityHidden(true)
            Text("Each bar is a night against the \(SleepFormat.duration(minutes: ledger.needMin)) sleep debt is counted from: above the line met it, below fell short.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius,
                                                                    style: .continuous))
    }

    /// The day of the month the night ended on.
    static func dayLabel(_ key: String) -> String {
        guard let d = dayParser.date(from: key) else { return "" }
        return d.formatted(.dateTime.day().locale(AppLanguage.activeLocale))
    }
}
