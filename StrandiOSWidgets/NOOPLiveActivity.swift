import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for an active live-HR session — shown on the Lock Screen and in the Dynamic Island, on the
/// same near-black card as the workout banners: the heart on its red disc, the heart rate large, and the day's
/// Charge and Effort as two small columns.
struct NOOPLiveActivity: Widget {
    /// The heart rate to draw: none once iOS has marked the banner stale. Each push is fresh for 30 s
    /// (`LiveActivityController.staleAfter`) and NOOP re-pushes a steady number well inside that, so a stale banner
    /// means the readings stopped — the strap off the wrist, or out of reach — even while NOOP itself is asleep and
    /// cannot say so: iOS redraws the banner at the stale date on its own.
    static func shownBpm(_ context: ActivityViewContext<NOOPActivityAttributes>) -> Int? {
        context.isStale ? nil : context.state.bpm
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NOOPActivityAttributes.self) { context in
            HStack(spacing: 12) {
                ActivityDisc(symbol: "heart.fill", tint: ActivityStyle.heart)
                VStack(alignment: .leading, spacing: 0) {
                    // The Heart Rate app's own name for it: shorter than the session title, which it stands for.
                    Text("Heart Rate")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ActivityStyle.heart)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(Self.shownBpm(context).map(String.init) ?? "–")
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                stats(context.state, valueSize: 20)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .activityCard()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 10) {
                        ActivityDisc(symbol: "heart.fill", tint: ActivityStyle.heart, size: 44)
                        Text(Self.shownBpm(context).map(String.init) ?? "–")
                            .font(.system(size: 30, weight: .semibold))
                            .monospacedDigit()
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    stats(context.state, valueSize: 17)
                        .padding(.trailing, 4)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(ActivityStyle.heart)
            } compactTrailing: {
                Text(Self.shownBpm(context).map(String.init) ?? "–")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ActivityStyle.heart)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(ActivityStyle.heart)
            }
            .keylineTint(ActivityStyle.heart)
        }
    }

    /// Charge + Effort (#446), each value centred under its own label (#759), `fixedSize` so neither clips.
    private func stats(_ state: NOOPActivityAttributes.ContentState, valueSize: CGFloat) -> some View {
        HStack(spacing: 14) {
            if let r = state.recovery { stat("Charge", "\(r)%", valueSize) }
            if let e = state.effort { stat("Effort", "\(e)", valueSize) }
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String, _ valueSize: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(ActivityStyle.secondary)
            Text(value)
                .font(.system(size: valueSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .multilineTextAlignment(.center)
        .fixedSize()
    }
}
