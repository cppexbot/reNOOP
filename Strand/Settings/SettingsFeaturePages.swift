//  SettingsFeaturePages.swift
//  NOOP · Settings → Workouts, Scores.

import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Workouts

struct WorkoutsSettingsPage: View {
    /// Opt-in: after a sync, offer to save a sustained raised-HR stretch as a workout. Never automatic.
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetectWorkoutsEnabled = false
    /// #703: the live-workout view holds the screen awake while recording. Shared with Android verbatim.
    @AppStorage("workoutKeepScreenOn") private var workoutKeepScreenOn = false
    /// Live-HR Live Activity (Lock Screen + Dynamic Island), iOS only (#336).
    @AppStorage(UnitPrefs.liveActivityKey) private var liveActivityEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Auto-detect workouts", isOn: $autoDetectWorkoutsEnabled)
            }
            Section {
                Toggle("Keep screen on", isOn: $workoutKeepScreenOn)
                #if os(iOS)
                Toggle("Heart rate in Dynamic Island", isOn: $liveActivityEnabled)
                #endif
            }
        }
        .settingsPage("Workouts")
    }
}

// MARK: - Scores

struct ScoresSettingsPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profile: ProfileStore

    /// #268: show Effort on NOOP's 0–100 axis or WHOOP's 0–21. Display-only.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    /// #1545 opt-in: Banister's exponential TRIMP instead of Edwards' zones. Re-scores the window.
    @AppStorage(PuffinExperiment.banisterEffortKey) private var banisterEffortEnabled = false

    /// #141: whole night or deep sleep only. Changes the number, so a switch re-scores.
    @AppStorage(UnitPrefs.hrvWindowKey) private var hrvWindowRaw = HrvWindow.whole.rawValue

    @State private var showScoringGuide = false
    @State private var showRecalibrateConfirm = false
    @State private var showRecalibrated = false
    @State private var showStepsCalibration = false

    var body: some View {
        Form {
            Section {
                Picker("Effort scale", selection: $effortScaleRaw) {
                    Text("0-100").tag(EffortScale.hundred.rawValue)
                    Text("0-21").tag(EffortScale.whoop.rawValue)
                }
                .settingsPicker()
                Toggle("Exponential scale", isOn: $banisterEffortEnabled)
                    .onChangeCompat(of: banisterEffortEnabled) { _ in
                        // The recipe changes stored Effort for every day in the window: re-score now.
                        Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
                    }
            } header: {
                Text("Effort")
            }

            Section {
                // #139/#132: daily steps = @57 counter ticks ÷ this divisor. Variable increment.
                LabeledContent("Step calibration") {
                    Stepper {
                        Text(String(format: "%.1f", profile.stepTicksPerStep))
                            .monospacedDigit()
                    } onIncrement: {
                        profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: true)
                    } onDecrement: {
                        profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: false)
                    }
                    .fixedSize()
                    .accessibilityLabel("Step calibration, \(String(format: "%.1f", profile.stepTicksPerStep)) counter ticks per step")
                }
                // WHOOP 4.0 steps ESTIMATE (a separate thing from the 5/MG counter divisor above).
                Button {
                    showStepsCalibration = true
                } label: {
                    LabeledContent("Steps estimate") {
                        HStack(spacing: 6) {
                            Text(stepsCalibrationSummary)
                            Image(systemName: "chevron.right")
                                .font(StrandFont.pro(13, weight: .semibold))
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    .foregroundStyle(StrandPalette.textPrimary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text("Steps")
            }

            Section {
                Picker("HRV window", selection: $hrvWindowRaw) {
                    Text("Night").tag(HrvWindow.whole.rawValue)
                    Text("Deep sleep").tag(HrvWindow.deep.rawValue)
                }
                .settingsPicker()
                .onChangeCompat(of: hrvWindowRaw) { _ in
                    // #201/#195: analyzeRecent re-scores and re-folds the baseline in one pass.
                    Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
                }
                Button("Reset baseline") { showRecalibrateConfirm = true }
            } header: {
                Text("Charge")
            }

            Section {
                Button("How scores work") { showScoringGuide = true }
                    .foregroundStyle(StrandPalette.textPrimary)
            }
        }
        .settingsPage("Scores")
        .sheet(isPresented: $showScoringGuide) { ScoringGuideView(onClose: { showScoringGuide = false }) }
        .confirmationDialog("Recalibrate your Charge baseline?",
                            isPresented: $showRecalibrateConfirm, titleVisibility: .visible) {
            Button("Recalibrate") { recalibrate() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This restarts the roughly 4-night build-up for Charge and your HRV baseline. Your history stays. Use it if a bad first week, like wearing it while sick, set your baseline off.")
        }
        .alert("Charge baseline recalibrating", isPresented: $showRecalibrated) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("NOOP will re-learn your baseline from tonight's data onward. Your history is kept, and it takes a few nights to settle.")
        }
        .sheet(isPresented: $showStepsCalibration) {
            StepsCalibrationSheet(repo: model.repo, onClose: { showStepsCalibration = false })
                .environmentObject(profile)
        }
    }

    /// Manual, the auto-fit confidence, or not yet calibrated.
    private var stepsCalibrationSummary: String {
        if profile.stepsManualCoefficient > 0 { return String(localized: "Manual") }
        if profile.stepsCalibrationCoefficient > 0 {
            return String(localized: "Auto · \(StepsCalibrationFormat.confidenceLabel(profile.stepsCalibrationConfidence)) confidence")
        }
        return String(localized: "Not calibrated")
    }

    /// Re-anchors every baseline that feeds Charge from now (`Baselines.recalibrateRecoveryBaselines`),
    /// then re-scores and refreshes. No stored day is deleted.
    private func recalibrate() {
        Baselines.recalibrateRecoveryBaselines()
        Task {
            await model.intelligence.analyzeRecent()
            await model.repo.refresh()
        }
        showRecalibrated = true
    }
}
