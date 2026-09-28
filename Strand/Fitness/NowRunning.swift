//  NowRunning.swift
//  NOOP · whatever is running while its screen is put away — a workout, a gym session or the interval
//  timer — resolved ONCE, and drawn as the iOS 26 Music mini-player: the tab bar's bottom accessory.

#if os(iOS)
import SwiftUI
import Combine
import StrandDesign

/// What is running right now, for the one accessory every tab shows. Each recorder keeps its own state; this
/// only answers "which one, if any" so the shell re-renders when that answer changes, never on a tick.
///
/// Priority when two run at once: the gym session (its sets need a tap), then the interval timer (it runs on
/// its own clock), then a workout (it records whatever else happens).
@MainActor
final class NowRunning: ObservableObject {
    enum Kind: String, Identifiable {
        case lift, intervals, workout
        var id: String { rawValue }
    }

    @Published private(set) var kind: Kind?
    /// The running workout as the accessory needs it — sport, start and pause — deduplicated, so the live
    /// heart-rate churn on `AppModel.activeWorkout` does not reach the accessory.
    @Published private(set) var workout: ActiveWorkoutIndicatorModel?
    /// The recording screen opened from the accessory (a workout or the intervals). The gym session keeps its
    /// own flag (`LiftSessionController.isPresented`), which its sheet has always been presented from.
    @Published var expanded: Kind?

    private let lift: LiftSessionController

    init(model: AppModel, lift: LiftSessionController, intervals: IntervalTimerRunner) {
        self.lift = lift
        model.$activeWorkout
            .map(ActiveWorkoutIndicatorModel.make(from:))
            .removeDuplicates()
            .assign(to: &$workout)
        let liftRunning = lift.$engine.map { $0.map { !$0.isFinished } ?? false }
        let intervalsRunning = Publishers.CombineLatest3(intervals.$phase, intervals.$running, intervals.$elapsed)
            .map { phase, running, elapsed in phase != .done && (running || elapsed > 0) }
        Publishers.CombineLatest3(liftRunning, intervalsRunning, $workout.map { $0 != nil })
            .map { lift, intervals, workout -> Kind? in
                lift ? .lift : intervals ? .intervals : workout ? .workout : nil
            }
            .removeDuplicates()
            .assign(to: &$kind)
    }

    /// Opens the recording screen for `kind`.
    func expand(_ kind: Kind) {
        if kind == .lift { lift.isPresented = true } else { expanded = kind }
    }
}

// MARK: - Accessory

/// The mini-player: the activity's glyph, its name over the running clock, and ONE control — pause for a
/// workout or the intervals, "set done" for a gym session. Tapping anywhere else opens the recording screen.
struct NowRunningAccessory: View {
    @EnvironmentObject private var now: NowRunning

    var body: some View {
        switch now.kind {
        case .lift: LiftAccessoryRow()
        case .intervals: IntervalsAccessoryRow()
        case .workout: WorkoutAccessoryRow()
        case nil: EmptyView()
        }
    }
}

/// A manual workout: the sport, its active time, pause / resume.
private struct WorkoutAccessoryRow: View {
    @EnvironmentObject private var now: NowRunning
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let w = now.workout {
            RunningAccessoryRow(
                glyph: sportSymbol(w.sport),
                title: WorkoutSource.localizedSport(w.sport),
                status: w.isPaused ? String(localized: "Paused") : nil,
                control: w.isPaused ? "play.fill" : "pause.fill",
                controlLabel: w.isPaused ? "Resume" : "Pause",
                action: { model.toggleWorkoutPause() },
                open: { now.expand(.workout) }
            ) {
                RunningClock { unix in
                    Int(ActiveWorkoutClock.activeElapsed(
                        start: w.startedAt, pausedAt: w.pausedAt, pausedDuration: w.pausedDuration,
                        now: Date(timeIntervalSince1970: TimeInterval(unix))))
                }
                .foregroundStyle(w.isPaused ? StrandPalette.textSecondary : StrandPalette.activityExerciseText)
            }
        }
    }
}

/// The gym session: the exercise, the set's clock (the rest counting down, in the rest's yellow), "set done".
private struct LiftAccessoryRow: View {
    @EnvironmentObject private var now: NowRunning
    @EnvironmentObject private var session: LiftSessionController
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    var body: some View {
        // `LiftSessionController.presentation`, the resolution the Lock Screen renders, so the two cannot
        // word the session differently.
        if let engine = session.engine,
           let shown = session.presentation(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric) {
            RunningAccessoryRow(
                glyph: "dumbbell.fill",
                title: shown.exercise,
                status: shown.status,
                control: "checkmark",
                controlLabel: "Next",
                action: { session.advance() },
                open: { now.expand(.lift) }
            ) {
                RunningClock { unix in engine.restRemaining(now: unix) ?? unix - engine.stageStartedAt }
                    .foregroundStyle(shown.isResting ? StrandPalette.fitnessTime : StrandPalette.activityExerciseText)
            }
        }
    }
}

/// The interval timer: the phase's countdown in the phase's hue, the round, pause / resume.
private struct IntervalsAccessoryRow: View {
    @EnvironmentObject private var now: NowRunning
    @EnvironmentObject private var runner: IntervalTimerRunner

    var body: some View {
        RunningAccessoryRow(
            glyph: "timer",
            title: String(localized: "Intervals"),
            status: "\(runner.phase.label) · \(min(runner.currentRound, runner.rounds))/\(runner.rounds)",
            control: runner.running ? "pause.fill" : "play.fill",
            controlLabel: runner.running ? "Pause" : "Resume",
            action: { runner.toggleRunning() },
            open: { now.expand(.intervals) }
        ) {
            Text(IntervalTimerRunner.clock(runner.remaining))
                .monospacedDigit()
                .foregroundStyle(runner.running ? runner.phaseColor : StrandPalette.textSecondary)
        }
    }
}

/// One row of the mini-player, laid out as Music's: the artwork slot (here the activity's glyph on Fitness's
/// green disc), the title over a second line, then a bare glyph button.
private struct RunningAccessoryRow<Clock: View>: View {
    let glyph: String
    let title: String
    let status: String?
    let control: String
    let controlLabel: LocalizedStringKey
    let action: () -> Void
    let open: () -> Void
    @ViewBuilder let clock: () -> Clock

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.activityExerciseText)
                .frame(width: 32, height: 32)
                .background(Circle().fill(StrandPalette.fitnessCard))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(StrandFont.pro(15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                HStack(spacing: 0) {
                    clock()
                    if let status {
                        Text(verbatim: " · \(status)")
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .font(StrandFont.pro(15))
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: action) {
                Image(systemName: control)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(controlLabel))
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(controlLabel), action)
    }
}

// MARK: - Shell

extension View {
    /// Hangs the mini-player under every tab while something runs: the native bottom accessory on iOS 26.1+
    /// (Liquid Glass, and it folds into the minimised tab bar), a glass capsule above the bar before that.
    @ViewBuilder
    func nowRunningAccessory(isActive: Bool) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: isActive) { NowRunningAccessory() }
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                if isActive {
                    NowRunningAccessory()
                        .padding(.vertical, 6)
                        .modifier(RunningCapsule())
                        .padding(.horizontal, 20)
                        .padding(.bottom, NoopMetrics.tabBarClearance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: isActive)
        }
    }
}

/// The capsule under the mini-player before iOS 26.1: Liquid Glass on 26.0, the bar's material before it.
private struct RunningCapsule: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.bar, in: Capsule())
        }
        #else
        content.background(.bar, in: Capsule())
        #endif
    }
}
#endif
