import SwiftUI
import StrandDesign

// The running session, condensed to a bar that sits above the tab bar wherever you are in the app.
//
// WHY IT EXISTS. Swiping the workout sheet down used to dismiss the session outright: the screen
// went away and took the strap handler and the tick with it, so taps and buzzes silently stopped
// working. Now swiping down MINIMISES to this bar. The session is still running — same clock, same
// strap gesture, same buzzes — and tapping the bar brings the full sheet back.
//
// It is deliberately a bar and not a badge: it has to show the one thing you need mid-workout
// without opening anything, which is how long is left of your rest.
//
// It is drawn as the iOS 26 Music mini-player sits above the tab bar: a glass capsule with the glyph, the
// session in a few short lines and the one control. COLOUR MATCHES THE SHEET so the two read as one
// thing: the clock is green while working, the rest's yellow while resting.

struct LiftSessionBar: View {
    @EnvironmentObject var session: LiftSessionController

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        // `LiftSessionController.presentation`, the same resolution the Lock Screen renders, so the two
        // cannot word the session differently. Resolved once per render; all three lines read it.
        if let engine = session.engine, let shown = session.presentation(system: unitSystem) {
            Button {
                session.isPresented = true
            } label: {
                // The Lock Screen banner's content (`LiftLiveActivity`), because this is the same banner
                // seen inside the app: the glyph and the numbers sit near the edges and the heart rate
                // stacks over the clock, so the words get the width (Utku, 21 Sep 2026, with a screenshot
                // of the bar: "more place for writings").
                HStack(spacing: 10) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StrandPalette.activityExerciseText)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(StrandPalette.fitnessCard))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(shown.exercise)
                            .font(StrandFont.pro(15, weight: .semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                        Text(shown.detail.map { "\(shown.status) — \($0)" } ?? shown.status)
                            .font(StrandFont.pro(13))
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                        // The set coming up, on one line that cuts the exercise name before the
                        // set number (`LiftSessionController.nextLine`).
                        Text(shown.next)
                            .font(StrandFont.pro(12))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 6)

                    // Heart rate over the clock, both flush right, each its own small view that updates
                    // itself (`LiftLiveReadouts.swift`), so a beat or a tick redraws one number, not the bar.
                    // The clock's width comes from a hidden "00:00" in its font — the widest a set or a rest
                    // shows under an hour — so the words beside it do not shift when it gains a digit.
                    VStack(alignment: .trailing, spacing: 1) {
                        LiftHeartRate()

                        Text(verbatim: "00:00")
                            .font(Self.clockFont)
                            .monospacedDigit()
                            .hidden()
                            .overlay(alignment: .trailing) {
                                bigClock(engine)
                                    .font(Self.clockFont)
                                    .foregroundStyle(tint(engine))
                                    .fixedSize()
                            }
                    }

                    // The same action the sheet's button performs, so a set can be closed out
                    // without opening anything.
                    Button { session.advance() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(StrandPalette.fitnessOnAccent)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(StrandPalette.activityExerciseText))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next")
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .liftBarGlass()
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the running session")
        }
    }

    private static let clockFont = Font.system(size: 20, weight: .semibold, design: .rounded)

    /// Green while a set or the warm-up runs, the duration yellow while resting.
    private func tint(_ engine: LiftSessionEngine) -> Color {
        if case .resting = engine.stage { return StrandPalette.fitnessTime }
        return StrandPalette.activityExerciseText
    }

    /// Rest counts DOWN (that is the number you act on); everything else counts up. Written as the Lock
    /// Screen writes the same clock — "0:45", "0:00", "1:05:00" — through NOOP's one running-clock format.
    private func bigClock(_ engine: LiftSessionEngine) -> LiftRunningClock {
        LiftRunningClock { now in engine.restRemaining(now: now) ?? now - engine.stageStartedAt }
    }
}

private extension View {
    /// The bar's surface: interactive Liquid Glass on iOS 26 / macOS 26, a material capsule before.
    @ViewBuilder
    func liftBarGlass() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
        #else
        self.background(.ultraThinMaterial, in: Capsule())
        #endif
    }
}
