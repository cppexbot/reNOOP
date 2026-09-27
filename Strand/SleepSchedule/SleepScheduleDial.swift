//  SleepScheduleDial.swift
//  NOOP · Sleep schedule — the Health app's bedtime / wake dial: a 24-hour face (0 at the top, a moon
//  under it, a sun over 12), a track ring around it, and the bedtime → wake arc on the track with a bed
//  at one end and an alarm clock at the other. Drag an end to move it, the arc to move both.

import SwiftUI
import StrandDesign

struct SleepScheduleDial: View {
    @Binding var bed: Int
    @Binding var wake: Int

    private enum Grab { case bed, wake, arc(offset: Int) }
    @State private var grab: Grab?

    /// Five-minute steps, as Health's dial snaps.
    private static let step = 5

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let m = Metrics(size: size)
            ZStack {
                Circle().fill(StrandPalette.sleepDialTrack)
                Circle().fill(StrandPalette.sleepDialFace).frame(width: m.faceR * 2, height: m.faceR * 2)
                face(m)
                arc(m)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(drag(m, origin: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Bedtime and Wake Up")))
        .accessibilityValue(Text(verbatim: "\(SleepSchedule.clock(bed, locale: AppLanguage.activeLocale)) – \(SleepSchedule.clock(wake, locale: AppLanguage.activeLocale))"))
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 15 : -15
            wake = SleepSchedule.wrap(wake + delta)
            bed = SleepSchedule.wrap(bed + delta)
        }
    }

    private struct Metrics {
        let size: CGFloat
        var r: CGFloat { size / 2 }
        var faceR: CGFloat { r * 0.685 }
        var arcR: CGFloat { r * 0.8425 }
        var arcWidth: CGFloat { r * 0.21 }
        var center: CGPoint { CGPoint(x: r, y: r) }

        func angle(_ minutes: Int) -> Double { Double(minutes) / Double(SleepSchedule.day) * 2 * .pi - .pi / 2 }
        func point(_ minutes: Int, radius: CGFloat) -> CGPoint {
            let a = angle(minutes)
            return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }
    }

    // MARK: - Face

    private func face(_ m: Metrics) -> some View {
        ZStack {
            Canvas { ctx, _ in
                // A tick every 15 minutes, longer on the hour.
                for q in 0..<96 {
                    let hour = q % 4 == 0
                    let minutes = q * 15
                    let outer = m.faceR - m.r * 0.035
                    let inner = outer - (hour ? m.r * 0.045 : m.r * 0.025)
                    var p = Path()
                    p.move(to: m.point(minutes, radius: inner))
                    p.addLine(to: m.point(minutes, radius: outer))
                    ctx.stroke(p, with: .color(StrandPalette.textTertiary.opacity(hour ? 0.9 : 0.55)),
                               lineWidth: hour ? 1.2 : 0.8)
                }
            }
            ForEach(Array(stride(from: 0, to: 24, by: 2)), id: \.self) { h in
                let p = m.point(h * 60, radius: m.faceR * 0.74)
                Text(verbatim: "\(h)")
                    .font(StrandFont.pro(m.r * 0.105, weight: .semibold))
                    .foregroundStyle(h % 6 == 0 ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                    .position(p)
            }
            Image(systemName: "moon.fill")
                .font(.system(size: m.r * 0.1))
                .foregroundStyle(StrandPalette.sleepSchedule)
                .position(m.point(0, radius: m.faceR * 0.5))
            Image(systemName: "sun.max.fill")
                .font(.system(size: m.r * 0.1))
                .foregroundStyle(StrandPalette.sleepDialSun)
                .position(m.point(12 * 60, radius: m.faceR * 0.5))
        }
        .frame(width: m.size, height: m.size)
        .accessibilityHidden(true)
    }

    // MARK: - Arc

    private func arc(_ m: Metrics) -> some View {
        let span = SleepSchedule.wrap(wake - bed)
        return ZStack {
            Canvas { ctx, _ in
                var p = Path()
                p.addArc(center: m.center, radius: m.arcR, startAngle: .radians(m.angle(bed)),
                         endAngle: .radians(m.angle(bed + span)), clockwise: false)
                ctx.stroke(p, with: .color(StrandPalette.sleepDialArc),
                           style: StrokeStyle(lineWidth: m.arcWidth, lineCap: .round))
                // Health's ribbed arc: a short radial tick every five minutes between the two ends.
                let inset = Int((m.arcWidth / 2) / (2 * .pi * m.arcR) * Double(SleepSchedule.day)) + 5
                var t = inset
                while t < span - inset {
                    var tick = Path()
                    tick.move(to: m.point(bed + t, radius: m.arcR - m.arcWidth * 0.2))
                    tick.addLine(to: m.point(bed + t, radius: m.arcR + m.arcWidth * 0.2))
                    ctx.stroke(tick, with: .color(StrandPalette.sleepDialArcTick), lineWidth: 1.5)
                    t += 5
                }
            }
            knob("bed.double.fill", at: m.point(bed, radius: m.arcR), m)
            knob("alarm.fill", at: m.point(wake, radius: m.arcR), m)
        }
        .frame(width: m.size, height: m.size)
    }

    private func knob(_ symbol: String, at p: CGPoint, _ m: Metrics) -> some View {
        Image(systemName: symbol)
            .font(.system(size: m.arcWidth * 0.42, weight: .semibold))
            .foregroundStyle(StrandPalette.sleepDialKnobGlyph)
            .position(p)
    }

    // MARK: - Dragging

    private func minutes(at location: CGPoint, origin: CGPoint) -> Int {
        let a = atan2(location.y - origin.y, location.x - origin.x) + .pi / 2
        let raw = Int((a / (2 * .pi) * Double(SleepSchedule.day)).rounded())
        return SleepSchedule.wrap(raw)
    }

    private static func snapped(_ minutes: Int) -> Int {
        SleepSchedule.wrap(Int((Double(minutes) / Double(step)).rounded()) * step)
    }

    /// Keeps the bedtime → wake span inside the sleep goal's range by holding the end that is not moving.
    private static func clampedSpan(_ span: Int) -> Int {
        let range = SleepSchedule.goalRange
        if range.contains(span) { return span }
        // Past the long end is nearer the short end the other way round the clock.
        return span > (range.upperBound + range.lowerBound + SleepSchedule.day) / 2 ? range.lowerBound
            : (span > range.upperBound ? range.upperBound : range.lowerBound)
    }

    private func drag(_ m: Metrics, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let at = minutes(at: value.location, origin: origin)
                if grab == nil {
                    grab = pickGrab(value.startLocation, origin: origin, m)
                }
                switch grab {
                case .bed:
                    let newBed = Self.snapped(at)
                    bed = SleepSchedule.wrap(wake - Self.clampedSpan(SleepSchedule.wrap(wake - newBed)))
                case .wake:
                    let newWake = Self.snapped(at)
                    wake = SleepSchedule.wrap(bed + Self.clampedSpan(SleepSchedule.wrap(newWake - bed)))
                case .arc(let offset):
                    let span = SleepSchedule.wrap(wake - bed)
                    let newBed = Self.snapped(at - offset)
                    bed = newBed
                    wake = SleepSchedule.wrap(newBed + span)
                case nil:
                    break
                }
            }
            .onEnded { _ in grab = nil }
    }

    private func pickGrab(_ start: CGPoint, origin: CGPoint, _ m: Metrics) -> Grab? {
        let local = CGPoint(x: start.x - origin.x + m.center.x, y: start.y - origin.y + m.center.y)
        func distance(_ p: CGPoint) -> CGFloat { hypot(local.x - p.x, local.y - p.y) }
        let dBed = distance(m.point(bed, radius: m.arcR))
        let dWake = distance(m.point(wake, radius: m.arcR))
        let reach = m.arcWidth * 0.9
        if min(dBed, dWake) < reach { return dBed <= dWake ? .bed : .wake }
        let radius = distance(m.center)
        guard abs(radius - m.arcR) < m.arcWidth else { return nil }
        let at = minutes(at: start, origin: origin)
        let offset = SleepSchedule.wrap(at - bed)
        return offset <= SleepSchedule.wrap(wake - bed) ? .arc(offset: offset) : nil
    }
}
