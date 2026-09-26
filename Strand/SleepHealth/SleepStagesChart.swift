//  SleepStagesChart.swift
//  NOOP · Sleep — one night's stages in the Apple Health layout.
//
//  Four labelled rows (Awake, REM, Light, Deep) separated by hairlines, dashed hour gridlines, rounded
//  blocks per interval and a soft vertical connector wherever the night moves between stages. Drawing
//  only: the intervals come from the same `SleepModel.Night` the rest of the app reads.

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
    private var axisHeight: CGFloat { compact ? 0 : 20 }

    private var span: TimeInterval { max(1, intervals.map(\.end).max() ?? 1) }

    var body: some View {
        GeometryReader { geo in
            let plotHeight = geo.size.height - axisHeight
            let rowHeight = plotHeight / CGFloat(Self.rowOrder.count)
            ZStack(alignment: .topLeading) {
                grid(width: geo.size.width, plotHeight: plotHeight, rowHeight: rowHeight)
                Canvas { ctx, size in
                    drawStages(ctx, width: size.width, rowHeight: rowHeight)
                    drawOverlay(ctx, size: size)
                }
                .frame(width: geo.size.width, height: plotHeight)
                if !compact {
                    rowLabels(rowHeight: rowHeight)
                    hourLabels(width: geo.size.width)
                        .offset(y: plotHeight + 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    // MARK: - Layout pieces

    private func grid(width: CGFloat, plotHeight: CGFloat, rowHeight: CGFloat) -> some View {
        Canvas { ctx, size in
            let line = GraphicsContext.Shading.color(StrandPalette.hairline)
            for i in 0...Self.rowOrder.count {
                let y = CGFloat(i) * rowHeight
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: line, lineWidth: 1)
            }
            for tick in hourTicks() {
                let x = xPos(tick.offset, width: size.width)
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: plotHeight)) },
                           with: line, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .frame(width: width, height: plotHeight)
    }

    private func rowLabels(rowHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.rowOrder, id: \.self) { stage in
                Text(stage.label)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.leading, 4)
                    .padding(.top, 3)
                    .frame(height: rowHeight, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
    }

    private func hourLabels(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourTicks().enumerated().filter { $0.offset % 2 == 0 }.map(\.element), id: \.offset) { tick in
                Text(tick.date, format: .dateTime.hour().minute().locale(AppLanguage.activeLocale))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize()
                    .offset(x: min(max(0, xPos(tick.offset, width: width) + 3), width - 44))
            }
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Drawing

    private func drawStages(_ ctx: GraphicsContext, width: CGFloat, rowHeight: CGFloat) {
        let blockHeight = rowHeight * 0.5
        func rowIndex(_ stage: SleepStage) -> Int { Self.rowOrder.firstIndex(of: stage) ?? 0 }
        func midY(_ stage: SleepStage) -> CGFloat { (CGFloat(rowIndex(stage)) + 0.5) * rowHeight }

        func alpha(_ stage: SleepStage) -> Double {
            guard let highlight else { return overlay.isEmpty ? 1 : 0.35 }
            return stage == highlight ? 1 : 0.18
        }

        // Connectors first, so the blocks sit on top of them.
        for (a, b) in zip(intervals, intervals.dropFirst()) where a.stage != b.stage {
            let x = xPos(b.start, width: width)
            let y1 = midY(a.stage), y2 = midY(b.stage)
            let rect = CGRect(x: x - 1.5, y: min(y1, y2), width: 3, height: abs(y2 - y1))
            let fade = highlight == nil && overlay.isEmpty ? 0.35 : 0.1
            let gradient = Gradient(colors: [a.stage.healthColor.opacity(fade), b.stage.healthColor.opacity(fade)])
            ctx.fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: x, y: y1),
                                                       endPoint: CGPoint(x: x, y: y2)))
        }
        for interval in intervals {
            let x1 = xPos(interval.start, width: width), x2 = xPos(interval.end, width: width)
            let w = max(2, x2 - x1)
            let rect = CGRect(x: x1, y: midY(interval.stage) - blockHeight / 2, width: w, height: blockHeight)
            let radius = min(5, w / 2)
            ctx.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                     with: .color(interval.stage.healthColor.opacity(alpha(interval.stage))))
        }
    }

    /// The overlaid vital as a line on its own vertical scale (`SleepMoreData.overlayDomain` across 10 %–90 %
    /// of the plot), lowest at the bottom.
    private func drawOverlay(_ ctx: GraphicsContext, size: CGSize) {
        guard overlay.count >= 2, let domain = SleepMoreData.overlayDomain(overlay) else { return }
        let lo = domain.lowerBound, spread = max(domain.upperBound - lo, 1e-6)
        func point(_ p: SleepComparisonPoint) -> CGPoint {
            CGPoint(x: xPos(p.x, width: size.width),
                    y: size.height * (0.9 - 0.8 * CGFloat((p.value - lo) / spread)))
        }
        var path = Path()
        path.move(to: point(overlay[0]))
        for p in overlay.dropFirst() { path.addLine(to: point(p)) }
        ctx.stroke(path, with: .color(overlayColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Scale

    private func xPos(_ t: TimeInterval, width: CGFloat) -> CGFloat {
        CGFloat(t / span) * width
    }

    /// Whole clock hours inside the night, as offsets from onset.
    private func hourTicks() -> [(offset: TimeInterval, date: Date)] {
        let cal = Calendar.current
        let end = onset.addingTimeInterval(span)
        guard var hour = cal.nextDate(after: onset, matching: DateComponents(minute: 0, second: 0),
                                      matchingPolicy: .nextTime) else { return [] }
        var out: [(TimeInterval, Date)] = []
        while hour < end {
            out.append((hour.timeIntervalSince(onset), hour))
            hour = hour.addingTimeInterval(3600)
        }
        return out
    }

    private var accessibilitySummary: String {
        let byStage = Dictionary(grouping: intervals, by: \.stage).mapValues { $0.reduce(0) { $0 + $1.duration } }
        return Self.rowOrder.compactMap { stage in
            guard let secs = byStage[stage], secs > 0 else { return nil }
            return "\(stage.label) \(SleepFormat.duration(minutes: secs / 60))"
        }.joined(separator: ", ")
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
