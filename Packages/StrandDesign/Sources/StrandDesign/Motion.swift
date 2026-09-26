import SwiftUI

// MARK: - Strand Motion (§9.6)
//
// Physiological motion — breathe / pulse / flow, no cartoon bounce.
// Ring draw-in, per-beat ripple, hover lift, sliding sidebar indicator.

public enum StrandMotion {

    // MARK: Spring presets

    /// Interactive spring — snappy, for direct manipulation (hover, press, sidebar slide).
    public static let interactive = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.1)

    /// Gentle spring — the house style for value changes (ring draw-in, gauges).
    /// spring(response: 0.5, damping: 0.8) per the brief.
    public static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// A slower, more deliberate spring for hero transitions (e.g. first ring materialize).
    public static let hero = Animation.spring(response: 0.85, dampingFraction: 0.85)

    // MARK: Durations

    /// Fast UI feedback (hover lift, chip state).
    public static let durationFast: Double = 0.18

    /// Standard transition (card appear, fades).
    public static let durationStandard: Double = 0.30

    /// Slow / draw-in (ring arc, waveform ignite).
    public static let durationSlow: Double = 0.9

    /// One breath cycle for ambient pulsing (bloom, listening flatline).
    public static let breathPeriod: Double = 3.2

    // MARK: Curves

    /// Ease for the ring/gauge draw-in when a value changes.
    public static let drawIn = Animation.easeOut(duration: durationSlow)

    /// The ring/gauge draw-in, suppressed when Reduce Motion is on. Returns `nil`
    /// (no animation) when reduced so `withAnimation` sets the fraction instantly and
    /// the arc/bead snaps to its final frame instead of sweeping. Mirrors
    /// `breathe(reduced:)` and honours Apple's Reduce Motion HIG.
    public static func drawIn(reduced: Bool) -> Animation? {
        reduced ? nil : drawIn
    }

    /// Looping breathe animation for ambient glow/pulse.
    public static var breathe: Animation {
        .easeInOut(duration: breathPeriod).repeatForever(autoreverses: true)
    }

    /// Looping breathe animation, suppressed when Reduce Motion is on. Returns
    /// `nil` (no animation) when reduced so call sites collapse to the resting
    /// frame instead of an indefinite loop. Honours Apple's Reduce Motion HIG.
    public static func breathe(reduced: Bool) -> Animation? {
        reduced ? nil : breathe
    }

    /// A single heartbeat ripple pulse.
    public static let pulse = Animation.easeOut(duration: 0.6)

    /// Standard fade.
    public static let fade = Animation.easeInOut(duration: durationStandard)

    // MARK: Sync signal

    /// Grace period a screen applies to the falling edge of the raw sync signal before it reflects the
    /// sync as over: `backfilling` drops between history chunks, and without this a status control would
    /// flap back to its idle reading in the middle of one logical sync.
    public static let syncIndicatorSignalDebounceNanoseconds: UInt64 = 3_000_000_000
}
