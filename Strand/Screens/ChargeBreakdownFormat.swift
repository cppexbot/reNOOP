import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Charge breakdown presentation (pure, testable)
//
// LANE 2 (iOS UI) presentation helpers for the "What shaped it" Charge breakdown, the score-
// confidence tier chip, the calibrating countdown copy and the relative skin-temp label. Every
// helper here is PURE (no SwiftUI state, no I/O) so the chip formatter and countdown copy are
// unit-tested directly; the views below consume them. They are presentation only: nothing here
// recomputes a score, a confidence or a driver delta - those arrive from the engine
// (`ChargeDriver`, `ScoreConfidence`, `SkinTempRelative`) and are surfaced verbatim.
//
// No fabricated numbers, no em-dashes. Design-system tokens only (StrandPalette / StrandFont /
// NoopMetrics); the +N/-N chip uses the recovery ramp endpoints (green peak / red depleted) so a
// supporting term reads green and a limiting term reads red, matching the Charge colour world.

enum ChargeBreakdownFormat {

    // MARK: - Signed point-delta chip (A1)

    /// The chip label for a term's signed point contribution, e.g. +6 pts / -3 pts / 0 pts.
    /// Always carries an explicit sign for a non-zero delta so a positive term reads "+N" not "N".
    /// Pure + unit-tested (`ChargeBreakdownFormatTests`).
    static func chipLabel(deltaPoints: Int) -> String {
        // Whole-phrase variants per sign/count so translators never see a stitched unit fragment.
        if deltaPoints > 0 {
            return deltaPoints == 1 ? String(localized: "+\(deltaPoints) pt")
                                    : String(localized: "+\(deltaPoints) pts")
        }
        if deltaPoints < 0 {   // the minus sign rides the value
            return deltaPoints == -1 ? String(localized: "\(deltaPoints) pt")
                                     : String(localized: "\(deltaPoints) pts")
        }
        return String(localized: "0 pts")
    }

    /// The chip colour for a signed delta, sampled from the RECOVERY RAMP endpoints so the Charge
    /// colour world stays consistent: a term that supported recovery (positive) reads the ramp's
    /// green peak, one that limited it (negative) reads the red depleted end, and a neutral term
    /// reads tertiary text so it doesn't shout. Pure.
    static func chipColor(deltaPoints: Int) -> Color {
        if deltaPoints > 0 { return StrandPalette.recoveryColor(100) }   // green peak end of the ramp
        if deltaPoints < 0 { return StrandPalette.recoveryColor(0) }     // red depleted end of the ramp
        return StrandPalette.textTertiary
    }

    /// VoiceOver phrasing of one driver row: label, signed points, value vs baseline, verdict.
    /// Built from the engine row verbatim (no recompute). Pure.
    static func driverAccessibilityLabel(_ d: ChargeDriver) -> String {
        // Whole-phrase variants (direction x count, and with/without baseline) so translators see
        // complete sentences, never stitched direction/plural fragments.
        let pts: String
        if d.deltaPoints == 0 {
            pts = String(localized: "no change")
        } else {
            let n = abs(d.deltaPoints)
            switch (d.deltaPoints > 0, n == 1) {
            case (true, true):   pts = String(localized: "up 1 point")
            case (true, false):  pts = String(localized: "up \(n) points")
            case (false, true):  pts = String(localized: "down 1 point")
            case (false, false): pts = String(localized: "down \(n) points")
            }
        }
        // The engine's label + verdict are catalog KEYS (see ChargeDrivers.swift). Interpolating them
        // raw into a String(localized:) template would leave them English in a localized build (the
        // template is the lookup key, its substitutions are not re-localized), so look each up first
        // and interpolate the already-localized text. valueText/baselineText are numeric read-outs.
        let label = String(localized: String.LocalizationValue(d.label))
        let verdict = String(localized: String.LocalizationValue(d.verdict))
        if d.baselineText.isEmpty {
            return String(localized: "\(label): \(pts). \(d.valueText). \(verdict).")
        }
        return String(localized: "\(label): \(pts). \(d.valueText), \(d.baselineText). \(verdict).")
    }

    // MARK: - Score-confidence tier chip (A3)

    /// The short tier TAG surfaced on a score tile / breakdown header. Pure presentation of the
    /// EXISTING `ScoreConfidence` (never recomputed): calibrating -> CALIBRATING, building -> EST.,
    /// solid -> REL. (reliable). Unit-tested.
    static func tierTag(_ confidence: ScoreConfidence) -> String {
        switch confidence {
        case .calibrating: return String(localized: "CALIBRATING")
        case .building:    return String(localized: "EST.")
        case .solid:       return String(localized: "REL.")
        }
    }

    /// The `ScoreState` pill style that carries the tier chip, mapping the existing confidence onto
    /// the design system's score-lifecycle hues (slate / blue / green). Pure.
    static func tierState(_ confidence: ScoreConfidence) -> ScoreState {
        switch confidence {
        case .calibrating: return .calibrating
        case .building:    return .building
        case .solid:       return .solid
        }
    }

    // MARK: - Relative skin-temp label (A5)

    /// The relative skin-temp read-out, e.g. "+0.3 C vs your normal" / "-0.4 C vs your normal".
    /// Built from the engine's signed deviation; one decimal, explicit sign, never a fake absolute.
    /// Pure + unit-tested.
    static func skinTempDeviationLabel(_ rel: SkinTempRelative) -> String {
        let sign = rel.deviationC >= 0 ? "+" : ""
        return String(localized: "\(sign)\(String(format: "%.1f", rel.deviationC)) C vs your normal")
    }

    /// The plain-English tier word for the relative skin-temp marker. Pure.
    static func skinTempTierWord(_ tier: SkinTempRelative.Tier) -> String {
        switch tier {
        case .cooler:  return String(localized: "Cooler than your baseline")
        case .typical: return String(localized: "Typical for you")
        case .warmer:  return String(localized: "Warmer than your baseline")
        }
    }
}
