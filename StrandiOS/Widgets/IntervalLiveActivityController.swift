#if os(iOS)
import Foundation
import ActivityKit
import Combine
import UIKit

/// Keeps the interval timer's Lock Screen banner (`IntervalActivityAttributes`) in step with the app's one
/// `IntervalTimerRunner`: started with the timer, pushed when the phase, round or pause changes — never per
/// second, the banner's countdown ticks on its own — and ended once the timer is finished or reset.
@MainActor
final class IntervalLiveActivityController {
    private var activity: Activity<IntervalActivityAttributes>?
    private var lastState: IntervalActivityAttributes.ContentState?
    private var isStarting = false
    private var bag = Set<AnyCancellable>()

    var isShowing: Bool { activity != nil }

    func follow(_ runner: IntervalTimerRunner) {
        // The phase, round and pause are what the banner shows; `remaining` only matters at those moments.
        Publishers.CombineLatest3(runner.$phase, runner.$currentRound, runner.$running)
            .combineLatest(runner.$elapsed.map { $0 > 0 }.removeDuplicates())
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self, weak runner] _ in
                guard let self, let runner else { return }
                self.update(runner)
            }
            .store(in: &bag)
    }

    private func update(_ runner: IntervalTimerRunner) {
        guard runner.inProgress, UnitPrefs.liveActivityEnabled(),
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            if activity != nil || !Activity<IntervalActivityAttributes>.activities.isEmpty { Task { await end() } }
            return
        }
        let now = Date()
        let ends = now.addingTimeInterval(TimeInterval(runner.remaining))
        let round = min(runner.currentRound, runner.rounds)
        let state = IntervalActivityAttributes.ContentState(
            isWork: runner.phase == .work,
            label: "\(runner.phase.label) · \(round)/\(runner.rounds)",
            phaseStartedAt: ends.addingTimeInterval(-TimeInterval(runner.phaseDuration)),
            phaseEndsAt: ends,
            pausedRemaining: runner.running ? nil : runner.remaining)
        guard state != lastState else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: nil)

        if activity == nil {
            activity = Activity<IntervalActivityAttributes>.activities.first {
                $0.activityState == .active || $0.activityState == .stale
            }
        }
        if let activity {
            Task { await activity.update(content) }
            return
        }
        // iOS starts a banner only for the app on screen; the timer is always started from it.
        guard UIApplication.shared.applicationState == .active, !isStarting else { return }
        isStarting = true
        activity = try? Activity.request(
            attributes: IntervalActivityAttributes(title: String(localized: "Intervals")),
            content: content, pushType: nil)
        isStarting = false
    }

    private func end() async {
        for act in Activity<IntervalActivityAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        lastState = nil
    }
}
#endif
