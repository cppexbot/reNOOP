//  BarButtons.swift
//  NOOP · the toolbar's buttons, one of each: ✕ to close a sheet, ✓ to finish it, and the monochrome glyph every
//  other bar button draws — as iOS 26's own apps (Health's ‹ and +, Fitness's ✕ and ✓) do.

import SwiftUI
import StrandDesign

/// ✕ in the leading toolbar slot: the iOS 26 close role (a glass circle), a plain xmark before it.
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Group {
            #if compiler(>=6.2)
            if #available(iOS 26.0, macOS 26.0, *) {
                Button(role: .close, action: action)
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .tint(StrandPalette.textPrimary)
    }

    private var fallback: some View {
        Button(action: action) { Image(systemName: "xmark") }
            .accessibilityLabel(Text("Close"))
    }
}

/// ✓ in the trailing toolbar slot — Done / Save / Add: the iOS 26 confirm role (a tinted glass circle), a
/// checkmark before it. Exercise green in Fitness's sheets, the accent blue in Health's.
struct SheetConfirmButton: View {
    /// Fitness's green by default; Health's sheets confirm in blue.
    var tint: Color = StrandPalette.activityExerciseText
    let action: () -> Void

    var body: some View {
        Group {
            #if compiler(>=6.2)
            if #available(iOS 26.0, macOS 26.0, *) {
                // White on the tinted glass, as the system's own ✓. The bare confirm role draws its glyph in a
                // lighter shade of the tint instead, which on NOOP's accent came out cyan.
                Button(role: .confirm, action: action) {
                    Image(systemName: "checkmark").foregroundStyle(glyph)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel(Text("Done"))
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .tint(tint)
    }

    /// White on blue; on Fitness's green the glyph Fitness puts there (`fitnessOnAccent`, black in dark).
    private var glyph: Color {
        tint == StrandPalette.activityExerciseText ? StrandPalette.fitnessOnAccent : .white
    }

    private var fallback: some View {
        Button(action: action) { Image(systemName: "checkmark") }
            .accessibilityLabel(Text("Done"))
    }
}

extension View {
    /// A bar button's glyph in the label colour, as iOS 26 draws Health's and Fitness's toolbar glyphs; the accent
    /// stays for links in the content. Put on a toolbar `Button` or `Menu`.
    func barGlyph() -> some View { tint(StrandPalette.textPrimary) }
}
