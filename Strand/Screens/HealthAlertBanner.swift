import SwiftUI
import StrandDesign
import StrandAnalytics
import Foundation

/// Strain/illness early-warning notice. Observes AppModel in isolation so the ~1 Hz HR stream re-renders
/// only this small view, not the whole screen. Renders nothing when there's no alert.
struct HealthAlertBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let alert = model.healthAlert {
            NoticeCard(title: Text(verbatim: HealthAlertCopy.title(alert)),
                       message: Text(verbatim: HealthAlertCopy.message(alert)),
                       systemImage: "exclamationmark.triangle.fill", tone: .warning)
        }
    }
}

/// The one wording of the semantic illness result, shared by the Summary notice and the system
/// notification so the two cannot say different things. Never the analytics engine's English copy.
enum HealthAlertCopy {
    static func title(_ alert: AppModel.HealthAlert) -> String {
        switch alert.message {
        case .raised:              return String(localized: "Signs of strain")
        case .alreadyUnwellAgree:  return String(localized: "Your signals agree you're unwell")
        case .alreadyUnwell:       return String(localized: "You logged feeling unwell")
        default:                   return String(localized: "Nothing notable")
        }
    }

    static func message(_ alert: AppModel.HealthAlert) -> String {
        guard alert.message == .raised else { return String(localized: "Take it easy today.") }
        let formatter = ListFormatter()
        formatter.locale = AppLanguage.activeLocale
        let signals = formatter.string(from: alert.firedSignals) ?? alert.firedSignals.joined(separator: ", ")
        return String(localized: "Up: \(signals). Take it easy today.")
    }
}
