import SwiftUI
import Foundation
import StrandDesign

/// Silent haptic HIIT interval timer.
///
/// Train hands-free: the strap buzzes every transition so you never have to look
/// at the screen. Strong triple-buzz at the start of each WORK block, a short
/// single buzz into REST, a 3-2-1 tick on the last seconds of every phase, and a
/// long 5-loop buzz when the whole session finishes. With no strap bonded it still
/// works as a big glanceable visual timer (just without haptics).
struct IntervalTimerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    // MARK: Config (persisted only in-view)

    @State private var workSeconds: Int = 30
    @State private var restSeconds: Int = 15
    @State private var rounds: Int = 8

    // MARK: Run state

    private enum Phase { case work, rest, done
        var label: String {
            switch self {
            case .work: return String(localized: "Work")
            case .rest: return String(localized: "Rest")
            case .done: return String(localized: "Done")
            }
        }
    }

    @State private var phase: Phase = .work
    @State private var currentRound: Int = 1
    @State private var remaining: Int = 30          // seconds left in the current phase
    @State private var running: Bool = false
    @State private var elapsed: Int = 0             // total elapsed seconds across the session

    // MARK: iPhone haptics (iOS only)
    //
    // The strap buzz (`buzz`) only fires when a strap is bonded; on iPhone the device in
    // the user's hand has a Taptic Engine, so we mirror every transition cue with native
    // haptics that fire regardless of bond state. A monotonically-bumped Int token drives a
    // single `.sensoryFeedback`, so even a repeated cue (the 3-2-1 tick three seconds running)
    // re-fires because the trigger value always changes.
    #if os(iOS)
    private enum HapticCue { case work, rest, tick, done }
    @State private var lastHaptic: HapticCue = .work
    @State private var hapticTick: Int = 0
    #endif

    // 1Hz tick.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: Derived

    private var phaseDuration: Int {
        switch phase {
        case .work: return max(1, workSeconds)
        case .rest: return max(1, restSeconds)
        case .done: return 1
        }
    }

    /// 0...1 progress through the current interval.
    private var intervalProgress: Double {
        guard phaseDuration > 0 else { return 0 }
        let done = Double(phaseDuration - remaining)
        return min(1, max(0, done / Double(phaseDuration)))
    }

    /// Total planned session length in seconds (work*rounds + rest*(rounds-1)).
    private var totalPlanned: Int {
        guard rounds > 0 else { return 0 }
        return workSeconds * rounds + restSeconds * max(0, rounds - 1)
    }

    /// The active phase's reset token: WORK uses the Effort blue, REST the Rest blue-grey, DONE the
    /// positive green. Tints the flat ring arc + the phase chip only (no glow).
    private var phaseColor: Color {
        switch phase {
        case .work: return StrandPalette.activityStandText
        case .rest: return StrandPalette.activityExerciseText
        case .done: return StrandPalette.activityExerciseText
        }
    }

    private var isFinished: Bool { phase == .done }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                stage
                controls
                planSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("Intervals"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onReceive(ticker) { _ in tick() }
        .onChangeCompat(of: workSeconds) { _ in if !running { resetToStart() } }
        .onChangeCompat(of: restSeconds) { _ in if !running { resetToStart() } }
        .onChangeCompat(of: rounds) { _ in
            if currentRound > rounds { currentRound = rounds }
            if !running { resetToStart() }
        }
        .onAppear { if remaining == 0 { resetToStart() } }
        // Keep the screen awake while a session runs (no-op on macOS). One onChange covers every
        // running→false transition, and onDisappear is the safety net so leaving mid-run never leaves the
        // idle timer disabled app-wide.
        .onChangeCompat(of: running) { ScreenIdle.keepAwake($0) }
        .onDisappear { ScreenIdle.keepAwake(false) }
        #if os(iOS)
        // iPhone haptics: one modifier, a different feel per cue, re-firing on every token bump. Fires
        // regardless of strap bond so the timer is fully usable unstrapped.
        .sensoryFeedback(trigger: hapticTick) { _, _ in
            switch lastHaptic {
            case .work: return .impact(weight: .heavy)
            case .rest: return .impact(weight: .light)
            case .tick: return .selection
            case .done: return .success
            }
        }
        #endif
    }

    // MARK: Stage — the Clock app's timer ring

    private var stage: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(phase.label)
                    .font(StrandFont.pro(22, weight: .bold))
                    .foregroundStyle(phaseColor)
                Text(isFinished ? String(localized: "\(rounds) rounds") : String(localized: "Round \(min(currentRound, rounds)) of \(rounds)"))
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            ring
            Text(live.bonded ? "Your strap buzzes at every change." : "Connect your strap to feel each change.")
                .font(StrandFont.pro(13))
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var ring: some View {
        let fraction = isFinished ? 1 : intervalProgress
        return ZStack {
            Circle().stroke(StrandPalette.textPrimary.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.0001, CGFloat(min(max(1 - fraction, 0), 1))))
                .rotation(.degrees(-90))
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .animation(.linear(duration: 1), value: fraction)
            VStack(spacing: 4) {
                Text(isFinished ? timeString(elapsed) : timeString(remaining))
                    .font(.system(size: 64, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                    .contentTransition(.numericText())
                Text("\(timeString(max(0, totalPlanned - elapsed))) left")
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .opacity(isFinished ? 0 : 1)
            }
        }
        .frame(width: 280, height: 280)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFinished ? "Session done" : "\(remaining) seconds remaining in \(phase.label)")
    }

    // MARK: Controls — Clock's two round buttons

    private var controls: some View {
        HStack {
            roundButton(String(localized: "Reset"), fill: StrandPalette.textPrimary.opacity(0.12),
                        text: StrandPalette.textPrimary) { stopAndReset() }
                .disabled(!running && remaining == phaseDuration && currentRound == 1 && phase == .work && elapsed == 0)
            Spacer()
            roundButton(running ? String(localized: "Pause") : (isFinished ? String(localized: "Restart") : String(localized: "Start")),
                        fill: (running ? StrandPalette.fitnessTime : StrandPalette.activityExerciseText).opacity(0.25),
                        text: running ? StrandPalette.fitnessTime : StrandPalette.activityExerciseText) {
                if isFinished { resetToStart() }
                toggleRunning()
            }
        }
        .padding(.horizontal, 8)
    }

    private func roundButton(_ title: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.pro(17))
                .foregroundStyle(text)
                .frame(width: 84, height: 84)
                .background(Circle().fill(fill))
                .overlay(Circle().inset(by: 3).stroke(fill, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Plan — the Fitness custom-workout blocks

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workout")
                .font(StrandFont.pro(22, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                planRow(String(localized: "Work"), symbol: "chevron.up.2", tint: StrandPalette.activityStandText,
                        value: $workSeconds, range: 5...600, step: 5, format: { timeString($0) })
                Divider().padding(.leading, 56)
                planRow(String(localized: "Rest"), symbol: "chevron.down.2", tint: StrandPalette.activityExerciseText,
                        value: $restSeconds, range: 5...600, step: 5, format: { timeString($0) })
                Divider().padding(.leading, 56)
                planRow(String(localized: "Rounds"), symbol: "repeat", tint: StrandPalette.textSecondary,
                        value: $rounds, range: 1...30, step: 1, format: { "\($0)" })
            }
            .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .disabled(running)
            .opacity(running ? 0.5 : 1)
            Text("Total \(timeString(totalPlanned))")
                .font(StrandFont.pro(13))
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private func planRow(_ title: String, symbol: String, tint: Color, value: Binding<Int>,
                         range: ClosedRange<Int>, step: Int, format: @escaping (Int) -> String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(format(value.wrappedValue))
                        .font(StrandFont.pro(15))
                        .monospacedDigit()
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Timer logic

    private func tick() {
        guard running, !isFinished else { return }

        // Optional 3-2-1 countdown tick on the last seconds of the current phase.
        if remaining <= 3 && remaining >= 1 {
            buzz(loops: 1)
            #if os(iOS)
            haptic(.tick)
            #endif
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

    private func advancePhase() {
        switch phase {
        case .work:
            if currentRound >= rounds {
                // Last work block finished → session complete.
                finishSession()
            } else {
                // Into rest.
                phase = .rest
                remaining = max(1, restSeconds)
                buzz(loops: 1)              // short cue into rest
                #if os(iOS)
                haptic(.rest)
                #endif
            }
        case .rest:
            // Rest done → next round's work.
            currentRound += 1
            phase = .work
            remaining = max(1, workSeconds)
            buzz(loops: 3)                  // strong cue into work
            #if os(iOS)
            haptic(.work)
            #endif
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
        buzz(loops: 5)                      // long completion cue
        #if os(iOS)
        haptic(.done)
        #endif
    }

    private func toggleRunning() {
        if isFinished { return }
        if running {
            running = false
        } else {
            // Starting fresh from a clean reset → fire the opening WORK cue.
            let startingFresh = (phase == .work && currentRound == 1
                                 && remaining == max(1, workSeconds) && elapsed == 0)
            running = true
            if startingFresh {
                buzz(loops: 3)
                #if os(iOS)
                haptic(.work)
                #endif
            }
        }
    }

    private func stopAndReset() {
        running = false
        resetToStart()
    }

    /// Reset run state back to round 1 / start of work, using current config.
    private func resetToStart() {
        phase = .work
        currentRound = 1
        remaining = max(1, workSeconds)
        elapsed = 0
    }

    /// Fire a strap buzz (no-op when not bonded — `buzz` already guards, but we
    /// also skip the call entirely so this stays a pure visual tool when unbonded).
    private func buzz(loops: UInt8) {
        guard live.bonded else { return }
        model.buzz(loops: loops, gate: HapticPrefs.intervals)
    }

    #if os(iOS)
    /// Fire an iPhone haptic cue. Additive to `buzz` and unguarded by bond state, so the
    /// timer gives tactile feedback even with no strap. Bumping the token re-triggers
    /// `.sensoryFeedback` even when the same cue repeats.
    private func haptic(_ cue: HapticCue) {
        lastHaptic = cue
        hapticTick &+= 1
    }
    #endif

    // MARK: Formatting

    private func timeString(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

#if DEBUG
#Preview("Interval Timer") {
    IntervalTimerView()
        .environmentObject(AppModel())
        .environmentObject(LiveState())
        .frame(width: 720, height: 900)
        .preferredColorScheme(.dark)
}
#endif
