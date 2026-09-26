import SwiftUI
import StrandDesign

// The two numbers on the session's surfaces that change on their own — the running clock and the live heart
// rate — each as its own small view, so a tick or a heartbeat redraws that one number and nothing around it.
//
// They used to be read by the screens that show them: the whole session sheet and the minimised bar watched
// the session's once-a-second tick and every change the app model published, and the sheet also watched the
// strap's live state, which changes with every log line and every beat. So the sheet — a hundred text fields —
// was redrawn several times a second for as long as it was open, even with NOOP off screen, and iOS killed
// NOOP for background CPU four times in one gym session (21 Sep 2026).

/// A running clock that ticks by itself while it is shown and costs nothing while it is not: a `TimelineView`
/// redraws this one text each second, aligned to the whole second, and SwiftUI runs a timeline only for a view
/// on screen. `seconds` turns the current unix second into what the clock reads; the format is NOOP's
/// `ActiveWorkoutClock.clock`, the one the Lock Screen's clock also reads as.
struct LiftRunningClock: View {
    let seconds: (Int) -> Int

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)) {
            context in
            Text(ActiveWorkoutClock.clock(seconds(Int(context.date.timeIntervalSince1970))))
                .monospacedDigit()
        }
    }
}

/// The live heart rate: the smoothed, spike-filtered `AppModel.bpm` every screen shows, never the raw per-beat
/// number. ALWAYS shown, a dash when the strap is not reading: an earlier version hid it with no reading, and
/// the first thing that produced was "there is no HR in the minimised tab" — an absent readout is
/// indistinguishable from an absent feature, while a dash says the strap is not reading, which is something to
/// act on. Display only: nothing here feeds a score; Effort stays what the strap measured.
///
/// A heart and the number, in the Health heart red — the session panel and the minimised bar both show it so.
struct LiftHeartRate: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(model.bpm.map(String.init) ?? "—")
                .font(StrandFont.pro(15, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(model.bpm == nil ? StrandPalette.textTertiary : StrandPalette.healthHeart)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.bpm.map { String(localized: "Heart rate \($0)") }
                            ?? String(localized: "Heart rate"))
    }
}
