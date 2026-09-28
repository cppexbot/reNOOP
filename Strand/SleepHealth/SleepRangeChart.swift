//  SleepRangeChart.swift
//  NOOP · Sleep — week / month / 6-month view: one floating bar per night (or week) from bedtime to wake,
//  on a clock that runs down through the night, Apple Health style.

import SwiftUI
import StrandDesign

struct SleepRangeChart: View {
    let window: SleepRangeWindow
    /// "Show More Sleep Data": each night's hypnogram (seconds from its onset) by slot, drawn down its bar
    /// in stage colours. Slots without one keep the plain bar.
    var stagesBySlot: [Int: [SleepInterval]] = [:]
    /// A stage picked below the chart: every other stage fades back.
    var highlight: SleepStage? = nil
    /// A vital per slot (x = slot index), dots joined on their own vertical scale.
    var overlay: [SleepComparisonPoint] = []
    var overlayColor: Color = StrandPalette.healthHeart

    private let axisHeight: CGFloat = 20
    private let labelWidth: CGFloat = 40

    /// Clock domain in minutes-of-night (after 18:00), whole hours, with room either side of the data.
    private var domain: ClosedRange<Double> {
        guard let lo = window.bars.map(\.onsetMin).min(), let hi = window.bars.map(\.wakeMin).max() else {
            return 240...840   // 22:00 → 08:00
        }
        let start = (floor(lo / 60) - 1) * 60, end = (ceil(hi / 60) + 1) * 60
        return start...max(start + 120, end)
    }

    var body: some View {
        GeometryReader { geo in
            let plotWidth = geo.size.width - labelWidth
            let plotHeight = geo.size.height - axisHeight
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    drawGrid(ctx, width: plotWidth, height: plotHeight)
                    drawBars(ctx, width: plotWidth, height: plotHeight)
                    drawOverlay(ctx, width: plotWidth, height: plotHeight)
                }
                .frame(width: plotWidth, height: plotHeight)
                hourLabels(height: plotHeight)
                    .offset(x: plotWidth + 4)
                slotLabels(width: plotWidth)
                    .offset(y: plotHeight + 4)
            }
        }
        // Axis labels sit in fixed gutters: they follow Dynamic Type only as far as the gutters hold them.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(window.averageAsleepMin.map { SleepFormat.duration(minutes: $0) } ?? ""))
    }

    // MARK: - Drawing

    private func y(_ minutes: Double, height: CGFloat) -> CGFloat {
        let d = domain
        return CGFloat((minutes - d.lowerBound) / (d.upperBound - d.lowerBound)) * height
    }

    private func slotCenter(_ slot: Int, width: CGFloat) -> CGFloat {
        let n = max(1, window.slotStarts.count)
        return (CGFloat(slot) + 0.5) * width / CGFloat(n)
    }

    private var gridHours: [Double] {
        stride(from: domain.lowerBound, through: domain.upperBound, by: 120).map { $0 }
    }

    private func drawGrid(_ ctx: GraphicsContext, width: CGFloat, height: CGFloat) {
        for minutes in gridHours {
            let yy = y(minutes, height: height)
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: yy)); $0.addLine(to: CGPoint(x: width, y: yy)) },
                       with: .color(StrandPalette.hairline), lineWidth: 1)
        }
    }

    private func drawBars(_ ctx: GraphicsContext, width: CGFloat, height: CGFloat) {
        let n = max(1, window.slotStarts.count)
        let barWidth = max(3, min(22, width / CGFloat(n) * 0.55))
        for bar in window.bars {
            let x = slotCenter(bar.slot, width: width) - barWidth / 2
            let top = y(bar.onsetMin, height: height), bottom = y(bar.wakeMin, height: height)
            let rect = CGRect(x: x, y: top, width: barWidth, height: max(barWidth, bottom - top))
            let radius = stagesBySlot.isEmpty ? barWidth / 2 : min(3, barWidth / 2)
            let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            let dim = overlay.isEmpty ? 1.0 : 0.35
            guard let intervals = stagesBySlot[bar.slot], !intervals.isEmpty else {
                ctx.fill(shape, with: .color(StrandPalette.healthSleepCore.opacity(highlight == nil ? dim : 0.18)))
                continue
            }
            var clipped = ctx
            clipped.clip(to: shape)
            for interval in intervals {
                let y1 = y(bar.onsetMin + interval.start / 60, height: height)
                let y2 = y(bar.onsetMin + interval.end / 60, height: height)
                let alpha = highlight.map { $0 == interval.stage ? 1.0 : 0.18 } ?? dim
                clipped.fill(Path(CGRect(x: x, y: y1, width: barWidth, height: max(0.75, y2 - y1))),
                             with: .color(interval.stage.healthColor.opacity(alpha)))
            }
        }
    }

    /// The overlaid vital: a dot per slot joined by a line, on its own scale (`SleepMoreData.overlayDomain`
    /// across 10 %–90 % of the plot).
    private func drawOverlay(_ ctx: GraphicsContext, width: CGFloat, height: CGFloat) {
        guard let domain = SleepMoreData.overlayDomain(overlay) else { return }
        let lo = domain.lowerBound, spread = max(domain.upperBound - lo, 1e-6)
        let points = overlay.map { p in
            CGPoint(x: slotCenter(Int(p.x), width: width),
                    y: height * (0.9 - 0.8 * CGFloat((p.value - lo) / spread)))
        }
        if points.count >= 2 {
            var line = Path()
            line.move(to: points[0])
            for p in points.dropFirst() { line.addLine(to: p) }
            ctx.stroke(line, with: .color(overlayColor.opacity(0.6)), lineWidth: 1.5)
        }
        let r: CGFloat = window.slotStarts.count > 10 ? 2.5 : 4
        for p in points {
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(dot, with: .color(overlayColor))
        }
    }

    // MARK: - Labels

    private func hourLabels(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(gridHours, id: \.self) { minutes in
                Text(clockLabel(minutes))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize()
                    .offset(y: y(minutes, height: height) - 7)
            }
        }
    }

    private func clockLabel(_ minutesOfNight: Double) -> String {
        let reference = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-6 * 3600)
        return reference.addingTimeInterval(minutesOfNight * 60)
            .formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale))
    }

    private func slotLabels(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(window.slotStarts.enumerated()), id: \.offset) { slot, start in
                if let text = slotLabel(slot: slot, start: start) {
                    Text(text)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize()
                        .frame(width: 40)
                        .offset(x: slotCenter(slot, width: width) - 20)
                }
            }
        }
    }

    /// Every weekday for a week, every seventh day for a month, a month name where one begins for 6 months.
    private func slotLabel(slot: Int, start: Date) -> String? {
        let locale = AppLanguage.activeLocale
        switch window.range {
        case .day, .week:
            return start.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        case .month:
            let fromEnd = window.slotStarts.count - 1 - slot
            return fromEnd % 7 == 0 ? start.formatted(.dateTime.day().locale(locale)) : nil
        case .sixMonths:
            let cal = Calendar.current
            // The first slot is labelled only when it opens its month; otherwise the next month's label,
            // a week or two along, would print on top of it.
            let opensMonth = slot == 0
                ? cal.component(.day, from: start) <= 7
                : cal.component(.month, from: start) != cal.component(.month, from: window.slotStarts[slot - 1])
            guard opensMonth else { return nil }
            return start.formatted(.dateTime.month(.abbreviated).locale(locale))
        }
    }
}
