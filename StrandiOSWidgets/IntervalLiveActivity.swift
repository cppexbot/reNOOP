import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for the interval timer, laid out as the iOS 26 Clock timer banner: the pause control in the
/// phase's hue on the left, the phase and round beside a light countdown on the right; in the Dynamic Island a
/// progress ring and the countdown. The countdown is `Text(timerInterval:)` and ticks without the app.
struct IntervalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IntervalActivityAttributes.self) { context in
            HStack(alignment: .center) {
                control(context.state, size: 46)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(context.state.label)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    countdown(context.state, font: .system(size: 46, weight: .light))
                }
                .foregroundStyle(tint(context.state))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityCard()
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    control(state, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(state.label)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        countdown(state, font: .system(size: 36, weight: .light))
                    }
                    .foregroundStyle(tint(state))
                    .padding(.trailing, 4)
                }
            } compactLeading: {
                ring(state)
            } compactTrailing: {
                ActivityClock(font: .system(size: 15, weight: .semibold)) { clockText(state) }
                    .foregroundStyle(tint(state))
            } minimal: {
                ring(state)
            }
            .keylineTint(tint(state))
        }
    }

    /// Work in the stand hue, rest in the exercise green — the running screen's colours.
    private func tint(_ state: IntervalActivityAttributes.ContentState) -> Color {
        state.isWork ? ActivityStyle.stand : ActivityStyle.exercise
    }

    private func control(_ state: IntervalActivityAttributes.ContentState, size: CGFloat) -> some View {
        ActivityControl(intent: IntervalsToggleIntent(),
                        symbol: state.pausedRemaining == nil ? "pause.fill" : "play.fill",
                        label: state.pausedRemaining == nil ? "Pause" : "Resume",
                        tint: tint(state), size: size)
    }

    private func countdown(_ state: IntervalActivityAttributes.ContentState, font: Font) -> some View {
        ActivityClock(template: "0:00", font: font) { clockText(state) }
    }

    /// The phase's countdown, ticking by itself while running and frozen while paused.
    @ViewBuilder
    private func clockText(_ state: IntervalActivityAttributes.ContentState) -> some View {
        if let paused = state.pausedRemaining {
            Text(verbatim: activityClockText(paused))
        } else {
            Text(timerInterval: state.phaseStartedAt...state.phaseEndsAt, countsDown: true)
        }
    }

    /// The phase's progress as a ring, as the Clock timer's island shows it.
    @ViewBuilder
    private func ring(_ state: IntervalActivityAttributes.ContentState) -> some View {
        Group {
            if let paused = state.pausedRemaining {
                let total = max(1, state.phaseEndsAt.timeIntervalSince(state.phaseStartedAt))
                ProgressView(value: Double(paused), total: total)
            } else {
                ProgressView(timerInterval: state.phaseStartedAt...state.phaseEndsAt, countsDown: true,
                             label: { EmptyView() }, currentValueLabel: { EmptyView() })
            }
        }
        .progressViewStyle(.circular)
        .tint(tint(state))
        .frame(width: 20, height: 20)
    }
}
