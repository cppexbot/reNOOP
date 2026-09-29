//  SleepMetricCards.swift
//  NOOP · Sleep — a figure as the Health cards set it (numbers large, units small and grey), shared by
//  the Sleep highlights and the Summary's Sleep card.

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

    /// Dynamic Type multipliers: a hero figure follows the large title, a card figure the title 2.
    @ScaledMetric(relativeTo: .title2) private var cardScale: CGFloat = 1
    @ScaledMetric(relativeTo: .largeTitle) private var heroScale: CGFloat = 1

    private var scaled: CGFloat { size * (size >= 30 ? heroScale : cardScale) }

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
                    .font(StrandFont.rounded(scaled * 0.8, weight: .bold))
                    .foregroundStyle(StrandPalette.text(for: tint))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func number(_ s: String) -> some View {
        Text(verbatim: s)
            .font(StrandFont.rounded(scaled, weight: .bold))
            .foregroundStyle(StrandPalette.text(for: tint))
    }

    private func unit(_ s: String) -> some View {
        Text(verbatim: s)
            .font(StrandFont.rounded(scaled * 0.6, weight: .semibold))
            .foregroundStyle(StrandPalette.textSecondary)
            .padding(.trailing, 3)
    }
}
