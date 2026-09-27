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

// MARK: - Typing

/// Messages' typing indicator: a grey 57.5 × 35 capsule with two small circles trailing from its
/// bottom-left corner, three dots fading between 20 % and 45 % a quarter-second apart, and the capsule
/// breathing by 3 %. Posed still under Reduce Motion / Quiet Motion.
struct MessageTypingIndicator: View {
    var still: Bool

    /// The room it takes below its capsule, like a bubble's tail.
    static let overhang: CGFloat = 6.71

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: still)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                Circle().fill(StrandPalette.messageIncoming)
                    .frame(width: 5, height: 5)
                    .offset(x: -4.95, y: 36.71)
                Circle().fill(StrandPalette.messageIncoming)
                    .frame(width: 11.5, height: 11.5)
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
                    .scaleEffect(still ? 1 : Self.breath(t), anchor: UnitPoint(x: 0.185, y: 0.28))
            }
            .frame(width: 57.5, height: 35, alignment: .topLeading)
        }
    }

    /// 0.2 → 0.45 over half a second and back, on the system's curve for it.
    private static func dotOpacity(_ t: Double) -> Double {
        let phase = t.truncatingRemainder(dividingBy: 1).magnitude
        let u = phase < 0.5 ? phase / 0.5 : (1 - phase) / 0.5
        return 0.2 + 0.25 * bezier(u, 0.75673, 0.015306, 0.58, 1)
    }

    /// 1 → 1.03 → 1 over 1.9 s, ease-in-ease-out.
    private static func breath(_ t: Double) -> CGFloat {
        let u = t.truncatingRemainder(dividingBy: 1.9).magnitude / 1.9
        let eased = bezier(u, 0.42, 0, 0.58, 1)
        return 1 + 0.03 * CGFloat(1 - abs(2 * eased - 1))
    }

    /// A CSS-style cubic-bezier timing curve evaluated at `x`.
    private static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
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
                .frame(height: 30.33)
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
