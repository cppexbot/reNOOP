//  InfoButton.swift
//  NOOP · the one ⓘ: a short explanation one tap away, in a popover — as Health's "About" and Fitness's info
//  bubbles open over the page rather than pushing one.

import SwiftUI
import StrandDesign

/// ⓘ that opens `content` in a popover, kept a popover on iPhone too (not a sheet). `.toolbar` is the plain
/// `info.circle` a bar button shows, tinted like its neighbours; `.circled` is the bold `info` on a small grey
/// disc that Health puts beside a chart's heading. The popover's text is set here, so every one reads alike.
struct InfoButton<Content: View>: View {
    enum Style { case toolbar, circled }

    var style: Style = .toolbar
    let label: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    @State private var shown = false
    @ScaledMetric(relativeTo: .subheadline) private var discSize: CGFloat = 30

    var body: some View {
        // A bar button keeps the bar's own button style (its glass on iOS 26); the disc draws itself.
        Group {
            if style == .circled {
                Button { shown = true } label: { glyph }.buttonStyle(.plain)
            } else {
                Button { shown = true } label: { glyph }.barGlyph()
            }
        }
        .accessibilityLabel(Text(label))
        .popover(isPresented: $shown, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) { content() }
                .font(StrandFont.pro(15))
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 320, alignment: .leading)
                .modifier(PopoverOnPhone())
        }
    }

    @ViewBuilder private var glyph: some View {
        switch style {
        case .toolbar:
            Image(systemName: "info.circle")
        case .circled:
            Image(systemName: "info")
                .font(StrandFont.pro(15, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: discSize, height: discSize)
                .background(StrandPalette.summaryCanvas, in: Circle())
                // A 44 pt target round the disc, laid out at the disc's size.
                .frame(width: max(44, discSize), height: max(44, discSize))
                .contentShape(Circle())
                .padding(-(max(44, discSize) - discSize) / 2)
        }
    }
}

/// A popover stays a popover on iPhone (iOS 16.4+), where it would otherwise become a sheet.
private struct PopoverOnPhone: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, macOS 13.3, *) {
            content.presentationCompactAdaptation(.popover)
        } else {
            content
        }
    }
}
