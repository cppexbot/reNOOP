//  SleepHealthComponents.swift
//  NOOP · Sleep — the segmented Sleep score ring (the Health app's Sleep Score ring).

import SwiftUI
import StrandDesign

// MARK: - Sleep score ring

/// The Health Sleep Score ring: one segment per part of the score, each as long as the points it is
/// worth, filled as far as the night did on it. A score with no known parts draws one arc.
struct SleepScoreRing: View {
    let score: SleepScore
    var lineWidth: CGFloat = 14

    static func color(_ part: SleepScore.Part) -> Color {
        switch part {
        case .duration: return StrandPalette.sleepScoreDuration
        case .interruptions: return StrandPalette.sleepScoreInterruption
        case .restorative: return StrandPalette.sleepScoreRestorative
        case .regularity: return StrandPalette.sleepScoreRegularity
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - lineWidth / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            func arc(_ from: Double, _ to: Double) -> Path {
                Path { p in
                    p.addArc(center: center, radius: r, startAngle: .degrees(from), endAngle: .degrees(to),
                             clockwise: false)
                }
            }
            guard !score.parts.isEmpty else {
                ctx.stroke(arc(-90, 270), with: .color(StrandPalette.sleepScoreDuration.opacity(0.2)), style: style)
                let end = -90 + 360 * min(1, Double(score.value) / 100)
                ctx.stroke(arc(-90, end), with: .color(StrandPalette.sleepScoreDuration), style: style)
                return
            }
            // Round caps reach half a line past each end, so the gap leaves room for both caps.
            let capDeg = Double(lineWidth / 2 / max(r, 1)) * 180 / .pi
            let gap = 2 * capDeg + 5
            let usable = 360 - gap * Double(score.parts.count)
            let worth = Double(score.parts.map(\.part.maxPoints).reduce(0, +))
            var start = -90 + gap / 2
            for part in score.parts {
                let span = usable * Double(part.part.maxPoints) / worth
                let color = Self.color(part.part)
                ctx.stroke(arc(start, start + span), with: .color(color.opacity(0.22)), style: style)
                if part.fraction > 0 {
                    ctx.stroke(arc(start, start + max(0.5, span * part.fraction)), with: .color(color), style: style)
                }
                start += span + gap
            }
        }
        .overlay {
            Text(verbatim: "\(score.value)")
                .font(StrandFont.number(34, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .minimumScaleFactor(0.6)
                .padding(lineWidth + 4)
        }
        // The score sits in a fixed ring: it follows Dynamic Type only as far as the ring holds it.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Sleep Score")))
        .accessibilityValue(Text(verbatim: "\(score.value)"))
    }
}
