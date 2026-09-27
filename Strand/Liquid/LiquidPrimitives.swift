//  LiquidPrimitives.swift
//  NOOP · Liquid design language
//
//  The Canvas renderers + SwiftUI view wrappers for the signature elements:
//  the circular vessel gauge, the horizontal tube, and the live heart-rate thread.
//  Each view owns a LiquidSim, steps it from a TimelineView clock, and reads the
//  one shared tilt source. Colours come from StrandDesign tokens at the call site.

import SwiftUI
import StrandDesign   // NoopMotionState — the shared quiet-motion gate

// MARK: - Renderers (pure GraphicsContext drawing)

enum LiquidRender {

    /// A softly sculpted circular progress ring. Geometry is fixed (`radius`, `lineWidth`, arc span);
    /// this pass only deepens the material — recessed track, frosted inner disc, semantic progress
    /// gradient — without neon bloom, tip dots, or layout changes.
    static func vessel(_ base: GraphicsContext, _ size: CGSize, _ sim: LiquidSim, now: Double, tint: Color) {
        let diameter = max(2, min(size.width, size.height) - 3)
        let rect = CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2,
                          width: diameter, height: diameter)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = diameter * 0.39
        let lineWidth = max(5, diameter * 0.105)
        let cap = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        var ctx = base

        // Restrained outer lift — light gray shadow, not deep black.
        let shadowRect = rect.offsetBy(dx: 0, dy: max(1, diameter * 0.010))
        ctx.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.14)))

        // One continuous centre disc — soft 3D: light top face, gentle rim shade.
        // No separate inset circle / hard ring line.
        ctx.fill(Path(ellipseIn: rect), with: .linearGradient(
            Gradient(colors: [
                NoopVisualStyle.surfaceTop,
                NoopVisualStyle.surfaceBottom
            ]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
        ))
        // Soft radial lift — brighter near the upper face, slightly deeper at the rim.
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.07), location: 0.00),
                .init(color: Color.white.opacity(0.02), location: 0.42),
                .init(color: Color.clear, location: 0.72),
                .init(color: Color.black.opacity(0.10), location: 1.00)
            ]),
            center: CGPoint(x: rect.midX, y: rect.minY + diameter * 0.32),
            startRadius: 0,
            endRadius: diameter * 0.52
        ))
        // Very soft lower-edge shade for a lightly recessed read.
        ctx.fill(Path(ellipseIn: rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color.clear, location: 0.00),
                .init(color: Color.clear, location: 0.55),
                .init(color: Color.black.opacity(0.06), location: 1.00)
            ]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
        ))

        let track = fullArc(center: center, radius: radius)

        // Recessed track — gray channel (original border tone), not black.
        ctx.stroke(track, with: .linearGradient(
            Gradient(colors: [
                Color.white.opacity(0.08),
                NoopVisualStyle.border.opacity(0.18),
                NoopVisualStyle.border.opacity(0.50)
            ]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
        ), style: StrokeStyle(lineWidth: lineWidth + 1.6, lineCap: .round))

        ctx.stroke(track, with: .color(NoopVisualStyle.border.opacity(0.72)), style: cap)

        let level = max(0, min(1, sim.level))
        if level > 0.004 {
            let progress = partialArc(center: center, radius: radius, level: level)

            // Contained under-lift — wider stroke, low opacity, no blur.
            ctx.stroke(progress, with: .color(tint.opacity(0.18)),
                       style: StrokeStyle(lineWidth: lineWidth + 2.0, lineCap: .round))

            // Progress arc — harsh semantic gradient (visible dark ↔ light bands).
            ctx.stroke(progress, with: .linearGradient(
                progressGradient(tint),
                startPoint: CGPoint(x: rect.minX, y: rect.maxY),
                endPoint: CGPoint(x: rect.maxX, y: rect.minY)
            ), style: cap)
        }

        // Outer instrument rim (unchanged placement).
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)),
                   with: .color(NoopVisualStyle.borderHighlight.opacity(0.55)), lineWidth: 1)
    }

    /// Full-span track arc — geometry unchanged from the original vessel.
    private static func fullArc(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        p.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                 endAngle: .degrees(270), clockwise: false)
        return p
    }

    private static func partialArc(center: CGPoint, radius: CGFloat, level: Double) -> Path {
        var p = Path()
        p.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * level), clockwise: false)
        return p
    }

    /// Harsh semantic gradient — tight stops so dark/light bands read clearly on the arc.
    private static func progressGradient(_ tint: Color) -> Gradient {
        Gradient(stops: [
            .init(color: tint.liquidDarker(0.48), location: 0.00),
            .init(color: tint.liquidLighter(0.38), location: 0.34),
            .init(color: tint.liquidDarker(0.22), location: 0.58),
            .init(color: tint.liquidLighter(0.28), location: 0.82),
            .init(color: tint.liquidDarker(0.35), location: 1.00)
        ])
    }

    /// A horizontal capsule tube filled to `frac`; tilt pushes the liquid along it.
    static func tube(_ base: GraphicsContext, _ size: CGSize, _ sim: LiquidSim, now: Double,
                     frac: Double, tint: Color, showsHighlight: Bool = true,
                     usesCleanFill: Bool = false) {
        let w = size.width, h = size.height, r = h / 2
        let outline = Path(roundedRect: CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1), cornerRadius: r)
        var ctx = base
        ctx.fill(outline, with: .color(NoopVisualStyle.inset))
        ctx.stroke(
            outline,
            with: .color(NoopVisualStyle.border.opacity(0.72)),
            lineWidth: NoopMetrics.hairlineWidth
        )

        var clip = ctx
        clip.clip(to: outline)
        let shift = -sim.a * h * 1.3
        let edge = max(r * 0.8, min(w - 2, frac * (w - 4) + shift))
        let bulge = r * 0.6 + sin(sim.p1 * 2) * sim.energy * h * 0.3 - 0.01 * h * 6
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: edge - r * 0.3, y: 0))
        p.addQuadCurve(to: CGPoint(x: edge - r * 0.3, y: h), control: CGPoint(x: edge + bulge, y: h / 2))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        let fillGradient = usesCleanFill
            ? progressGradient(tint)
            : Gradient(colors: [tint.opacity(0.84), tint.liquidDarker(0.28).opacity(0.86)])
        clip.fill(p, with: .linearGradient(
            fillGradient,
            startPoint: CGPoint(x: 0, y: usesCleanFill ? h / 2 : 0),
            endPoint: CGPoint(x: usesCleanFill ? w : 0, y: usesCleanFill ? h / 2 : h)
        ))
        if showsHighlight {
            clip.fill(Path(CGRect(x: 2, y: 1.2, width: max(0, edge - r * 0.6), height: 1)),
                      with: .color(.white.opacity(0.12)))
        }
        if !usesCleanFill {
            for i in 0..<min(8, sim.flecks.count) {
                let f = sim.flecks[i]
                let spark = pow(max(0, sin(f.ph + sim.a * 5 + now * f.sp)), 10)
                if spark < 0.08 { continue }
                let fx = 3 + (f.x + 1.05) / 2.1 * max(1, edge - 8)
                clip.fill(Path(CGRect(x: fx, y: h * 0.15 + f.z * h * 0.7,
                                      width: 1 + spark, height: 1 + spark)),
                          with: .color(.white.opacity(spark * 0.6)))
            }
        }
    }
}

// MARK: - Views

/// Applies the splash tap either as a normal tap (consuming it) or as a simultaneous gesture (sharing
/// it with whatever wraps the view).
///
/// A plain `onTapGesture` inside a `NavigationLink` swallows the tap, so the link never pushes. That is
/// why the hero rings could splash but not navigate. `simultaneousGesture` lets both run, which is the
/// behaviour a tappable gauge wants; standalone vessels keep the consuming tap so nothing else changes.
private struct LiquidSplashTap: ViewModifier {
    let passesThrough: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if passesThrough {
            content.simultaneousGesture(TapGesture().onEnded { action() })
        } else {
            content.onTapGesture { action() }
        }
    }
}

/// A circular liquid gauge. `value` is 0...1 (nil = empty/no-data). Tap → splash.
///
/// `animated: false` renders a single static frame (no TimelineView, no CoreMotion) — the small
/// gauges in card rows / vitals slosh imperceptibly at 26–30pt but each cost a live 30fps Canvas,
/// so they pose still and CoreAnimation caches them. The big hero gauges stay animated.
struct LiquidVessel: View {
    let value: Double?
    let tint: Color
    var animated: Bool = true
    /// When the vessel sits inside a NavigationLink or Button, the splash tap must not CONSUME the
    /// tap or the wrapping control never fires. Opt in and the splash runs as a simultaneous gesture
    /// instead, so both happen: the liquid still splashes and the link still pushes. Default false
    /// keeps every standalone vessel byte-identical (#1995).
    var tapPassesThrough: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var sim: LiquidSim
    @State private var splashes = 0

    // The custom init exists to seed `_sim` from `value`, which also means the memberwise init is NOT
    // synthesised: any new stored property has to be threaded through here or callers cannot pass it.
    init(value: Double?, tint: Color, animated: Bool = true, tapPassesThrough: Bool = false) {
        self.value = value
        self.tint = tint
        self.animated = animated
        self.tapPassesThrough = tapPassesThrough
        _sim = State(initialValue: LiquidSim(target: value ?? 0))
    }

    var body: some View {
        if animated && !motion.poseStill(reduceMotion) { gauge } else { staticGauge }
    }

    private var gauge: some View {
        // 60fps: on the 120Hz ProMotion panel a 30fps cap updated the fluid only every 4th refresh,
        // which read as juddery slosh. Only the 3 hero gauges + HR thread run live now (the small ones
        // are static), so the higher rate is affordable and the liquid actually flows.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tl in
            let now = liquidSeconds(tl.date)
            Canvas { context, size in
                sim.step(now: now, tilt: LiquidMotion.shared.tilt, target: value ?? 0)
                LiquidRender.vessel(context, size, sim, now: now, tint: tint)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .modifier(LiquidSplashTap(passesThrough: tapPassesThrough) { sim.splash(12); splashes &+= 1 })
        .liquidTapHaptic(trigger: splashes)   // light tap feedback (guarded so the primitives compile on macOS 13)
        .onAppear { LiquidMotion.shared.acquire() }
        .onDisappear { LiquidMotion.shared.release() }
    }

    /// One-shot, cached render — posed at the fill line, no clock, no motion acquire.
    private var staticGauge: some View {
        Canvas { context, size in
            LiquidRender.vessel(context, size, LiquidSim.posed(value ?? 0), now: 0, tint: tint)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
    }
}

/// A horizontal liquid tube filled to `frac` (0...1).
///
/// `animated: false` poses it still and lets CoreAnimation cache the layer — the 8pt grid tubes
/// and 12pt workout bar don't need a live 30fps Canvas each. Hero-adjacent tubes can stay live.
struct LiquidTube: View {
    let frac: Double
    let tint: Color
    var height: CGFloat = 14
    var animated: Bool = true
    var showsHighlight: Bool = true
    var usesCleanFill: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var sim = LiquidSim(target: 0)

    var body: some View {
        if animated && !motion.poseStill(reduceMotion) { liveTube } else { staticTube }
    }

    private var liveTube: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let now = liquidSeconds(tl.date)
            Canvas { context, size in
                sim.step(now: now, tilt: LiquidMotion.shared.tilt, target: frac)
                LiquidRender.tube(context, size, sim, now: now, frac: max(0, min(1, frac)),
                                  tint: tint, showsHighlight: showsHighlight,
                                  usesCleanFill: usesCleanFill)
            }
        }
        .frame(height: height)
        .onAppear { LiquidMotion.shared.acquire() }
        .onDisappear { LiquidMotion.shared.release() }
    }

    private var staticTube: some View {
        Canvas { context, size in
            LiquidRender.tube(context, size, LiquidSim.posed(frac), now: 0,
                              frac: max(0, min(1, frac)), tint: tint,
                              showsHighlight: showsHighlight, usesCleanFill: usesCleanFill)
        }
        .frame(height: height)
    }
}

// MARK: - Shared liquid components (cross-platform: used by the liquid screens on iOS + mac)

extension View {
    /// A light selection/impact haptic, available only where `sensoryFeedback` is (iOS 17 / macOS 14);
    /// a no-op below that so the liquid primitives still compile on the macOS 13 deployment target.
    @ViewBuilder func liquidTapHaptic(trigger: some Equatable) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.sensoryFeedback(.impact(weight: .light), trigger: trigger)
        } else {
            self
        }
    }
}

/// The "this card was pressed" response for any tappable liquid card — a small settle inward plus a
/// touch of dimming. Cheap (a transform), so it's free on static cards and makes every tap feel physical.
struct LiquidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
