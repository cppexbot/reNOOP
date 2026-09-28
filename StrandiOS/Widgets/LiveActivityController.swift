#if os(iOS)
import Foundation
import ActivityKit
import Combine
import UIKit

/// Starts, updates, and ends the heart-rate Live Activity on the Lock Screen and in the Dynamic Island for a recorded
/// workout (`LiveHRBannerLifecycle`): started with the workout, the heart rate while the strap measures it, the dash
/// while it does not, ended with the workout. It follows the strap and the workout from process start (`follow`).
@MainActor
final class LiveActivityController {
    private var activity: Activity<NOOPActivityAttributes>?
    /// What the banner reads — the live heart rate, the link, the day's recovery and effort — set once by `follow`.
    private weak var model: AppModel?
    /// Whether the Lift Log or interval banner is on screen, which the heart rate banner makes room for.
    private var standsAside: () -> Bool = { false }
    private var cancellables: Set<AnyCancellable> = []
    private var lastPush: Date = .distantPast
    /// What the banner was last pushed with, so an unchanged banner is not pushed again
    /// (`LiveHRBannerPushPolicy`). Nil until this controller pushes, and again once it ends the activity.
    private var shownState: NOOPActivityAttributes.ContentState?
    /// Cached `ActivityAuthorizationInfo` — `update` runs at ~1 Hz off the live HR stream, and
    /// instantiating this system bridge per tick is needless allocation. ActivityKit's auth status
    /// only changes via Settings, so caching for the controller's lifetime is safe.
    private let authInfo = ActivityAuthorizationInfo()
    /// Synchronous gate against concurrent `Activity.request` calls. The `else` branch below is
    /// re-entered while the first request is still in flight (it hasn't assigned `self.activity`
    /// yet), so without this guard two close-together HR samples could both fire `Activity.request`
    /// and create duplicate Live Activities.
    private var isStarting = false
    /// This run started or fed the banner for a workout, so its end is the workout ending and it may linger with
    /// the last reading. A banner picked up from an earlier run and never fed is removed at once instead.
    private var servedWorkout = false
    /// An end is in flight, so the ticks that arrive meanwhile neither end it again nor log it twice.
    private var isEnding = false
    /// iOS refused a start, and it was logged: once, not on every tick while NOOP is on screen.
    private var refusalLogged = false
    /// How long after the last push iOS treats the banner as fresh; after that the banner draws the dash
    /// (`NOOPLiveActivity.shownBpm`). The safety net for a NOOP that can no longer say so itself: a strap going quiet
    /// or dropping its link is pushed as the dash at once (`LiveHRBannerPushPolicy`). Nothing is re-pushed just to
    /// stay fresh (HIG: update a Live Activity only when new content is available), so this is the widget's own
    /// cap (`HrDisplay.staleCap`): the age past which neither surface claims a reading stands for the wearer.
    static let staleAfter: TimeInterval = HrDisplay.staleCap

    /// Follow the strap and the workout from process start, not from a screen. iOS starts NOOP in the background — the
    /// strap reconnecting, a sync, the Sync Strap shortcut — and a process started that way need not build any screen
    /// (the shortcut's never does), while a banner the previous run left on the Lock Screen for a workout still being
    /// recorded is there to be picked up and fed from the first reading. Called once, from the app's `init`, like the
    /// Lift Log's own resume.
    func follow(_ model: AppModel, standsAside: @escaping () -> Bool) {
        self.model = model
        self.standsAside = standsAside
        // A `@Published` sink runs in willSet: each hands on the value being written and reads the other from `live`.
        // AppModel's own sinks, subscribed before these, have already folded the value into its median (`bpm`).
        model.live.$heartRate
            .sink { [weak self, weak model] hr in
                guard let model else { return }
                self?.refreshBanner(heartRate: hr, connected: model.live.connected)
            }
            .store(in: &cancellables)
        model.live.$connected
            .sink { [weak self, weak model] isConnected in
                guard let model else { return }
                self?.refreshBanner(heartRate: model.live.heartRate, connected: isConnected)
            }
            .store(in: &cancellables)
        // The workout starting and ending is what starts and ends the banner; a pause changes nothing it shows.
        model.$activeWorkout
            .map { $0 != nil }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] active in self?.refreshBanner(workoutActive: active) }
            .store(in: &cancellables)
        // The switch acts at once, not at the next heart-rate tick, which a strap off the wrist may not send for hours.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .map { _ in UnitPrefs.liveActivityEnabled() }
            .prepend(UnitPrefs.liveActivityEnabled())
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.refreshBanner() }
            .store(in: &cancellables)
    }

    /// NOOP came on screen, the only time iOS lets it start the banner: offered now rather than at the next heart-rate
    /// change, which a strap off the wrist may not bring for a long while. Said by the caller, from the scene phase,
    /// because `applicationState` can still read inactive while the scene turns active.
    func appBecameActive() {
        refreshBanner(appActive: true)
    }

    private func refreshBanner(appActive: Bool? = nil, workoutActive: Bool? = nil) {
        guard let model else { return }
        refreshBanner(heartRate: model.live.heartRate, connected: model.live.connected, appActive: appActive,
                      workoutActive: workoutActive)
    }

    /// #911: recovery and effort come from the SAME shared `Repository.widgetAnchor` the widget and the watch use, so
    /// the banner cannot name a different day at the rollover; memoized, because this runs on every heart-rate tick
    /// (re-deriving it once scanned the whole history, #1051). `workoutActive` is handed in by the workout's own sink,
    /// which runs in willSet, before `activeWorkout` holds the value being written.
    private func refreshBanner(heartRate: Int?, connected: Bool, appActive: Bool? = nil,
                               workoutActive: Bool? = nil) {
        guard let model else { return }
        let day = model.repo.cachedWidgetAnchor()
        update(bpm: connected ? (model.bpm ?? heartRate) : nil, recovery: day?.recovery.map { Int($0.rounded()) },
               connected: connected, workoutActive: workoutActive ?? (model.activeWorkout != nil),
               standsAside: standsAside(),
               appActive: appActive ?? (UIApplication.shared.applicationState == .active),
               effort: day?.strain.map { Int($0.rounded()) })
    }

    /// Drive the activity from the latest live values (`LiveHRBannerLifecycle` decides start / push / end). Starts
    /// with a workout, in the foreground (`appActive`) where a workout is started, before a heart rate arrives if need
    /// be; a running banner shows the dash through a dropped link or a strap that is not measuring, and ends when the
    /// workout does, when its switch is off, or when the session's own banner takes the screen (`standsAside`). Pushed
    /// only when what it shows changes (`LiveHRBannerPushPolicy`), never just to stay fresh.
    private func update(bpm: Int?, recovery: Int?, connected: Bool, workoutActive: Bool, standsAside: Bool,
                        appActive: Bool, effort: Int?) {
        guard authInfo.areActivitiesEnabled else { return }

        // A banner iOS ended (after about eight hours) or the user swiped away is gone: forget it, so the next time
        // NOOP is on screen during the workout it starts one again rather than pushing to nothing. (One NOOP is ending is not gone yet.)
        if !isEnding, let activity, !Self.isShowing(activity) {
            self.activity = nil
            shownState = nil
            log("gone from the Lock Screen (ended by iOS or dismissed); started again when NOOP is next on screen "
                + "during a workout")
        }
        // Re-adopt an activity that outlived a previous app session. ActivityKit keeps Live Activities
        // alive across launches/relaunches, but a fresh controller starts with `activity == nil`, so
        // without recovering the handle here we can neither update nor END an already-showing activity
        // — which made the #336 opt-out a no-op (#341: toggle off, heart stays) and risked spawning a
        // duplicate on the start path below. Done on the HR tick rather than in `init` because
        // `Activity.activities` isn't reliably hydrated at the instant of process launch.
        if activity == nil, let adopted = Activity<NOOPActivityAttributes>.activities.first(where: Self.isShowing) {
            activity = adopted
            log("picked up the one already on the Lock Screen")
        }

        // The workout ending, the switch (#336) and the session's own banner end it; nothing that passes does
        // (`LiveHRBannerLifecycle`).
        let now = Date()
        let switchOn = UnitPrefs.liveActivityEnabled()
        let step = LiveHRBannerLifecycle.step(
            switchOn: switchOn, workoutActive: workoutActive, standsAside: standsAside,
            showing: activity != nil, appActive: appActive)
        switch step {
        case .nothing: return
        case .end:
            guard !isEnding else { return }
            isEnding = true
            // Only the workout ending leaves the last reading up for a while, as a finished workout's banner does.
            // The switch turned off, or the session's own banner arriving, removes it at once.
            let lingers = switchOn && !standsAside && servedWorkout
            log(!switchOn ? "ended: its switch is off"
                : standsAside ? "ended: the session's own banner takes its place"
                : "ended: the workout ended")
            Task { await end(lingering: lingers) }
            return
        case .start, .push: servedWorkout = true
        }

        // Link down: the dash, never the last number (`bonded` stays true across a disconnect, and keying off it once
        // left a fabricated "live" HR standing). No timed end: a timer in a suspended app fires at its next wake,
        // which is typically the strap coming back — exactly when the banner should stay.
        let state = NOOPActivityAttributes.ContentState(bpm: connected ? bpm : nil, recovery: recovery,
                                                        bonded: connected, effort: effort)

        if let activity {
            // The number giving way to the dash (the strap off the wrist, the link dropping) is pushed at once: no
            // tick follows it, so a push skipped for spacing would leave the last number standing. An unchanged
            // banner is never re-pushed: no finite stale date is handed to the policy, so it asks only for change.
            guard LiveHRBannerPushPolicy.due(shown: shownState, next: state, reading: \.bpm,
                                             sinceLastPush: now.timeIntervalSince(lastPush),
                                             staleAfter: .infinity) else { return }
            if let shown = shownState, (shown.bpm == nil) != (state.bpm == nil) { logReading(state) }
            lastPush = now
            shownState = state
            let staleDate = now.addingTimeInterval(Self.staleAfter)
            Task { await activity.update(ActivityContent(state: state, staleDate: staleDate)) }
        } else if start(state, at: now) {
            log(state.bpm == nil ? "started, showing – until a heart rate arrives" : "started")
        }
    }

    /// Ask iOS for a new banner, which it grants only while NOOP is on screen. Returns whether it did.
    @discardableResult
    private func start(_ state: NOOPActivityAttributes.ContentState, at now: Date) -> Bool {
        // Set the start gate SYNCHRONOUSLY before any await so a second `update` arriving on the
        // main actor while `Activity.request` is still in flight bails here instead of issuing a
        // second request. The 2-second throttle above only guards the update path.
        guard !isStarting else { return false }
        isStarting = true
        defer { isStarting = false }
        do {
            let started = try Activity.request(
                attributes: NOOPActivityAttributes(title: String(localized: "Live HR")),
                content: ActivityContent(state: state, staleDate: now.addingTimeInterval(Self.staleAfter)),
                pushType: nil
            )
            activity = started
            lastPush = now
            shownState = state
            refusalLogged = false
            return true
        } catch {
            if !refusalLogged {
                refusalLogged = true
                log("iOS did not start it: \(error.localizedDescription)")
            }
            return false
        }
    }

    /// The banner turning to the dash, or back to a number: pushed at once (`LiveHRBannerPushPolicy`), and logged.
    private func logReading(_ state: NOOPActivityAttributes.ContentState) {
        if state.bpm != nil {
            log("heart rate again")
        } else {
            log(state.bonded ? "– (strap connected, no heart rate)" : "– (strap not connected)")
        }
    }

    /// One line in NOOP's strap log for each thing that happens to the banner: started, picked up, ended,
    /// gone, and each turn to the dash and back. Rare, so always on. A tester's banner once showed the dash for a
    /// strap he was wearing, and a log without a word about the banner could not say why (24 Sep 2026).
    private func log(_ line: String) {
        model?.live.append(log: AppModel.stamped("Live HR banner: " + line))
    }

    /// Still on the Lock Screen and able to take an update: not ended by iOS, the user or NOOP.
    private static func isShowing(_ activity: Activity<NOOPActivityAttributes>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }

    /// `lingering`: the workout ended, so the banner stays on the Lock Screen with its last reading for
    /// `LiveHRBannerLifecycle.lingerAfterWorkout`; otherwise it goes at once.
    private func end(lingering: Bool) async {
        // The final content carries no stale date, so the last reading is not turned into the dash while it lingers.
        let lastContent = shownState.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = lingering
            ? .after(Date().addingTimeInterval(LiveHRBannerLifecycle.lingerAfterWorkout))
            : .immediate
        // End every NOOP Live Activity, not just our cached handle — covers a straggler from a prior
        // session we never re-adopted (#341) and any rare duplicate. Iterating the live list is the
        // only way to reach activities this controller instance never started.
        for act in Activity<NOOPActivityAttributes>.activities {
            await act.end(act.id == activity?.id ? lastContent : nil, dismissalPolicy: policy)
        }
        self.activity = nil
        shownState = nil
        servedWorkout = false
        isEnding = false
    }
}
#endif
