//  SummaryCards.swift
//  NOOP · Summary home — the card building blocks (Apple Health Summary idiom).
//
//  Solid rounded cards on the grouped canvas: a small tinted icon + title row with a chevron, then one
//  bold value and at most a caption and a mini chart. Glass is reserved for floating controls.

import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Container + section header

struct SummaryCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.summaryCard,
                        in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }

    static var radius: CGFloat { 22 }
}

struct SummarySectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(StrandFont.rounded(22))
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, NoopMetrics.space4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Icon + tinted title on the left, chevron on the right — the header row every Summary card shares.
struct SummaryCardTitleRow: View {
    let icon: String
    let title: String
    let tint: Color
    var trailing: String? = nil
    /// Off for a card that opens nothing.
    var chevron = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(StrandFont.headline)
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

// MARK: - Rings card

struct SummaryRingRow: Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let caption: String?
    let color: Color
    let route: TabRoute
}

/// The rings as the Health Summary's pinned Activity card (flame + "Activity"): a tinted title row with its stamp, then each
/// ring's figure in its own column (coloured label, bold value, grey unit) split by hairlines, and the
/// rings themselves small at the trailing edge. Each column taps through to its own page.
struct SummaryRingsCard: View {
    let rings: [ActivityRing]
    let rows: [SummaryRingRow]
    var stamp: String? = nil

    var body: some View {
        SummaryCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Activity")
                        .font(StrandFont.headline)
                    Spacer(minLength: 8)
                    if let stamp {
                        Text(stamp)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(StrandPalette.activityTitle)
                .accessibilityAddTraits(.isHeader)

                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(StrandPalette.hairline)
                                .frame(width: NoopMetrics.hairlineWidth, height: 40)
                                .padding(.horizontal, 12)
                        }
                        NavigationLink(value: row.route) { column(row) }
                            .buttonStyle(.plain)
                    }
                    Spacer(minLength: 10)
                    ActivityRingsView(rings: rings, diameter: 64)
                }
            }
        }
    }

    private func column(_ row: SummaryRingRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.title)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(row.color)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: row.value)
                    .font(StrandFont.number(24, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if !row.unit.isEmpty {
                    Text(verbatim: row.unit)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if let caption = row.caption {
                Text(caption)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pinned metric card

struct SummaryMetricCard: View {
    let metric: KeyMetric
    let reading: SummaryMetricReading
    let series: [Double]
    /// "Today" / "Yesterday" / a date: when the value was measured (`SummaryStamp`).
    var stamp: String? = nil

    var body: some View {
        NavigationLink(value: reading.route) {
            SummaryCard {
                VStack(alignment: .leading, spacing: 10) {
                    SummaryCardTitleRow(icon: metric.customizationIcon, title: metric.title,
                                        tint: metric.healthTint, trailing: stamp)
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(verbatim: reading.value)
                                    .font(StrandFont.number(24, weight: .bold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                if !reading.unit.isEmpty {
                                    Text(verbatim: reading.unit)
                                        .font(StrandFont.subhead.weight(.semibold))
                                        .foregroundStyle(StrandPalette.textSecondary)
                                }
                            }
                            if let caption = reading.caption {
                                Text(caption)
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        SummaryMiniChart(values: series, style: reading.chart, tint: metric.healthTint)
                            .frame(width: 72, height: 30)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// A week at a glance: a line for continuous vitals, bars for daily totals. Draws nothing under two points.
struct SummaryMiniChart: View {
    let values: [Double]
    let style: SummaryMetricReading.ChartStyle
    let tint: Color

    var body: some View {
        if values.count >= 2 {
            switch style {
            case .line:
                Sparkline(values: values, gradient: Gradient(colors: [tint.opacity(0.55), tint]),
                          lineWidth: 2, showsArea: false, showsHead: true, showsHover: false)
            case .bars:
                bars
            }
        } else {
            Color.clear
        }
    }

    private var bars: some View {
        let top = values.max() ?? 0
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, v in
                    Capsule()
                        .fill(tint.opacity(index == values.count - 1 ? 1 : 0.45))
                        .frame(height: max(3, geo.size.height * (top > 0 ? v / top : 0)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Highlight card

struct SummaryHighlightCard: View {
    let highlight: SummaryHighlight
    /// The last seven days of Effort, drawn under a training-variety highlight (which has no figure pair).
    var effortWeek: [Double] = []

    var body: some View {
        NavigationLink(value: TabRoute.metric(highlight.routeKey)) {
            SummaryCard {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryCardTitleRow(icon: icon, title: highlight.title, tint: tint)
                    Text(highlight.sentence)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let figures = figures {
                        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                        figures
                    } else if highlight.key == "monotony", effortWeek.count >= 2 {
                        // The claim is "every day looks alike": seven near-equal bars show it at a glance,
                        // where the monotony index itself is a number nobody reads.
                        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                        weekBars(effortWeek)
                        Text("Effort, last 7 days")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// The two figures a Health highlight sets under its sentence: the latest reading and the baseline it
    /// was read against (or the 7-day against the 28-day load). Monotony has no pair to show.
    private var figures: HighlightFigures? {
        switch highlight.evidenceData {
        case .metric(let value, let baseline, let unit, let decimals):
            // The engine's unit is a locale-free key ("ms", "bpm", "br/min"); the catalogue translates it.
            return HighlightFigures(leftTitle: String(localized: "Latest"), left: ReadinessCopy.number(value, decimals: decimals),
                                    rightTitle: String(localized: "Your Normal"), right: ReadinessCopy.number(baseline, decimals: decimals),
                                    unit: String(localized: String.LocalizationValue(unit)),
                                    leftValue: value, rightValue: baseline, tint: tint)
        case .trainingLoad(let acute, let chronic):
            return HighlightFigures(leftTitle: String(localized: "Last 7 Days"), left: ReadinessCopy.number(acute, decimals: 1),
                                    rightTitle: String(localized: "Last 28 Days"), right: ReadinessCopy.number(chronic, decimals: 1),
                                    unit: "", leftValue: acute, rightValue: chronic, tint: tint)
        case .monotony, .none:
            return nil
        }
    }

    /// A week of daily bars across the card, today's solid and the rest faded — Health's highlight chart.
    private func weekBars(_ values: [Double]) -> some View {
        let top = max(values.max() ?? 0, 1e-6)
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, v in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(index == values.count - 1 ? 1 : 0.4))
                    .frame(width: 22, height: max(4, 64 * CGFloat(v / top)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 64, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var icon: String {
        switch highlight.key {
        case "hrv": return "waveform.path.ecg"
        case "rhr": return "heart.fill"
        case "respRate": return "lungs.fill"
        default: return "figure.run"
        }
    }

    private var tint: Color {
        switch highlight.key {
        case "hrv": return KeyMetric.hrv.healthTint
        case "rhr": return KeyMetric.restingHr.healthTint
        case "respRate": return KeyMetric.respiratory.healthTint
        default: return StrandPalette.summaryEffortRing
        }
    }
}

/// A Health highlight's figure pair: the tinted reading on the left, the grey one it is read against on the
/// right, and a bar for each under them.
struct HighlightFigures: View {
    let leftTitle: String
    let left: String
    let rightTitle: String
    let right: String
    let unit: String
    let leftValue: Double
    let rightValue: Double
    let tint: Color

    var body: some View {
        let top = max(leftValue, rightValue, 1e-6)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                figure(leftTitle, left, tint: tint)
                Spacer()
                figure(rightTitle, right, tint: StrandPalette.textSecondary, trailing: true)
            }
            VStack(alignment: .leading, spacing: 5) {
                bar(leftValue / top, tint: tint)
                bar(rightValue / top, tint: StrandPalette.textTertiary.opacity(0.45))
            }
            .accessibilityHidden(true)
        }
    }

    private func figure(_ title: String, _ value: String, tint: Color, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(StrandFont.number(22, weight: .bold))
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(verbatim: unit)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private func bar(_ fraction: Double, tint: Color) -> some View {
        GeometryReader { geo in
            Capsule().fill(tint)
                .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, fraction)))))
        }
        .frame(height: 8)
    }
}

// MARK: - Strap status

/// The active device's link state as quiet text in the Summary's bar, the way a Health card shows
/// its time: battery glyph + percent, "Syncing", or "Not connected". Tap → Devices. Resolves through the
/// `StrapBatteryDisplay`, the one place that decides what the link state may honestly claim.
struct SummaryStrapStatus: View {
    /// A bar item: glyphs and the battery figure only, the words left to VoiceOver.
    var compact = false

    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter
    @State private var syncing = false

    private var display: StrapBatteryDisplay {
        .resolve(activeIsWhoop: live.activeIsWhoop, connected: live.connected,
                 batteryPct: live.batteryPct, charging: live.charging,
                 ringPct: live.ouraBatteryPct, ringCharging: live.ouraWearState == .charging)
    }

    var body: some View {
        Group {
            if case .notActiveDevice = display {
                EmptyView()
            } else {
                Button { router.openDevices() } label: { label }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(accessibility))
            }
        }
        .debouncedSyncSignal(live.backfilling, into: $syncing)
    }

    @ViewBuilder private var label: some View {
        HStack(spacing: 5) {
            if syncing {
                ProgressView().controlSize(.mini)
                if !compact { Text("Syncing") }
            } else {
                switch display {
                case .offline, .notActiveDevice:
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    if !compact { Text("Not connected") }
                case .pending(let charging):
                    Image(systemName: charging ? "battery.100percent.bolt" : "battery.50percent")
                case .charge(let pct, let charging, _):
                    Image(systemName: charging ? "battery.100percent.bolt" : Self.batterySymbol(pct))
                    Text(verbatim: "\(Int(pct.rounded()))%")
                        .monospacedDigit()
                }
            }
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textSecondary)
        .lineLimit(1)
    }

    private var accessibility: String {
        if syncing { return String(localized: "Syncing strap history") }
        switch display {
        case .offline, .notActiveDevice: return String(localized: "Strap not connected")
        case .pending: return String(localized: "Strap")
        case .charge(let pct, _, let isRing):
            let n = Int(pct.rounded())
            return isRing ? String(localized: "Ring battery \(n) percent") : String(localized: "Strap battery \(n) percent")
        }
    }

    static func batterySymbol(_ pct: Double) -> String {
        switch pct {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Day pager

/// ‹ day › — the one place a screen names the day (or night) it shows. The arrows step through the days
/// on record; the title opens a calendar. Shared by the Summary and the Sleep page so both move the same way.
struct DayPager<Picker: View>: View {
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    var backLabel: LocalizedStringKey = "Previous day"
    var forwardLabel: LocalizedStringKey = "Next day"
    @Binding var showPicker: Bool
    @ViewBuilder var picker: Picker

    var body: some View {
        HStack(spacing: 4) {
            arrow("chevron.left", enabled: canGoBack, action: onBack)
                .accessibilityLabel(Text(backLabel))
            Spacer(minLength: 0)
            Button { showPicker = true } label: {
                Text(title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker) { picker }
            Spacer(minLength: 0)
            arrow("chevron.right", enabled: canGoForward, action: onForward)
                .accessibilityLabel(Text(forwardLabel))
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(StrandMotion.interactive) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? StrandPalette.accent : StrandPalette.textTertiary)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
