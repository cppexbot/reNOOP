import SwiftUI
import StrandDesign

// The pieces of Coach's Messages (iOS 26) look that are not the screen itself: the bubble outline and
// its screen-pinned blue, the typing indicator, the header with the Coach circle, and Liquid Glass.
// Sizes are the Messages app's own (its bubble path, balloon metrics and typing layer), not estimates.

// MARK: - Bubble

/// The Messages bubble outline: continuous corners of radius 20.14 and, on the last bubble of a run,
/// the rounded tail that hangs `tailHeight` below the body at the sender's bottom corner. The rect
/// includes the tail's room when `tail` is set, so the body is `tailHeight` shorter than the frame.
///
/// A port of the system path: each corner is three cubics whose control points move between a
/// "pill" set (a side of exactly 2 × radius, one line of text) and the full set (a side of 2 × 30.79
/// or more) in proportion to the side's length; the tail is seven fixed cubics anchored at the body's
/// bottom corner. Built for a tail on the right in a y-down space and mirrored for the left.
struct MessageBubbleShape: Shape {
    /// How far the tail reaches below the body.
    static let tailHeight: CGFloat = 6.8337
    /// One line of 17 pt text with 10 pt above and below; a bubble is never narrower or shorter.
    static let minSide: CGFloat = 40.2871

    let outgoing: Bool
    let tail: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = max(0, rect.height - (tail ? Self.tailHeight : 0))
        let tv = Corner.progress(side: h), th = Corner.progress(side: w)
        let ev = Corner.extent(tv), eh = Corner.extent(th)

        var p = Path()
        p.move(to: CGPoint(x: 0, y: ev))
        Corner.add(to: &p, at: CGPoint(x: 0, y: 0), d1: CGVector(dx: 0, dy: 1), d2: CGVector(dx: 1, dy: 0), t1: tv, t2: th)
        p.addLine(to: CGPoint(x: w - eh, y: 0))
        Corner.add(to: &p, at: CGPoint(x: w, y: 0), d1: CGVector(dx: -1, dy: 0), d2: CGVector(dx: 0, dy: 1), t1: th, t2: tv)
        p.addLine(to: CGPoint(x: w, y: h - ev))
        if tail {
            for (c1, c2, end) in Self.tailSegments {
                p.addCurve(to: CGPoint(x: w + end.x, y: h + end.y),
                           control1: CGPoint(x: w + c1.x, y: h + c1.y),
                           control2: CGPoint(x: w + c2.x, y: h + c2.y))
            }
        } else {
            Corner.add(to: &p, at: CGPoint(x: w, y: h), d1: CGVector(dx: 0, dy: -1), d2: CGVector(dx: -1, dy: 0), t1: tv, t2: th)
        }
        p.addLine(to: CGPoint(x: eh, y: h))
        Corner.add(to: &p, at: CGPoint(x: 0, y: h), d1: CGVector(dx: 1, dy: 0), d2: CGVector(dx: 0, dy: -1), t1: th, t2: tv)
        p.closeSubpath()

        let mirror = outgoing ? CGAffineTransform.identity
                              : CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        return p.applying(mirror.concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }

    /// The tail, relative to the body's bottom-right corner: in from the right side, down to the tip
    /// and back up into the bottom edge 22.23 pt from the corner.
    private static let tailSegments: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 0, y: -15.8065), CGPoint(x: -1.4251, y: -11.5844), CGPoint(x: -4.0568, y: -8.1338)),
        (CGPoint(x: -5.1232, y: -6.7358), CGPoint(x: -6.3545, y: -5.5035), CGPoint(x: -7.7150, y: -4.4552)),
        (CGPoint(x: -9.6538, y: -2.9434), CGPoint(x: -10.4928, y: -1.3662), CGPoint(x: -10.4928, y: 0.4065)),
        (CGPoint(x: -10.4928, y: 1.5980), CGPoint(x: -10.2823, y: 2.7754), CGPoint(x: -8.5711, y: 5.0234)),
        (CGPoint(x: -7.7502, y: 6.1011), CGPoint(x: -8.5741, y: 7.2009), CGPoint(x: -9.8572, y: 6.7134)),
        (CGPoint(x: -12.4961, y: 5.7113), CGPoint(x: -15.5015, y: 3.8873), CGPoint(x: -18.1342, y: 1.9404)),
        (CGPoint(x: -20.4930, y: 0.1960), CGPoint(x: -21.1215, y: 0.0197), CGPoint(x: -22.2284, y: 0.0127)),
    ]

    /// One continuous corner of radius 20.14. Distances are measured from the corner along side 1 (the
    /// side the outline arrives on, `d1`) and side 2 (`d2`); `t1`/`t2` place each side between its pill
    /// and full control points.
    private enum Corner {
        private static let radius: CGFloat = 20.1436
        private static let fullExtent: CGFloat = 30.7927
        // Each pair is (pill, full).
        private static let a1: (CGFloat, CGFloat) = (17.5906, 21.9261)
        private static let b1: (CGFloat, CGFloat) = ( 0.4853,  0.0)
        private static let c1y: (CGFloat, CGFloat) = (15.0608, 17.4928)
        private static let p1x: (CGFloat, CGFloat) = ( 1.4301,  1.5090)
        private static let p1y: (CGFloat, CGFloat) = (12.6891, 12.7205)
        private static let f: (CGFloat, CGFloat) = ( 3.4776,  3.4055)
        private static let g: (CGFloat, CGFloat) = ( 7.5491,  7.5100)

        static func progress(side: CGFloat) -> CGFloat {
            min(1, max(0, (side / 2 - radius) / (fullExtent - radius)))
        }
        static func extent(_ t: CGFloat) -> CGFloat { lerp((radius, fullExtent), t) }

        private static func lerp(_ v: (CGFloat, CGFloat), _ t: CGFloat) -> CGFloat { v.0 + (v.1 - v.0) * t }

        static func add(to p: inout Path, at c: CGPoint, d1: CGVector, d2: CGVector, t1: CGFloat, t2: CGFloat) {
            func pt(_ s1: CGFloat, _ s2: CGFloat) -> CGPoint {
                CGPoint(x: c.x + d1.dx * s1 + d2.dx * s2, y: c.y + d1.dy * s1 + d2.dy * s2)
            }
            p.addCurve(to: pt(lerp(p1y, t1), lerp(p1x, t1)),
                       control1: pt(lerp(a1, t1), 0),
                       control2: pt(lerp(c1y, t1), lerp(b1, t1)))
            p.addCurve(to: pt(lerp(p1x, t2), lerp(p1y, t2)),
                       control1: pt(lerp(g, t1), lerp(f, t1)),
                       control2: pt(lerp(f, t1), lerp(g, t2)))
            p.addCurve(to: pt(0, extent(t2)),
                       control1: pt(lerp(b1, t2), lerp(c1y, t2)),
                       control2: pt(0, lerp(a1, t2)))
        }
    }
}

/// The fill behind a bubble. A reply is flat grey; a question takes its shade from a blue gradient
/// that spans the whole transcript viewport, as in Messages, so bubbles lighten toward the top of the
/// screen and shift as they scroll.
struct MessageBubbleFill: View {
    static let space = "coach.transcript"
    let outgoing: Bool
    let viewportHeight: CGFloat

    var body: some View {
        if outgoing {
            GeometryReader { geo in
                let frame = geo.frame(in: .named(Self.space))
                let height = max(frame.height, 1)
                LinearGradient(colors: [StrandPalette.messageOutgoingTop, StrandPalette.messageOutgoingBottom],
                               startPoint: UnitPoint(x: 0.5, y: -frame.minY / height),
                               endPoint: UnitPoint(x: 0.5, y: (max(viewportHeight, frame.maxY) - frame.minY) / height))
            }
        } else {
            StrandPalette.messageIncoming
        }
    }
}

// MARK: - Motion

/// The curves Messages moves with, evaluated by time so an animation can follow a target that is
/// itself moving (the transcript scrolls while a bubble flies into it).
enum MessageMotion {
    /// A CSS-style cubic-bezier timing curve at `x` in 0…1.
    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        func coord(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
        }
        var lo = 0.0, hi = 1.0, s = x
        for _ in 0..<24 {
            s = (lo + hi) / 2
            if coord(s, x1, x2) < x { lo = s } else { hi = s }
        }
        return coord(s, y1, y2)
    }

    /// Core Animation's default curve.
    static func standard(_ x: Double) -> Double { bezier(x, 0.25, 0.1, 0.25, 1) }

    /// A damped spring from 0 to 1 (SwiftUI's `response` / `dampingFraction`), with an initial velocity
    /// in fractions per second.
    static func spring(_ t: Double, response: Double, damping: Double, velocity: Double = 0) -> Double {
        guard t > 0 else { return 0 }
        let w = 2 * Double.pi / response
        if damping < 1 {
            let wd = w * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * w * t) * (cos(wd * t) + ((damping * w - velocity) / wd) * sin(wd * t))
        }
        return 1 - exp(-w * t) * (1 + (w - velocity) * t)
    }

    /// Straight-line interpolation through measured `(time, value)` samples.
    static func samples(_ t: Double, _ points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for (a, b) in zip(points, points.dropFirst()) where t <= b.0 {
            return a.1 + (b.1 - a.1) * (t - a.0) / (b.0 - a.0)
        }
        return last.1
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
}

// MARK: - Sending

/// A question on its way from the field into the transcript.
struct OutgoingFlight: Equatable {
    let text: String
    /// The field's frame when it was sent, in the transcript's coordinate space.
    let from: CGRect
    let start: Date
    /// The transcript message it becomes, once the engine has appended it.
    var messageID: UUID?

    /// Long enough for the spring to settle.
    static let duration: TimeInterval = 0.75
}

/// Where a flight lands, kept by reference and outside observation: the landing bubble updates it as
/// the transcript scrolls and the flight reads it each frame, without redrawing anything else.
final class FlightTarget {
    var rect: CGRect?
    /// The flight's own clock. SwiftUI draws on the main thread, which building the request can hold
    /// for a tenth of a second; a frame after such a pause moves the flight on by at most 1/30 s, so it
    /// resumes where it was instead of skipping ahead (Messages animates off the main thread and never
    /// pauses at all).
    private(set) var elapsed: TimeInterval = 0
    private var lastFrame: Date?

    func restart() {
        elapsed = 0
        lastFrame = nil
    }

    /// Ends the flight where it stands: its clock jumps to the settled end, so the waiting sender lets the
    /// bubble underneath take over. For a flight caught by the quiet-motion gate mid-air.
    func land() {
        elapsed = OutgoingFlight.duration
        lastFrame = nil
    }

    func tick(_ now: Date) -> TimeInterval {
        if let lastFrame { elapsed += min(max(0, now.timeIntervalSince(lastFrame)), 1.0 / 30) }
        lastFrame = now
        return elapsed
    }
}

/// Messages' send: the field's text turns into a bubble where it was typed, narrows to its text while
/// dipping to 78 % and springing back, and flies to its place in the transcript. Curves are measured
/// from the Messages app frame by frame: the travel is a spring (response 0.54, damping 0.71), the
/// narrowing a critically damped one (0.22), the size and the fade-in follow the recorded samples.
struct FlyingMessageBubble: View {
    let flight: OutgoingFlight
    /// Where the bubble lands, read live: the transcript scrolls while it flies.
    let target: FlightTarget
    let viewportHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    /// Under Reduce Motion / Quiet Motion there is no flight: the question simply appears in place.
    var body: some View {
        let still = motion.poseStill(reduceMotion)
        // Still, there is no timeline at all: a paused one keeps the render server busy.
        Group {
            if still {
                Color.clear
            } else {
                TimelineView(.animation(minimumInterval: nil)) { context in
                    bubble(at: target.tick(context.date))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { if still { target.land() } }
        .onChangeCompat(of: still) { if $0 { target.land() } }
    }

    private func bubble(at t: TimeInterval) -> some View {
        let from = CGRect(x: flight.from.minX, y: flight.from.minY,
                          width: flight.from.width, height: flight.from.height + MessageBubbleShape.tailHeight)
        let to = target.rect ?? from
        let travel = MessageMotion.spring(t, response: 0.54, damping: 0.71)
        let narrow = MessageMotion.spring(t, response: 0.22, damping: 1, velocity: 8)
        let width = MessageMotion.lerp(from.width, to.width, narrow)
        let height = MessageMotion.lerp(from.height, to.height, narrow)
        let right = MessageMotion.lerp(from.maxX, to.maxX, travel)
        let bottom = MessageMotion.lerp(from.maxY, to.maxY, travel)
        return Text(flight.text)
            .font(StrandFont.pro(17))
            .foregroundStyle(StrandPalette.messageOutgoingText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: max(0, to.width - 28), alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: width, height: height, alignment: .topLeading)
            .background {
                MessageBubbleFill(outgoing: true, viewportHeight: viewportHeight)
                    .clipShape(MessageBubbleShape(outgoing: true, tail: true))
            }
            .scaleEffect(Self.scale(t), anchor: .bottomTrailing)
            .opacity(Self.opacity(t))
            .position(x: right - width / 2, y: bottom - height / 2)
    }

    private static func scale(_ t: Double) -> CGFloat {
        CGFloat(MessageMotion.samples(t, [(0, 1), (0.063, 0.866), (0.113, 0.81), (0.16, 0.78), (0.2, 0.79),
                                          (0.235, 0.836), (0.265, 0.87), (0.3, 0.92), (0.333, 0.95),
                                          (0.365, 0.964), (0.4, 0.99), (0.45, 1.006), (0.5, 1)]))
    }

    private static func opacity(_ t: Double) -> Double {
        MessageMotion.samples(t, [(0, 0.6), (0.063, 0.72), (0.097, 0.83), (0.132, 0.97), (0.15, 1)])
    }
}

// MARK: - Typing

/// Messages' typing indicator: a grey 57.5 × 35 capsule with two small circles trailing from its
/// bottom-left corner, three dots fading between 20 % and 45 % a quarter-second apart.
///
/// Its motion is ChatKit's: the circles grow in one after another (small, then 0.065 s and 0.12 s
/// later the medium and the capsule), each from nothing over 0.25 s while nudged out and back along
/// its own offset over 0.4 s; they then breathe (the small by 15 % over 0.7 s, the medium 10 % over
/// 0.9 s, the capsule 3 % over 1.9 s); and on `endedAt` everything shrinks away over 0.25 s. Posed
/// still, whole and unmoving, under Reduce Motion / Quiet Motion.
struct MessageTypingIndicator: View {
    var still: Bool
    var appearedAt: Date
    var endedAt: Date?

    /// The room it takes below its capsule, like a bubble's tail.
    static let overhang: CGFloat = 6.71
    /// How long it takes to shrink away.
    static let shrinkDuration: TimeInterval = 0.25

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    var body: some View {
        // The caller's `still`, or the gate read here, so the indicator can never loop past it.
        let still = self.still || motion.poseStill(reduceMotion)
        // Still, the frame is drawn once with no timeline behind it: a paused one keeps the render server busy.
        if still {
            frame(at: Date(), still: true)
        } else {
            TimelineView(.animation(minimumInterval: nil)) { context in
                frame(at: context.date, still: false)
            }
        }
    }

    private func frame(at date: Date, still: Bool) -> some View {
        Group {
            let t = date.timeIntervalSince(appearedAt)
            let gone = endedAt.map { 1 - MessageMotion.bezier(date.timeIntervalSince($0) / Self.shrinkDuration, 0.25, 0, 0.25, 1) } ?? 1
            ZStack(alignment: .topLeading) {
                Circle().fill(StrandPalette.messageIncoming)
                    .frame(width: 5, height: 5)
                    .modifier(Grow(t: t, begin: 0, offset: CGSize(width: 5.5, height: -2.5), yCurve: (0.33163, 0.1),
                                   pulse: (0.15, 0.7), anchor: UnitPoint(x: 0.318, y: 0.318), gone: gone, still: still))
                    .offset(x: -4.95, y: 36.71)
                Circle().fill(StrandPalette.messageIncoming)
                    .frame(width: 11.5, height: 11.5)
                    .modifier(Grow(t: t, begin: 0.065, offset: CGSize(width: 5, height: 3.5), yCurve: (0.33163, 0.1),
                                   pulse: (0.1, 0.9), anchor: UnitPoint(x: 0.326, y: 0.37), gone: gone, still: still))
                    .offset(x: -0.11, y: 26.55)
                Capsule().fill(StrandPalette.messageIncoming)
                    .frame(width: 57.5, height: 35)
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(StrandPalette.messageTypingDot)
                                    .frame(width: 8.5, height: 8.5)
                                    .opacity(still ? 0.32 : Self.dotOpacity(t - Double(i) * 0.25))
                            }
                        }
                        .offset(x: 11.67, y: 13.33)
                    }
                    .modifier(Grow(t: t, begin: 0.12, offset: CGSize(width: 5, height: -6), yCurve: (0.20918, 0.25816),
                                   pulse: (0.03, 1.9), anchor: UnitPoint(x: 0.185, y: 0.28), gone: gone, still: still))
            }
            .frame(width: 57.5, height: 35, alignment: .topLeading)
        }
    }

    /// 0.2 → 0.45 over half a second and back, on the system's curve for it.
    private static func dotOpacity(_ t: Double) -> Double {
        let phase = t.truncatingRemainder(dividingBy: 1).magnitude
        let u = phase < 0.5 ? phase / 0.5 : (1 - phase) / 0.5
        return 0.2 + 0.25 * MessageMotion.bezier(u, 0.75673, 0.015306, 0.58, 1)
    }

    /// One circle's grow-in, breathing and shrink-away.
    private struct Grow: ViewModifier {
        let t: Double
        let begin: Double
        let offset: CGSize
        /// The first control point of the vertical nudge's curve (the second is 0.56122, 0.95408).
        let yCurve: (Double, Double)
        /// How much it breathes and over how long.
        let pulse: (amount: Double, period: Double)
        let anchor: UnitPoint
        let gone: Double
        let still: Bool

        func body(content: Content) -> some View {
            let local = t - begin
            let grown = still ? 1 : MessageMotion.standard(local / 0.25)
            let nudge = local / 0.4
            let bump = { (u: Double) in u < 0.5 ? u / 0.5 : (1 - u) / 0.5 }
            let dx = still || nudge >= 1 ? 0 : offset.width * bump(MessageMotion.standard(nudge))
            let dy = still || nudge >= 1 ? 0 : offset.height * bump(MessageMotion.bezier(nudge, yCurve.0, yCurve.1, 0.56122, 0.95408))
            let cycle = t.truncatingRemainder(dividingBy: pulse.period).magnitude / pulse.period
            let eased = MessageMotion.bezier(cycle, 0.42, 0, 0.58, 1)
            let breath = still ? 1 : 1 + pulse.amount * (1 - abs(2 * eased - 1))
            content
                .scaleEffect(CGFloat(max(0, grown * breath * gone)), anchor: anchor)
                .offset(x: dx, y: dy)
        }
    }
}

// MARK: - Header

/// Messages' conversation header: the contact circle (here the Coach glyph on the contact gradient)
/// with a glass capsule carrying the name and a chevron, overlapping its bottom edge.
struct CoachConversationHeader: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: -4.33) {
                Circle()
                    .fill(LinearGradient(colors: [StrandPalette.messageAvatarTop, StrandPalette.messageAvatarBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(StrandFont.pro(27, weight: .medium))
                            .foregroundStyle(StrandPalette.messageOutgoingText)
                    }
                    .frame(width: 60.33, height: 60.33)
                HStack(spacing: 4) {
                    Text("Coach")
                        .font(StrandFont.pro(17, weight: .semibold))
                        .foregroundStyle(StrandPalette.messageIncomingText)
                    Image(systemName: "chevron.right")
                        .font(StrandFont.pro(11, weight: .bold))
                        .foregroundStyle(StrandPalette.messagePlaceholder)
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 30.33)
                .messageGlass(Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Coach settings"))
    }
}

// MARK: - Glass

extension View {
    /// Interactive Liquid Glass in `shape` (iOS 26 / macOS 26); a bar material with a hairline before.
    @ViewBuilder
    func messageGlass<S: InsettableShape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.messageMaterial(shape)
        }
        #else
        self.messageMaterial(shape)
        #endif
    }

    private func messageMaterial<S: InsettableShape>(_ shape: S) -> some View {
        self
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
    }
}

// MARK: - Times

/// When each message first appeared, so the transcript can print Messages' "Today 09:41" stamps. The
/// engine's messages carry no time of their own; this keeps one per message id, recorded by the screen
/// as a message arrives and dropped once the message leaves the transcript. A message restored from a
/// launch before it was recorded simply has no time, and no stamp is invented for it.
enum CoachMessageTimes {
    private static let key = "coach.messageTimes"

    static func load() -> [UUID: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        var out: [UUID: Date] = [:]
        for (id, seconds) in raw {
            if let uuid = UUID(uuidString: id) { out[uuid] = Date(timeIntervalSince1970: seconds) }
        }
        return out
    }

    static func save(_ times: [UUID: Date]) {
        let raw = Dictionary(uniqueKeysWithValues: times.map { ($0.key.uuidString, $0.value.timeIntervalSince1970) })
        UserDefaults.standard.set(raw, forKey: key)
    }
}
