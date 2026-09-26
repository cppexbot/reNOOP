import Foundation

// MARK: - Strain load word (§9.1 strain ramp)

/// A short load word for a strain value, mirroring the recovery state idea. Computed off the fill
/// fraction (not the raw value) so the bands read the same on the 0–100 and 0–21 display scales.
public enum StrainLoadLabel {
    public static func forFraction(_ fraction: Double) -> String {
        switch min(max(fraction, 0), 1) {
        case ..<(6.0 / 21):   return String(localized: "LIGHT", bundle: .module)
        case ..<(10.0 / 21):  return String(localized: "MODERATE", bundle: .module)
        case ..<(14.0 / 21):  return String(localized: "STRENUOUS", bundle: .module)
        case ..<(18.0 / 21):  return String(localized: "HIGH", bundle: .module)
        default:              return String(localized: "ALL-OUT", bundle: .module)
        }
    }
}
