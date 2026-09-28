import Foundation

/// The language NOOP's copy is in. The system owns the choice (Settings → NOOP → Language on iOS, System
/// Settings → General → Language & Region → Applications on macOS); NOOP only reads what the bundles
/// resolved at launch, so `Text`, `String(localized:)`, notifications and `StrandDesign.module` strings can
/// never disagree about it.
enum AppLanguage {
    /// Locale used by SwiftUI format styles for the language that the currently-running bundles chose.
    static var activeLocale: Locale {
        let bundleLanguage = Bundle.main.preferredLocalizations.first ?? "en"
        let language = bundleLanguage.split(separator: "-").first.map(String.init) ?? bundleLanguage
        // Preserve the device's regional conventions (24-hour clock, date order, decimal separator) while
        // taking month/weekday words from the app language: English on a German device becomes `en_DE`.
        if let region = Locale.autoupdatingCurrent.region?.identifier {
            return Locale(identifier: "\(language)_\(region)")
        }
        return Locale(identifier: language)
    }

    /// The running language by its own name ("Русский", "English", "中文（简体）"), the value Settings shows
    /// beside its Language row.
    static var displayName: String {
        let id = Bundle.main.preferredLocalizations.first ?? "en"
        let own = Locale(identifier: id)
        return (own.localizedString(forIdentifier: id) ?? id).capitalized(with: own)
    }

    /// The key the retired in-app language picker wrote. The `AppleLanguages` override it set is the same
    /// one the system's per-app Language setting reads and edits, so that override is left in place.
    static let retiredStorageKey = "noop.appLanguage"
}
