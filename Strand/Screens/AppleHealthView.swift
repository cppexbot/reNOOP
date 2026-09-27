import SwiftUI
import StrandDesign
import WhoopStore
import Foundation

// MARK: - Apple Health (per-source page)
//
// A grouped Settings page: the live HealthKit connection (iOS), ONE range control, a row per
// metric (latest value, or the mean for sleep), then chart rows grouped as Heart & vitals,
// Activity & energy, Body composition and Sleep — each chart the same height with an
// avg/min/max footer.
//
// Everything reads from the "apple-health" source. ALL history is loaded once; the
// range control simply windows it client-side, RELATIVE TO THE LATEST data point
// (not "now"). Per the data contract a series may be SPARSE (weight/body-fat are
// weekly): if the selected window holds ≥1 point we SHOW THAT WINDOW (so W/M/3M stay
// visibly distinct); only when it holds ZERO points do we auto-expand to the smallest
// larger range that does. Metric rows show the LATEST point with "as of <date>".

/// #833/v7.7.2 (Apple Health per-source freeze): the snapshot AppleHealthView.load() builds, parked on the
/// long-lived Repository so a re-mount (macOS keys the NavigationSplitView detail with `.id`, so every sidebar
/// switch cold-mounts the screen) can RESTORE it in-memory instead of re-running the whole apple-health history
/// read on the @MainActor. The exact twin of `InsightsLoadCache` for #833; holds load()'s three `@State`
/// outputs. Consumed only when the seq AND the dayKey still match (see `Repository.appleHealthLoadedSeq` /
/// `appleHealthLoadedDayKey`).
struct AppleHealthLoadCache {
    let appleRows: [AppleDaily]
    let workoutCount: Int
    let series: [String: [(day: String, value: Double)]]
}

/// #833/v7.7.2: `.task(id:)` key for the Apple Health load, the data-refresh seq PLUS today's local day-key, so
/// the load re-runs both on a data change AND on a calendar-day rollover while the screen stays mounted across
/// midnight (keying on `refreshSeq` alone left the inside-load dayKey guard unreachable). The exact twin of
/// InsightsView's `InsightsLoadKey`.
struct AppleHealthLoadKey: Equatable {
    let seq: Int
    let dayKey: String
}

struct AppleHealthView: View {
    @EnvironmentObject var repo: Repository

    // iOS-only: the live two-way HealthKit bridge, injected at StrandiOSApp. macOS has no HealthKit
    // (HealthKitBridge is `#if os(iOS)` in its own file and isn't in the macOS environment), so this
    // property and every `health.*` use below MUST stay inside `#if os(iOS)`.
    #if os(iOS)
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var model: AppModel
    #endif

    // Imperial/Metric display preference (D#103). Weight and lean mass (stored kg) re-label to lb here;
    // every other Apple Health metric is unit-agnostic. Display-only.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    /// kg value → the active mass unit, full string with label (e.g. "74.5 kg" / "164.2 lb").
    private func massLabel(_ kg: Double) -> String { UnitFormatter.massFromKilograms(kg, system: unitSystem) }

    /// Optional pre-seeded data for previews; when set, the async store load is
    /// skipped (store-backed reads can't be seeded in a preview). Production leaves
    /// this nil and loads from the repository in `.task`.
    private let previewData: PreviewData?

    init() { self.previewData = nil }
    fileprivate init(previewData: PreviewData) { self.previewData = previewData }

    // Loaded state.
    @State private var loaded = false
    @State private var appleRows: [AppleDaily] = []
    @State private var workoutCount = 0

    // Raw series (day, value) keyed by metric — ALL history, ascending by day.
    @State private var series: [String: [(day: String, value: Double)]] = [:]

    // The active range window. The data goes back years — never hard-cap.
    @State private var range: RangeWindow = .quarter

    /// Memoized per-metric resolved window. Resolving a key (effective range +
    /// trimmed rows) re-slices the full multi-year series and, on auto-widen, slices
    /// it once per candidate range. The view body asks for the same key many times
    /// per render (every metric row, every chart row, plus rangeSummaryCaption), and
    /// SwiftUI re-evaluates the body on hover / animation / 1Hz HR ticks. The inputs
    /// (`series`, `range`) only change on load or a range change, so we compute once and
    /// cache, recomputing via .onChangeCompat(of:) when an input actually changes.
    @State private var windowCache: [String: ResolvedSeries] = [:]

    /// Memoized per-day rows trimmed to the active window. Read by
    /// `rangeSummaryCaption` every render; depends only on
    /// `appleRows` + `range`, so it's cached alongside `windowCache`.
    @State private var windowedRowsCache: [AppleDaily] = []

    /// A key's resolved (possibly auto-widened) window: the effective range plus the
    /// rows trimmed to it.
    private struct ResolvedSeries {
        var effective: RangeWindow
        var rows: [(day: String, value: Double)]
    }

    // The series keys this page pulls from the apple-health source.
    private static let seriesKeys = [
        "steps", "active_kcal", "vo2max",
        "resting_hr", "hrv", "spo2", "resp_rate", "asleep_min",
        "weight", "body_fat", "lean_mass", "bmi"
    ]

    // yyyy-MM-dd → Date (en_US_POSIX / UTC), per the project's date contract.
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let asOfFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM"
        return f
    }()

    /// Thousands-grouped integer formatter (steps / calories). Static so it isn't reallocated
    /// per tile on every render. (perf plan Q3)
    private static let groupedIntFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private func date(_ day: String) -> Date? { Self.dayParser.date(from: day) }

    // MARK: - Range control (W / M / 3M / 6M / 1Y / ALL) — the ONE range control.

    enum RangeWindow: String, CaseIterable, Identifiable {
        case week, month, quarter, half, year, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week:    return String(localized: "W")
            case .month:   return String(localized: "M")
            case .quarter: return String(localized: "3M")
            case .half:    return String(localized: "6M")
            case .year:    return String(localized: "1Y")
            case .all:     return String(localized: "ALL")
            }
        }
        /// Number of trailing days; nil = everything.
        var days: Int? {
            switch self {
            case .week:    return 7
            case .month:   return 30
            case .quarter: return 90
            case .half:    return 180
            case .year:    return 365
            case .all:     return nil
            }
        }
        var name: String {
            switch self {
            case .week:    return String(localized: "week")
            case .month:   return String(localized: "month")
            case .quarter: return String(localized: "3 months")
            case .half:    return String(localized: "6 months")
            case .year:    return String(localized: "year")
            case .all:     return String(localized: "all history")
            }
        }
        /// This range plus every LARGER range, ascending — the auto-expand search
        /// order when the selected window holds zero points.
        var widening: [RangeWindow] {
            let order: [RangeWindow] = [.week, .month, .quarter, .half, .year, .all]
            guard let i = order.firstIndex(of: self) else { return [.all] }
            return Array(order[i...])
        }
    }

    var body: some View {
        Form {
            #if os(iOS)
            liveSyncSection
            #endif
            if !loaded {
                loadingSection
            } else if !hasAnyData {
                Section {
                    #if os(iOS)
                    // #348 — when the build can't carry the HealthKit entitlement there's no "Enable"
                    // button to tap, so the empty state points at the file import instead.
                    Text(health.auth == .entitlementMissing
                         ? LocalizedStringKey("Nothing here yet. Import a Health export .zip in Data Sources.")
                         : LocalizedStringKey("Nothing here yet."))
                        .foregroundStyle(StrandPalette.textSecondary)
                    #else
                    Text("Nothing imported yet. Import a Health export .zip in Data Sources.")
                        .foregroundStyle(StrandPalette.textSecondary)
                    #endif
                }
            } else {
                rangeSection
                summarySection
                heartSection
                activitySection
                bodySection
                sleepSection
            }
        }
        .settingsPage("Apple Health")
        .refreshable { await repo.refresh() }
        .task(id: AppleHealthLoadKey(seq: repo.refreshSeq, dayKey: Repository.localDayKey(Date()))) { await load(allowCache: true) }
        .onChangeCompat(of: range) { _ in rebuildWindowCache() }
    }

    /// Rebuild the per-metric resolved-window cache from scratch. Called once after
    /// load and again whenever `range` changes — never inside the render path.
    private func rebuildWindowCache() {
        var cache: [String: ResolvedSeries] = [:]
        cache.reserveCapacity(Self.seriesKeys.count)
        for key in Self.seriesKeys {
            let eff = computeEffectiveRange(key)
            cache[key] = ResolvedSeries(effective: eff, rows: slice(key, eff))
        }
        windowCache = cache
        windowedRowsCache = computeWindowedRows()
    }

    /// True if ANY series or per-day row holds data (drives the empty state).
    private var hasAnyData: Bool {
        if !appleRows.isEmpty { return true }
        return series.values.contains { !$0.isEmpty }
    }

    // MARK: - Load

    private func load(allowCache: Bool = false) async {
        // Previews inject data directly (store-backed reads can't be seeded). Stays ABOVE the cache path so a
        // preview never touches the repo.
        if let pd = previewData {
            appleRows = pd.rows.sorted { $0.day < $1.day }
            workoutCount = pd.workoutCount
            series = pd.series
            rebuildWindowCache()
            loaded = true
            return
        }

        // #833/v7.7.2: the whole heavy load, cache short-circuit, DEBUG fire tally, and write-back live on the
        // long-lived repo (`performAppleHealthLoad`, a headless-testable seam) so a re-mount RESTORES the prior
        // snapshot in-memory instead of re-running the whole apple-health history read on the @MainActor, which
        // is the freeze fix. `allowCache` is true ONLY on the `.task(id:)`-driven path (a re-mount / data refresh
        // / day rollover); the direct load() sites (Enable / Sync now) leave it false so a live sync always
        // re-reads. The seam owns the cache; this view just copies the snapshot into its `@State`.
        let snapshot = await repo.performAppleHealthLoad(seriesKeys: Self.seriesKeys, allowCache: allowCache)
        appleRows = snapshot.appleRows
        workoutCount = snapshot.workoutCount
        series = snapshot.series
        rebuildWindowCache()
        loaded = true
    }

    // MARK: - Range control

    private var rangeSection: some View {
        Section {
            Picker("Range", selection: $range) {
                ForEach(RangeWindow.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } footer: {
            Text(rangeSummaryCaption)
        }
    }

    /// Window-level caption under the control: how many days the per-day rows span in
    /// the selected range, plus a flag if any tracked series had to auto-widen.
    private var rangeSummaryCaption: String {
        let n = windowedRows.count
        let anyWidened = Self.seriesKeys.contains { !raw($0).isEmpty && effectiveRange($0) != range }
        // Whole-phrase variants per count so translators see complete sentences (never a stitched plural).
        if anyWidened {
            return n == 1
                ? String(localized: "1 day · \(range.name) · some sparse series widened")
                : String(localized: "\(n) days · \(range.name) · some sparse series widened")
        }
        return n == 1
            ? String(localized: "1 day · \(range.name)")
            : String(localized: "\(n) days · \(range.name)")
    }

    /// AppleDaily rows trimmed to the active window (for the day count), taken
    /// RELATIVE TO THE LATEST recorded day rather than "now". Served from the
    /// per-render cache; recomputed only when `appleRows`/`range` change.
    private var windowedRows: [AppleDaily] {
        loaded ? windowedRowsCache : computeWindowedRows()
    }

    /// The actual windowing of the per-day rows. Called only from
    /// rebuildWindowCache and the not-yet-loaded fallback — never per render.
    private func computeWindowedRows() -> [AppleDaily] {
        guard let n = range.days else { return appleRows }
        guard let lastDay = appleRows.last?.day, let last = date(lastDay) else { return [] }
        let cutoff = last.addingTimeInterval(-Double(n - 1) * 86_400)
        return appleRows.filter { row in
            guard let d = date(row.day) else { return false }
            return d >= cutoff
        }
    }

    private var loadingSection: some View {
        Section {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading your Apple Health history…")
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    // MARK: - Live Apple Health (iOS only)
    //
    // The opt-in entry point for the two-way HealthKitBridge. macOS has no HealthKit, so this whole
    // section — and every `health.*` reference — is `#if os(iOS)`-gated. Tapping "Enable Apple Health"
    // shows the system permission sheet (rationale strings ship in the iOS target's Info.plist), then
    // runs the first read + write-back and refreshes this screen. Once authorized, a "Sync now"
    // row and the last-synced time take its place.
    #if os(iOS)
    private var liveSyncSection: some View {
        Section {
            HStack(spacing: 8) {
                Circle()
                    .fill(liveStatusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(liveStatusText)
            }

            switch health.auth {
            case .unavailable, .entitlementMissing:
                EmptyView()

            case .unknown, .denied:
                Button("Enable Apple Health") {
                    Task {
                        await health.requestAuthorization()
                        await HealthSyncRefreshCoordinator.run(
                            sync: { await health.sync() },
                            refresh: {
                                await model.refreshAfterAppleHealthSync(
                                    authorized: health.auth == .authorized)
                            }
                        )
                        await load()
                    }
                }

            case .authorized:
                if let last = health.lastSync {
                    LabeledContent("Last sync", value: relativeAgo(last.timeIntervalSince1970))
                }
                Button("Sync now") {
                    Task {
                        await HealthSyncRefreshCoordinator.run(
                            sync: { await health.sync() },
                            refresh: {
                                await model.refreshAfterAppleHealthSync(
                                    authorized: health.auth == .authorized)
                            }
                        )
                        await load()
                    }
                }
                .disabled(health.syncing)
            }

            if let err = health.lastError {
                Text(err)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusCritical)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            liveSyncFooter
        }
    }

    private var liveStatusText: LocalizedStringKey {
        switch health.auth {
        case .unavailable, .entitlementMissing: return "Not available"
        case .unknown, .denied:                 return "Not connected"
        case .authorized:                       return health.syncing ? "Syncing" : "Connected"
        }
    }

    private var liveStatusColor: Color {
        switch health.auth {
        case .authorized:                       return StrandPalette.settingsGreen
        case .denied, .entitlementMissing:      return StrandPalette.settingsOrange
        case .unknown, .unavailable:            return StrandPalette.settingsGray
        }
    }

    @ViewBuilder
    private var liveSyncFooter: some View {
        switch health.auth {
        case .unavailable:
            Text("Apple Health isn't available on \(Platform.deviceNounPhrase).")
        case .entitlementMissing:
            // #348 / #930: the sideload was re-signed WITHOUT the HealthKit entitlement (free
            // Apple IDs always lack it; some paid reseller certs do too), so "Enable Apple Health"
            // can never work and the app can never appear under Settings › Health › Data Access
            // & Devices.
            Text("This install can't connect to Apple Health directly.")
        case .denied:
            Text("If you don't see the prompt, enable NOOP under Settings › Health › Data Access & Devices.")
        case .unknown, .authorized:
            EmptyView()
        }
    }
    #endif

    // MARK: - Metric rows (one per metric, latest or mean over the window)

    private var summarySection: some View {
        Section {
            metricRow(key: "steps", label: "Steps", fmt: { intString($0) })
            metricRow(key: "resting_hr", label: "Resting HR", unit: "bpm",
                      fmt: { "\(Int($0.rounded()))" })
            metricRow(key: "hrv", label: "HRV", unit: "ms",
                      fmt: { "\(Int($0.rounded()))" })
            metricRow(key: "vo2max", label: "VO₂ Max", unit: "ml/kg",
                      fmt: { String(format: "%.1f", $0) })
            metricRow(key: "weight", label: "Weight", fmt: { massLabel($0) })
            metricRow(key: "body_fat", label: "Body Fat", unit: "%",
                      fmt: { String(format: "%.1f", $0) })
            metricRow(key: "lean_mass", label: "Lean Mass", fmt: { massLabel($0) })
            metricRow(key: "asleep_min", label: "Asleep avg",
                      aggregate: .mean, fmt: { durationString($0) })
            LabeledContent {
                Text(verbatim: "\(workoutCount)")
                    .foregroundStyle(workoutCount > 0 ? StrandPalette.textSecondary : StrandPalette.textTertiary)
            } label: {
                Text("Workouts")
            }
        } header: {
            Text("Summary")
        }
    }

    /// How a row's value is derived from its window.
    private enum Aggregate { case latest, mean }

    /// One row for one metric. Sparse-safe: the window auto-widens, the value is the
    /// LATEST point ("as of <date>") unless a mean is requested, and "—" when empty.
    private func metricRow(key: String, label: LocalizedStringKey, unit: String = "",
                           aggregate: Aggregate = .latest,
                           fmt: @escaping (Double) -> String) -> some View {
        let rows = resolvedWindow(key)
        let values = rows.map(\.value)
        let value: String
        let caption: String?
        if values.isEmpty {
            value = "—"
            caption = nil
        } else {
            switch aggregate {
            case .latest:
                let v = values.last ?? 0
                value = unit.isEmpty ? fmt(v) : "\(fmt(v)) \(unit)"
                caption = rows.last.flatMap { date($0.day) }.map { String(localized: "as of \(Self.asOfFormatter.string(from: $0))") }
            case .mean:
                let m = mean(values) ?? 0
                value = unit.isEmpty ? fmt(m) : "\(fmt(m)) \(unit)"
                caption = String(localized: "avg · \(values.count)d")
            }
        }
        return LabeledContent {
            Text(value)
                .foregroundStyle(values.isEmpty ? StrandPalette.textTertiary : StrandPalette.textSecondary)
        } label: {
            Text(label)
            if let caption { Text(caption) }
        }
    }

    // MARK: - Chart sections (one chart row per metric, same height per page)

    private var heartSection: some View {
        Section {
            chartRow(title: "Resting heart rate", key: "resting_hr",
                     gradient: roseGradient, fallback: 40...80,
                     fmt: { "\(Int($0.rounded())) bpm" })
            chartRow(title: "Heart rate variability", key: "hrv",
                     gradient: purpleGradient, fallback: 20...120,
                     fmt: { "\(Int($0.rounded())) ms" })
            chartRow(title: "Blood oxygen", key: "spo2",
                     gradient: cyanGradient, fallback: 90...100,
                     fmt: { String(format: "%.1f%%", $0) })
            chartRow(title: "Respiratory rate", key: "resp_rate",
                     gradient: accentGradient, fallback: 10...22,
                     fmt: { String(format: "%.1f rpm", $0) })
        } header: {
            Text("Heart & vitals")
        }
    }

    private var activitySection: some View {
        Section {
            chartRow(title: "Steps", key: "steps",
                     gradient: cyanGradient, fallback: 0...12000,
                     fmt: { intString($0) })
            chartRow(title: "Active energy", key: "active_kcal",
                     gradient: amberGradient, fallback: 0...1000,
                     fmt: { "\(intString($0)) kcal" })
        } header: {
            Text("Activity & energy")
        }
    }

    private var bodySection: some View {
        Section {
            chartRow(title: "Weight", key: "weight",
                     gradient: accentGradient, fallback: 50...100,
                     fmt: { massLabel($0) })
            chartRow(title: "Body fat", key: "body_fat",
                     gradient: amberGradient, fallback: 8...35,
                     fmt: { String(format: "%.1f%%", $0) })
            chartRow(title: "Lean body mass", key: "lean_mass",
                     gradient: accentGradient, fallback: 40...80,
                     fmt: { massLabel($0) })
            chartRow(title: "BMI", key: "bmi",
                     gradient: purpleGradient, fallback: 16...35,
                     fmt: { String(format: "%.1f", $0) })
        } header: {
            Text("Body composition")
        }
    }

    private var sleepSection: some View {
        Section {
            chartRow(title: "Asleep", key: "asleep_min",
                     gradient: purpleGradient, fallback: 240...600,
                     fmt: { durationString($0) })
        } header: {
            Text("Sleep")
        }
    }

    /// One chart row for a metric series: title + mean on the right, the TrendChart body
    /// (same height for every row), then avg/min/max/points. Sparse-safe via resolvedWindow.
    private func chartRow(title: LocalizedStringKey, key: String, gradient: Gradient,
                          fallback: ClosedRange<Double>,
                          fmt: @escaping (Double) -> String) -> some View {
        let rows = resolvedWindow(key)
        let pts = trendPoints(rows)
        let vals = rows.map(\.value)
        let footerItems: [(LocalizedStringKey, String)] = {
            guard let avg = mean(vals), let lo = vals.min(), let hi = vals.max() else {
                return [("Avg", "—"), ("Min", "—"), ("Max", "—"), ("Points", "0")]
            }
            return [("Avg", fmt(avg)), ("Min", fmt(lo)), ("Max", fmt(hi)), ("Points", "\(vals.count)")]
        }()
        return VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
                Text(mean(vals).map { fmt($0) } ?? "—")
            } label: {
                Text(title)
            }
            Group {
                if pts.count >= 2 {
                    TrendChart(
                        points: pts,
                        gradient: gradient,
                        valueRange: valueRange(pts, fallback: fallback),
                        showsArea: true,
                        height: NoopMetrics.chartHeight,
                        valueFormat: fmt
                    )
                } else if let only = vals.last {
                    // A single point is not a line — present the lone reading,
                    // never an "empty" state when the series has data.
                    singlePoint(only, fmt: fmt, accent: StrandPalette.sample(stops: gradient.stops, at: 0.85))
                } else {
                    emptyChart
                }
            }
            .frame(height: NoopMetrics.chartHeight)
            HStack(spacing: 0) {
                ForEach(Array(footerItems.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                        Text(item.1)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Lone-reading body for series with exactly one point in range.
    private func singlePoint(_ value: Double, fmt: (Double) -> String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Latest reading")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
            Text(fmt(value)).font(StrandFont.number(34)).foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var emptyChart: some View {
        Text("No readings recorded.")
            .foregroundStyle(StrandPalette.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Per-metric gradients (colour communicates category only)

    private var accentGradient: Gradient {
        Gradient(colors: [StrandPalette.accentMuted, StrandPalette.accent, StrandPalette.accentHover])
    }
    private var roseGradient: Gradient {
        Gradient(colors: [StrandPalette.statusWarning, StrandPalette.statusCritical])
    }
    private var cyanGradient: Gradient {
        Gradient(colors: [StrandPalette.metricCyan.opacity(0.55), StrandPalette.metricCyan])
    }
    private var amberGradient: Gradient {
        Gradient(colors: [StrandPalette.metricAmber.opacity(0.55), StrandPalette.metricAmber])
    }
    private var purpleGradient: Gradient {
        Gradient(colors: [StrandPalette.metricPurple.opacity(0.55), StrandPalette.metricPurple])
    }

    // MARK: - Series helpers (sparse-data fallback to ALL)

    /// All-history rows for a key (ascending by day).
    private func raw(_ key: String) -> [(day: String, value: Double)] { series[key] ?? [] }

    /// The latest recorded day for a key (anchors its windows).
    private func latestDate(_ key: String) -> Date? {
        guard let d = raw(key).last?.day else { return nil }
        return date(d)
    }

    /// Rows for a key over a given range, taken RELATIVE TO THE LATEST data point
    /// (not "now"); `.all` returns everything.
    private func slice(_ key: String, _ r: RangeWindow) -> [(day: String, value: Double)] {
        let all = raw(key)
        guard let n = r.days else { return all }
        guard let last = latestDate(key) else { return [] }
        let cutoff = last.addingTimeInterval(-Double(n - 1) * 86_400)
        return all.filter { row in
            guard let d = date(row.day) else { return false }
            return d >= cutoff
        }
    }

    /// The range actually shown for a key: the SELECTED range whenever its window
    /// holds ≥1 point, otherwise the smallest LARGER range that does — so switching
    /// ranges stays visibly distinct and only sparse windows widen. Served from the
    /// per-render cache; falls back to a fresh compute on a cache miss.
    private func effectiveRange(_ key: String) -> RangeWindow {
        windowCache[key]?.effective ?? computeEffectiveRange(key)
    }

    /// The actual effective-range computation (re-slices the series, once per widening
    /// candidate). Called only from rebuildWindowCache and the cache-miss fallback —
    /// never repeatedly within a single render.
    private func computeEffectiveRange(_ key: String) -> RangeWindow {
        guard !raw(key).isEmpty else { return range }
        for r in range.widening where !slice(key, r).isEmpty { return r }
        return .all
    }

    /// Rows for a key trimmed to its resolved (possibly widened) window. Served from
    /// the per-render cache; falls back to a fresh compute on a cache miss.
    private func resolvedWindow(_ key: String) -> [(day: String, value: Double)] {
        if let cached = windowCache[key]?.rows { return cached }
        return slice(key, computeEffectiveRange(key))
    }

    private func trendPoints(_ rows: [(day: String, value: Double)]) -> [TrendPoint] {
        rows.compactMap { row in
            guard let dt = date(row.day) else { return nil }
            return TrendPoint(date: dt, value: row.value)
        }
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func valueRange(_ pts: [TrendPoint], fallback: ClosedRange<Double>, pad: Double = 0.12) -> ClosedRange<Double> {
        let v = pts.map(\.value)
        guard let lo = v.min(), let hi = v.max() else { return fallback }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let span = hi - lo
        return (lo - span * pad)...(hi + span * pad)
    }

    private func intString(_ v: Double) -> String {
        let n = Int(v.rounded())
        if abs(n) >= 1000 {
            return Self.groupedIntFmt.string(from: NSNumber(value: n)) ?? "\(n)"
        }
        return "\(n)"
    }

    private func durationString(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Preview seam

extension AppleHealthView {
    /// In-memory bundle that bypasses the store-backed async load for previews.
    fileprivate struct PreviewData {
        var rows: [AppleDaily]
        var workoutCount: Int
        var series: [String: [(day: String, value: Double)]]
    }
}

#if DEBUG
@MainActor
private func appleHealthPreviewData() -> AppleHealthView.PreviewData {
    let cal = Calendar(identifier: .gregorian)
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.dateFormat = "yyyy-MM-dd"
    let today = Date()

    var rows: [AppleDaily] = []
    var series: [String: [(day: String, value: Double)]] = [
        "steps": [], "active_kcal": [], "vo2max": [],
        "resting_hr": [], "hrv": [], "spo2": [], "resp_rate": [], "asleep_min": [],
        "weight": [], "body_fat": [], "lean_mass": [], "bmi": []
    ]

    // Seed ~2 years so the range control has real depth to window into.
    for i in stride(from: 729, through: 0, by: -1) {
        guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
        let day = fmt.string(from: d)
        let phase = Double(729 - i)
        let steps  = 8000 + 3200 * sin(phase / 6.0) + Double((Int(phase) * 53) % 1800)
        let active = 420 + 180 * sin(phase / 5.0 + 0.6) + Double((Int(phase) * 17) % 90)
        let rhr    = 53 + 4 * sin(phase / 8.0) + Double((Int(phase) * 7) % 4) - 2
        let hrv    = 58 + 16 * sin(phase / 9.0) + Double((Int(phase) * 13) % 11) - 5
        let spo2   = 96 + 1.4 * sin(phase / 4.0) + Double((Int(phase) * 3) % 2)
        let resp   = 14.5 + 1.2 * sin(phase / 7.0)
        let vo2    = 47 + 2.2 * sin(phase / 21.0)
        let asleep = 410 + 55 * sin(phase / 5.0 + 1.1) + Double((Int(phase) * 11) % 30) - 15
        // Slow body-composition drift over the two years (measured WEEKLY → sparse).
        let weight = 78.0 - 5.0 * sin(phase / 220.0) + 0.6 * sin(phase / 13.0)
        let bodyFat = 18.0 - 3.0 * sin(phase / 240.0) + 0.4 * sin(phase / 11.0)
        let lean   = weight * (1.0 - bodyFat / 100.0)
        let bmi    = weight / (1.78 * 1.78)

        rows.append(AppleDaily(
            day: day,
            steps: Int(steps.rounded()),
            activeKcal: max(120, active),
            basalKcal: 1600,
            vo2max: vo2,
            avgHr: 72,
            maxHr: 148,
            walkingHr: 96,
            weightKg: weight))

        series["steps"]?.append((day, max(0, steps)))
        series["active_kcal"]?.append((day, max(80, active)))
        series["vo2max"]?.append((day, vo2))
        series["resting_hr"]?.append((day, max(40, rhr)))
        series["hrv"]?.append((day, max(15, hrv)))
        series["spo2"]?.append((day, min(100, spo2)))
        series["resp_rate"]?.append((day, resp))
        series["asleep_min"]?.append((day, max(180, asleep)))
        // Body composition is logged once a week → deliberately sparse, to exercise
        // the trailing-window → ALL fallback (a W/M view would otherwise be empty).
        if Int(phase) % 7 == 0 {
            series["weight"]?.append((day, weight))
            series["body_fat"]?.append((day, bodyFat))
            series["lean_mass"]?.append((day, lean))
            series["bmi"]?.append((day, bmi))
        }
    }

    return .init(rows: rows, workoutCount: 124, series: series)
}

#Preview("Apple Health — seeded") {
    AppleHealthView(previewData: appleHealthPreviewData())
        .environmentObject(Repository(deviceId: "preview"))
        .frame(width: 920, height: 980)
        .preferredColorScheme(.dark)
}

#Preview("Apple Health — empty") {
    AppleHealthView(previewData: .init(rows: [], workoutCount: 0, series: [:]))
        .environmentObject(Repository(deviceId: "preview"))
        .frame(width: 920, height: 600)
        .preferredColorScheme(.dark)
}
#endif
