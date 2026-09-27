import SwiftUI
import Foundation
import StrandDesign

/// Silent haptic HIIT interval timer.
///
/// Train hands-free: the strap buzzes every transition so you never have to look at the screen. Strong
/// triple-buzz at the start of each work block, a short single buzz into rest, a 3-2-1 tick on the last
/// seconds of every phase, and a long 5-loop buzz when the whole session finishes. With no strap bonded it
/// still works as a big glanceable visual timer, and the iPhone's own haptics mirror every cue.
///
/// The setup page is modelled on the Fitness app's custom workout: a start card, then the blocks. Starting
/// opens the same dark recording screen a workout uses (`IntervalRunView`).
struct IntervalTimerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @StateObject private var runner = IntervalTimerRunner()
    @State private var showRun = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                startCard
                blocks
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("Intervals"))
        .onAppear {
            // Strap buzz only when bonded, so the timer stays a pure visual tool otherwise.
            runner.buzz = { [weak model, weak live] loops in
                guard live?.bonded == true else { return }
                model?.buzz(loops: loops, gate: HapticPrefs.intervals)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showRun) { IntervalRunView(runner: runner) { showRun = false } }
        #else
        .sheet(isPresented: $showRun) { IntervalRunView(runner: runner) { showRun = false } }
        #endif
    }

    /// Fitness's start card: what will run, and the green play circle.
    private var startCard: some View {
        Button {
            if !runner.inProgress { runner.start() }
            showRun = true
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Image(systemName: "timer")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(StrandPalette.activityExerciseText)
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(StrandPalette.fitnessOnAccent)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(StrandPalette.activityExerciseText))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(runner.inProgress ? "Resume Intervals" : "Intervals")
                        .font(StrandFont.pro(22, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(verbatim: "\(runner.rounds) × \(IntervalTimerRunner.clock(runner.workSeconds)) / \(IntervalTimerRunner.clock(runner.restSeconds))")
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.activityExerciseText)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.fitnessCard, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The blocks, one card each, set with − / + like Fitness's goal screen.
    private var blocks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workout")
                .font(StrandFont.pro(22, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 4)
            block("Work", symbol: "chevron.up.2", tint: StrandPalette.activityStandText,
                  value: IntervalTimerRunner.clock(runner.workSeconds),
                  minus: { runner.workSeconds = max(5, runner.workSeconds - 5) },
                  plus: { runner.workSeconds = min(600, runner.workSeconds + 5) })
            block("Rest", symbol: "chevron.down.2", tint: StrandPalette.activityExerciseText,
                  value: IntervalTimerRunner.clock(runner.restSeconds),
                  minus: { runner.restSeconds = max(5, runner.restSeconds - 5) },
                  plus: { runner.restSeconds = min(600, runner.restSeconds + 5) })
            block("Rounds", symbol: "repeat", tint: StrandPalette.textPrimary,
                  value: "\(runner.rounds)",
                  minus: { runner.rounds = max(1, runner.rounds - 1) },
                  plus: { runner.rounds = min(30, runner.rounds + 1) })
            Text("Total \(IntervalTimerRunner.clock(runner.totalPlanned))")
                .font(StrandFont.pro(15))
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 4)
        }
        .disabled(runner.running)
        .opacity(runner.running ? 0.5 : 1)
    }

    private func block(_ title: LocalizedStringKey, symbol: String, tint: Color, value: String,
                       minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(value)
                    .font(StrandFont.pro(28, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            Spacer()
            stepButton("minus", tint: tint, action: minus)
            stepButton("plus", tint: tint, action: plus)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func stepButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tint.opacity(0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Running

/// The interval in progress, on the same dark recording screen a workout uses: the phase and round, the
/// phase countdown as a large figure in the phase's hue, the heart rate and the time left overall, then the
/// panel with the total clock and stop / pause / skip.
struct IntervalRunView: View {
    @ObservedObject var runner: IntervalTimerRunner
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Minimising leaves the timer running; the setup page offers to resume it.
            RecordingTopBar(onMinimize: onClose)
            VStack(alignment: .leading, spacing: 0) {
                RecordingHeading(caption: runner.isFinished
                                    ? String(localized: "\(runner.rounds) rounds")
                                    : String(localized: "Round \(min(runner.currentRound, runner.rounds)) of \(runner.rounds)"),
                                 tint: runner.phaseColor, title: runner.phase.label)
                    .padding(.top, 8)
                Spacer(minLength: 8)
                Text(IntervalTimerRunner.clock(runner.isFinished ? runner.elapsed : runner.remaining))
                    .font(.system(size: 120, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(runner.phaseColor)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(runner.phaseColor)
                            .frame(width: geo.size.width * (runner.isFinished ? 1 : runner.phaseProgress))
                            .animation(.linear(duration: 1), value: runner.phaseProgress)
                    }
                }
                .frame(height: 8)
                Spacer(minLength: 8)
                LiftHeartRateFigure()
                Spacer(minLength: 8)
                LiveFigure(value: IntervalTimerRunner.clock(max(0, runner.totalPlanned - runner.elapsed)),
                           label: String(localized: "TOTAL\nLEFT"))
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            RecordingPanel(
                glyph: AnyView(Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(StrandPalette.activityExerciseText)),
                clock: { RecordingClockText(text: IntervalTimerRunner.clock(runner.elapsed)) },
                trailing: { EmptyView() },
                leading: {
                    RecordingButton(symbol: "xmark", label: "End") {
                        runner.stopAndReset()
                        onClose()
                    }
                },
                center: {
                    if runner.isFinished {
                        RecordingButton(symbol: "arrow.counterclockwise", size: 112, prominent: true,
                                        label: "Restart") { runner.resetToStart(); runner.start() }
                    } else {
                        RecordingButton(symbol: runner.running ? "pause.fill" : "play.fill", size: 112,
                                        prominent: !runner.running,
                                        label: runner.running ? "Pause" : "Resume") { runner.toggleRunning() }
                    }
                },
                right: {
                    RecordingButton(symbol: "forward.end.fill", label: "Skip") { runner.skipPhase() }
                        .disabled(runner.isFinished)
                })
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // Keep the screen awake while a session runs (no-op on macOS); onDisappear is the safety net so
        // leaving mid-run never leaves the idle timer disabled app-wide.
        .onChangeCompat(of: runner.running) { ScreenIdle.keepAwake($0) }
        .onAppear { ScreenIdle.keepAwake(runner.running) }
        .onDisappear { ScreenIdle.keepAwake(false) }
        #if os(iOS)
        // iPhone haptics: a different feel per cue, re-firing on every token bump. Fires regardless of strap
        // bond so the timer is fully usable unstrapped.
        .sensoryFeedback(trigger: runner.hapticTick) { _, _ in
            switch runner.lastHaptic {
            case .work: return .impact(weight: .heavy)
            case .rest: return .impact(weight: .light)
            case .tick: return .selection
            case .done: return .success
            }
        }
        #endif
    }
}

// MARK: - Runner

/// The timer's state and rules, owned by the setup page so the running screen and the page share one clock.
@MainActor
final class IntervalTimerRunner: ObservableObject {
    enum Phase {
        case work, rest, done
        var label: String {
            switch self {
            case .work: return String(localized: "Work")
            case .rest: return String(localized: "Rest")
            case .done: return String(localized: "Done")
            }
        }
    }
    enum HapticCue { case work, rest, tick, done }

    @Published var workSeconds = 30 { didSet { if !running { resetToStart() } } }
    @Published var restSeconds = 15 { didSet { if !running { resetToStart() } } }
    @Published var rounds = 8 {
        didSet {
            if currentRound > rounds { currentRound = rounds }
            if !running { resetToStart() }
        }
    }

    @Published private(set) var phase: Phase = .work
    @Published private(set) var currentRound = 1
    /// Seconds left in the current phase.
    @Published private(set) var remaining = 30
    @Published private(set) var running = false
    /// Total elapsed seconds across the session.
    @Published private(set) var elapsed = 0
    @Published private(set) var lastHaptic: HapticCue = .work
    @Published private(set) var hapticTick = 0

    /// Strap buzz, set by the page (it knows whether a strap is bonded).
    var buzz: (UInt8) -> Void = { _ in }
    private var timer: Timer?

    init() {
        // Scheduled on `.common` rather than the default run loop mode: a plain `scheduledTimer` stalls
        // while the run loop is tracking a touch (holding a button, dragging), so the countdown would
        // freeze mid-press and then jump to catch up the moment the finger lifts.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    var isFinished: Bool { phase == .done }
    /// Started and not reset — the page offers to resume rather than start over.
    var inProgress: Bool { !isFinished && (running || elapsed > 0) }

    var phaseDuration: Int {
        switch phase {
        case .work: return max(1, workSeconds)
        case .rest: return max(1, restSeconds)
        case .done: return 1
        }
    }

    var phaseProgress: Double {
        min(1, max(0, Double(phaseDuration - remaining) / Double(phaseDuration)))
    }

    var totalPlanned: Int {
        guard rounds > 0 else { return 0 }
        return workSeconds * rounds + restSeconds * max(0, rounds - 1)
    }

    var phaseColor: Color {
        switch phase {
        case .work: return StrandPalette.activityStandText
        case .rest, .done: return StrandPalette.activityExerciseText
        }
    }

    // MARK: Rules

    func start() {
        if isFinished { resetToStart() }
        if !running { toggleRunning() }
    }

    private func tick() {
        guard running, !isFinished else { return }
        // 3-2-1 countdown tick on the last seconds of the current phase.
        if remaining <= 3 && remaining >= 1 {
            buzz(1)
            haptic(.tick)
        }
        if remaining > 1 {
            remaining -= 1
            elapsed += 1
            return
        }
        // remaining hits 0 — advance to the next phase/round.
        elapsed += 1
        advancePhase()
    }

    /// Ends the current phase now, as its countdown reaching zero would.
    func skipPhase() {
        guard !isFinished else { return }
        advancePhase()
    }

    private func advancePhase() {
        switch phase {
        case .work:
            if currentRound >= rounds {
                finishSession()
            } else {
                phase = .rest
                remaining = max(1, restSeconds)
                buzz(1)                     // short cue into rest
                haptic(.rest)
            }
        case .rest:
            currentRound += 1
            phase = .work
            remaining = max(1, workSeconds)
            buzz(3)                         // strong cue into work
            haptic(.work)
        case .done:
            break
        }
    }

    private func finishSession() {
        withAnimation(.snappy) {
            phase = .done
            remaining = 0
            running = false
        }
        buzz(5)                             // long completion cue
        haptic(.done)
    }

    func toggleRunning() {
        if isFinished { return }
        if running {
            running = false
        } else {
            // Starting fresh from a clean reset → fire the opening work cue.
            let startingFresh = phase == .work && currentRound == 1 && remaining == max(1, workSeconds) && elapsed == 0
            running = true
            if startingFresh {
                buzz(3)
                haptic(.work)
            }
        }
    }

    func stopAndReset() {
        running = false
        resetToStart()
    }

    /// Back to round 1 / start of work, using the current setup.
    func resetToStart() {
        phase = .work
        currentRound = 1
        remaining = max(1, workSeconds)
        elapsed = 0
    }

    /// An iPhone haptic cue. Bumping the token re-triggers `.sensoryFeedback` even when a cue repeats.
    private func haptic(_ cue: HapticCue) {
        lastHaptic = cue
        hapticTick &+= 1
    }

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
