import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for a strap history sync — the Lock Screen banner and the Dynamic Island, on the same card as
/// NOOP's other banners: the sync glyph on its disc, what the sync has done in one line (the strap's backlog
/// under it when it reported one), and the elapsed time while it runs.
///
/// No progress bar, because there is no total to draw one against (see `SyncActivityAttributes`).
struct SyncLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SyncActivityAttributes.self) { context in
            HStack(spacing: 12) {
                ActivityDisc(symbol: glyph(context.state.phase), tint: tint(context.state.phase))
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.state.status)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    if let detail = context.state.detail {
                        Text(detail)
                            .font(.system(size: 15))
                            .foregroundStyle(ActivityStyle.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if isActive(context.state.phase) {
                    elapsed(since: context.state.startedAt)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ActivityStyle.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .activityCard()
        } dynamicIsland: { context in
            // ONE line, deliberately. iOS shows the expanded layout for a few seconds whenever an activity
            // starts and offers no way to start compact, so the only lever on that flash is how tall the
            // expanded layout is: no bottom or centre region, so it is a short pill rather than a card.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(context.state.status) } icon: {
                        Image(systemName: glyph(context.state.phase))
                            .foregroundStyle(tint(context.state.phase))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isActive(context.state.phase) {
                        elapsed(since: context.state.startedAt)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ActivityStyle.secondary)
                            .padding(.trailing, 4)
                    }
                }
            } compactLeading: {
                // One symbol, no label, so the compact pill stays as narrow as the live-HR one.
                Image(systemName: glyph(context.state.phase))
                    .foregroundStyle(tint(context.state.phase))
            } compactTrailing: {
                // "…" until the first chunk lands; then the chunk count, the only live number a sync has.
                // Never "0", so the island never claims progress the strap has not made.
                Text(context.state.chunks > 0 ? "\(context.state.chunks)" : "…")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint(context.state.phase))
            } minimal: {
                Image(systemName: glyph(context.state.phase))
                    .foregroundStyle(tint(context.state.phase))
            }
            .keylineTint(tint(context.state.phase))
        }
    }
}

private func isActive(_ phase: SyncActivityAttributes.Phase) -> Bool {
    phase == .connecting || phase == .syncing
}

/// Counts up on its own from the run's start; no pushes needed to keep it moving.
private func elapsed(since start: Date) -> some View {
    ActivityClock(font: .system(size: 17, weight: .semibold)) {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
    }
}

/// The sync arrows for both active phases (the "…" vs count carries the difference, keeping the pill's width
/// steady), a tick once done, a warning when the strap went quiet.
private func glyph(_ phase: SyncActivityAttributes.Phase) -> String {
    switch phase {
    case .connecting, .syncing: return "arrow.triangle.2.circlepath"
    case .done: return "checkmark"
    case .interrupted: return "exclamationmark"
    }
}

private func tint(_ phase: SyncActivityAttributes.Phase) -> Color {
    phase == .interrupted ? ActivityStyle.problem : ActivityStyle.ok
}
