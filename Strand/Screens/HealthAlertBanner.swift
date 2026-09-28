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
///
/// Worded as what the numbers did, not as a diagnosis: the signals are outside the wearer's range, which is
/// what NOOP measured; whether they are unwell is theirs to say. The notification is also kept off the Lock
/// Screen (`NotificationPresenter.healthCategoryId`), since these are health readings.
enum HealthAlertCopy {
    static func title(_ alert: AppModel.HealthAlert) -> String {
        switch alert.message {
        case .raised:              return String(localized: "Signs of strain")
        case .alreadyUnwellAgree:  return String(localized: "Signals Outside Your Range")
        case .alreadyUnwell:       return String(localized: "You logged feeling unwell")
        default:                   return String(localized: "Nothing notable")
        }
    }

    /// What moved, each with its own sign ("RHR +6, HRV −18%, Respiration up"). No "Up:" in front: HRV moves
    /// illness-ward by DROPPING, so a lead word naming one direction mislabelled it. A plain comma list rather
    /// than a ListFormatter "and", because each item is a reading, not a clause.
    static func message(_ alert: AppModel.HealthAlert) -> String {
        guard alert.message == .raised, !alert.firedSignals.isEmpty else {
            return String(localized: "Take it easy today.")
        }
        return alert.firedSignals.joined(separator: ", ")
    }
}
