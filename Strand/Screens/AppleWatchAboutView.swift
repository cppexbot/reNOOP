import SwiftUI
import StrandDesign

// MARK: - About Apple Watch data
//
// The honest "what your Apple Watch is good at, and where it's lighter" page (M2 of the
// Watch-as-a-device project). NOOP can run off only an Apple Watch (the phone computes our
// Charge / Rest / Effort / Fitness Age live from HealthKit) but the watch is not a chest
// strap, and this page says so plainly. It renders the per-metric capability + confidence
// table from the design spec: each row is the metric and its confidence rating.
//
// This is content only: it reads from no store and holds no live state, so it renders the
// SAME on macOS and iOS. The actual permission request lives in the setup flow
// (AppleWatchSetupView), which this page links to. Reachable from Settings → About.
//
// Honest tone, plain voice, no fabricated numbers. Every confidence label here is the same
// honest "Great / Good / Calibrating / Not available" stance the scores use on Today.

/// One row of the capability/confidence table: a metric and where the watch sits on it. The
/// confidence drives the row's status dot, so a glance reads honestly.
private struct WatchMetric: Identifiable {
    enum Confidence {
        case great        // use it as-is, the watch is strong here
        case good         // solid, with a small caveat
        case calibrating  // needs a baseline first, no fabricated number until then
        case unavailable  // the sensor or model can't honestly support it

        var pillLabel: String {
            switch self {
            case .great:        return String(localized: "Great")
            case .good:         return String(localized: "Good")
            case .calibrating:  return String(localized: "Calibrating")
            case .unavailable:  return String(localized: "Not available")
            }
        }

        /// The status dot beside the label, in the Settings hues.
        var dot: Color {
            switch self {
            case .great:        return StrandPalette.settingsGreen
            case .good:         return StrandPalette.settingsBlue
            case .calibrating:  return StrandPalette.settingsOrange
            case .unavailable:  return StrandPalette.settingsGray
            }
        }
    }

    let id = UUID()
    let icon: String
    /// The row icon's tile colour.
    let color: Color
    let metric: String
    let confidence: Confidence
}

struct AppleWatchAboutView: View {
    /// Optional hook so the page can present the setup/permission flow. The About page links to
    /// it as its primary call to action; left nil (e.g. on macOS, which has no HealthKit) the
    /// button is hidden and the page reads as pure reference content.
    var onStartSetup: (() -> Void)?

    init(onStartSetup: (() -> Void)? = nil) {
        self.onStartSetup = onStartSetup
    }

    // The honest table, straight from the spec's scoring + confidence map. Order runs from what
    // the watch is strongest at down to what it can't honestly do, so the page reads as a fair
    // appraisal rather than a sales pitch.
    private let metrics: [WatchMetric] = [
        WatchMetric(icon: "bed.double.fill", color: StrandPalette.settingsIndigo, metric: String(localized: "Sleep / Rest"),
                    confidence: .great),
        WatchMetric(icon: "figure.walk", color: StrandPalette.settingsOrange, metric: String(localized: "Steps & workouts"),
                    confidence: .great),
        WatchMetric(icon: "lungs.fill", color: StrandPalette.settingsGreen, metric: String(localized: "Fitness Age"),
                    confidence: .great),
        WatchMetric(icon: "flame.fill", color: StrandPalette.settingsRed, metric: String(localized: "Effort"),
                    confidence: .good),
        WatchMetric(icon: "heart.fill", color: StrandPalette.settingsPink, metric: String(localized: "Recovery / Charge"),
                    confidence: .calibrating),
        WatchMetric(icon: "thermometer.medium", color: StrandPalette.settingsTeal, metric: String(localized: "Skin temperature"),
                    confidence: .good),
        WatchMetric(icon: "drop.degreesign", color: StrandPalette.settingsCyan, metric: String(localized: "Blood oxygen (SpO₂)"),
                    confidence: .unavailable),
    ]

    var body: some View {
        Form {
            if let onStartSetup {
                Section {
                    Button("Set up Apple Watch", action: onStartSetup)
                        .accessibilityHint("Opens the Apple Watch setup and Health permission")
                }
            }

            Section {
                ForEach(metrics) { metricRow($0) }
            } header: {
                Text("What the watch can do")
            }
        }
        .settingsPage("About Apple Watch data")
    }

    /// Health Checklist's row: the icon, then the name and a dot with the rating.
    private func metricRow(_ item: WatchMetric) -> some View {
        HStack(alignment: .center, spacing: 14) {
            SettingsIcon(systemName: item.icon, color: item.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.metric)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.confidence.dot)
                        .frame(width: 8, height: 8)
                    Text(verbatim: item.confidence.pillLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        // One accessible element per metric: the screen reader hears the metric and its confidence
        // as a single unit instead of loose fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.metric). \(item.confidence.pillLabel)")
    }
}

#if DEBUG
#Preview("About Apple Watch data") {
    NavigationStack {
        AppleWatchAboutView(onStartSetup: {})
    }
    .preferredColorScheme(.dark)
}
#endif
