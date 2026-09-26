//  SleepMetricCards.swift
//  NOOP · Sleep — the Sleep page's data tiles: two to a row, each a small tinted glyph and title, the
//  figure large with its unit small, and at most one caption (the Health Summary-card idiom, compact).
//
//  Presentation only. The page resolves every figure from the same `SleepModel` / `DailyMetric` rows the
//  rest of the app reads and hands it in.

import SwiftUI
import StrandDesign

/// A figure as the Health cards set it: numbers large, units small and grey.
enum SleepCardValue {
    case duration(Double)
    case number(String, unit: String?)
    case text(String)
}

struct SleepCardValueText: View {
    let value: SleepCardValue
    var size: CGFloat = 26
    /// The figure's colour; units stay grey.
    var tint: Color = StrandPalette.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            switch value {
            case .duration(let minutes):
                let p = SleepFormat.parts(minutes: minutes)
                if p.hours > 0 {
                    number("\(p.hours)")
                    unit(String(localized: "sleep.unit.hr", defaultValue: "hr"))
                }
                if p.minutes > 0 || p.hours == 0 {
                    number("\(p.minutes)")
                    unit(String(localized: "sleep.unit.min", defaultValue: "min"))
                }
            case .number(let n, let u):
                number(n)
                if let u { unit(u) }
            case .text(let t):
                Text(t)
                    .font(StrandFont.rounded(size * 0.8, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func number(_ s: String) -> some View {
        Text(verbatim: s)
            .font(StrandFont.rounded(size, weight: .bold))
            .foregroundStyle(tint)
    }

    private func unit(_ s: String) -> some View {
        Text(verbatim: s)
            .font(StrandFont.rounded(size * 0.6, weight: .semibold))
            .foregroundStyle(StrandPalette.textSecondary)
            .padding(.trailing, 3)
    }
}

struct SleepMetricTile: Identifiable {
    let id: String
    let icon: String
    let title: String
    let tint: Color
    let value: SleepCardValue
    var caption: String? = nil
}

/// Tiles two to a row; a row's tiles share its height.
struct SleepTileGrid: View {
    let tiles: [SleepMetricTile]

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { i in
                GridRow {
                    tile(tiles[i])
                    if i + 1 < tiles.count {
                        tile(tiles[i + 1])
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private func tile(_ t: SleepMetricTile) -> some View {
        SummaryCard {
            VStack(alignment: .leading, spacing: 8) {
                // One line, and the glyph in a fixed-width slot, so every tile's title, figure and caption
                // sit on the same lines as its neighbour's.
                HStack(spacing: 6) {
                    Image(systemName: t.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 16, alignment: .center)
                    Text(t.title)
                        .font(StrandFont.subhead.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .foregroundStyle(t.tint)
                SleepCardValueText(value: t.value)
                if let caption = t.caption {
                    Text(caption)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
