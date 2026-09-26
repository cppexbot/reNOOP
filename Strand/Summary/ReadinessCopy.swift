//  ReadinessCopy.swift
//  NOOP · the localized words for a `ReadinessEngine.Signal`.
//
//  The engine speaks in keys, flags and locale-free evidence; this turns them into the user's language.
//  Shared by the classic Today synthesis card and the Summary highlights so the two can never describe
//  the same signal differently.

import Foundation
import StrandAnalytics

enum ReadinessCopy {
    /// Short name of the signal ("HRV", "Resting HR", …).
    static func label(_ key: String) -> String {
        switch key {
        case "hrv": return String(localized: "HRV")
        case "rhr": return String(localized: "Resting HR")
        case "respRate": return String(localized: "Respiratory rate")
        case "acwr": return String(localized: "Training load")
        case "monotony": return String(localized: "Training variety")
        default: return key
        }
    }

    /// The measured-vs-baseline figures behind a signal, or nil when the engine gave none.
    static func evidence(_ evidence: ReadinessEngine.Evidence?) -> String? {
        guard let evidence else { return nil }
        switch evidence {
        case .metric(let value, let baseline, let unit, let decimals):
            let valueText = number(value, decimals: decimals)
            let baselineText = number(baseline, decimals: decimals)
            return String(localized: "\(valueText) vs \(baselineText) \(unit)")
        case .trainingLoad(let acute, let chronic):
            let acuteText = number(acute, decimals: 1)
            let chronicText = number(chronic, decimals: 1)
            return String(localized: "7d \(acuteText) / 28d \(chronicText)")
        case .monotony(let value):
            return String(localized: "monotony \(number(value, decimals: 1))")
        }
    }

    /// One plain-language read of the signal, lower-case, meant to follow its label.
    static func detail(_ signal: ReadinessEngine.Signal) -> String {
        if signal.key == "acwr", let evidence = signal.evidenceData,
           case .trainingLoad(let acute, let chronic) = evidence {
            let ratio = number(chronic > 0 ? acute / chronic : 0, decimals: 2)
            switch signal.flag {
            case .good: return String(localized: "in the sweet spot (acute:chronic \(ratio))")
            case .bad: return String(localized: "spiking (acute:chronic \(ratio)) - higher injury risk")
            case .watch: return acute < chronic
                ? String(localized: "ramping down (acute:chronic \(ratio)) - room to build")
                : String(localized: "building fast (acute:chronic \(ratio)) - watch fatigue")
            case .neutral: return String(localized: "in the sweet spot (acute:chronic \(ratio))")
            }
        }
        switch (signal.key, signal.flag) {
        case ("hrv", .good): return String(localized: "above your baseline - well recovered")
        case ("hrv", .neutral), ("rhr", .neutral): return String(localized: "in your normal range")
        case ("hrv", .watch): return String(localized: "a touch below baseline")
        case ("hrv", .bad): return String(localized: "suppressed - a sign of autonomic fatigue")
        case ("rhr", .good): return String(localized: "at or below baseline")
        case ("rhr", .watch): return String(localized: "running a little high")
        case ("rhr", .bad): return String(localized: "elevated - overtraining or illness can do this")
        case ("respRate", .bad): return String(localized: "up vs baseline - sometimes an early sign of getting sick")
        case ("respRate", .watch): return String(localized: "slightly raised vs baseline")
        case ("monotony", _): return String(localized: "low - similar strain every day raises strain/illness risk")
        default: return String(localized: "in your normal range")
        }
    }

    /// The signal as one complete sentence, for a Summary highlight. Written whole rather than glued from
    /// `label` + `detail`: the glued form cannot agree in gender or number once translated (Russian read
    /// "Training variety … low" with a feminine adjective on a neuter noun).
    static func sentence(_ signal: ReadinessEngine.Signal) -> String {
        switch (signal.key, signal.flag) {
        case ("hrv", .good): return String(localized: "Your HRV is above your normal — you're well recovered.")
        case ("hrv", .watch): return String(localized: "Your HRV is a little below your normal.")
        case ("hrv", .bad): return String(localized: "Your HRV is well below your normal — a sign of fatigue.")
        case ("rhr", .good): return String(localized: "Your resting heart rate is at or below your normal.")
        case ("rhr", .watch): return String(localized: "Your resting heart rate is running a little high.")
        case ("rhr", .bad):
            return String(localized: "Your resting heart rate is elevated — overtraining or illness can do this.")
        case ("respRate", .bad):
            return String(localized: "Your respiratory rate is up — sometimes an early sign of getting sick.")
        case ("respRate", .watch): return String(localized: "Your respiratory rate is slightly above your normal.")
        case ("acwr", .bad):
            return String(localized: "Your last 7 days of training are well above your 28-day average — a higher injury risk.")
        case ("acwr", .watch):
            if case .trainingLoad(let acute, let chronic)? = signal.evidenceData, acute < chronic {
                return String(localized: "You trained less in the last 7 days than over the last 28 — there's room to build.")
            }
            return String(localized: "Your training load is building fast — watch for fatigue.")
        case ("acwr", _):
            return String(localized: "Your training load over the last 7 days is in line with the last 28.")
        case ("monotony", _):
            return String(localized: "Your Effort has been much the same every day — mix hard and easy days.")
        default:
            return String(localized: "\(label(signal.key)) is in your normal range.")
        }
    }

    static func number(_ value: Double, decimals: Int) -> String {
        decimals == 0
            ? String(Int(value.rounded()))
            : String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, value)
    }
}
