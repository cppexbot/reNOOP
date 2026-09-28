//  NoticeCard.swift
//  NOOP · the one in-app notice, as Health and Fitness show theirs on iOS 26: a card with a glyph coloured
//  by what it means, a short title, at most one short sentence, at most one action, and ✕ (or a swipe)
//  when it can be put away. Every banner, status plaque and warning in the app draws through this.

import SwiftUI
import StrandDesign

struct NoticeCard: View {
    /// What the notice means, which colours its glyph.
    enum Tone {
        case info, progress, warning, error, success

        var color: Color {
            switch self {
            case .info:     return StrandPalette.settingsBlue
            case .progress: return StrandPalette.textSecondary
            case .warning:  return StrandPalette.settingsOrange
            case .error:    return StrandPalette.settingsRed
            case .success:  return StrandPalette.settingsGreen
            }
        }
    }

    let title: Text
    var message: Text?
    var systemImage: String = "info.circle.fill"
    var tone: Tone = .info
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?
    /// Set when the notice can be put away: shows ✕ and takes a sideways swipe.
    var onDismiss: (() -> Void)?

    @State private var dragX: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var glyphHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var closeSize: CGFloat = 24
    private var closeHit: CGFloat { max(44, closeSize) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            glyph
                .frame(width: glyphWidth, height: glyphHeight)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(StrandFont.pro(15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    message
                        .font(StrandFont.pro(15))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(StrandFont.pro(15, weight: .semibold))
                            .foregroundStyle(StrandPalette.settingsBlue)
                            // A 44 pt target around the text; the card keeps its height.
                            .contentShape(Rectangle().inset(by: -12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(StrandFont.pro(12, weight: .bold))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(width: closeSize, height: closeSize)
                        .background(StrandPalette.textTertiary.opacity(0.18), in: Circle())
                        // A 44 pt target round the 24 pt disc, without growing the card.
                        .frame(width: closeHit, height: closeHit)
                        .contentShape(Circle())
                        .padding(-(closeHit - closeSize) / 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.summaryCard,
                    in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
        .offset(x: dragX)
        .opacity(1 - min(abs(dragX) / 240, 0.6))
        .gesture(onDismiss == nil ? nil : swipe)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var glyph: some View {
        if tone == .progress {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { dragX = $0.translation.width }
            .onEnded { value in
                if abs(value.translation.width) > 100 {
                    withAnimation(StrandMotion.fade) { dragX = value.translation.width > 0 ? 500 : -500 }
                    onDismiss?()
                } else {
                    withAnimation(StrandMotion.fade) { dragX = 0 }
                }
            }
    }
}
