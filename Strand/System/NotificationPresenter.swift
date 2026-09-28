import Foundation
import UserNotifications

/// Foreground presentation delegate for the app's local notifications (wind-down nudge, smart-alarm
/// backup, battery/illness alerts).
///
/// Without a `UNUserNotificationCenterDelegate`, iOS/macOS suppress a notification's banner while the
/// app is in the FOREGROUND (the default). A user testing a reminder with the app open would see
/// nothing and conclude notifications are broken. Returning banner + sound + list here makes them
/// visible whether the app is open or not — matching what the user expects from a reminder. The one
/// exception is news the open app already shows in its own banner, which goes to the list only.
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
    /// one place. The morning brief routes by its request id and needs no category here.
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

    /// Request ids whose news the open app already shows in its own banner (NT-2): in the foreground they
    /// go quietly to Notification Centre instead of dropping a second banner over the first.
    private static let inAppBannerIds: Set<String> = ["illness-watch"]

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if Self.inAppBannerIds.contains(notification.request.identifier) {
            completionHandler([.list])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }

    /// Handle a tap on a delivered notification, routed by its request id (NT-2). Only the morning brief
    /// (K5) routes anywhere; every other notification (wind-down, smart-alarm, battery/illness) just opens
    /// the app to wherever it was.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier.hasPrefix(CoachBriefScheduler.requestIdPrefix) {
            onCoachBriefTapped?()
        }
        completionHandler()
    }
}
