import SwiftUI
import Combine
import StrandDesign

// StressCheckInSheet.swift — the L3 closed-loop JITAI surface (the "passive" layer). When the shipped,
// unit-tested `StressOnsetDetector` fires (a fresh, non-metabolic HRV dip while the user is still), the
// central hook (Wave 3, in BLEManager's existing offload/evaluateStress call-site) posts a pending nudge
// on `StressNudgeCenter`; a short sheet asks its one question. NEVER an alarm, NEVER a push (unless the
// user separately opted into notifications), NEVER a diagnosis — "HRV dipped while you were still", with
// Breathe now / Not now, matching DaytimeStress's "passive suggestion" stance. Turning check-ins off lives in
// Settings → Notifications, beside the switch that turned them on.
//
// See docs/superpowers/specs/2026-06-19-v5-haptic-biofeedback-design.md (L3 / UX → "Auto-nudge (passive)").

/// The single observable the L3 hook posts to and the check-in sheet observes. Self-contained — the central wiring
/// (Wave 3) holds one instance and calls `present()` when `StressOnsetDetector.evaluate` returns
/// `shouldNudge`; the sheet binds to `pending`. Keeping it here (not in AppModel) means the UI lane owns
/// the whole surface; Wave 3 only needs to inject the instance + call `present`.
@MainActor
final class StressNudgeCenter: ObservableObject {
    /// A live nudge awaiting the user, or nil. Carries the engine's numbers.
    @Published var pending: Nudge? = nil

    struct Nudge: Equatable {
        /// The fast short-window RMSSD at the moment of the dip (ms), for the honest sub-line.
        let fastRMSSD: Double?
        /// The slow baseline RMSSD (ms) it dipped below.
        let baselineRMSSD: Double?
        /// When it fired.
        let firedAt: Date
    }

    /// Post a nudge (the central L3 hook calls this on a fire). Idempotent-ish: a newer fire replaces an
    /// un-acted one.
    func present(fastRMSSD: Double?, baselineRMSSD: Double?) {
        pending = Nudge(fastRMSSD: fastRMSSD, baselineRMSSD: baselineRMSSD, firedAt: Date())
    }

    func dismiss() { pending = nil }
}

/// Asks the check-in's one question in a short sheet whenever a nudge is pending: Breathe now / Not now.
/// Dismissing it is "Not now".
struct StressCheckInSheetHost: View {
    @ObservedObject var center: StressNudgeCenter
    /// Start a one-minute breathing cue (the host runs it at the resonance / 5.5 pace).
    var onBreatheNow: () -> Void
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: Binding(get: { center.pending != nil },
                                        set: { if !$0 { center.dismiss() } })) {
                StressCheckInSheet(
                    onBreatheNow: {
                        center.dismiss()
                        onBreatheNow()
                    },
                    onNotNow: { center.dismiss() })
                .presentationDetents(dts.isAccessibilitySize ? [.large] : [.height(300)])
                #if os(macOS)
                .frame(width: 420)
                #endif
            }
    }
}

private struct StressCheckInSheet: View {
    let onBreatheNow: () -> Void
    let onNotNow: () -> Void
    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .title) private var glyphSize: CGFloat = 30

    var body: some View {
        if dts.isAccessibilitySize {
            ScrollView { content }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Image(systemName: "wind")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(StrandPalette.healthRespiratory)
                .padding(.top, 28)
            Text("Your HRV dipped while you were still. Want a minute to breathe?")
                .font(StrandFont.pro(20, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.horizontal, 28)
            Spacer(minLength: 16)
            // One prominent action and one plain one, as a system sheet asks.
            Button(action: onBreatheNow) {
                Text("Breathe now")
                    .font(StrandFont.pro(17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .checkInPrimaryButton()
            .padding(.horizontal, 20)
            Button(action: onNotNow) {
                Text("Not now")
                    .font(StrandFont.pro(17))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(StrandPalette.accent)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    /// iOS 26's prominent Liquid Glass capsule in the breathing hue; a bordered prominent capsule before
    /// it (and the Mac's native bezel, since `.capsule` there is macOS 14).
    @ViewBuilder func checkInPrimaryButton() -> some View {
        #if compiler(>=6.2) && os(iOS)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
                .tint(StrandPalette.healthRespiratory)
                .foregroundStyle(.black)
                .controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .tint(StrandPalette.healthRespiratory).foregroundStyle(.black).controlSize(.large)
        }
        #elseif os(iOS)
        self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .tint(StrandPalette.healthRespiratory).foregroundStyle(.black).controlSize(.large)
        #else
        self.buttonStyle(.borderedProminent)
            .tint(StrandPalette.healthRespiratory).foregroundStyle(.black).controlSize(.large)
        #endif
    }
}
