//  SleepStagesChart.swift
//  NOOP · Sleep — one night's stages in the Apple Health layout.
//
//  Health's iOS 26 day chart, measured off the real app: four rows (Awake, REM, Core, Deep), each named
//  at its top-left and closed by a rule, a solid frame at both ends with dashed hour lines between, and
//  the clock under the plot. Each stage block sits in a pale halo of its own hue; wherever the night moves
//  between stages a pale band joins the two blocks, flaring into them with a rounded fillet, and the whole
//  pale layer shades from one row's hue to the next. Drawing only: the intervals come from the same
//  `SleepModel.Night` the rest of the app reads.

import SwiftUI
import StrandDesign

extension SleepStage {
    /// The Health-style hue for this stage.
    var healthColor: Color {
        switch self {
        case .awake: return StrandPalette.healthSleepAwake
        case .rem: return StrandPalette.healthSleepRem
        case .light: return StrandPalette.healthSleepCore
        case .deep: return StrandPalette.healthSleepDeep
        }
    }
}

struct SleepStagesChart: View {
    /// Intervals in seconds from `onset`.
    let intervals: [SleepInterval]
    let onset: Date
    /// A stage picked in "Show More Sleep Data": every other stage fades back.
    var highlight: SleepStage? = nil
    /// A vital drawn over the night (x = seconds from onset), scaled to the plot on its own axis.
    var overlay: [SleepComparisonPoint] = []
    var overlayColor: Color = StrandPalette.healthHeart
    /// A thumbnail for a card: the rows and blocks only, no stage names and no hour axis.
    var compact = false

    static let rowOrder: [SleepStage] = [.awake, .rem, .light, .deep]

    @Environment(\.displayScale) private var displayScale

    private var span: TimeInterval { max(1, intervals.map(\.end).max() ?? 1) }

    var body: some View {
        Canvas { ctx, size in
            if compact {
                drawThumbnail(ctx, size: size)
            } else {
                drawChart(ctx, size: size)
            }
        }
        // Past this size the stage names would run into the blocks under them.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .modifier(StagesAccessibility(compact: compact, summary: accessibilitySummary) { stageElements })
    }

    // MARK: - Scale

    /// The plot's time scale as offsets from `onset`: where the left edge sits and how long the plot is.
    private struct TimeAxis {
        let start: TimeInterval
        let length: TimeInterval
        /// Hour lines after the left edge, one per section; the last is the right edge.
        var step: TimeInterval { length / 4 }

        func x(_ t: TimeInterval, width: CGFloat) -> CGFloat { CGFloat((t - start) / length) * width }
    }

    /// Health's day axis: the left edge is the night's start rounded down to its hour, and the plot is four
    /// equal sections of whole hours, as few as reach the end (9 PM · 12 AM · 3 AM · 6 AM for an ordinary
    /// night, six-hour sections for a day-long one).
    private var chartAxis: TimeAxis {
        let hourStart = Calendar.current.dateInterval(of: .hour, for: onset)?.start ?? onset
        let start = hourStart.timeIntervalSince(onset)
        let hours = max(1, ((span - start) / (4 * 3600)).rounded(.up))
        return TimeAxis(start: start, length: 4 * hours * 3600)
    }

    // MARK: - Chart

    // Health's proportions, measured off the app at 3×: a row is ~67 pt; its block spans 38–85 % of it
    // under the stage name, in a 1.5 pt halo of 25 % of its hue; blocks round at 4 pt; a transition band is
    // the halo's width and flares into each block with a 5⅓ pt fillet.
    private static let blockTop: CGFloat = 0.377
    private static let blockBottom: CGFloat = 0.85
    private static let halo: CGFloat = 1.5
    private static let paleOpacity = 0.25
    private static let blockRadius: CGFloat = 4
    private static let filletRadius: CGFloat = 16.0 / 3

    private func drawChart(_ ctx: GraphicsContext, size: CGSize) {
        let axis = chartAxis
        let hairline = 1 / max(displayScale, 1)
        // Health sets both in the footnote size: the stage names medium, the clock semibold.
        let clockFont = StrandFont.footnote.weight(.semibold)
        let clockTexts = (0..<4).map { k in
            ctx.resolve(Text(onset.addingTimeInterval(axis.start + Double(k) * axis.step), format: clockFormat)
                .font(clockFont)
                .foregroundColor(StrandPalette.healthChartAxisLabel))
        }
        let clockHeight = clockTexts.map { $0.measure(in: size).height }.max() ?? 0
        let plot = CGRect(x: 0, y: 0, width: size.width, height: max(0, size.height - clockHeight))
        let rowHeight = plot.height / CGFloat(Self.rowOrder.count)
        let blocks = blockRects(axis: axis, width: plot.width, rowHeight: rowHeight)

        // Pale layer first: the hour lines and row rules are drawn over it, the blocks over them.
        drawPale(ctx, blocks: blocks, plot: plot, rowHeight: rowHeight)

        // Solid frame at both ends, dashed hour lines between, all running down through the clock.
        let grid = GraphicsContext.Shading.color(StrandPalette.healthChartGrid)
        for k in 0...4 {
            let x = min(max(hairline / 2, axis.x(axis.start + Double(k) * axis.step, width: size.width)),
                        size.width - hairline / 2)
            let line = Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }
            let edge = k == 0 || k == 4
            ctx.stroke(line, with: grid, style: StrokeStyle(lineWidth: hairline, dash: edge ? [] : [2, 2]))
        }
        // A rule closes each row; the top of the plot stays open.
        for i in 1...Self.rowOrder.count {
            let y = CGFloat(i) * rowHeight - hairline / 2
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                       with: .color(StrandPalette.healthChartLabel), lineWidth: hairline)
        }

        for block in blocks {
            ctx.fill(Path(roundedRect: block.rect, cornerRadius: block.radius, style: .continuous),
                     with: .color(block.stage.healthColor.opacity(alpha(block.stage))))
        }
        drawOverlay(ctx, size: plot.size)

        // The stage names at each row's top-left, the clock under the plot beside its hour line.
        for (i, stage) in Self.rowOrder.enumerated() {
            let name = ctx.resolve(Text(stage.chartLabel)
                .font(StrandFont.footnote.weight(.medium))
                .foregroundColor(StrandPalette.healthChartLabel))
            ctx.draw(name, at: CGPoint(x: 5.5, y: CGFloat(i) * rowHeight + 3), anchor: .topLeading)
        }
        for (k, text) in clockTexts.enumerated() {
            let x = axis.x(axis.start + Double(k) * axis.step, width: size.width)
            ctx.draw(text, at: CGPoint(x: x + 2.5, y: plot.maxY), anchor: .topLeading)
        }
    }

    /// "19:00" where the clock runs to 24 hours, "9 PM" where it has AM/PM — Health drops the minutes
    /// there, as every line falls on the hour.
    private var clockFormat: Date.FormatStyle {
        let locale = AppLanguage.activeLocale
        let twelveHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") ?? false
        return twelveHour ? .dateTime.hour().locale(locale) : .dateTime.hour().minute().locale(locale)
    }

    private struct Block {
        let stage: SleepStage
        let rect: CGRect
        let radius: CGFloat
        /// The transition line at the block's start (from the previous stage) and end (into the next).
        var inbound: CGFloat?
        var outbound: CGFloat?
        /// Whether the neighbour at that end sits below (true) or above (false) this block.
        var inboundBelow = false
        var outboundBelow = false
    }

    private func blockRects(axis: TimeAxis, width: CGFloat, rowHeight: CGFloat) -> [Block] {
        func row(_ stage: SleepStage) -> Int { Self.rowOrder.firstIndex(of: stage) ?? 0 }
        var out: [Block] = intervals.map { interval in
            let x1 = axis.x(interval.start, width: width), x2 = axis.x(interval.end, width: width)
            let top = (CGFloat(row(interval.stage)) + Self.blockTop) * rowHeight
            let rect = CGRect(x: x1, y: top, width: max(1, x2 - x1),
                              height: (Self.blockBottom - Self.blockTop) * rowHeight)
            return Block(stage: interval.stage, rect: rect,
                         radius: min(Self.blockRadius, rect.width / 2, rect.height / 2))
        }
        for i in out.indices.dropFirst() where out[i - 1].stage != out[i].stage {
            let x = out[i].rect.minX
            let below = row(out[i].stage) > row(out[i - 1].stage)
            out[i - 1].outbound = x
            out[i - 1].outboundBelow = below
            out[i].inbound = x
            out[i].inboundBelow = !below
        }
        return out
    }

    /// Every block's halo, a band at every stage change, and the fillets where a band meets a halo, filled
    /// as one shape (drawn opaque in a layer, then faded, so overlaps don't darken) and shaded from each
    /// row's hue to the next.
    private func drawPale(_ ctx: GraphicsContext, blocks: [Block], plot: CGRect, rowHeight: CGFloat) {
        let h = Self.halo
        var shape = Path()
        for (i, block) in blocks.enumerated() {
            let halo = block.rect.insetBy(dx: -h, dy: -h)
            let haloRadius = min(block.radius + h, halo.width / 2)
            shape.addPath(Path(roundedRect: halo, cornerRadius: haloRadius, style: .continuous))

            // The band into the next block, centred on the change and as wide as the two halos.
            if let x = block.outbound, i + 1 < blocks.count {
                let a = block.rect.midY, b = blocks[i + 1].rect.midY
                shape.addRect(CGRect(x: x - h, y: min(a, b), width: 2 * h, height: abs(b - a)))
            }

            // Where a band meets the halo its corner is square: the band runs flush down the halo's side.
            if let x = block.inbound {
                let y = block.inboundBelow ? block.rect.midY : halo.minY
                shape.addRect(CGRect(x: x - h, y: y, width: haloRadius, height: halo.height / 2))
            }
            if let x = block.outbound {
                let y = block.outboundBelow ? block.rect.midY : halo.minY
                shape.addRect(CGRect(x: x + h - haloRadius, y: y, width: haloRadius, height: halo.height / 2))
            }

            // Fillets on the halo's edge facing each band, on the side the halo runs on. Two bands leaving
            // the same edge share the run between them, so their fillets meet in an arch.
            for below in [true, false] {
                let edgeY = below ? halo.maxY : halo.minY
                let dy: CGFloat = below ? 1 : -1
                let inX = block.inbound.flatMap { block.inboundBelow == below ? $0 : nil }
                let outX = block.outbound.flatMap { block.outboundBelow == below ? $0 : nil }
                let run: CGFloat
                if let inX, let outX {
                    run = ((outX - h) - (inX + h)) / 2
                } else if let inX {
                    run = (halo.maxX - haloRadius) - (inX + h)
                } else if let outX {
                    run = (outX - h) - (halo.minX + haloRadius)
                } else {
                    continue
                }
                let r = min(Self.filletRadius, run)
                guard r > 0.25 else { continue }
                if let inX { shape.addPath(Self.fillet(corner: CGPoint(x: inX + h, y: edgeY), dx: 1, dy: dy, r: r)) }
                if let outX { shape.addPath(Self.fillet(corner: CGPoint(x: outX - h, y: edgeY), dx: -1, dy: dy, r: r)) }
            }
        }

        // The rows' hues down the plot, each pure from its blocks' top edge.
        let stops = Self.rowOrder.enumerated().map { i, stage in
            Gradient.Stop(color: stage.healthColor,
                          location: (CGFloat(i) + Self.blockTop) / CGFloat(Self.rowOrder.count))
        }
        var layer = ctx
        layer.opacity = Self.paleOpacity * (highlight == nil && overlay.isEmpty ? 1 : 0.4)
        layer.drawLayer { l in
            l.fill(shape, with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: plot.minY),
                                                endPoint: CGPoint(x: 0, y: plot.maxY)))
        }
    }

    /// The concave corner where a band (running from `corner` along `dy`) meets a halo edge (running from
    /// `corner` along `dx`): the corner's square less a circle of radius `r`.
    private static func fillet(corner c: CGPoint, dx: CGFloat, dy: CGFloat, r: CGFloat) -> Path {
        Path { p in
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + dx * r, y: c.y))
            p.addArc(tangent1End: c, tangent2End: CGPoint(x: c.x, y: c.y + dy * r), radius: r)
            p.closeSubpath()
        }
    }

    private func alpha(_ stage: SleepStage) -> Double {
        guard let highlight else { return overlay.isEmpty ? 1 : 0.35 }
        return stage == highlight ? 1 : 0.18
    }

    // MARK: - Card thumbnail

    private func drawThumbnail(_ ctx: GraphicsContext, size: CGSize) {
        let rowHeight = size.height / CGFloat(Self.rowOrder.count)
        let blockHeight = rowHeight * 0.5
        let axis = TimeAxis(start: 0, length: span)
        let line = GraphicsContext.Shading.color(StrandPalette.hairline)
        for i in 0...Self.rowOrder.count {
            let y = CGFloat(i) * rowHeight
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                       with: line, lineWidth: 1)
        }
        // Dashed lines on the whole clock hours inside the night.
        let firstHour = Calendar.current.nextDate(after: onset, matching: DateComponents(minute: 0, second: 0),
                                                  matchingPolicy: .nextTime)
        var hour = firstHour.map { $0.timeIntervalSince(onset) } ?? span
        while hour < span {
            let x = axis.x(hour, width: size.width)
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                       with: line, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            hour += 3600
        }
        func midY(_ stage: SleepStage) -> CGFloat {
            (CGFloat(Self.rowOrder.firstIndex(of: stage) ?? 0) + 0.5) * rowHeight
        }
        // Connectors first, so the blocks sit on top of them.
        for (a, b) in zip(intervals, intervals.dropFirst()) where a.stage != b.stage {
            let x = axis.x(b.start, width: size.width)
            let y1 = midY(a.stage), y2 = midY(b.stage)
            let rect = CGRect(x: x - 1.5, y: min(y1, y2), width: 3, height: abs(y2 - y1))
            let gradient = Gradient(colors: [a.stage.healthColor.opacity(0.35), b.stage.healthColor.opacity(0.35)])
            ctx.fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: x, y: y1),
                                                       endPoint: CGPoint(x: x, y: y2)))
        }
        for interval in intervals {
            let x1 = axis.x(interval.start, width: size.width), x2 = axis.x(interval.end, width: size.width)
            let w = max(2, x2 - x1)
            let rect = CGRect(x: x1, y: midY(interval.stage) - blockHeight / 2, width: w, height: blockHeight)
            ctx.fill(Path(roundedRect: rect, cornerRadius: min(5, w / 2), style: .continuous),
                     with: .color(interval.stage.healthColor))
        }
    }

    /// The overlaid vital as a line on its own vertical scale (`SleepMoreData.overlayDomain` across 10 %–90 %
    /// of the plot), lowest at the bottom.
    private func drawOverlay(_ ctx: GraphicsContext, size: CGSize) {
        guard overlay.count >= 2, let domain = SleepMoreData.overlayDomain(overlay) else { return }
        let axis = chartAxis
        let lo = domain.lowerBound, spread = max(domain.upperBound - lo, 1e-6)
        func point(_ p: SleepComparisonPoint) -> CGPoint {
            CGPoint(x: axis.x(p.x, width: size.width),
                    y: size.height * (0.9 - 0.8 * CGFloat((p.value - lo) / spread)))
        }
        var path = Path()
        path.move(to: point(overlay[0]))
        for p in overlay.dropFirst() { path.addLine(to: point(p)) }
        ctx.stroke(path, with: .color(overlayColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    /// One element per stage row, laid out as the rows are: its total, its share of the night, and when.
    private var stageElements: some View {
        let byStage = Dictionary(grouping: intervals, by: \.stage)
        let whole = intervals.reduce(0) { $0 + $1.duration }
        let locale = AppLanguage.activeLocale
        func clock(_ t: TimeInterval) -> String {
            onset.addingTimeInterval(t).formatted(.dateTime.hour().minute().locale(locale))
        }
        return VStack(spacing: 0) {
            ForEach(Self.rowOrder, id: \.self) { stage in
                let spans = byStage[stage] ?? []
                let secs = spans.reduce(0) { $0 + $1.duration }
                if secs > 0 {
                    let share = (whole > 0 ? secs / whole : 0)
                        .formatted(.percent.precision(.fractionLength(0)).locale(locale))
                    let times = spans.map { "\(clock($0.start))–\(clock($0.end))" }.joined(separator: ", ")
                    Rectangle()
                        .accessibilityLabel(Text(stage.label))
                        .accessibilityValue(Text(verbatim:
                            "\(SleepFormat.duration(minutes: secs / 60)), \(share). \(times)"))
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
        }
    }

    private var accessibilitySummary: String {
        let byStage = Dictionary(grouping: intervals, by: \.stage).mapValues { $0.reduce(0) { $0 + $1.duration } }
        return Self.rowOrder.compactMap { stage in
            guard let secs = byStage[stage], secs > 0 else { return nil }
            return "\(stage.label) \(SleepFormat.duration(minutes: secs / 60))"
        }.joined(separator: ", ")
    }
}

/// A card's thumbnail reads as one sentence inside its card; the full chart is a container of its rows.
private struct StagesAccessibility<Rows: View>: ViewModifier {
    let compact: Bool
    let summary: String
    @ViewBuilder let rows: () -> Rows

    func body(content: Content) -> some View {
        if compact {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: summary))
        } else {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Stages"))
                .accessibilityChildren(children: rows)
        }
    }
}

/// "7 h 42 min" in the user's language, split so the number and unit can be styled apart.
enum SleepFormat {
    static func parts(minutes: Double) -> (hours: Int, minutes: Int) {
        let total = max(0, Int(minutes.rounded()))
        return (total / 60, total % 60)
    }

    /// "7 h 42 min", "8 h" on the whole hour, "25 min" under an hour.
    static func duration(minutes: Double) -> String {
        let p = parts(minutes: minutes)
        if p.hours > 0 {
            return p.minutes == 0 ? String(localized: "\(p.hours) h") : String(localized: "\(p.hours) h \(p.minutes) min")
        }
        return String(localized: "\(p.minutes) min")
    }
}
