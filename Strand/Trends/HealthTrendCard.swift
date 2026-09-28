//  HealthTrendCard.swift
//  NOOP · Trends — one trend as Health draws it: the metric's name in its category hue, one sentence
//  ("Trending lower for 8 weeks"), then the whole span's readings in grey with the earlier period's average
//  drawn across them in grey and the recent period's in the metric's hue, each labelled with its figure,
//  and "18-week avg" / "8-week avg" underneath.

import SwiftUI
import StrandDesign
import StrandAnalytics

struct HealthTrendCard: View {
    let metric: MetricDescriptor
    let trend: HealthTrend
    let units: MetricHealthStyle.Units

    private var tint: Color { MetricHealthStyle.tint(metric) }

    var body: some View {
        SummaryCard {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    SummaryCardTitleRow(icon: AllMetricsCatalog.category(metric).icon, title: metric.title, tint: tint)
                    SummaryCardTitleRow(icon: AllMetricsCatalog.category(metric).icon,
                                        title: AllMetricsCatalog.shortTitle(metric), tint: tint)
                }
                Text(Self.sentence(trend))
                    .font(StrandFont.pro(22, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HealthTrendChart(trend: trend, mark: mark, tint: tint,
                                 baselineLabel: figure(trend.baselineAverage),
                                 recentLabel: figure(trend.recentAverage))
                    .frame(height: 92)
                HStack {
                    Text(Self.averageLabel(trend.baselineLength, unit: trend.unit))
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer(minLength: 8)
                    Text(Self.averageLabel(trend.recentCount, unit: trend.unit))
                        .foregroundStyle(tint)
                }
                .font(StrandFont.pro(15))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [
            metric.title, Self.sentence(trend),
            "\(Self.averageLabel(trend.baselineLength, unit: trend.unit)): \(figure(trend.baselineAverage))",
            "\(Self.averageLabel(trend.recentCount, unit: trend.unit)): \(figure(trend.recentAverage))",
        ].joined(separator: ". ")))
    }

    /// How the readings are drawn: bars for totals and scores, rings for vitals, a joined line for the
    /// slow measures — the mark the metric's own page uses.
    private var mark: MetricHealthStyle.Mark {
        MetricHealthStyle.chart(metric, series: []).mark
    }

    /// The average's figure over its line: a duration keeps its units ("7 hr 6 min"), anything else is the
    /// number alone, as Health labels these lines.
    private func figure(_ value: Double) -> String {
        let tokens = MetricHealthStyle.tokens(metric, value, units: units)
        return (metric.unit == "min" ? tokens : tokens.filter { !$0.isUnit }).map(\.text).joined(separator: " ")
    }

    static func sentence(_ trend: HealthTrend) -> String {
        let n = trend.recentCount
        switch (trend.direction, trend.unit) {
        case (.higher, .day): return String(localized: "Trending higher for \(n) days")
        case (.higher, .week): return String(localized: "Trending higher for \(n) weeks")
        case (.lower, .day): return String(localized: "Trending lower for \(n) days")
        case (.lower, .week): return String(localized: "Trending lower for \(n) weeks")
        }
    }

    static func averageLabel(_ n: Int, unit: HealthTrend.Unit) -> String {
        unit == .day ? String(localized: "\(n) day avg") : String(localized: "\(n)-week avg")
    }
}

/// The card's chart: every slot's reading in grey, the two averages as thick lines across their periods,
/// each labelled at its outer end.
struct HealthTrendChart: View {
    let trend: HealthTrend
    let mark: MetricHealthStyle.Mark
    let tint: Color
    let baselineLabel: String
    let recentLabel: String

    /// Room above the plot for the figures that sit on the lines.
    private let labelRoom: CGFloat = 22
    private let labelHeight: CGFloat = 18

    var body: some View {
        let values = trend.slots.compactMap { $0 }
        let lo0 = min(values.min() ?? 0, trend.baselineAverage, trend.recentAverage)
        let hi = max(values.max() ?? 1, trend.baselineAverage, trend.recentAverage)
        // Bars stand on a floor below the lowest reading so the movement shows, as on Health's charts.
        let lo = mark == .bars || mark == .diverging ? lo0 - max(hi - lo0, 1e-9) * 0.5 : lo0
        let span = max(hi - lo, 1e-9)
        return GeometryReader { geo in
            let count = max(trend.slots.count, 1)
            let slot = geo.size.width / CGFloat(count)
            let plotHeight = geo.size.height - labelRoom
            let y: (Double) -> CGFloat = { v in labelRoom + plotHeight * CGFloat(1 - (v - lo) / span) }
            let x: (Int) -> CGFloat = { i in slot * (CGFloat(i) + 0.5) }
            let split = slot * CGFloat(trend.baselineCount)
            let grey = StrandPalette.textTertiary.opacity(0.35)
            // The earlier average spans the readings it is the average of, not the empty start of the span.
            let firstRecorded = slot * CGFloat(trend.slots.firstIndex { $0 != nil } ?? 0)
            ZStack(alignment: .topLeading) {
                marks(slot: slot, x: x, y: y, bottom: geo.size.height, grey: grey)
                averageLine(from: firstRecorded, to: split - slot * 0.25, y: y(trend.baselineAverage),
                            color: StrandPalette.textSecondary)
                averageLine(from: split + slot * 0.25, to: geo.size.width, y: y(trend.recentAverage), color: tint)
                label(baselineLabel, color: StrandPalette.textSecondary, width: geo.size.width - firstRecorded,
                      alignment: .leading)
                    .offset(x: firstRecorded, y: y(trend.baselineAverage) - labelHeight - 4)
                label(recentLabel, color: tint, width: geo.size.width, alignment: .trailing)
                    .offset(y: y(trend.recentAverage) - labelHeight - 4)
            }
        }
        // The figures ride fixed rows over the lines: they follow Dynamic Type only as far as the rows hold them.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func marks(slot: CGFloat, x: @escaping (Int) -> CGFloat, y: @escaping (Double) -> CGFloat,
                       bottom: CGFloat, grey: Color) -> some View {
        let points = trend.slots.enumerated().compactMap { i, v in v.map { (i, $0) } }
        switch mark {
        case .bars, .diverging:
            let width = min(8, slot * 0.6)
            ForEach(points, id: \.0) { i, v in
                RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                    .fill(grey)
                    .frame(width: width, height: max(3, bottom - y(v)))
                    .offset(x: x(i) - width / 2, y: y(v))
            }
        case .line:
            Path { p in
                for (n, point) in points.enumerated() {
                    let at = CGPoint(x: x(point.0), y: y(point.1))
                    if n == 0 { p.move(to: at) } else { p.addLine(to: at) }
                }
            }
            .stroke(grey, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            rings(points, x: x, y: y, grey: grey, slot: slot)
        case .dots:
            rings(points, x: x, y: y, grey: grey, slot: slot)
        }
    }

    private func rings(_ points: [(Int, Double)], x: @escaping (Int) -> CGFloat, y: @escaping (Double) -> CGFloat,
                       grey: Color, slot: CGFloat) -> some View {
        let d = min(7, max(4, slot * 0.7))
        return ForEach(points, id: \.0) { i, v in
            Circle()
                .strokeBorder(grey, lineWidth: 1.5)
                .background(Circle().fill(StrandPalette.summaryCard))
                .frame(width: d, height: d)
                .offset(x: x(i) - d / 2, y: y(v) - d / 2)
        }
    }

    private func label(_ text: String, color: Color, width: CGFloat, alignment: Alignment) -> some View {
        Text(verbatim: text)
            .font(StrandFont.pro(15, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: width, height: labelHeight, alignment: alignment)
    }

    private func averageLine(from x0: CGFloat, to x1: CGFloat, y: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: max(0, x1 - x0), height: 4)
            .offset(x: x0, y: y - 2)
    }
}
