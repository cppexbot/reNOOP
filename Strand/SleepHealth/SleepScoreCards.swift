//  SleepScoreCards.swift
//  NOOP · Sleep — the cards of the Sleep page, set as the iOS 26 Health app's Sleep Score page: the score
//  card (ring, word, the parts' points, one sentence), the Sleep and Vitals tiles side by side, and the
//  Sleep: Stages highlight. Measured off Health in the simulator at 3×.
//
//  Presentation only: the score, the night and the vitals arrive resolved from the caller.

import SwiftUI
import StrandDesign

/// A card's title in its hue with a chevron at the far end, as Health heads its Sleep Score cards.
struct SleepCardHeader: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(StrandFont.headline)
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(StrandFont.pro(17, weight: .semibold))
                .foregroundStyle(StrandPalette.healthChevron)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Score card

struct SleepScoreCard: View {
    let score: SleepScore

    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 13

    var body: some View {
        let stacked = dts.isAccessibilitySize
        let head = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
        SummaryCard(insets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 0) {
                SleepCardHeader(title: String(localized: "Sleep Score"), tint: StrandPalette.sleepScoreTitle)
                head {
                    SleepScoreRing(score: score)
                        .frame(width: 111, height: 111)
                    Text(SleepScore.word(score.value))
                        .font(StrandFont.pro(34, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(stacked ? 2 : 1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.top, 11)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SleepScoreRing.legendOrder, id: \.self) { part in
                        if let earned = score.parts.first(where: { $0.part == part }) { legendRow(earned) }
                    }
                }
                .padding(.top, 4)
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    .padding(.vertical, 12)
                Text(score.sentence)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "● Duration: 50 of 50" — the name bold, the points plain. An imported score's parts carry no points.
    private func legendRow(_ part: SleepScore.PartScore) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(SleepScoreRing.color(part.part))
                .frame(width: dotSize, height: dotSize)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + dotSize * 0.33 }
            if let points = part.points {
                Text("\(part.part.cardLabel):").fontWeight(.semibold)
                    + Text(verbatim: " ") + Text("\(points) of \(part.part.maxPoints)")
            } else {
                Text(part.part.cardLabel).fontWeight(.semibold)
            }
        }
        .font(StrandFont.body)
        .foregroundStyle(StrandPalette.textPrimary)
    }
}

// MARK: - Tiles

/// One of the two tiles under the score card: a title with its chevron, then the tile's picture.
struct SleepPageTile<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        SummaryCard(insets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 0) {
                SleepCardHeader(title: title, tint: tint)
                Spacer(minLength: 0)
                content
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Health's Sleep tile: the night's stages across the tile and the time asleep under them in the Sleep hue.
struct SleepDurationTile: View {
    let intervals: [SleepInterval]
    let onset: Date
    let asleepMinutes: Double

    var body: some View {
        SleepPageTile(title: String(localized: "Sleep"), tint: StrandPalette.sleepScoreTitle) {
            VStack(alignment: .leading, spacing: 10) {
                SleepStagesChart(intervals: intervals, onset: onset, compact: true)
                    .frame(height: 104)
                    .padding(.top, 6)
                SleepTileDuration(minutes: asleepMinutes)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "19 h 51 min" all in the Sleep hue, the figures bold and the units a size down, as the tile sets it.
struct SleepTileDuration: View {
    let minutes: Double
    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 21

    var body: some View {
        let p = SleepFormat.parts(minutes: minutes)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if p.hours > 0 {
                figure("\(p.hours)")
                unit(String(localized: "sleep.unit.hr", defaultValue: "hr"))
            }
            if p.minutes > 0 || p.hours == 0 {
                figure("\(p.minutes)")
                unit(String(localized: "sleep.unit.min", defaultValue: "min"))
            }
        }
        .foregroundStyle(StrandPalette.sleepScoreTitle)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func figure(_ s: String) -> some View {
        Text(verbatim: s).font(StrandFont.pro(size, weight: .bold))
    }

    private func unit(_ s: String) -> some View {
        Text(verbatim: s).font(StrandFont.pro(size * 0.8, weight: .semibold)).padding(.trailing, 2)
    }
}

/// Health's Vitals tile. While the ranges are being learned: one capsule per night still needed (the
/// nights on record filled) and how many are left. Once they exist: the typical band between the high and
/// low zones, a ring per vital where the night fell, and "Typical" or the count of outliers.
struct SleepVitalsTile: View {
    let vitals: SleepVitals

    var body: some View {
        SleepPageTile(title: String(localized: "vitals.title", defaultValue: "Vitals"), tint: StrandPalette.vitalsTypical) {
            if vitals.nightsRemaining > 0 { waiting } else { reading }
        }
        .accessibilityElement(children: .combine)
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(0..<SleepVitals.nightsNeeded, id: \.self) { i in
                    if i > 0 { Spacer(minLength: 4) }
                    Capsule()
                        .strokeBorder(StrandPalette.vitalsPending, lineWidth: 2)
                        .background(Capsule().fill(i < vitals.nightsRecorded ? StrandPalette.vitalsTypicalBand : .clear))
                        .frame(width: 13.5)
                }
            }
            .frame(height: 67)
            .padding(.top, 12)
            .accessibilityHidden(true)
            HStack(spacing: 8) {
                Text(verbatim: "\(vitals.nightsRemaining)")
                    .font(StrandFont.pro(36, weight: .light))
                Text(verbatim: Self.sessionsWords(vitals.nightsRemaining))
                    .font(StrandFont.pro(15, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    /// "sleep sessions until results" in the count's plural form, without the count: the tile sets the
    /// number large beside the words.
    static func sessionsWords(_ count: Int) -> String {
        String(localized: "\(count) sleep sessions until results")
            .replacingOccurrences(of: "\(count)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 10) {
            SleepVitalsBand(readings: vitals.readings)
                .frame(height: 92)
                .padding(.top, 10)
                .accessibilityHidden(true)
            SleepVitalsVerdict(outliers: vitals.outliers, size: 21)
        }
    }
}

/// "Typical" in the Vitals hue, or "2 outliers" in the outlier hue.
struct SleepVitalsVerdict: View {
    let outliers: Int
    let size: CGFloat

    var body: some View {
        Group {
            if outliers == 0 {
                Text(String(localized: "vitals.typical", defaultValue: "Typical"))
                    .foregroundStyle(StrandPalette.vitalsTypical)
            } else {
                Text("\(outliers) outliers")
                    .foregroundStyle(StrandPalette.vitalsOutlier)
            }
        }
        .font(StrandFont.pro(size, weight: .semibold))
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The tile's picture: a grey high zone, the typical band, a grey low zone, and one ring per vital in its
/// own slot, set by where the night fell in its range (in a grey zone, and in the outlier hue, when it
/// fell outside).
struct SleepVitalsBand: View {
    let readings: [SleepVitals.Reading]

    var body: some View {
        Canvas { ctx, size in
            let zone: CGFloat = 6, gap: CGFloat = 6
            let band = CGRect(x: 0, y: zone + gap, width: size.width, height: size.height - 2 * (zone + gap))
            let zoneColor = GraphicsContext.Shading.color(StrandPalette.vitalsZone)
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: zone), cornerRadius: zone / 2),
                     with: zoneColor)
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: size.height - zone, width: size.width, height: zone),
                          cornerRadius: zone / 2), with: zoneColor)
            ctx.fill(Path(roundedRect: band, cornerRadius: 6, style: .continuous),
                     with: .color(StrandPalette.vitalsTypicalBand.opacity(0.55)))

            let slots = CGFloat(SleepVitals.Metric.allCases.count)
            let ring: CGFloat = 11
            for reading in readings {
                guard let slot = SleepVitals.Metric.allCases.firstIndex(of: reading.metric) else { continue }
                let x = size.width * (CGFloat(slot) + 0.5) / slots
                let p = reading.position
                let y: CGFloat = p > 1 ? zone / 2 : p < 0 ? size.height - zone / 2
                    : band.maxY - ring / 2 - 2 - CGFloat(p) * (band.height - ring - 4)
                let color = reading.isOutlier ? StrandPalette.vitalsOutlier : StrandPalette.vitalsTypical
                let rect = CGRect(x: x - ring / 2, y: y - ring / 2, width: ring, height: ring)
                ctx.fill(Path(ellipseIn: rect), with: .color(StrandPalette.sleepScoreCard))
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1.25, dy: 1.25)), with: .color(color), lineWidth: 2.5)
            }
        }
    }
}

// MARK: - Sleep: Stages highlight

/// Health's "Sleep: Stages" highlight: the night's length in a sentence, then each stage named with its
/// total beside its row of the night, and the night's start and end under it.
struct SleepStagesHighlightCard: View {
    let intervals: [SleepInterval]
    let onset: Date
    let asleepMinutes: Double

    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 57

    private var span: TimeInterval { max(1, intervals.map(\.end).max() ?? 1) }

    var body: some View {
        HighlightCard(icon: "bed.double.fill", title: String(localized: "sleep.hl.stages", defaultValue: "Sleep: Stages"),
                      tint: StrandPalette.sleepScoreTitle,
                      sentence: String(localized: "Your \(SleepFormat.duration(minutes: asleepMinutes)) of sleep and its stages last night:"),
                      spacing: 10) {
            EmptyView()
        } chart: {
            chart
        }
    }

    private var chart: some View {
        let totals = Dictionary(grouping: intervals, by: \.stage).mapValues { $0.reduce(0) { $0 + $1.duration } }
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SleepStagesChart.rowOrder, id: \.self) { stage in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stage.chartLabel)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(SleepFormat.duration(minutes: (totals[stage] ?? 0) / 60))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .font(StrandFont.subhead.weight(.medium))
                    .lineLimit(1)
                    .frame(height: rowHeight, alignment: .center)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 4) {
                SleepStagesChart(intervals: intervals, onset: onset, compact: true)
                    .frame(height: rowHeight * CGFloat(SleepStagesChart.rowOrder.count))
                    .background { rowRules }
                axis
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "sleep.hl.stages", defaultValue: "Sleep: Stages")))
    }

    /// Dotted rules between the rows.
    private var rowRules: some View {
        Canvas { ctx, size in
            let rows = CGFloat(SleepStagesChart.rowOrder.count)
            for i in 1..<Int(rows) {
                let y = size.height * CGFloat(i) / rows
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(StrandPalette.healthChartGrid), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
    }

    /// A dotted line with a tick at each end, the night's start and end under the ticks.
    private var axis: some View {
        VStack(spacing: 2) {
            Canvas { ctx, size in
                let y = size.height / 2
                let tint = GraphicsContext.Shading.color(StrandPalette.healthChartAxisLabel)
                ctx.stroke(Path { $0.move(to: CGPoint(x: 1, y: y)); $0.addLine(to: CGPoint(x: size.width - 1, y: y)) },
                           with: tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 3]))
                for x in [CGFloat(1), size.width - 1] {
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                               with: tint, lineWidth: 1.5)
                }
            }
            .frame(height: 8)
            HStack {
                Text(onset, format: .dateTime.hour().minute().locale(AppLanguage.activeLocale))
                Spacer()
                Text(onset.addingTimeInterval(span), format: .dateTime.hour().minute().locale(AppLanguage.activeLocale))
            }
            .font(StrandFont.subhead.weight(.semibold))
            .foregroundStyle(StrandPalette.healthChartAxisLabel)
            .padding(.horizontal, 6)
        }
    }
}
