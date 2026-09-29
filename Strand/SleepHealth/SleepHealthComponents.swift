//  SleepHealthComponents.swift
//  NOOP · Sleep — the segmented Sleep score ring (the Health app's Sleep Score ring).

import SwiftUI
import StrandDesign

// MARK: - Sleep score ring

/// The Health Sleep Score ring, measured off iOS 26: one thick segment per part of the score, as long as
/// the points it is worth, with square ends rounded at the corners. A segment's full thickness is its
/// pale track; the points the night earned fill it from the inner edge outward, so a part at 24 of 30
/// is a solid band four fifths as thick. A score with no known parts (an imported one) is one segment.
struct SleepScoreRing: View {
    let score: SleepScore

    static func color(_ part: SleepScore.Part) -> Color {
        switch part {
        case .duration: return StrandPalette.sleepScoreDuration
        case .interruptions: return StrandPalette.sleepScoreInterruption
        case .restorative: return StrandPalette.sleepScoreRestorative
        case .regularity: return StrandPalette.sleepScoreRegularity
        }
    }

    /// Clockwise from twelve o'clock, as Health sets its parts: Interruptions, then Duration round the
    /// bottom, the rest up the left.
    static let order: [SleepScore.Part] = [.interruptions, .duration, .restorative, .regularity]
    /// The card lists them from Duration onward, round the ring, as Health's legend does.
    static let legendOrder: [SleepScore.Part] = [.duration, .restorative, .regularity, .interruptions]

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Canvas { ctx, size in draw(ctx, size: size) }
                // Health's figure: SF Pro bold at a quarter of the ring's width.
                Text(verbatim: "\(score.value)")
                    .font(.system(size: d * 0.25, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .minimumScaleFactor(0.6)
                    .padding(d * 0.2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Sleep Score")))
        .accessibilityValue(Text(verbatim: Self.spokenValue(score)))
    }

    // Health's proportions: the band is 40 % of the radius, segments stand 3 pt apart at mid-band and
    // their corners round at 4.5 pt on a 111 pt ring.
    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let outer = min(size.width, size.height) / 2
        let thickness = outer * 0.4
        let inner = outer - thickness
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let corner = outer * 4.5 / 55.5
        let gap = Double(3 / (inner + thickness / 2))

        let parts: [(color: Color, worth: Double, fraction: Double)] = score.parts.isEmpty
            ? [(StrandPalette.sleepScoreDuration, 1, Double(score.value) / 100)]
            : Self.order.compactMap { part in
                score.parts.first { $0.part == part }.map {
                    (Self.color(part), Double(part.maxPoints), min(1, max(0, $0.fraction)))
                }
            }
        let worth = parts.reduce(0) { $0 + $1.worth }
        let count = Double(parts.count)
        let usable = 2 * Double.pi - (count > 1 ? gap * count : 0)
        var start = -Double.pi / 2 + (count > 1 ? gap / 2 : 0)
        for part in parts {
            let span = usable * part.worth / worth
            ctx.fill(Self.sector(center: center, inner: inner, outer: outer, from: start, to: start + span,
                                 corner: corner),
                     with: .color(part.color.opacity(0.25)))
            if part.fraction > 0 {
                let earned = inner + thickness * part.fraction
                ctx.fill(Self.sector(center: center, inner: inner, outer: earned, from: start, to: start + span,
                                     corner: min(corner, (earned - inner) / 2)),
                         with: .color(part.color))
            }
            start += span + (count > 1 ? gap : 0)
        }
    }

    /// A ring segment between two radii and two angles (radians, clockwise on screen from 3 o'clock) with
    /// its four corners rounded.
    static func sector(center c: CGPoint, inner: CGFloat, outer: CGFloat, from a0: Double, to a1: Double,
                       corner r: CGFloat) -> Path {
        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            CGPoint(x: c.x + radius * CGFloat(cos(angle)), y: c.y + radius * CGFloat(sin(angle)))
        }
        // Angular room the corner takes on each arc, kept inside half the segment.
        let half = (a1 - a0) / 2
        let dOuter = min(Double(r / max(outer, 1)), half)
        let dInner = min(Double(r / max(inner, 1)), half)
        return Path { p in
            p.move(to: point((inner + outer) / 2, a0))
            p.addArc(tangent1End: point(outer, a0), tangent2End: point(outer, a0 + dOuter * 2), radius: r)
            p.addArc(center: c, radius: outer, startAngle: .radians(a0 + dOuter), endAngle: .radians(a1 - dOuter),
                     clockwise: false)
            p.addArc(tangent1End: point(outer, a1), tangent2End: point(inner, a1), radius: r)
            p.addArc(tangent1End: point(inner, a1), tangent2End: point(inner, a1 - dInner * 2), radius: r)
            p.addArc(center: c, radius: inner, startAngle: .radians(a1 - dInner), endAngle: .radians(a0 + dInner),
                     clockwise: true)
            p.addArc(tangent1End: point(inner, a0), tangent2End: point(outer, a0), radius: r)
            p.closeSubpath()
        }
    }

    /// "72, Duration 38 of 50, Interruptions 17 of 20, …": the score and what each segment holds.
    static func spokenValue(_ score: SleepScore) -> String {
        let parts = score.parts.map { part -> String in
            guard let points = part.points else { return part.part.label }
            return "\(part.part.label) \(String(localized: "\(points) of \(part.part.maxPoints)"))"
        }
        return (["\(score.value)"] + parts).joined(separator: ", ")
    }
}
