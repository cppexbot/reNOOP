import WidgetKit
import SwiftUI
import StrandDesign

/// K10: A Lock Screen / Home Screen widget showing the stored Coach morning brief.
///
/// Design contract (see PRD-K10 + D8):
/// - The widget reads **stored** brief text from the App Group — it NEVER calls the network.
///   The brief is generated on a schedule by `CoachBriefScheduler` (K5) and mirrored into the
///   App Group via `publishToWidget`. The widget just displays whatever text is there.
/// - Tap → opens the Coach tab (via the app's URL scheme / deeplink).
/// - Supported families: `accessoryRectangular` (Lock Screen), `systemSmall` (Home Screen).
///   The Lock Screen accessory shows the first line; the Home Screen widget shows more.
struct CoachBriefEntry: TimelineEntry {
    let date: Date
    let briefText: String?
    let briefDate: Date?
    /// The app's Coach master switch (`noop.coachEnabled`), mirrored into the App Group. Off: the widget
    /// shows nothing of the Coach.
    var coachEnabled = true
}

struct CoachBriefProvider: TimelineProvider {
    /// App Group keys — must match `CoachBriefScheduler.K.widgetBriefKey` / `.widgetBriefDateKey`.
    private static let briefKey = "coachBrief.widgetText"
    private static let briefDateKey = "coachBrief.widgetDate"
    private static let coachEnabledKey = "coachBrief.coachEnabled"

    func placeholder(in context: Context) -> CoachBriefEntry {
        CoachBriefEntry(
            date: Date(),
            briefText: "Recovery is strong today — consider a higher-intensity session this afternoon.",
            briefDate: Date()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CoachBriefEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CoachBriefEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 30 minutes — the app pushes a reload via WidgetCenter when a new brief is
        // published, so this is just a safety net for when the app isn't running.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> CoachBriefEntry {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName)
        let text = defaults?.string(forKey: CoachBriefProvider.briefKey)
        let date = defaults?.object(forKey: CoachBriefProvider.briefDateKey) as? Date
        let enabled = defaults?.object(forKey: CoachBriefProvider.coachEnabledKey) as? Bool ?? true
        return CoachBriefEntry(date: Date(), briefText: enabled ? text : nil, briefDate: enabled ? date : nil,
                               coachEnabled: enabled)
    }
}

struct CoachBriefWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CoachBriefEntry

    var body: some View {
        if !entry.coachEnabled {
            // Coach switched off in the app: an empty glyph, no copy.
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityLabel(Text("Coach is off"))
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        default:
            small
        }
    }

    // MARK: - Lock Screen: accessoryRectangular

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StrandPalette.healthBody)
                Text("Coach")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StrandPalette.healthBody)
                Spacer(minLength: 0)
                if let date = entry.briefDate {
                    Text(date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Text(briefDisplay)
                .font(.system(size: 11))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Lock Screen: accessoryInline

    private var inline: some View {
        Text(briefOneLine)
    }

    // MARK: - Home Screen: systemSmall

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(StrandPalette.healthBody)
                Text("Coach Brief")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.healthBody)
                Spacer()
            }
            if entry.briefText == nil {
                Text("No brief yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(StrandPalette.textTertiary)
            } else {
                Text(briefDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(5)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let date = entry.briefDate {
                Text(date, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(12)
    }

    // MARK: - Text helpers

    /// The full brief text for the widget body, or a placeholder when there's no brief.
    private var briefDisplay: String {
        entry.briefText ?? "No brief available."
    }

    /// One-line summary for the inline accessory (capped at ~100 chars).
    private var briefOneLine: String {
        guard let text = entry.briefText else { return "Coach: no brief yet" }
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 100 else { return "Coach: \(trimmed)" }
        let cut = trimmed.index(trimmed.startIndex, offsetBy: 100)
        return "Coach: \(trimmed[..<cut].trimmingCharacters(in: .whitespaces))…"
    }
}

struct CoachBriefWidget: Widget {
    static let kind = "CoachBriefWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CoachBriefProvider()) { entry in
            if #available(iOS 17.0, *) {
                CoachBriefWidgetView(entry: entry)
                    .containerBackground(.background, for: .widget)
            } else {
                CoachBriefWidgetView(entry: entry)
                    .padding()
                    .background(.background)
            }
        }
        .configurationDisplayName("Coach Brief")
        .description("Today's coaching brief at a glance. Tap to open Coach.")
        .supportedFamilies([
            .systemSmall,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}
