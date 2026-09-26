//  ActivityRingsView.swift
//  NOOP · Summary home — three concentric rings drawn the way Apple Watch draws Activity.
//
//  Drawing only. Each ring gets a fill fraction already clamped by `RingFraction` and a start → end hue
//  pair: a dark track in its own hue, then an arc whose colour deepens-to-brightens along its length, with
//  round caps painted in the exact hue at each end (an angular gradient alone would paint the start cap
//  in the END colour, since the cap reaches back past 0°). The rings sit on a black disc, as Health's
//  small Activity rings do in either appearance — the neon hues are made for black.

import SwiftUI
import StrandDesign

struct ActivityRing: Identifiable {
    let id: String
    let fraction: Double
    let start: Color
    let end: Color
}

struct ActivityRingsView: View {
    /// Outermost first.
    let rings: [ActivityRing]
    var diameter: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// The disc's margin around the outer ring.
    private var inset: CGFloat { diameter * 0.04 }
    private var lineWidth: CGFloat { diameter * 0.1 }
    private var ringGap: CGFloat { diameter * 0.01 }

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let step = inset + CGFloat(index) * (lineWidth + ringGap)
                ringView(ring, size: diameter - step * 2)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { appeared = true } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { appeared = true }
            }
        }
        .accessibilityHidden(true)
    }

    private func ringView(_ ring: ActivityRing, size: CGFloat) -> some View {
        RingArc(fraction: appeared ? ring.fraction : 0, start: ring.start, end: ring.end, lineWidth: lineWidth)
            .frame(width: size, height: size)
    }
}

/// One ring. Animatable over its fraction so the fill, the gradient and the end cap all travel along the
/// arc together while the rings fill in (a plain offset would carry the cap across the chord).
private struct RingArc: View, Animatable {
    var fraction: Double
    let start: Color
    let end: Color
    let lineWidth: CGFloat

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            // The stroke straddles its path, so the path is inset by half the width: the ring then sits
            // fully inside its frame and its centre line is exactly `radius`, where the caps ride.
            let radius = (min(geo.size.width, geo.size.height) - lineWidth) / 2
            ZStack {
                Circle()
                    .stroke(start.opacity(0.26), lineWidth: lineWidth)
                    .padding(lineWidth / 2)
                if fraction > 0.001 {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(AngularGradient(gradient: Gradient(colors: [start, end]), center: .center,
                                                startAngle: .zero, endAngle: .degrees(360 * fraction)),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .padding(lineWidth / 2)
                        .rotationEffect(.degrees(-90))
                    cap(start, radius: radius, angle: 0)
                    cap(end, radius: radius, angle: 360 * fraction)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// A round cap centred on the ring's path at `angle` degrees clockwise from twelve o'clock.
    private func cap(_ color: Color, radius: CGFloat, angle: Double) -> some View {
        let rad = (angle - 90) * .pi / 180
        return Circle()
            .fill(color)
            .frame(width: lineWidth, height: lineWidth)
            .offset(x: radius * CGFloat(cos(rad)), y: radius * CGFloat(sin(rad)))
    }
}
