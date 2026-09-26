import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Explore (Metric Explorer)
//
// The catalog-driven "Explore" surface: a grouped list — one SectionHeader per MetricCatalog.category,
// then a row per metric — pushing the Health-style `MetricDetailView` (Strand/MetricHealth/).

// yyyy-MM-dd → Date, fixed UTC / en_US_POSIX (per task spec).
private let strandDayParser: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private func parseDay(_ day: String) -> Date? { strandDayParser.date(from: day) }

/// The category accent (colour communicates category only — never decoration).
private func metricAccent(_ m: MetricDescriptor) -> Color {
    switch m.key {
    case "recovery", "sleep_performance", "hours_vs_needed_pct", "sleep_consistency",
         "restorative_pct", "restorative_min", "sleep_efficiency", "sleep_total_min",
         "sleep_deep_min", "sleep_rem_min":
        return StrandPalette.accent
    case "strain", "hr_zones45_min", "hr_zones_all_min", "strength_min", "hr_zones13_min":
        return StrandPalette.strainColor(14)              // mid-strain hue
    case "hrv", "vo2max", "lean_mass":
        return StrandPalette.metricPurple
    case "rhr", "stress", "sleep_debt_min", "body_fat", "max_hr":
        return StrandPalette.metricRose
    case "spo2", "steps":
        return StrandPalette.metricCyan
    case "energy_kcal", "active_kcal":
        return StrandPalette.metricAmber
    default:
        switch m.source {
        case "apple-health": return StrandPalette.metricCyan
        case "xiaomi-band":  return StrandPalette.metricAmber
        default:             return StrandPalette.textPrimary
        }
    }
}

// MARK: - Range

/// The W/2W/3W/M/3M/6M/1Y/ALL window, driving the single SegmentedPillControl.
enum ExploreRange: Int, CaseIterable, Identifiable, Hashable {
    case week = 7, twoWeeks = 14, threeWeeks = 21, month = 30, quarter = 90, half = 180, year = 365, all = 0
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .twoWeeks: return String(localized: "2W"); case .threeWeeks: return String(localized: "3W")
        case .week: return String(localized: "W"); case .month: return String(localized: "M"); case .quarter: return String(localized: "3M")
        case .half: return String(localized: "6M"); case .year: return String(localized: "1Y"); case .all: return String(localized: "ALL")
        }
    }
    var name: String {
        switch self {
        case .twoWeeks: return String(localized: "2 weeks"); case .threeWeeks: return String(localized: "3 weeks")
        case .week: return String(localized: "week"); case .month: return String(localized: "month"); case .quarter: return String(localized: "quarter")
        case .half: return String(localized: "6 months"); case .year: return String(localized: "year"); case .all: return String(localized: "all time")
        }
    }
    /// Trailing days the window spans (nil = everything).
    var days: Int? { self == .all ? nil : rawValue }
}

// MARK: - Readings table projection (task #8)

/// One windowed reading behind a vital's detail chart: its day ("YYYY-MM-DD"), the value, and the RAW
/// source id it came from (a strap id, the "-noop" computed sibling, "apple-health", or "health-connect").
/// The readings TABLE and the "N readings" caption both derive from this ONE windowed list, so they can
/// never disagree; the raw source maps to a human label via `provenanceDisplayLabel` — the SAME
/// resolver every provenance surface uses, so no source vocabulary is invented. Swift twin of Android's `VitalReading`.
struct VitalReading: Equatable {
    let day: String
    let value: Double
    let source: String
}

let vo2MaxAttributionPrefix = "vo2max-estimator:"

/// #103/queue-11a follow-up: a display-source token for a `spo2` reading that came from the
/// `spo2_candidate` fallback (WHOOP `spo2_candidate_82` or Oura ceiling@100 `0x6F`, device-conditional)
/// rather than a calibrated `spo2Pct` import. Every OTHER surface that shows this fallback (the Key
/// Metrics tile, `VitalSignsSummary`) already labels it "strap estimate (unverified)"
/// — this Explorer/"Your Cards" drill-down had no candidate fallback at all until now (found 2026-08-24:
/// an Oura-only or WHOOP-4.0-only install with the toggle ON saw nothing here past the last calibrated
/// import, even though the Key Metrics tile right next to it showed a real number). Same
/// prefix-token idiom as `vo2MaxAttributionSource` just below, so the existing readings-table plumbing
/// needs no new machinery — only `provenanceDisplayLabel` gains one more case.
let spo2CandidateAttributionSource = "spo2-candidate-estimate"

/// A display-source token that keeps the existing readings-table plumbing while naming the estimator.
/// `nil` is deliberately preserved as `unknown`; a legacy point must never inherit today's profile method.
func vo2MaxAttributionSource(_ estimator: Vo2MaxEstimator?) -> String {
    vo2MaxAttributionPrefix + (estimator?.rawValue ?? "unknown")
}

/// Will the chart show a visible break in this VO₂max trend?
///
/// Derived from `vo2MaxTrendSegmentIds` rather than recomputed, so the caption and the segmentation can
/// never disagree. A GAP IN DAYS under one estimator is still a single segment and draws no break, so it
/// correctly gets no caption: a break means the readings were not produced alike, not that the data
/// paused. Named for the BREAK: an untagged legacy reading resolves to "...estimator:unknown", so an
/// unknown -> Nes transition splits the line while the method itself may never have changed.
/// Kotlin twin `vo2MaxTrendHasBreak`.
func vo2MaxTrendHasBreak(days: [String], sourceByDay: [String: String]) -> Bool {
    Set(vo2MaxTrendSegmentIds(days: days, sourceByDay: sourceByDay)).count > 1
}

/// Sequential segment ids for the VO₂max trend. The counter matters when a user changes Nes → Uth → Nes:
/// using the method name alone would reconnect the two non-adjacent Nes runs across the Uth interval.
func vo2MaxTrendSegmentIds(days: [String], sourceByDay: [String: String]) -> [String] {
    var previous: String?
    var group = -1
    return days.map { day in
        let source = sourceByDay[day] ?? vo2MaxAttributionSource(nil)
        if source != previous { group += 1; previous = source }
        return "\(group):\(source)"
    }
}

func vo2MaxEstimatorDisplayName(_ estimator: Vo2MaxEstimator?) -> String {
    switch estimator {
    case .nes: return "Nes 2011"
    case .uth: return "Uth 2004"
    case nil:  return String(localized: "Unknown")
    }
}

/// Product mark, never natural-language copy. Keeping it out of localization also makes source
/// classification stable when the app language changes.
private let provenanceWhoopBrandName = "WHOOP"

/// PURE mapper (unit-testable), a raw resolver source id onto the spec's provenance labels, given
/// the strap's real `deviceId`. ANY NOOP-computed strap sibling (a "-noop"-suffixed id, not just the
/// active strap's) reads "On-device" — matching by suffix so a computed row from a non-active strap
/// can't fall through to `FusionSource.noopComputed`'s raw "NOOP" displayName; the imported strap source
/// (`deviceId`, normally "my-whoop") reads "Whoop"; the Apple-Health source reads "Apple Health".
/// Any other real source (Mi Band, Health Connect, nutrition) keeps its `FusionSource.displayName`
///, still the genuine merge winner, never a blanket claim. Mirror EXACTLY in Kotlin.
func provenanceDisplayLabel(rawSource: String, deviceId: String) -> String {
    if rawSource.hasPrefix(vo2MaxAttributionPrefix) {
        let raw = String(rawSource.dropFirst(vo2MaxAttributionPrefix.count))
        let method = vo2MaxEstimatorDisplayName(Vo2MaxEstimator(rawValue: raw))
        return "\(String(localized: "On-device")) · \(method)"
    }
    // #103/queue-11a follow-up: the Explorer's spo2 candidate-fallback rows (see
    // `spo2CandidateAttributionSource`) must read "strap estimate (unverified)", the SAME copy every
    // other candidate-fallback surface uses — never a device name, which would misrepresent an
    // unvalidated estimate as a calibrated reading in this table's Source column.
    if rawSource == spo2CandidateAttributionSource {
        return String(localized: "strap estimate (unverified)")
    }
    if rawSource.hasSuffix("-noop") { return String(localized: "On-device") }
    if rawSource == deviceId || rawSource == Repository.whoopSource { return provenanceWhoopBrandName }
    if rawSource == Repository.appleHealthSource { return "Apple Health" }
    // Localize the non-brand source names here rather than exposing the analytics layer's
    // intentionally locale-free wire/display vocabulary.
    switch FusionSource(rawValue: rawSource) {
    case .healthConnect: return "Health Connect"
    case .xiaomiBand:    return "Mi Band"
    case .nutritionCsv:  return String(localized: "Nutrition")
    case .localCache:    return String(localized: "Cached")
    case .whoopImport:   return provenanceWhoopBrandName
    case .noopComputed:  return String(localized: "On-device")
    case .appleHealth:   return "Apple Health"
    case nil:            return rawSource
    }
}

/// One row of a vital detail's readings table: the reading's day (localized), its formatted value with
/// unit, and a human source label. Plain strings so the view is a thin renderer and the projection stays
/// unit-testable. Swift twin of Android's `VitalReadingRow`.
struct VitalReadingRow: Equatable {
    let time: String
    let value: String
    let source: String
}

/// Project a vital's windowed `readings` into table rows, NEWEST FIRST — the same list (so the same count)
/// the "N readings" caption shows, guaranteeing the two never drift. Each row pairs the reading's DAY
/// (these vital series carry one aggregated reading per night, so a row's "time" is its localized calendar
/// date; the date always shows since a charted window spans 2+ days) with the model's own `format`ted
/// value + `unit` and the source label from `provenanceDisplayLabel` (a strap id → "Whoop", its
/// "-noop" sibling → "On-device", "apple-health" → "Apple Health", "health-connect" → "Health Connect").
/// `strapDeviceId` is the active strap id the resolver needs. Byte-identical projection to Android's
/// `vitalReadingRows`.
func vitalReadingRows(readings: [VitalReading], unit: String, strapDeviceId: String,
                      now: Date = Date(), format: (Double) -> String) -> [VitalReadingRow] {
    readings.reversed().map { reading in
        let value = format(reading.value)
        return VitalReadingRow(
            time: vitalReadingDateLabel(reading.day, now: now),
            value: unit.isEmpty ? value : "\(value) \(unit)",
            source: provenanceDisplayLabel(rawSource: reading.source, deviceId: strapDeviceId)
        )
    }
}

/// "9 Jun" for a "YYYY-MM-DD" reading day (today / yesterday read as words to match the hero "as of"
/// line); the verbatim string if it doesn't parse. UTC-fixed and localized, matching this file's other date
/// labels. Swift twin of Android's `vitalReadingDateLabel`.
func vitalReadingDateLabel(_ day: String, now: Date = Date()) -> String {
    guard let date = parseDay(day) else { return day }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    if cal.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
    if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
       cal.isDate(date, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
    let formatter = DateFormatter()
    formatter.locale = AppLanguage.activeLocale
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "d MMM"
    return formatter.string(from: date)
}

// MARK: - Skin-temp explorer notes (#1847 / #1848)

/// Whether the skin-temp explorer must explain that it fell back to deviations despite the
/// user's Settings choice asking for temperatures. Twin of Android's `shouldExplainSkinTempFallback`.
///
/// True only when the user asked for absolute, the screen is NOT leading with absolutes, and NO
/// night in the window carries one — so the fallback is total, not partial. A window with one
/// stored temperature and twenty deltas still leads with temperatures (the #1850 window-wide rule),
/// so this note stays silent there; it fires only when the setting genuinely cannot be honoured.
func shouldExplainSkinTempFallback(prefer: SkinTempDisplay.Kind, leadsAbsolute: Bool,
                                   anyAbsoluteInWindow: Bool) -> Bool {
    prefer == .absolute && !leadsAbsolute && !anyAbsoluteInWindow
}

/// Whether the skin-temp explorer must explain that deviation-only nights were dropped from the
/// series when leading with absolutes. Twin of Android's `shouldExplainShortenedSkinTempSeries`.
///
/// True ONLY when leading with the absolute — the deviation-led branch also drops rows (calibrating
/// nights that have only an absolute, and the #622 bimodal partition), but those are the OPPOSITE
/// kind, so this note's sentence would be precisely backwards there. True only when rows were
/// actually dropped, so a complete series stays silent.
func shouldExplainShortenedSkinTempSeries(leadsAbsolute: Bool, shownReadings: Int,
                                          rowsWithEitherNumber: Int) -> Bool {
    leadsAbsolute && shownReadings < rowsWithEitherNumber
}

// MARK: - Root: categorized list

/// The "Explore" picker — categories as sections, metrics as rows, each pushing a
/// MetricDetailView. A faint trailing "•" marks metrics whose series is empty.
struct MetricExplorerView: View {
    @EnvironmentObject var repo: Repository
    /// metric.id → whether its series is empty. Filled INCREMENTALLY by `probeEmptiness()`; a metric
    /// absent from the map simply has no empty-dot yet (rows never wait on it — see `MetricRow`).
    @State private var emptyByID: [String: Bool] = [:]
    @State private var probedRefreshSeq: Int?
    /// True while the empty-dot probe is still running its first pass. Drives a small inline progress
    /// hint in the header, never gating the rows: the catalog is static, so every row's label/icon/unit
    /// must paint immediately even before any series read returns (#199).
    @State private var probing = true

    var body: some View {
        #if os(macOS)
        // macOS: Explore is a standalone detail pane, so it owns its NavigationStack.
        NavigationStack { exploreScaffold }
            .task(id: repo.refreshSeq) { await probeEmptiness(refreshSeq: repo.refreshSeq) }
        #else
        // iOS: Explore is pushed INSIDE the More tab's NavigationStack. A nested NavigationStack made
        // tapping a metric bounce straight back to the More list (#199) — so use the ambient stack; the
        // rows push their detail with a direct closure-based NavigationLink (#38).
        exploreScaffold
            .task(id: repo.refreshSeq) { await probeEmptiness(refreshSeq: repo.refreshSeq) }
        #endif
    }

    private var exploreScaffold: some View {
        // PERF (scroll): lazy column. Unlike most screens, Explore's content is a flat list of sibling
        // sections (the probe hint, the Deep Timeline row, then a long per-category ForEach of metric
        // cards), so LazyVStack genuinely builds the off-screen category cards on demand. No
        // `staggeredAppear` here and identical column alignment/spacing (20) + per-child bottom padding,
        // so the layout is byte-identical to the eager VStack.
        ScreenScaffold(title: "Explore", subtitle: "Every signal, one tap deep.",
                       onRefresh: { await repo.refresh() }, lazy: true,
                       topBackground: liquidScaffoldSky()) {
            // A quiet, non-blocking hint while the empty-dot probe runs its first pass. The rows below
            // render in full immediately regardless — this only reassures during the scan, and never
            // leaves the screen reading as a bare/empty list before the probe lands (#199).
            if probing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning your data…")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The headline tap-through (#575): a full-day, full-resolution, zoomable timeline. Sits above
            // the per-metric catalog because it's a different kind of view — every second of one day rather
            // than one number per day. Closure-based NavigationLink, matching the metric rows below (#38/#199).
            NavigationLink {
                FullDayChartView()
            } label: {
                deepTimelineRow
            }
            // Liquid press language: the settle-inward LiquidPressStyle (the same physical response the
            // Today / batch-1 cards use), replacing the classic StrandPressableButtonStyle.
            .buttonStyle(LiquidPressStyle())
            #if os(iOS)
            .simultaneousGesture(TapGesture().onEnded { StrandHaptic.selection.play() })
            #endif
            .padding(.bottom, NoopMetrics.sectionGap - 20)

            ForEach(MetricCatalog.categories, id: \.self) { category in
                let metrics = MetricCatalog.inCategory(category)
                if !metrics.isEmpty {
                    VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                        // Localized at the render site only; `category` itself stays the raw
                        // English identifier that `inCategory` filters on.
                        SectionHeader("\(MetricCatalog.categoryDisplayName(category))", overline: "Category",
                                      trailing: "\(metrics.count)")
                        NoopCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(metrics.enumerated()), id: \.element.id) { idx, metric in
                                    // Push the detail directly (closure-based), like every other More-tab
                                    // screen. The old value + .navigationDestination(for:) pairing resolved
                                    // against TWO registered destinations and double-pushed — the detail
                                    // flashed then popped straight back (#38).
                                    NavigationLink {
                                        MetricDetailView(metric: metric)
                                    } label: {
                                        MetricRow(metric: metric,
                                                  isEmpty: emptyByID[metric.id] ?? false)
                                    }
                                    // Full-row press-down feedback in the liquid language — the settle-inward
                                    // LiquidPressStyle (a transform, so it works edge-to-edge with dividers
                                    // between, no corner radius to match). Matches Today's tappable rows.
                                    .buttonStyle(LiquidPressStyle())
                                    #if os(iOS)
                                    // Light selection tick on tap; the simultaneousGesture leaves the
                                    // NavigationLink push intact.
                                    .simultaneousGesture(TapGesture().onEnded {
                                        StrandHaptic.selection.play()
                                    })
                                    #endif
                                    if idx < metrics.count - 1 {
                                        Divider().overlay(StrandPalette.hairline)
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, NoopMetrics.sectionGap - 20)
                }
            }
        }
        // Rows push MetricDetailView directly (closure-based NavigationLink above) — no value/destination
        // pairing, which is what double-pushed (#38). Nothing else registers a MetricDescriptor destination.
    }

    /// The hero entry that opens the Deep Timeline (#575). A full-bleed card, not a list row, so it reads
    /// as the headline above the per-metric catalog.
    private var deepTimelineRow: some View {
        NoopCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(StrandPalette.metricRose.opacity(0.16))
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(StrandPalette.metricRose)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Deep Timeline")
                        .font(StrandFont.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Every second of your day, zoomable.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deep Timeline, every second of your day, zoomable")
        .accessibilityAddTraits(.isButton)
    }

    /// One lightweight pass to learn which metrics have no series, so rows can flag them with the
    /// faint trailing dot. Failures default to "has data" (no dot).
    ///
    /// #199 originally fixed this by publishing PER METRIC rather than in one final batch, because the
    /// sweep ran ~60 sequential `exploreSeries` reads — each hopping back to the @MainActor Repository —
    /// and the freshly-pushed list painted blank until it finished. That made the symptom bearable
    /// without addressing the cost: the sweep still read sixty full histories, built sixty dictionaries
    /// and sorted them, only to keep sixty booleans.
    ///
    /// `Repository.nonEmptyMetricIDs` asks the cheap question instead — one DISTINCT-key query per
    /// source plus one in-memory pass — so the whole probe is now a single await. The per-metric
    /// publishing and the `Task.yield()` are gone with it: there is no longer a long sweep to interleave
    /// with layout, and one assignment publishes the lot. Rows still render their label / icon / unit
    /// without waiting on this — the map only ever ADDS a trailing dot.
    private func probeEmptiness(refreshSeq: Int) async {
        guard probedRefreshSeq != refreshSeq || emptyByID.isEmpty else { probing = false; return }
        probedRefreshSeq = refreshSeq
        probing = true
        let nonEmpty = await repo.nonEmptyMetricIDs(MetricCatalog.all)
        guard !Task.isCancelled else { return }
        emptyByID = Dictionary(uniqueKeysWithValues: MetricCatalog.all.map { ($0.id, !nonEmpty.contains($0.id)) })
        probing = false
    }
}

// MARK: - One catalog row

private struct MetricRow: View {
    let metric: MetricDescriptor
    let isEmpty: Bool

    // Trailing unit chip follows the Imperial/Metric preference (kg→lb, °C→°F) and the Effort scale
    // (/100→/21, #268).
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var unitLabel: String {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        let temp = UnitPrefs.resolveTemperature(system: system, override: temperatureRaw)
        let effort = UnitPrefs.resolveEffortScale(effortScaleRaw)
        return metric.displayUnit(system: system, temperature: temp, effortScale: effort)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(StrandPalette.surfaceInset)
                Image(systemName: metric.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(metricAccent(metric))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(metric.sourceLabel)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }

            Spacer(minLength: 8)

            if !unitLabel.isEmpty {
                Text(unitLabel)
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            // Faint trailing dot ONLY when this metric has no series at all.
            if isEmpty {
                Text("•")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary.opacity(0.5))
                    .accessibilityLabel("No data")
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        // Whole-string key per variant (never a concatenated localized tail on an a11y label).
        .accessibilityLabel(isEmpty
            ? "\(metric.title), \(unitLabel.isEmpty ? MetricCatalog.categoryDisplayName(metric.category) : unitLabel), no data"
            : "\(metric.title), \(unitLabel.isEmpty ? MetricCatalog.categoryDisplayName(metric.category) : unitLabel)")
        .accessibilityAddTraits(.isButton)
    }
}

// The detail page every row pushes is `MetricDetailView` (Strand/MetricHealth/).

// MARK: - Preview

#if DEBUG
@MainActor
private func explorerPreviewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    repo.loaded = true
    return repo
}

#Preview("Explore") {
    MetricExplorerView()
        .environmentObject(explorerPreviewRepo())
        .frame(width: 900, height: 820)
        .preferredColorScheme(.dark)
}

#Preview("Metric Detail") {
    let repo = explorerPreviewRepo()
    return NavigationStack {
        MetricDetailView(metric: MetricCatalog.all.first { $0.key == "recovery" }!)
    }
    .environmentObject(repo)
    .environmentObject(ProfileStore())
    .environmentObject(IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: "preview"))
    .frame(width: 900, height: 820)
    .preferredColorScheme(.dark)
}
#endif
