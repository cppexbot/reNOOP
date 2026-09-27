import SwiftUI
import Combine
import StrandDesign

// StressCheckInSheet.swift — the L3 closed-loop JITAI surface (the "passive" layer). When the shipped,
// unit-tested `StressOnsetDetector` fires (a fresh, non-metabolic HRV dip while the user is still), the
// central hook (Wave 3, in BLEManager's existing offload/evaluateStress call-site) posts a pending nudge
// on `StressNudgeCenter`; a short sheet asks its one question. NEVER an alarm, NEVER a push (unless the
// user separately opted into notifications), NEVER a diagnosis — "HRV dipped while you were still", with
// Breathe now / Not now / Turn off, matching DaytimeStress's "passive suggestion" stance.
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

/// Asks the check-in's one question in a short sheet whenever a nudge is pending: Breathe now / Not now,
/// and a small Turn off (the master toggle, via `BiofeedbackPrefs`). Dismissing it is "Not now".
struct StressCheckInSheetHost: View {
    @ObservedObject var center: StressNudgeCenter
    /// Start a one-minute breathing cue (the host runs it at the resonance / 5.5 pace).
    var onBreatheNow: () -> Void

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: Binding(get: { center.pending != nil },
                                        set: { if !$0 { center.dismiss() } })) {
                StressCheckInSheet(
                    onBreatheNow: {
                        center.dismiss()
                        onBreatheNow()
                    },
                    onNotNow: { center.dismiss() },
                    onTurnOff: {
                        BiofeedbackPrefs.checkInEnabled = false
                        center.dismiss()
                    })
                .presentationDetents([.height(300)])
                #if os(macOS)
                .frame(width: 420)
                #endif
            }
    }
}

private struct StressCheckInSheet: View {
    let onBreatheNow: () -> Void
    let onNotNow: () -> Void
    let onTurnOff: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "wind")
                .font(.system(size: 30, weight: .semibold))
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
            Button(action: onBreatheNow) {
                Text("Breathe now")
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(StrandPalette.healthRespiratory))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            HStack {
                Button("Turn off", action: onTurnOff)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                Button("Not now", action: onNotNow)
                    .foregroundStyle(StrandPalette.accent)
            }
            .font(StrandFont.pro(17))
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}
