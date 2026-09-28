import Foundation
import UserNotifications
import StrandAnalytics

/// Surfaces the strap battery state as a user notification — a LOW warning when the cell falls to
/// the threshold so the user can top up before tonight's sleep, and a CHARGED note when it reaches
/// 100%. Mirrors `IllnessNotifier`: requestAuthorization() up front when the toggle is enabled,
/// status-only check at fire time, and the persisted gate advances even when delivery is deferred.
/// On-device only; gated behind the user's "Battery alerts" setting (default ON) by the caller (#368).
enum BatteryNotifier {
    private static let lowAlertedKey = "behavior.batteryLowAlerted"
    private static let fullAlertedKey = "behavior.batteryFullAlerted"
    private static let runtimeAlertedKey = "behavior.batteryRuntimeAlerted"
    /// Gates for the two ESCALATION alerts. Separate keys on purpose — see `onCriticalBattery` /
    /// `onBedtimeRunway`: a latched `lowAlertedKey`/`runtimeAlertedKey` must never silence them.
    private static let criticalAlertedKey = "behavior.batteryCriticalAlerted"
    private static let bedtimeAlertedKey = "behavior.batteryBedtimeAlerted"

    /// NT-2: every battery alert is one notification about one thing, the strap's battery, so they share
    /// ONE request id: a newer alert replaces the older on the Lock Screen instead of stacking a second,
    /// third and fourth about the same discharge. The thread groups it with any copy an older build left.
    static let notificationId = "battery"
    private static let threadId = "battery"
    /// Which alert the standing notification is, so clearing the stale "charged" note never pulls a
    /// low-battery warning that replaced it.
    private static let kindKey = "batteryKind"
    private enum Kind: String { case low, full, runtime, critical, bedtime }
    /// The per-alert ids older builds posted under; cleared with the full note so none outlives the change.
    private static let legacyIds = ["battery-low", "battery-full", "battery-runtime", "battery-critical", "battery-bedtime"]

    /// Pure crossing-with-hysteresis policy, identical on macOS/iOS and Android (#368). The two
    /// `*Alerted` flags are PERSISTED, so they survive process death — and the 25% re-arm band means
    /// a 14↔15% jitter fires the low alert exactly once per discharge cycle (no in-memory prevPct
    /// crossing that re-fires on every bounce and resets on restart). Full re-arms only below 100.
    enum BatteryAlertPolicy {
        static let lowThreshold = 15
        static let lowRearmAbove = 25
        static let fullThreshold = 100

        /// `charging == nil` means unknown — the low alert still fires (only a confirmed `true`
        /// suppresses it). Returns the fire decisions plus the next persisted flag state.
        ///
        /// `clearFull` (#514): the strap was showing a "fully charged" notification and has now
        /// dropped below 100% — the standing note is stale, so cancel it. It's exactly the full
        /// re-arm transition (previouslyFullAlerted && pct < fullThreshold), surfaced so the
        /// notifier can pull the delivered + pending full-charge notification by its id.
        static func evaluate(pct: Int,
                             charging: Bool?,
                             lowAlerted: Bool,
                             fullAlerted: Bool)
            -> (fireLow: Bool, fireFull: Bool, clearFull: Bool, newLowAlerted: Bool, newFullAlerted: Bool) {
            var low = lowAlerted
            var full = fullAlerted
            // The stale 100%-full note must be cleared the moment we re-arm below the full line.
            let clearFull = fullAlerted && pct < fullThreshold
            // Re-arm (hysteresis) so jitter near a threshold can't re-fire. #80: re-arm ONLY on genuine
            // recovery (pct >= lowRearmAbove), NOT on charging. The strap reports its charge bit only every
            // ~8 min, so it flickers true→nil; re-arming on `true` then firing on the `nil` gap re-fired the
            // low alert repeatedly WHILE charging. `fireLow`'s `charging != true` still suppresses an explicit
            // charging reading, and a null-charging strap (generic/FTMS) still alerts.
            if pct >= lowRearmAbove { low = false }
            if pct < fullThreshold { full = false }
            // Fire at most once per genuine crossing.
            let fireLow = !low && pct <= lowThreshold && charging != true
            let fireFull = !full && pct >= fullThreshold
            if fireLow { low = true }
            if fireFull { full = true }
            return (fireLow, fireFull, clearFull, low, full)
        }
    }

    /// Ask up front (called when the user enables the alerts) so the system dialog appears at a
    /// predictable moment, not on the first low-battery crossing.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Run the policy against a fresh battery reading and post at most one notification per genuine
    /// crossing. No-op when the setting is off. The persisted flags are written back ALWAYS (so the
    /// gate advances even if the user declined notifications or delivery is deferred — mirroring how
    /// `IllnessNotifier` marks the day up front).
    static func onBatteryUpdate(pct: Int, charging: Bool?, enabled: Bool) {
        guard enabled else { return }
        let d = UserDefaults.standard
        let result = BatteryAlertPolicy.evaluate(
            pct: pct,
            charging: charging,
            lowAlerted: d.bool(forKey: lowAlertedKey),
            fullAlerted: d.bool(forKey: fullAlertedKey))
        // Advance the persisted gate up front so the once-per-crossing limit holds regardless of
        // authorization or delivery — the in-app battery surfaces stay the live view either way.
        d.set(result.newLowAlerted, forKey: lowAlertedKey)
        d.set(result.newFullAlerted, forKey: fullAlertedKey)
        if result.fireLow {
            post(.low,
                 title: String(localized: "Low Battery"),
                 body: String(localized: "Charge it before tonight."))
        }
        if result.fireFull {
            post(.full,
                 title: String(localized: "Strap Charged"),
                 body: String(localized: "Your WHOOP is at 100%."))
        }
        // #514: the strap has dropped below 100% — pull the stale "fully charged" note (delivered
        // banner + any still-pending request) so it can't linger after the cell discharges. Only when the
        // shared id still holds the full note: a low alert that replaced it stays.
        if result.clearFull { clearFullNote() }
    }

    private static func clearFullNote() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: legacyIds)
        center.removePendingNotificationRequests(withIdentifiers: legacyIds)
        center.getDeliveredNotifications { delivered in
            if delivered.contains(where: { $0.request.identifier == notificationId && isFull($0.request.content) }) {
                center.removeDeliveredNotifications(withIdentifiers: [notificationId])
            }
        }
        center.getPendingNotificationRequests { pending in
            if pending.contains(where: { $0.identifier == notificationId && isFull($0.content) }) {
                center.removePendingNotificationRequests(withIdentifiers: [notificationId])
            }
        }
    }

    private static func isFull(_ content: UNNotificationContent) -> Bool {
        content.userInfo[kindKey] as? String == Kind.full.rawValue
    }

    /// Predictive twin of `onBatteryUpdate`: run the runtime estimate against
    /// `BatteryEstimator.runtimeAlert` (fire ≤24 h, re-arm ≥36 h — see the policy for why a runtime
    /// threshold beats a fixed SoC one) and post at most one notification per discharge cycle. The
    /// 15% SoC alert stays as the safety net for straps with no usable estimate (`estimate == nil`
    /// is a no-op here). Same gating discipline as #368: the persisted flag advances even when
    /// delivery is deferred, and the whole thing no-ops when the "Battery alerts" setting is off.
    static func onRuntimeEstimate(remainingHours: Double?, charging: Bool?, enabled: Bool) {
        guard enabled, let remainingHours else { return }
        let d = UserDefaults.standard
        let result = BatteryEstimator.runtimeAlert(remainingHours: remainingHours,
                                                   charging: charging,
                                                   alerted: d.bool(forKey: runtimeAlertedKey))
        d.set(result.newAlerted, forKey: runtimeAlertedKey)
        if result.fire {
            post(.runtime,
                 title: String(localized: "Strap Battery Low"),
                 body: String(localized: "\(BatteryEstimator.label(hours: remainingHours)) left. Charge it tonight."))
        }
    }

    /// CRITICAL low-battery escalation — the second alert below the 15% one (#368 fires at
    /// `BatteryAlertPolicy.lowThreshold`, this at `BatteryEstimator.criticalSocPct`).
    ///
    /// Why a whole second alert rather than a lower first threshold: on the reference incident the
    /// user's device flags show BOTH the 15% alert and the 24 h predictive alert had already fired —
    /// and both then LATCHED (`lowAlerted` until 25%, `runtimeAlerted` until a 36 h estimate). So the
    /// last ~3 h of the discharge, from 15% down to the ~10% cutoff, passed in total silence and cost
    /// a night of biometrics. This gate is independent of both: `criticalAlertedKey` is its own key, so
    /// a latched low/runtime alert cannot suppress it. Same discipline as #368 otherwise — self-gates
    /// on the setting, advances the persisted flag even when delivery is deferred, once per cycle.
    static func onCriticalBattery(pct: Int, charging: Bool?, enabled: Bool) {
        guard enabled else { return }
        let d = UserDefaults.standard
        let result = BatteryEstimator.criticalAlert(pct: pct,
                                                    charging: charging,
                                                    alerted: d.bool(forKey: criticalAlertedKey))
        d.set(result.newAlerted, forKey: criticalAlertedKey)
        if result.fire {
            post(.critical,
                 title: String(localized: "Charge Your Strap Now"),
                 body: String(localized: "\(pct)% left. It stops recording near 10%."),
                 interruptionLevel: .active)
        }
    }

    /// BEDTIME night-guard — "this won't last the night", delivered while there is still time to act.
    ///
    /// Independent of `runtimeAlertedKey` by design: the generic "recharge tonight" alert may well have
    /// fired (and latched) many hours earlier — on the reference incident it fired ~18 h before the
    /// strap died. This asks a narrower, time-anchored question at the pre-bed moment, and re-arms
    /// every night rather than every charge, so it speaks even when everything else has gone quiet.
    /// `runway` is nil at cold-start (no learned bedtime) — the policy stays silent rather than
    /// inventing one.
    static func onBedtimeRunway(nowSecOfDay: Int,
                                habitualMidsleepSec: Int?,
                                typicalSleepHours: Double?,
                                usableRemainingHours: Double?,
                                charging: Bool?,
                                enabled: Bool) {
        guard enabled else { return }
        let d = UserDefaults.standard
        let result = BatteryEstimator.bedtimeAlert(nowSecOfDay: nowSecOfDay,
                                                   habitualMidsleepSec: habitualMidsleepSec,
                                                   typicalSleepHours: typicalSleepHours,
                                                   usableRemainingHours: usableRemainingHours,
                                                   charging: charging,
                                                   alerted: d.bool(forKey: bedtimeAlertedKey))
        d.set(result.newAlerted, forKey: bedtimeAlertedKey)
        if result.fire, let runway = result.runway {
            post(.bedtime,
                 title: String(localized: "Won't Last the Night"),
                 body: String(localized: "\(BatteryEstimator.label(hours: runway.usableHours)) left. Charge before bed."),
                 interruptionLevel: .active)
        }
    }

    private static func post(_ kind: Kind, title: String, body: String,
                             interruptionLevel: UNNotificationInterruptionLevel = .active) {
        let center = UNUserNotificationCenter.current()
        // Authorization is requested once via requestAuthorization() when alerts are enabled; here
        // we only check status (no second system prompt).
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            // A charge reminder is not time-critical: only the wake-up backup breaks through a Focus (AL-1).
            content.interruptionLevel = interruptionLevel
            content.threadIdentifier = threadId
            content.userInfo = [kindKey: kind.rawValue]
            center.add(UNNotificationRequest(identifier: notificationId,
                                             content: content, trigger: nil))
        }
    }
}
