//  MetricHealthChart.swift
//  NOOP · Metric page — the chart in the page's first card, drawn the way Health draws a data type on
//  iOS 26: solid hairlines with the values on a trailing axis, dashed verticals at the date ticks, and a
//  press-and-drag that picks one mark for the header to read out. What is plotted — bars, rings, a line
//  or bars either side of zero, on which scale, with or without the period's average across it — is the
//  metric's own (`MetricHealthStyle.chart`).

import SwiftUI
import Charts
import StrandDesign

struct MetricHealthChart: View {
    let window: MetricHealthWindow
    let spec: MetricHealthStyle.Chart
    let tint: Color
    /// Segment id per point for a line that must break where its method changed (VO₂max estimates).
    var segments: [Date: String] = [:]
    let axisLabel: (Double) -> String
    @Binding var selection: MetricHealthPoint?

    @State private var rawSelection: Date?

    private var calendar: Calendar { .current }
    private var locale: Locale { AppLanguage.activeLocale }

    var body: some View {
        chart
            .chartXScale(domain: window.start...window.end)
            .chartYScale(domain: yDomain)
            .chartXAxis { xAxis }
            .chartYAxis { yAxis }
            .modifier(SelectionModifier(raw: $rawSelection))
            .onChangeCompat(of: rawSelection) { picked in
                selection = picked.flatMap(nearest)
            }
            .onChangeCompat(of: window) { _ in rawSelection = nil; selection = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(window.range.label))
    }

    // MARK: Marks

    private var chart: some View {
        Chart {
            if spec.showsAverage, let average = window.average, window.points.count > 1 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(StrandPalette.textSecondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if spec.mark == .diverging {
                RuleMark(y: .value("Baseline", 0))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            if let selection {
                RuleMark(x: .value("Picked", selection.start, unit: window.range.bucket))
                    .foregroundStyle(StrandPalette.textTertiary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(window.points) { p in
                let dim = selection != nil && selection != p
                let hue = spec.barTint?(p.value) ?? tint
                switch spec.mark {
                case .bars:
                    BarMark(x: .value("Date", p.start, unit: window.range.bucket),
                            y: .value("Value", p.value), width: .ratio(0.62))
                        .foregroundStyle(hue.opacity(dim ? 0.3 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                case .diverging:
                    BarMark(x: .value("Date", p.start, unit: window.range.bucket),
                            yStart: .value("Zero", 0), yEnd: .value("Value", p.value), width: .ratio(0.62))
                        .foregroundStyle(hue.opacity(dim ? 0.3 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                case .dots:
                    PointMark(x: .value("Date", p.start, unit: window.range.bucket), y: .value("Value", p.value))
                        .symbol { ring(dim: dim) }
                case .line:
                    LineMark(x: .value("Date", p.start, unit: window.range.bucket), y: .value("Value", p.value),
                             series: .value("Segment", segments[p.start] ?? "line"))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", p.start, unit: window.range.bucket), y: .value("Value", p.value))
                        .symbol { ring(dim: dim) }
                }
            }
        }
    }

    /// A reading as Health's Vitals and Cardio Fitness charts draw it: a hollow ring in the metric's hue.
    private func ring(dim: Bool) -> some View {
        let d: CGFloat = window.points.count > 20 ? 8 : 10
        return Circle()
            .strokeBorder(tint.opacity(dim ? 0.3 : 1), lineWidth: d > 8 ? 2.5 : 2)
            .background(Circle().fill(StrandPalette.summaryCard))
            .frame(width: d, height: d)
    }

    // MARK: Axes

    private var yDomain: ClosedRange<Double> {
        let values = window.points.map(\.value)
        if spec.mark == .diverging {
            let top = max(values.map(abs).max() ?? 0, 0.3) * 1.25
            return -top...top
        }
        if let fixed = spec.domain {
            return min(fixed.lowerBound, values.min() ?? fixed.lowerBound)...max(fixed.upperBound, values.max() ?? fixed.upperBound)
        }
        guard let lo = values.min(), let hi = values.max() else { return 0...4 }
        if spec.mark == .bars { return 0...max(hi * 1.12, 1) }
        let pad = max((hi - lo) * 0.25, max(abs(hi) * 0.04, 1))
        return (lo - pad)...(hi + pad)
    }

    /// Round values across the domain, about four of them.
    private var yTicks: [Double] {
        let d = yDomain
        let raw = (d.upperBound - d.lowerBound) / 4
        guard raw > 0, raw.isFinite else { return [] }
        let mag = pow(10, floor(log10(raw)))
        // 2.5 only where it still lands on whole numbers (25, 250…), so no tick reads "92.5".
        let steps: [Double] = mag >= 10 ? [1, 2, 2.5, 5, 10] : [1, 2, 5, 10]
        let step = steps.map { $0 * mag }.first { $0 >= raw } ?? 10 * mag
        var ticks: [Double] = []
        var v = ceil(d.lowerBound / step) * step
        while v <= d.upperBound + step * 1e-6 {
            ticks.append(v)
            v += step
        }
        return ticks
    }

    @AxisContentBuilder private var yAxis: some AxisContent {
        AxisMarks(position: .trailing, values: yTicks) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: NoopMetrics.hairlineWidth))
                .foregroundStyle(StrandPalette.hairline)
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(verbatim: axisLabel(v))
                        .font(StrandFont.pro(12))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    @AxisContentBuilder private var xAxis: some AxisContent {
        AxisMarks(values: xTicks) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: NoopMetrics.hairlineWidth, dash: [2, 3]))
                .foregroundStyle(StrandPalette.hairline)
            AxisValueLabel(anchor: window.range == .week ? .top : .topLeading) {
                if let date = value.as(Date.self) {
                    Text(verbatim: xLabel(date))
                        .font(StrandFont.pro(12))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    /// Every day for a week, each week's first day for a month, and each month's first day for 6M and Y.
    private var xTicks: [Date] {
        switch window.range {
        case .week:
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: window.start) }
                .map { calendar.date(byAdding: .hour, value: 12, to: $0) ?? $0 }
        case .month:
            var weekStart = calendar.dateInterval(of: .weekOfYear, for: window.start)?.start ?? window.start
            if weekStart < window.start { weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? window.end }
            return stride(from: 0, to: 35, by: 7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
                .filter { $0 < window.end }
        case .sixMonths, .year:
            var out: [Date] = []
            var cursor = calendar.dateInterval(of: .month, for: window.start)?.start ?? window.start
            if cursor < window.start, let next = calendar.date(byAdding: .month, value: 1, to: cursor) { cursor = next }
            while cursor < window.end {
                out.append(cursor)
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }
            return out
        }
    }

    private func xLabel(_ date: Date) -> String {
        switch window.range {
        case .week: return date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        case .month: return date.formatted(.dateTime.day().locale(locale))
        case .sixMonths: return date.formatted(.dateTime.month(.abbreviated).locale(locale))
        case .year: return date.formatted(.dateTime.month(.narrow).locale(locale))
        }
    }

    // MARK: Selection

    private func nearest(_ date: Date) -> MetricHealthPoint? {
        if let hit = window.points.first(where: { date >= $0.start && date < $0.end }) { return hit }
        return window.points.min { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }
}

/// Press-and-drag picking where the OS has it (iOS 17 / macOS 14); a plain chart before that.
private struct SelectionModifier: ViewModifier {
    @Binding var raw: Date?

    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.chartXSelection(value: $raw)
        } else {
            content
        }
    }
}
