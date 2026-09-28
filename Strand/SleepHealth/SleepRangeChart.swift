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

    /// Clock domain in minutes-of-night (after 18:00), whole hours, with room either side of the data.
    private var domain: ClosedRange<Double> {
        guard let lo = window.bars.map(\.onsetMin).min(), let hi = window.bars.map(\.wakeMin).max() else {
            return 240...840   // 22:00 → 08:00
        }
        let start = (floor(lo / 60) - 1) * 60, end = (ceil(hi / 60) + 1) * 60
        return start...max(start + 120, end)
    }

    var body: some View {
        // The clock and the slot names take the room their labels need, so neither runs into the plot or
        // into each other at any text size.
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Canvas { ctx, size in
                    drawGrid(ctx, width: size.width, height: size.height)
                    drawBars(ctx, width: size.width, height: size.height)
                    drawOverlay(ctx, width: size.width, height: size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                hourLabels
            }
            HStack(spacing: 4) {
                slotLabels
                // Keeps the slot names under the plot only: the clock column's width, drawn empty.
                hourLabelSet(every: 1).frame(height: 0).hidden()
            }
        }
        // Past this size the clock alone would take a third of the plot.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .modifier(AccessibilityLabelIfPresent(text: window.averageAsleepMin.map {
            String(localized: "Average \(SleepFormat.duration(minutes: $0))")
        }))
        .accessibilityChildren { barElements }
    }

    // MARK: - VoiceOver

    /// One element per slot, laid out as the slots are, for the bars VoiceOver steps through.
    private var barElements: some View {
        let bySlot = Dictionary(window.bars.map { ($0.slot, $0) }, uniquingKeysWith: { a, _ in a })
        return HStack(spacing: 0) {
            ForEach(Array(window.slotStarts.indices), id: \.self) { slot in
                if let bar = bySlot[slot] {
                    Rectangle()
                        .accessibilityLabel(Text(verbatim: barDate(bar)))
                        .accessibilityValue(Text(verbatim:
                            "\(clockLabel(bar.onsetMin))–\(clockLabel(bar.wakeMin)), \(SleepFormat.duration(minutes: bar.asleepMin))"))
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
        }
    }

    /// A night's weekday, day and month; a 6-month bar's week.
    private func barDate(_ bar: SleepRangeBar) -> String {
        let locale = AppLanguage.activeLocale
        guard window.range == .sixMonths else {
            return bar.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        }
        let f = DateIntervalFormatter()
        f.locale = locale
        f.dateTemplate = "dMMMM"
        return f.string(from: bar.start, to: Calendar.current.date(byAdding: .day, value: 6, to: bar.start) ?? bar.start)
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

    /// The clock down the trailing edge: every gridline while the labels fit, every other one once they don't.
    private var hourLabels: some View {
        ViewThatFits(in: .vertical) {
            hourLabelSet(every: 1)
            hourLabelSet(every: 2)
        }
    }

    private func hourLabelSet(every step: Int) -> some View {
        let d = domain
        let hours = gridHours.enumerated().filter { $0.offset % step == 0 }.map(\.element)
        let axis = AxisTickLabels(vertical: true,
                                  fractions: hours.map { CGFloat(($0 - d.lowerBound) / (d.upperBound - d.lowerBound)) })
        return axis {
            ForEach(hours, id: \.self) { minutes in
                Text(clockLabel(minutes))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func clockLabel(_ minutesOfNight: Double) -> String {
        let reference = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-6 * 3600)
        return reference.addingTimeInterval(minutesOfNight * 60)
            .formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale))
    }

    /// The slot names under the plot; every other one when they would touch.
    private var slotLabels: some View {
        ViewThatFits(in: .horizontal) {
            slotLabelSet(every: 1)
            slotLabelSet(every: 2)
        }
    }

    private func slotLabelSet(every step: Int) -> some View {
        let n = CGFloat(max(1, window.slotStarts.count))
        let labelled = window.slotStarts.enumerated()
            .compactMap { slot, start in slotLabel(slot: slot, start: start).map { (slot: slot, text: $0) } }
            .enumerated().filter { $0.offset % step == 0 }.map(\.element)
        let axis = AxisTickLabels(fractions: labelled.map { (CGFloat($0.slot) + 0.5) / n })
        return axis {
            ForEach(labelled, id: \.slot) { label in
                Text(label.text)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
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

/// Chart axis labels, each centred on its tick at a fraction along the axis and kept inside it. Across the
/// axis it is as wide (or tall) as its largest label. Asked for its ideal length it reports what the labels
/// need not to touch, so a `ViewThatFits` can fall back to a sparser set instead of printing "09:0011:00".
struct AxisTickLabels: Layout {
    var vertical = false
    let fractions: [CGFloat]
    var gap: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let cross = sizes.map { vertical ? $0.width : $0.height }.max() ?? 0
        let length = (vertical ? proposal.height : proposal.width) ?? neededLength(sizes)
        return vertical ? CGSize(width: cross, height: length) : CGSize(width: length, height: cross)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let length = vertical ? bounds.height : bounds.width
        for (i, start) in starts(sizes, length: length).enumerated() {
            let point = vertical ? CGPoint(x: bounds.minX, y: bounds.minY + start)
                                 : CGPoint(x: bounds.minX + start, y: bounds.minY)
            subviews[i].place(at: point, anchor: .topLeading, proposal: ProposedViewSize(sizes[i]))
        }
    }

    /// Each label's leading edge along the axis: centred on its tick, clamped inside the axis.
    private func starts(_ sizes: [CGSize], length: CGFloat) -> [CGFloat] {
        sizes.enumerated().map { i, size in
            let extent = vertical ? size.height : size.width
            let f = i < fractions.count ? fractions[i] : 0
            return min(max(0, f * length - extent / 2), max(0, length - extent))
        }
    }

    private func fits(_ sizes: [CGSize], length: CGFloat) -> Bool {
        let s = starts(sizes, length: length)
        let extents = sizes.map { vertical ? $0.height : $0.width }
        guard let widest = extents.max(), widest <= length else { return extents.isEmpty }
        let spans = zip(s, extents).map { ($0, $0 + $1) }.sorted { $0.0 < $1.0 }
        return zip(spans, spans.dropFirst()).allSatisfy { $0.1 + gap <= $1.0 }
    }

    /// The shortest axis the labels fit on, to the nearest point (the search ceiling when they never do).
    private func neededLength(_ sizes: [CGSize]) -> CGFloat {
        var lo: CGFloat = 0, hi: CGFloat = 4096
        guard fits(sizes, length: hi) else { return hi }
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if fits(sizes, length: mid) { hi = mid } else { lo = mid }
        }
        return hi.rounded(.up)
    }
}

/// A label only when there is something to say: an empty one would still make VoiceOver stop on it.
struct AccessibilityLabelIfPresent: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.accessibilityLabel(Text(verbatim: text))
        } else {
            content
        }
    }
}
