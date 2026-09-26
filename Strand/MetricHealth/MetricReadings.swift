import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Metric readings
//
// The pure helpers behind a metric's readings: the range enum, the readings-table projection, the
// VO₂max estimator attribution, the provenance labels and the skin-temperature notes.

// yyyy-MM-dd → Date, fixed UTC / en_US_POSIX (per task spec).
private let strandDayParser: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private func parseDay(_ day: String) -> Date? { strandDayParser.date(from: day) }

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

