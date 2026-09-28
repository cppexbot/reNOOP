import Foundation
import UserNotifications

/// Foreground presentation delegate for the app's local notifications (wind-down nudge, smart-alarm
/// backup, battery/illness alerts).
///
/// Without a `UNUserNotificationCenterDelegate`, iOS/macOS suppress a notification's banner while the
/// app is in the FOREGROUND (the default). A user testing a reminder with the app open would see
/// nothing and conclude notifications are broken. Returning banner + sound + list here makes them
/// visible whether the app is open or not — matching what the user expects from a reminder.
///
/// Cross-platform (iOS + macOS). Register once at launch:
/// `UNUserNotificationCenter.current().delegate = NotificationPresenter.shared`.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    /// The category every notification carrying the wearer's health readings posts under (the illness heads-up).
    /// Registered with a hidden-previews placeholder, so a locked phone shows "Health notice" rather than the
    /// readings (HIG: keep sensitive, personal information out of a notification's visible preview).
    static let healthCategoryId = "health"

    /// Built when the app root assigns `shared` as the delegate at launch, which is also the one moment the
    /// categories need registering: before anything is posted, once per process.
    private override init() {
        super.init()
        Self.registerCategories()
    }

    /// `setNotificationCategories` REPLACES the whole set, so every category NOOP registers is declared here, in
    /// one place. The morning brief's category needs no registration to route a tap and is not listed.
    private static func registerCategories() {
        let health = UNNotificationCategory(
            identifier: healthCategoryId, actions: [], intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: "Health notice"), options: [])
        UNUserNotificationCenter.current().setNotificationCategories([health])
    }

    /// K5: wired by the app root (`StrandApp` on macOS, `StrandiOSApp` on iOS) at launch to route a
    /// tapped scheduled morning-brief notification to the Coach screen via `NavRouter.openCoach()`. nil
    /// is a safe no-op (the tap is simply not routed) rather than a crash if this ever fires before the
    /// root has wired it.
    var onCoachBriefTapped: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Handle a tap on a delivered notification. Only the scheduled morning-brief category (K5) routes
    /// anywhere; every other notification (wind-down, smart-alarm, battery/illness) just opens the app
    /// to wherever it was, matching the pre-K5 behaviour.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.categoryIdentifier == CoachBriefScheduler.notificationCategoryId {
            onCoachBriefTapped?()
        }
        completionHandler()
    }
}
