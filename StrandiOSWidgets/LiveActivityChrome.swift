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
/// aligned over it: to the trailing edge on a banner's right, to the leading edge in the island's compact
/// trailing slot, where a shorter reading has to sit snug against the camera rather than leave a gap by it
/// (LA-2). The font is the caller's, never overridden here (LA-3).
struct ActivityClock<Clock: View>: View {
    var template: String = "00:00"
    let font: Font
    var alignment: TextAlignment = .trailing
    @ViewBuilder let clock: () -> Clock

    var body: some View {
        let leading = alignment == .leading
        Text(verbatim: template)
            .font(font)
            .monospacedDigit()
            .hidden()
            .overlay(alignment: leading ? .leading : .trailing) {
                clock()
                    .font(font)
                    .monospacedDigit()
                    .multilineTextAlignment(leading ? .leading : .trailing)
                    .lineLimit(1)
            }
    }
}

/// A reading small enough for the island's minimal presentation, which shows updated information rather
/// than a bare logo (LA-2): the number in the activity's hue, scaled down rather than clipped.
struct ActivityMinimalValue: View {
    let value: String
    let tint: Color

    var body: some View {
        Text(verbatim: value)
            .font(.system(size: 14, weight: .semibold))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(tint)
    }
}

/// "0:45" for a count of seconds, as NOOP's running clocks read.
func activityClockText(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}
