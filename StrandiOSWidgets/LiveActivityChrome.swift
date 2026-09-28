import WidgetKit
import SwiftUI
import AppIntents
import StrandDesign

// The pieces every NOOP banner shares, taken from Apple's own iOS 26 banners: the Fitness workout banner (the
// activity's glyph on a tinted disc, the clock large, a round grey control) and the Clock timer banner (a
// tinted control, the label and a light countdown in the timer's hue). Both sit on the same near-black card,
// so NOOP's banners do too, drawn in the dark palette whatever the Lock Screen's appearance.

enum ActivityStyle {
    /// The card behind every banner: near-black, as Fitness and Clock draw theirs.
    static let background = Color.black.opacity(0.78)
    /// Hues on that card: the app's tokens, which resolve to their dark values under `activityCard()`.
    /// Work and rest, everywhere a workout alternates them: work in the Exercise green, rest in the Stand cyan.
    static let exercise = StrandPalette.activityExerciseText
    static let rest = StrandPalette.activityStandText
    static let heart = StrandPalette.healthHeart
    static let ok = StrandPalette.settingsGreen
    static let problem = StrandPalette.settingsRed
    static let secondary = Color.white.opacity(0.6)
}

extension View {
    /// The shared banner surface: the near-black card, white system actions, the dark palette for the content.
    func activityCard() -> some View {
        self
            .environment(\.colorScheme, .dark)
            .activityBackgroundTint(ActivityStyle.background)
            .activitySystemActionForegroundColor(.white)
    }
}

/// The activity's glyph on a disc of its own hue — the left end of the Fitness banner.
struct ActivityDisc: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 46

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.2)))
            .accessibilityHidden(true)
    }
}

/// A round control. Grey with a white glyph by default (the Fitness pause); `tint` draws it in the hue (the
/// Clock timer's pause). The intent runs in the app; `label` is what VoiceOver reads for the glyph.
struct ActivityControl<Intent: LiveActivityIntent>: View {
    let intent: Intent
    let symbol: String
    let label: LocalizedStringKey
    var tint: Color? = nil
    var size: CGFloat = 46

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(tint ?? .white)
                .frame(width: size, height: size)
                .background(Circle().fill((tint ?? .white).opacity(tint == nil ? 0.22 : 0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// A self-ticking clock that takes only the width of its widest reading. A running `Text(timerInterval:)` claims
/// every point it is offered, so the width comes from a hidden template in the same font and the live clock is
/// right-aligned over it.
struct ActivityClock<Clock: View>: View {
    var template: String = "00:00"
    let font: Font
    @ViewBuilder let clock: () -> Clock

    var body: some View {
        Text(verbatim: template)
            .font(font)
            .monospacedDigit()
            .hidden()
            .overlay(alignment: .trailing) {
                clock()
                    .font(font)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
    }
}

/// "0:45" for a count of seconds, as NOOP's running clocks read.
func activityClockText(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}
