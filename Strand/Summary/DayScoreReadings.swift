//  DayScoreReadings.swift
//  NOOP · Summary home — the honest per-day score reads (the Charge carry, the Rest freshness gate) that
//  the Summary, the watch bridge and the widget anchor share, so no two surfaces can disagree about which
//  night a number belongs to.

import Foundation
import StrandAnalytics
import WhoopStore

enum DayScoreReadings {
    /// Pure carry-over selector for the Charge a day shows before it scores its own (twin of the Android
    /// `lastScoredRecoveryDay`).
    /// Returns the freshest scored prior row to carry over, or nil. `days` is oldest→newest; the chosen
    /// row is the last with a non-nil recovery that ISN'T today's (still-nil) key. nil unless: it's today,
    /// today itself isn't scored, and we're not mid-calibration (calibration owns its own copy), so past
    /// days / a scored today / a calibrating today all carry nothing and live behaviour is unchanged.
    static func lastScoredRecoveryDay(days: [DailyMetric], selectedDayKey: String,
                                      isToday: Bool, todayScored: Bool, isCalibrating: Bool) -> DailyMetric? {
        guard isToday, !todayScored, !isCalibrating else { return nil }
        // Defensive future-day guard (#547): the carry-over must NEVER select a day after today's key, or a
        // stray future-dated row (a bad-clock strap that slipped past the ingest gate / pre-heal DB) would
        // surface as "last night · 12 Jul". `selectedDayKey` is today's logical-day key here (isToday), and
        // yyyy-MM-dd compares lexicographically, so `$0.day < selectedDayKey` keeps only genuine prior days.
        // Belt-and-suspenders on top of the gate + one-time heal, cheap and never wrong.
        return days.last(where: { $0.recovery != nil && $0.day < selectedDayKey })
    }

    /// Carry-over recency cap (#779): the "Last night" framing only holds when the carried scored day is
    /// within this many days of today. A weeks-old import is still carried so the recovery side isn't a bare
    /// blank, but it is relabelled "Latest sleep · <date>" so a stale number is NEVER passed off as today's.
    static let carryFreshnessDays = 2

    /// True when the carried scored day is OLDER than the freshness cap (#779), which drives the "Latest
    /// sleep" relabel. Pure + unit-testable. Both keys are "yyyy-MM-dd"; an unparseable key (or non-positive gap)
    /// reads as fresh so we never over-claim staleness. `todayKey` is today's logical-day key (carry-over is
    /// today-only). Mirror EXACTLY in Kotlin.
    static func isCarryStale(priorDayKey: String, todayKey: String) -> Bool {
        guard let prior = dayKeyParser.date(from: priorDayKey),
              let today = dayKeyParser.date(from: todayKey) else { return false }
        let days = Calendar.current.dateComponents([.day], from: prior, to: today).day ?? 0
        return days > carryFreshnessDays
    }

    /// #977 — HONEST Rest resolution for the selected day. Today's own scored Rest wins; otherwise, ONLY on
    /// today, tail-fall-back to the last scored night — but ONLY when that night is within the carry-freshness
    /// window (`isCarryStale == false`). A live 5.0 whose sleep never scores (no overnight gravity ⇒ no
    /// `sleep_performance` point ever written) used to pin Rest to a weeks-old scored night while Charge kept
    /// advancing; gating the tail-fallback lets the Rest hero fall through to its No-Data/calibrating state
    /// instead of freezing on a stale number. The legitimate morning carry of last night's Rest (before today
    /// scores) is preserved unchanged. Pure + unit-testable. Mirror EXACTLY in Kotlin.
    static func freshRestScore(todayValue: Double?, lastDay: String?, lastValue: Double?,
                               isTodaySelected: Bool, todayKey: String) -> Double? {
        if let v = todayValue { return v }
        guard isTodaySelected, let lastDay, let lastValue,
              !isCarryStale(priorDayKey: lastDay, todayKey: todayKey) else { return nil }
        return lastValue
    }

    /// The carried recovery caption stamp, keyed on that scored day's own date and its recency. Within the
    /// freshness cap it reads "Last night · <date>"; once the carried day is older than the cap (#779) it
    /// reads "Latest sleep · <date>" so a weeks-old import is never surfaced as "Last night". Shared by every
    /// carried recovery read-out so the prior-day provenance reads identically. Mirror EXACTLY in Kotlin.
    static func carriedCaption(priorDayKey: String, todayKey: String) -> String {
        let date = lastChargeDateFmt(priorDayKey)
        return isCarryStale(priorDayKey: priorDayKey, todayKey: todayKey)
            ? String(localized: "Latest sleep · \(date)")
            : String(localized: "Last night · \(date)")
    }

    /// Parses a stored `yyyy-MM-dd` day key in the device-local zone (matching how DailyMetric.day
    /// is written), local so a key never shifts a day under timezone conversion.
    private static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    /// "d MMM" for a stored `yyyy-MM-dd` day key, used by the carried-over Charge caption (#543). Falls
    /// back to the raw key if it can't be parsed so the caption is never empty.
    private static func lastChargeDateFmt(_ dayKey: String) -> String {
        guard let date = dayKeyParser.date(from: dayKey) else { return dayKey }
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }
}

/// What the Charge ring can honestly say for the selected day. Pure + static so the truth table is
/// testable with no clock and no view (`ChargeDisplayCarryTests`).
///
/// See `ChargeDisplayCarryTests` for the regression this closes: reading the day's `recovery` raw meant
/// that after the 04:00 rollover — or on any day with no scored night — Charge blanked while Rest
/// (`DayScoreReadings.freshRestScore`) and the vitals (`Repository.lastVitalsDay`) carried right beside it,
/// and the widget/watch/Live Activity (`Repository.widgetAnchor`, #911) all showed a number.
///
/// The SELECTION is not re-implemented here: callers pass the row `DayScoreReadings.lastScoredRecoveryDay`
/// picked (its #547 future-day guard included) and the caption comes from `DayScoreReadings.carriedCaption`.
enum ChargeDisplay: Equatable {
    /// The selected day scored its own Charge.
    case scored(pct: Double)
    /// No score for the selected day; showing a REAL prior night's, stamped with whose it is.
    case carried(pct: Double, caption: String)
    /// Pre-seed-gate: the baseline is still learning and owns its own "N of 4 nights" copy.
    case calibrating(nights: Int)
    /// Nothing honest to show — no score, no prior night, and not calibrating.
    case noData

    /// The number the Charge ring draws, or nil for the honest empty state. A carry draws the REAL
    /// prior value; the empty states draw nothing rather than a fabricated zero.
    var pct: Double? {
        switch self {
        case .scored(let p): return p
        case .carried(let p, _): return p
        case .calibrating, .noData: return nil
        }
    }

    /// The short Charge-state label. It stays SHORT — the carried day's full "Last night · <date>" stamp
    /// lives in `caption`, not here. Only `.calibrating` may say "Calibrating": the pill used to key off
    /// `recovery != nil` and so claimed a calibrating baseline on every unscored day, including a
    /// trusted wearer who simply hadn't worn the strap that night.
    var stateLabel: String {
        switch self {
        case .scored: return String(localized: "Solid")
        case .carried: return String(localized: "Last night")
        case .calibrating: return String(localized: "Calibrating")
        case .noData: return String(localized: "No data")
        }
    }

    static func resolve(todayRecovery: Double?, priorScored: DailyMetric?,
                        calibrationNights: Int?, todayKey: String) -> ChargeDisplay {
        if let pct = todayRecovery { return .scored(pct: pct) }
        // Calibration owns its own copy and beats the carry — mid-calibration there is no trustworthy
        // prior score to stand in. Mirrors `lastScoredRecoveryDay`, which returns nil when calibrating.
        if let n = calibrationNights { return .calibrating(nights: n) }
        // `lastScoredRecoveryDay` only ever selects a row whose recovery is non-nil, so the second bind
        // is belt-and-suspenders: a nil falls through to noData rather than fabricating a carry.
        guard let prior = priorScored, let pct = prior.recovery else { return .noData }
        return .carried(pct: pct,
                        caption: DayScoreReadings.carriedCaption(priorDayKey: prior.day, todayKey: todayKey))
    }
}
