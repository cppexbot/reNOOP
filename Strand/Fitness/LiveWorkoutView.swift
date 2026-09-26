//  LiveWorkoutView.swift
//  NOOP · the workout in progress, laid out as the iOS 26 Fitness app records one on iPhone: always dark,
//  the live figures stacked in large rounded numerals, and a glass panel at the bottom holding the activity,
//  the running clock in Exercise green and the controls.
//
//  Every figure comes from the same live feed and scorers as the rest of the app (#238): heart rate is the
//  smoothed `AppModel.bpm`, Effort the running `ActiveWorkout.liveStrain`, distance and pace the on-device
//  GPS recorder (#1195), and speed / cadence / power a connected fitness sensor.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

struct LiveWorkoutView: View {
    @EnvironmentObject private var model: AppModel
    // PERF: deliberately does NOT observe `LiveState` — a strap publishes it ~1 Hz and every packet would
    // re-render the whole screen. The sensor rows are a leaf (`SensorFigures`) that owns that observation.
    let onClose: () -> Void

    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    /// Keep the screen awake while recording (#703). Opt-in; the toggle lives in Settings.
    @AppStorage("workoutKeepScreenOn") private var keepScreenOn = false

    /// End and Delete both confirm first (#517): a stray tap must not end or discard the recording.
    @State private var showEndConfirm = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                effortFigure
                heartRateFigure
                if let avg = model.activeWorkout?.avgHr, avg > 0 {
                    LiveFigure(value: "\(avg)", label: "AVERAGE\nHEART RATE")
                }
                DistancePaceFigures(recorder: model.gpsRecorder)
                SensorFigures()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controlPanel }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // The workout ended elsewhere (e.g. a restart cleared it): close.
        .onChangeCompat(of: model.activeWorkout == nil) { gone in if gone { onClose() } }
        // Arm the realtime HR stream while this screen is up (#681) — on a WHOOP 5/MG live HR only flows
        // while it is armed. Ref-counted in AppModel, so it balances with the Live tab's own arm.
        .onAppear {
            model.startRealtimeHR()
            if keepScreenOn { ScreenIdle.keepAwake(true) }
        }
        .onDisappear {
            model.stopRealtimeHR()
            // Always release, even if the toggle was flipped off mid-workout.
            ScreenIdle.keepAwake(false)
        }
        .alert("End this workout?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) {
                model.endWorkout()
                onClose()
            }
        } message: {
            Text("This stops recording and saves what's captured so far. It can't be resumed.")
        }
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.discardWorkout()
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Figures

    private var effortFigure: some View {
        let strain = model.activeWorkout?.liveStrain ?? 0
        let shown = UnitFormatter.effortValue(strain, scale: effortScale)
        return LiveFigure(value: effortScale == .whoop ? String(format: "%.1f", shown) : "\(Int(shown.rounded()))",
                          label: "EFFORT")
    }

    private var heartRateFigure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(model.bpm.map { "\($0)" } ?? "--")
                .font(LiveFigure.numeral)
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Image(systemName: "heart.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(StrandPalette.healthHeart)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate"))
        .accessibilityValue(Text(model.bpm.map { "\($0) bpm" } ?? "–"))
    }

    // MARK: - Control panel

    private var controlPanel: some View {
        VStack(spacing: 16) {
            HStack {
                WorkoutTypeIcon(workoutType: model.activeWorkout?.sport ?? WorkoutCatalog.defaultSportName,
                                size: 22, weight: .semibold, color: StrandPalette.activityExerciseText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(StrandPalette.fitnessCard))
                Spacer()
                clock
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            HStack {
                controlButton("trash", size: 64, tint: StrandPalette.statusCritical,
                              label: "Delete") { showDeleteConfirm = true }
                Spacer()
                pauseButton
                Spacer()
                controlButton("xmark", size: 64, tint: .white, label: "End workout") { showEndConfirm = true }
            }
        }
        .padding(20)
        .liveWorkoutPanelGlass()
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    /// Minutes, seconds and hundredths — the stopwatch Fitness runs while recording.
    private var clock: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { ctx in
            Text(Self.stopwatch(model.activeWorkout?.elapsed(at: ctx.date) ?? 0))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(StrandPalette.activityExerciseText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityLabel(Text("Elapsed time"))
    }

    private var pauseButton: some View {
        let paused = model.activeWorkout?.isPaused == true
        return Button { model.toggleWorkoutPause() } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(paused ? StrandPalette.fitnessOnAccent : .white)
                .frame(width: 88, height: 88)
                .background(Circle().fill(paused ? StrandPalette.activityExerciseText : Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(paused ? "Resume" : "Pause"))
    }

    private func controlButton(_ symbol: String, size: CGFloat, tint: Color, label: LocalizedStringKey,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    static func stopwatch(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        let whole = Int(total)
        let hundredths = Int((total - Double(whole)) * 100)
        return whole >= 3600
            ? String(format: "%d:%02d:%02d.%02d", whole / 3600, whole / 60 % 60, whole % 60, hundredths)
            : String(format: "%02d:%02d.%02d", whole / 60, whole % 60, hundredths)
    }
}

// MARK: - Figure

/// One live figure: a large rounded numeral with its small-caps label beside it, as Fitness stacks them.
private struct LiveFigure: View {
    static let numeral = Font.system(size: 76, weight: .medium, design: .rounded)

    let value: String
    var unit: String = ""
    let label: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            (Text(value).font(Self.numeral)
             + Text(unit.uppercased()).font(.system(size: 40, weight: .medium, design: .rounded)))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Live-observing leaves

/// Distance and pace from the on-device GPS recorder (#1195). Observes the recorder on its own, so a fix
/// re-renders only these rows; renders nothing before the first accepted fix.
private struct DistancePaceFigures: View {
    @ObservedObject var recorder: GpsWorkoutRecorder
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private var system: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
    }

    var body: some View {
        if recorder.isRecording, recorder.pointCount > 0 {
            let (d, du) = WorkoutDetailView.split(WorkoutDetailView.distance(recorder.distanceM, system: system))
            LiveFigure(value: d, unit: du, label: "")
            LiveFigure(value: UnitFormatter.paceFromSecPerKm(recorder.paceSecPerKm, system: system),
                       label: "AVERAGE\nPACE")
        }
    }
}

/// Speed / cadence / power from a connected fitness sensor. Owns the `LiveState` observation (see the note
/// on `LiveWorkoutView`), so a sensor packet re-renders only these rows.
private struct SensorFigures: View {
    @EnvironmentObject private var live: LiveState
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private var system: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
    }

    var body: some View {
        if live.hasSensorMetrics {
            if let speed = UnitFormatter.speedFromKilometersPerHour(live.sensorSpeedKmh, system: system) {
                let (v, u) = WorkoutDetailView.split(speed)
                LiveFigure(value: v, unit: u, label: "SPEED")
            }
            if let cadence = LiveState.formatCadence(live.sensorCadence) {
                LiveFigure(value: "\(cadence)", label: "CADENCE")
            }
            if let power = LiveState.formatPowerWatts(live.sensorPowerWatts) {
                LiveFigure(value: "\(power)", unit: "W", label: "POWER")
            }
        }
    }
}

// MARK: - Glass

private extension View {
    /// The bottom panel's surface: Liquid Glass on iOS 26 / macOS 26, a dark material before.
    @ViewBuilder
    func liveWorkoutPanelGlass() -> some View {
        let shape = RoundedRectangle(cornerRadius: 40, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}
