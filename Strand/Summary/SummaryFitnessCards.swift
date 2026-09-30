//  SummaryFitnessCards.swift
//  NOOP · Summary home — the top of the page as Apple Fitness sets its Summary (iOS 26): the Activity Rings
//  card (three wide rings on the leading side, each ring's name over its coloured figure on the trailing
//  side) and a pair of square tiles under it that the user chooses (Fitness's Step Count / Step Distance:
//  title with a grey chevron disc, "Today", the figure in the metric's hue, a columned chart). Everything
//  under them is Health's Summary.

import SwiftUI
import StrandDesign

// MARK: - Rings card

/// Fitness's "Activity Rings" card, drawn for Charge / Effort / Rest, without its title. Each figure taps
/// through to its page, the rings to the first one's.
struct SummaryFitnessRingsCard: View {
    let rings: [ActivityRing]
    let rows: [SummaryRingRow]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var unitSize: CGFloat = 19

    var body: some View {
        // Fitness titles this card; here the rings and their names speak for themselves.
        SummaryCard(insets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            if dts.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    ringsLink
                    figures
                }
            } else {
                HStack(alignment: .center, spacing: 24) {
                    ringsLink.padding(.leading, 4)
                    figures
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private var ringsLink: some View {
        let rings = ActivityRingsView(rings: rings, diameter: 140, fitness: true,
                                      // Fitness is dark-only and sets the rings straight on its card; on a
                                      // white card they keep Health's black disc.
                                      disc: colorScheme == .light)
        if let route = rows.first?.route {
            NavigationLink(value: route) { rings }.buttonStyle(.plain)
        } else {
            rings
        }
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            ForEach(rows) { row in
                NavigationLink(value: row.route) { figure(row) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func figure(_ row: SummaryRingRow) -> some View {
        let tint = StrandPalette.text(for: row.color)
        return VStack(alignment: .leading, spacing: -2.5) {
            Text(row.title)
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: row.value)
                    .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                if !row.unit.isEmpty {
                    Text(verbatim: row.unit)
                        .font(.system(size: unitSize, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if let caption = row.caption {
                Text(caption)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tiles

/// The two metrics the Fitness tiles show, stored as "a,b". Anything unreadable falls back to the pair a
/// fresh install gets; the two slots never hold the same metric.
enum SummaryTilePrefs {
    static let storageKey = "summary.tiles"
    static let defaults: [KeyMetric] = [.steps, .calories]

    /// Metrics a tile can show: every Key Metric except the three the rings already carry.
    static let choices: [KeyMetric] = KeyMetric.allCases.filter { ![.charge, .effort, .rest].contains($0) }

    static func decode(_ raw: String) -> [KeyMetric] {
        let picked = raw.split(separator: ",")
            .compactMap { KeyMetric(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { choices.contains($0) }
        guard picked.count == 2, picked[0] != picked[1] else { return defaults }
        return picked
    }

    /// Puts `metric` in `slot`; when the other tile already shows it, the two swap.
    static func replacing(_ raw: String, slot: Int, with metric: KeyMetric) -> String {
        var tiles = decode(raw)
        guard tiles.indices.contains(slot), choices.contains(metric) else { return encode(tiles) }
        if let other = tiles.firstIndex(of: metric), other != slot {
            tiles.swapAt(slot, other)
        } else {
            tiles[slot] = metric
        }
        return encode(tiles)
    }

    static func encode(_ tiles: [KeyMetric]) -> String { tiles.map(\.rawValue).joined(separator: ",") }
}

/// One Fitness Summary tile: title and chevron disc, the stamp, the figure in the metric's hue, and the
/// week in columns under it. Long-press offers the other metrics ("Change Card").
struct SummaryFitnessTile: View {
    let metric: KeyMetric
    let reading: SummaryMetricReading
    /// One slot per day, oldest → newest (nil where the day has no value).
    let week: [Double?]
    let weekKeys: [String]
    let stamp: String?
    let onChange: (KeyMetric) -> Void

    @Environment(\.summaryCardFill) private var cardFill
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title) private var unitSize: CGFloat = 20

    var body: some View {
        NavigationLink(value: reading.route) {
            SummaryCard(insets: EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(metric.title)
                            .font(StrandFont.pro(17, weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        chevronDisc
                    }
                    Text(verbatim: stamp ?? " ")
                        .font(StrandFont.pro(13))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.top, 10.7)
                    figure
                        .padding(.top, -0.3)
                    SummaryTileChart(values: week, dayKeys: weekKeys, style: reading.chart,
                                     tint: metric.healthTint)
                        .frame(height: 83)
                        .padding(.top, 8.3)
                        .padding(.trailing, -1)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Picker(selection: Binding(get: { metric }, set: onChange)) {
                ForEach(SummaryTilePrefs.choices) { choice in
                    Label(choice.title, systemImage: choice.customizationIcon).tag(choice)
                }
            } label: {
                Label("Change Card", systemImage: "arrow.triangle.2.circlepath")
            }
            .pickerStyle(.menu)
        }
        .accessibilityElement(children: .combine)
    }

    private var figure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(verbatim: reading.value)
                .font(.system(size: valueSize, weight: .medium, design: .rounded))
            if !reading.unit.isEmpty {
                Text(verbatim: reading.unit)
                    .font(.system(size: unitSize, weight: .medium, design: .rounded))
            }
        }
        .foregroundStyle(reading.hasValue ? StrandPalette.text(for: metric.healthTint) : StrandPalette.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// Fitness's grey disc with the chevron punched out in the card's own colour.
    private var chevronDisc: some View {
        Circle()
            .fill(StrandPalette.fitnessTileDisc)
            .frame(width: 17, height: 17)
            .overlay {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(cardFill)
                    .offset(x: 0.5)
            }
            .padding(.trailing, -3)
            .accessibilityHidden(true)
    }
}

/// The tile's chart: one column per day between thin full-height rules, the day's letter at the foot of
/// each rule, and the day's value as a bar (totals) or a dot (readings, scaled to the week's own range).
struct SummaryTileChart: View {
    let values: [Double?]
    let dayKeys: [String]
    let style: SummaryMetricReading.ChartStyle
    let tint: Color

    /// The plot's share of the height; the band under it carries the day letters.
    private static let plotFraction: CGFloat = 68.0 / 83.0

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let slot = geo.size.width / CGFloat(count)
            let plot = geo.size.height * Self.plotFraction
            let rule: CGFloat = 0.67
            ZStack(alignment: .topLeading) {
                ForEach(0...count, id: \.self) { i in
                    Rectangle()
                        .fill(StrandPalette.fitnessTileRule)
                        .frame(width: rule, height: geo.size.height)
                        .offset(x: min(CGFloat(i) * slot, geo.size.width - rule))
                }
                ForEach(Array(dayKeys.enumerated()), id: \.offset) { i, key in
                    Text(verbatim: Self.letter(key))
                        .font(StrandFont.pro(11, weight: .medium))
                        .foregroundStyle(StrandPalette.fitnessTileRule)
                        .fixedSize()
                        .offset(x: CGFloat(i) * slot + 5, y: plot + 1)
                }
                marks(slot: slot, plot: plot)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func marks(slot: CGFloat, plot: CGFloat) -> some View {
        let present = values.compactMap { $0 }
        switch style {
        case .bars:
            let top = max(present.max() ?? 0, 0)
            let width = min(slot * 0.36, 7)
            ForEach(Array(values.enumerated()), id: \.offset) { i, value in
                if let value, top > 0, value > 0 {
                    let height = max(2, plot * CGFloat(value / top) * 0.92)
                    RoundedRectangle(cornerRadius: min(1.5, width / 2), style: .continuous)
                        .fill(tint)
                        .frame(width: width, height: height)
                        .offset(x: CGFloat(i) * slot + (slot - width) / 2, y: plot - height)
                }
            }
        case .line:
            let low = present.min() ?? 0, high = present.max() ?? 0
            let span = max(high - low, abs(high) * 0.02, 0.0001)
            let dot: CGFloat = 7
            ForEach(Array(values.enumerated()), id: \.offset) { i, value in
                if let value {
                    // The week's range fills the middle of the plot, so a flat week sits halfway up.
                    let unit = present.count > 1 && high > low ? (value - low) / span : 0.5
                    let y = plot * (0.85 - 0.7 * CGFloat(unit))
                    Circle()
                        .fill(tint)
                        .frame(width: dot, height: dot)
                        .offset(x: CGFloat(i) * slot + (slot - dot) / 2, y: y - dot / 2)
                }
            }
        }
    }

    /// "П", "В", "С"… — the day's one-letter weekday in the app language.
    static func letter(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar.current
        cal.locale = AppLanguage.activeLocale
        guard parts.count == 3,
              let date = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return "" }
        let weekday = cal.component(.weekday, from: date)
        return cal.veryShortStandaloneWeekdaySymbols[weekday - 1]
    }
}

// MARK: - Health data glyph

/// Health's "Show All Health Data" glyph: a grey rounded square with a small pink heart in its corner.
struct HealthDataGlyph: View {
    var size: CGFloat = 19

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .strokeBorder(StrandPalette.healthDataGlyph, lineWidth: size * 0.1)
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(StrandPalette.healthHeart)
                    .padding(.top, size * 0.2)
                    .padding(.trailing, size * 0.2)
            }
            .accessibilityHidden(true)
    }
}
