import SwiftUI

// MARK: - The locked component system
//
// Every screen composes ONLY these. Fixed dimensions + one spacing scale guarantee
// the uniform, instrument-grade look from the reference. Do not invent ad-hoc cards.

public enum NoopMetrics {
    public static let cardRadius: CGFloat = NoopVisualStyle.cardRadius
    public static let cardPadding: CGFloat = NoopVisualStyle.cardPadding
    public static let gap: CGFloat = NoopVisualStyle.itemGap
    public static let sectionGap: CGFloat = NoopVisualStyle.sectionGap
    public static let screenPadding: CGFloat = NoopVisualStyle.pagePadding
    /// Height of the floating tab bar, for chrome laid OVER the `TabView` itself (the pre-iOS 26.1
    /// mini-player capsule). Never pad scroll content with it: a system `TabView` already insets its
    /// scroll views by the bar and bottom accessory, and sheets and macOS have no bar at all (Craft-4).
    public static let tabBarClearance: CGFloat = 76
    /// Canonical diameter for compact circular controls in dense header chrome.
    public static let compactControlSize: CGFloat = 36
    /// Even inset around a header control before applying exact-bounds Liquid Glass, matching the inset
    /// the system's `.small` glass chrome gives sibling header circles. Equal on both axes so the
    /// control stays circular.
    public static let syncIndicatorGlassPadding: CGFloat = 5

    // MARK: Standardised spacing scale (the ONE source of truth for margins)
    //
    // A 4pt-based ramp. Reach for these instead of literal numbers so every gap,
    // inset and margin lines up to the same grid. Note `cardPadding` (16) above is
    // the same value as `space4` — kept as a named alias for the existing call sites.
    public static let space1:  CGFloat = 4
    /// Optical separation for paired labels; structural layout still follows the 4-point ramp.
    public static let spaceHalf: CGFloat = 2
    public static let space2:  CGFloat = 8
    public static let space3:  CGFloat = 12
    public static let space4:  CGFloat = 16
    public static let space5:  CGFloat = 20
    public static let space6:  CGFloat = 24
    public static let space8:  CGFloat = 32

    // MARK: Named layout constants — the canonical margins/heights screens compose with.
    /// Horizontal page margin (the gutter on the left/right edge of a screen). Use via `.screenPadding()`.
    public static let screenHPadding: CGFloat = NoopVisualStyle.pagePadding
    /// Vertical gap between stacked elements INSIDE a card.
    public static let cardInnerSpacing: CGFloat = 12
    /// Standard one-pixel edge used by cards and compact controls.
    public static let hairlineWidth: CGFloat = 1
    /// Fully-rounded corner radius — pills, chips, capsule buttons.
    public static let pillRadius: CGFloat = NoopVisualStyle.pillRadius
    /// Minimum desktop size for a navigation-based customization sheet.
    public static let editorSheetMinWidth: CGFloat = 440
    public static let editorSheetMinHeight: CGFloat = 600
}

// MARK: - Screen padding

public extension View {
    /// Apply the canonical horizontal page gutter (`NoopMetrics.screenHPadding`). The single
    /// source of truth for left/right screen margins — use this instead of a literal padding so
    /// every screen lines up to the same edge.
    func screenPadding() -> some View {
        self.padding(.horizontal, NoopMetrics.screenHPadding)
    }
}

// MARK: - iOS sheet presentation idiom

#if os(iOS)
public extension View {
    /// The house iOS sheet idiom: detents plus the grabber, which appears only when the sheet
    /// has more than one detent to drag between. macOS sheets are free-floating windows and must
    /// NOT receive this, so the helper is iOS-only and call sites stay shared via #if.
    /// `largeFirst == false` opens at .medium with .large reachable by dragging up (short
    /// forms); `true` opens full-height (long scrolls).
    func noopSheetPresentation(largeFirst: Bool) -> some View {
        self
            // A single detent cannot be resized, so it shows no grabber (K-10).
            .presentationDragIndicator(largeFirst ? .hidden : .visible)
            .presentationDetents(largeFirst ? [.large] : [.medium, .large])
    }
}
#endif

// MARK: - Surface

// MARK: - Section header

// MARK: - Metric tile (UNIFORM fixed height)

// Backward-compatible convenience: a StatTile with NO accessory (the common case) — every existing
// call site keeps working unchanged, and the type defaults `Accessory` to `EmptyView`.

// MARK: - Trend chip — a small tinted delta pill with a direction arrow.

// MARK: - Chart card (UNIFORM: header + fixed chart body + footer)

// MARK: - Range control (the ONE segmented pill control, used everywhere)

// MARK: - Badges

// MARK: - Numeric field helpers (iOS soft-keyboard)

public extension View {
    /// Configures a TextField for whole-number-or-decimal entry on iOS: the decimal-pad
    /// keyboard (handles both integer Avg-HR and decimal calories). No-op on macOS
    /// (hardware keyboard), so the SAME shared view compiles on both. Pair with
    /// `.keyboardDoneToolbar(...)` on the enclosing view to add a Done button (the decimal
    /// pad has no return key).
    /// `integer` gives whole-number fields (reps, sets, seconds) the number pad, which has no separator
    /// to type a fraction that would parse to nothing (CR-11).
    func numericKeyboard(integer: Bool = false) -> some View {
        #if os(iOS)
        self.keyboardType(integer ? .numberPad : .decimalPad).textContentType(nil)
        #else
        self
        #endif
    }

    /// Adds a single trailing "Done" button to the software-keyboard accessory bar that
    /// resigns the given focus binding. iOS-only; the keyboard toolbar is hosted by the
    /// keyboard itself, so it works inside a sheet with no NavigationStack. No-op on macOS.
    func keyboardDoneToolbar<Value: Hashable>(_ focus: FocusState<Value?>.Binding) -> some View {
        #if os(iOS)
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus.wrappedValue = nil }
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.accent)
            }
        }
        #else
        self
        #endif
    }
}

// MARK: - Buttons (Titanium & Gold) — ADDED additively, no existing API touched.
//
// Three house button styles for primary actions, secondary chrome and ghost/gold
// CTAs. Drop in via `.buttonStyle(.noopPrimary)` etc. on any `Button`. All read off
// the new gold tokens so they match Apple ⇄ Android. Pressed = subtle dim + scale.

// MARK: - Score state pill (SOLID / BUILDING / CALIBRATING / LIVE)
//
// ADDED additively — the existing `StatePill` (tone-based, in StatePill.swift) is
// untouched. This is the score-lifecycle chip the new design calls for: SOLID = gold
// fill, BUILDING = blue, CALIBRATING = slate, LIVE = gold dot with a pulsing halo.

public enum ScoreState: Sendable, Equatable {
    case solid        // a settled, trustworthy score
    case building     // accruing nights, not yet settled
    case calibrating  // baseline still forming
    case live         // streaming right now

    /// The chip's hue, drawn from the re-pointed palette (gold / blue / slate).
    public var color: Color {
        switch self {
        case .solid:        return StrandPalette.statusPositive // settled / trustworthy — WHOOP green
        case .live:         return StrandPalette.accent          // streaming now — WHOOP blue
        case .building:     return StrandPalette.sleepLight   // #4A90E2 blue
        case .calibrating:  return StrandPalette.textTertiary // #8A94A4 slate
        }
    }
    public var label: LocalizedStringKey {
        switch self {
        case .solid:       return "Solid"
        case .building:    return "Building"
        case .calibrating: return "Calibrating"
        case .live:        return "Live"
        }
    }
    var pulsing: Bool { self == .live }
}
