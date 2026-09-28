//  LiveWorkoutView.swift
//  NOOP · the workout in progress, laid out as the iOS 26 Fitness app records one on iPhone: always dark,
//  the live figures spread down the screen in large rounded numerals, a second page for heart-rate zones, and a
//  dark panel at the bottom holding the activity, the running clock in Exercise green, today's rings and the controls.
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
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    // PERF: deliberately does NOT observe `LiveState` — a strap publishes it ~1 Hz and every packet would
    // re-render the whole screen. The sensor rows are a leaf (`SensorFigures`) that owns that observation.
    let onClose: () -> Void

    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    /// Keep the screen awake while recording (#703). Opt-in; the toggle lives in Settings.
    @AppStorage("workoutKeepScreenOn") private var keepScreenOn = false
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    /// Ending confirms first (#517), and offers discarding there too, so a stray tap loses nothing.
    @State private var showEndConfirm = false
    /// 0 = figures, 1 = heart-rate zones — the two pages Fitness swipes between.
    @State private var page = 0
    /// Today's Charge / Effort / Rest, drawn as the small rings beside the clock.
    @State private var rings: [ActivityRing] = []

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 88
    @ScaledMetric(relativeTo: .title2) private var heartSize: CGFloat = 26
    @ScaledMetric(relativeTo: .title3) private var panelGlyphSize: CGFloat = 20

    private var zoneSet: HRZoneSet { model.profile.hrZoneSet }
    private var zone: Int { model.bpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Minimising leaves the workout running; the Workouts tab shows it until it is ended.
            RecordingTopBar(onMinimize: onClose)
            TabView(selection: $page) {
                figuresPage.tag(0)
                zonesPage.tag(1)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            RecordingPageDots(count: 2, selection: page)
                .padding(.vertical, 12)
            controlPanel
        }
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
        .task { await loadRings() }
        .confirmationDialog("End this workout?", isPresented: $showEndConfirm, titleVisibility: .hidden) {
            Button("End Workout") {
                model.endWorkout()
                onClose()
            }
            Button("Delete Workout", role: .destructive) {
                model.discardWorkout()
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Pages

    /// The figures, spread down the screen as Fitness spaces them.
    private var figuresPage: some View {
        RecordingFigures {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 8)
                LiveFigure(value: "\(Int(model.activeWorkoutCalories.rounded()))", label: String(localized: "ACTIVE\nKCAL"))
                Spacer(minLength: 8)
                heartRateFigure
                Spacer(minLength: 8)
                DistancePaceFigures(recorder: model.gpsRecorder, spacer: true) {
                    effortFigure
                    Spacer(minLength: 8)
                    LiveFigure(value: (model.activeWorkout?.avgHr ?? 0) > 0 ? "\(model.activeWorkout!.avgHr)" : "--",
                               label: String(localized: "AVERAGE\nHEART RATE"))
                }
                SensorFigures()
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
        }
    }

    /// Heart-rate zones: the current zone named in its hue over five segments, as the Workout app shows it.
    private var zonesPage: some View {
        RecordingFigures {
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Text(zone >= 1 ? String(localized: "Zone \(zone)") : String(localized: "Below Zone 1"))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(zone >= 1 ? StrandPalette.fitnessZone(zone) : .white.opacity(0.6))
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { z in
                        Capsule()
                            .fill(StrandPalette.fitnessZone(z).opacity(z == zone ? 1 : 0.25))
                            .frame(height: z == zone ? 14 : 8)
                    }
                }
                heartRateFigure
                if let band = zoneSet.zones.first(where: { $0.number == zone }) {
                    Text("\(Int(band.lower))–\(Int(band.upper)) \(String(localized: "bpm"))")
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
        }
    }

    private var effortFigure: some View {
        let strain = model.activeWorkout?.liveStrain ?? 0
        let shown = UnitFormatter.effortValue(strain, scale: effortScale)
        return LiveFigure(value: effortScale == .whoop ? String(format: "%.1f", shown) : "\(Int(shown.rounded()))",
                          label: String(localized: "EFFORT"))
    }

    private var heartRateFigure: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(model.bpm.map { "\($0)" } ?? "--")
                .font(LiveFigure.numeral(numeralSize))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
            Image(systemName: "heart.fill")
                .font(.system(size: heartSize, weight: .bold))
                .foregroundStyle(StrandPalette.healthHeart)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate"))
        .accessibilityValue(Text(model.bpm.map { "\($0) bpm" } ?? "–"))
    }

    // MARK: - Control panel

    private var controlPanel: some View {
        let paused = model.activeWorkout?.isPaused == true
        return RecordingPanel(
            glyph: AnyView(WorkoutTypeIcon(workoutType: model.activeWorkout?.sport ?? WorkoutCatalog.defaultSportName,
                                           size: panelGlyphSize, weight: .semibold, color: StrandPalette.activityExerciseText)),
            clock: {
                TimelineView(.animation(minimumInterval: 0.05)) { ctx in
                    RecordingClockText(text: Self.stopwatch(model.activeWorkout?.elapsed(at: ctx.date) ?? 0))
                }
                .accessibilityLabel(Text("Elapsed time"))
            },
            trailing: { ActivityRingsView(rings: rings, diameter: 44).opacity(rings.isEmpty ? 0 : 1) },
            leading: { RecordingButton(symbol: "xmark", label: "End workout") { showEndConfirm = true } },
            center: {
                RecordingButton(symbol: paused ? "play.fill" : "pause.fill", size: 112, prominent: paused,
                                label: paused ? "Resume" : "Pause") { model.toggleWorkoutPause() }
            },
            right: {
                RecordingButton(symbol: "waveform.path.ecg", label: "Heart rate zones") {
                    withAnimation { page = page == 0 ? 1 : 0 }
                }
            })
    }

    private func loadRings() async {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        let prefs = SummaryLoader.Prefs(dayCycleMode: DayCycleMode.persisted(dayCycleModeRaw), unitSystem: system,
                                        fahrenheit: false, skinTempKind: .absolute)
        let snap = await SummaryLoader.load(repo: repo, profile: profile, offset: 0, prefs: prefs)
        rings = [
            ActivityRing(id: "charge", fraction: RingFraction.of(snap.charge.pct, max: 100),
                         start: StrandPalette.activityMoveStart, end: StrandPalette.activityMoveEnd),
            ActivityRing(id: "effort", fraction: RingFraction.of(snap.effort, max: 100),
                         start: StrandPalette.activityExerciseStart, end: StrandPalette.activityExerciseEnd),
            ActivityRing(id: "rest", fraction: RingFraction.of(snap.rest, max: 100),
                         start: StrandPalette.activityStandStart, end: StrandPalette.activityStandEnd),
        ]
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

// MARK: - Live-observing leaves

/// Distance and pace from the on-device GPS recorder (#1195). Observes the recorder on its own, so a fix
/// re-renders only these rows; renders nothing before the first accepted fix.
private struct DistancePaceFigures<Fallback: View>: View {
    @ObservedObject var recorder: GpsWorkoutRecorder
    var spacer = false
    /// Shown instead while there is no GPS fix (an indoor or non-GPS session).
    @ViewBuilder let fallback: () -> Fallback
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private var system: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
    }

    var body: some View {
        if recorder.isRecording, recorder.pointCount > 0 {
            LiveFigure(value: UnitFormatter.paceFromSecPerKm(recorder.paceSecPerKm, system: system),
                       label: String(localized: "AVERAGE\nPACE"))
            if spacer { Spacer(minLength: 8) }
            let (d, du) = WorkoutDetailView.split(WorkoutDetailView.distance(recorder.distanceM, system: system))
            LiveFigure(value: d, unit: du, label: "")
        } else {
            fallback()
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
                LiveFigure(value: v, unit: u, label: String(localized: "SPEED"))
            }
            if let cadence = LiveState.formatCadence(live.sensorCadence) {
                LiveFigure(value: "\(cadence)", label: String(localized: "CADENCE"))
            }
            if let power = LiveState.formatPowerWatts(live.sensorPowerWatts) {
                LiveFigure(value: "\(power)", unit: "W", label: String(localized: "POWER"))
            }
        }
    }
}
