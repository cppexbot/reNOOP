import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for a running Lift Log session, in the iOS 26 Fitness and Clock banners' language: a round
/// "set done" control in the session's green, the session in words, the clock large on the right.
///
/// It carries what the tab bar's mini-player does, resolved by the same `LiftSessionController.presentation`:
/// the exercise, the set and its numbers, the set coming up, the heart rate and the clock — green while a set is
/// worked, the rest's yellow through the rest.
///
/// THE CLOCK TICKS WITHOUT THE APP. Both timers are `Text(timerInterval:)`, driven by dates in the content
/// state, so the Lock Screen counts on its own between pushes. The app only sends a new state when something
/// actually changes (stage, set, heart rate), never once a second to animate a number.
struct LiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiftActivityAttributes.self) { context in
            lockScreen(context.state)
                .activityCard()
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityDisc(symbol: "dumbbell.fill", tint: ActivityStyle.exercise, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityControl(intent: LiftSetDoneIntent(), symbol: "checkmark", label: "Next", size: 44)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 0) {
                        Text(state.exercise)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        ActivityClock(font: .system(size: 34, weight: .semibold)) { clock(state) }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Text(statusLine(state))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        heartRate(state)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(ActivityStyle.secondary)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                // The heart rate, where the island has the room for it, with the dumbbell standing in until
                // the strap reports one — so this side is never blank (Utku, 22 Sep 2026).
                if let bpm = state.bpm {
                    Label { Text("\(bpm)").monospacedDigit() } icon: { Image(systemName: "heart.fill") }
                        .font(Self.islandFont)
                        .foregroundStyle(ActivityStyle.heart)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .font(Self.islandFont)
                        .foregroundStyle(ActivityStyle.exercise)
                }
            } compactTrailing: {
                ActivityClock(font: Self.islandFont) { clock(state) }
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(tint(state))
            }
            .keylineTint(tint(state))
        }
    }

    /// The Dynamic Island's compact face, shared by its heart rate and its clock.
    private static let islandFont = Font.system(size: 15, weight: .semibold)

    /// Green while working, yellow through the rest — the sheet's and the mini-player's colour language.
    private func tint(_ state: LiftActivityAttributes.ContentState) -> Color {
        state.isResting ? ActivityStyle.rest : ActivityStyle.exercise
    }

    /// "Set 2 — 8 x 60 kg", as the mini-player words it.
    private func statusLine(_ state: LiftActivityAttributes.ContentState) -> String {
        state.detail.map { "\(state.status) — \($0)" } ?? state.status
    }

    /// The heart rate, ALWAYS present, a dash when the strap is not reading: a readout that vanishes is
    /// indistinguishable from a missing feature — which is exactly how it was first reported.
    private func heartRate(_ state: LiftActivityAttributes.ContentState) -> some View {
        Label {
            Text(state.bpm.map(String.init) ?? "—").monospacedDigit()
        } icon: {
            Image(systemName: "heart.fill")
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(state.bpm == nil ? ActivityStyle.secondary : ActivityStyle.heart)
    }

    private func lockScreen(_ state: LiftActivityAttributes.ContentState) -> some View {
        // The Clock timer banner's order — the control on the left in the session's green, the clock on the
        // right — so the words get the middle (Utku, 21 Sep 2026: "the writings are usually cut too quick").
        HStack(spacing: 12) {
            ActivityControl(intent: LiftSetDoneIntent(), symbol: "checkmark", label: "Next",
                            tint: ActivityStyle.exercise)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.exercise)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(statusLine(state))
                    .font(.system(size: 15))
                    .foregroundStyle(ActivityStyle.secondary)
                // The set coming up, arriving pre-localized from the app. The set number comes before the
                // exercise, so the tail truncation a long name needs cuts the name and keeps the number.
                Text(state.next)
                    .font(.system(size: 13))
                    .foregroundStyle(ActivityStyle.secondary)
                    .truncationMode(.tail)
            }
            .lineLimit(1)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 0) {
                ActivityClock(template: "0:00", font: .system(size: 30, weight: .semibold)) { clock(state) }
                heartRate(state)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    /// Counts DOWN through a rest (the number you act on) and UP through a set, both self-ticking.
    ///
    /// Both branches use `Text(timerInterval:)`, which is the API widgets are given for a clock that
    /// advances without the app pushing. `Text(date, style: .timer)` looks equivalent and is not: on
    /// the Lock Screen it rendered "25 minutes" — a rounded, prose duration — where a gym timer has
    /// to read 25:02.
    ///
    /// A rest that is over reads 0:00 and stays there, as the mini-player does
    /// (`LiftSessionEngine.restRemaining` floors at zero); a clock climbing from zero on the Lock Screen
    /// read as a new timer rather than a finished rest (gym session, 16 Sep 2026). The countdown's range
    /// therefore starts at the REST'S start, not at `.now`: a widget re-rendered after the end still gets
    /// a range that is entirely past, which `Text(timerInterval:)` shows as its end value. A rest with no
    /// length shows the same 0:00. A working set counts up from its start; a zero-length range would
    /// render nothing, so that end is pushed a day out — well beyond any session.
    private func clock(_ state: LiftActivityAttributes.ContentState) -> some View {
        Group {
            if let ends = state.restEndsAt {
                if ends > state.stageStartedAt {
                    Text(timerInterval: state.stageStartedAt...ends, countsDown: true)
                } else {
                    Text(verbatim: "0:00")
                }
            } else {
                Text(timerInterval: state.stageStartedAt...state.stageStartedAt.addingTimeInterval(86_400),
                     countsDown: false)
            }
        }
        .foregroundStyle(tint(state))
    }
}
