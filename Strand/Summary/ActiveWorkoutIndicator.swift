//  ActiveWorkoutIndicator.swift
//  NOOP · Summary home — the "workout in progress" card pinned above the day.

import SwiftUI
import StrandDesign

// MARK: - Active-workout-in-progress indicator
//
// A "workout in progress" card the Summary home shows whenever a manual workout is active. Tapping it
// routes to the Live surface and opens the in-exercise screen (via NavRouter.openActiveWorkout()). Detection
// reads the single source of truth, `AppModel.activeWorkout`, which already survives an app kill (it's
// rehydrated from the durable snapshot on launch), so the card auto-appears and auto-clears with no new
// lifecycle wiring.

/// The indicator's value-typed view model: just the sport label + the workout's start, derived from
/// `AppModel.ActiveWorkout`. Equatable so the leaf below only re-renders when one of these actually changes,
/// and the elapsed clock is formatted from a pure function the tests pin.
struct ActiveWorkoutIndicatorModel: Equatable {
    let sport: String
    let startedAt: Date
    /// The pause state has to be CARRIED, not just consulted: this value type is what the card renders
    /// from, so without these two fields the indicator cannot subtract the paused time or say it is
    /// paused, however correct `AppModel` is. That is precisely how it kept counting through #1533.
    var pausedAt: Date? = nil
    var pausedDuration: TimeInterval = 0

    var isPaused: Bool { pausedAt != nil }

    static func make(from workout: AppModel.ActiveWorkout?) -> ActiveWorkoutIndicatorModel? {
        guard let workout else { return nil }
        return ActiveWorkoutIndicatorModel(sport: workout.sport, startedAt: workout.start,
                                           pausedAt: workout.pausedAt,
                                           pausedDuration: workout.pausedDuration)
    }

    /// Elapsed ACTIVE time, formatted M:SS up to an hour and H:MM:SS once an hour has passed (so a
    /// 90-minute session reads "1:30:00", not "90:00"). Clamped at zero so a clock-skew negative reads 0:00.
    /// Pure + injectable `now` for deterministic tests. (StrandFont.bodyNumber already applies tabular figures,
    /// so the call site does NOT add `.monospacedDigit()`.)
    ///
    /// `pausedAt`/`pausedDuration` default to "never paused" so the existing call sites and tests that
    /// predate pause keep their exact meaning; the math itself lives in `ActiveWorkoutClock`.
    static func elapsed(since start: Date, pausedAt: Date? = nil, pausedDuration: TimeInterval = 0,
                        now: Date = Date()) -> String {
        ActiveWorkoutClock.clock(Int(ActiveWorkoutClock.activeElapsed(
            start: start, pausedAt: pausedAt, pausedDuration: pausedDuration, now: now)))
    }
}

/// The running workout as a Summary card in Fitness's green: the sport's glyph and name in the title row
/// ("Paused" beside it while paused), then the elapsed clock large. The whole card opens the workout.
private struct ActiveWorkoutIndicatorCard: View {
    let model: ActiveWorkoutIndicatorModel
    let onReturn: () -> Void

    var body: some View {
        Button(action: onReturn) {
            SummaryCard {
                VStack(alignment: .leading, spacing: 8) {
                    // A frozen clock alone is ambiguous with a STALLED one, so say which it is. Reuses the
                    // "Paused" string #1533 already localized rather than minting new copy for a tag.
                    SummaryCardTitleRow(icon: sportSymbol(model.sport),
                                        title: WorkoutSource.localizedSport(model.sport),
                                        tint: StrandPalette.activityExerciseText,
                                        trailing: model.isPaused ? String(localized: "Paused") : nil)
                    // A per-second live clock. The TimelineView re-evaluates ONLY this Text every second, so
                    // the tick never re-renders the rest of the card (let alone the Summary body).
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(verbatim: ActiveWorkoutIndicatorModel.elapsed(
                            since: model.startedAt, pausedAt: model.pausedAt,
                            pausedDuration: model.pausedDuration, now: context.date))
                            .font(StrandFont.number(34, weight: .bold))
                            .foregroundStyle(model.isPaused ? StrandPalette.textSecondary : StrandPalette.fitnessTime)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        // One VoiceOver element: sport + state + clock, activated to return to the workout.
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Return to workout"))
    }
}

/// Leaf-isolated so an in-progress workout's ~per-sample `AppModel` churn (the elapsed clock tick + the
/// rewritten `activeWorkout`) re-renders ONLY this card, never the whole Summary. Renders nothing when no
/// workout is active, so the card auto-appears/clears purely off `AppModel.activeWorkout`. It carries its
/// own `app`/`router` environment objects, so a caller only needs to place `ActiveWorkoutIndicatorSection()`
/// in its body. Twin of Android's `WorkoutInProgressCard`.
struct ActiveWorkoutIndicatorSection: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var router: NavRouter

    var body: some View {
        if let model = ActiveWorkoutIndicatorModel.make(from: app.activeWorkout) {
            ActiveWorkoutIndicatorCard(model: model) {
                router.openActiveWorkout()
            }
            .transition(.opacity)
        }
    }
}
