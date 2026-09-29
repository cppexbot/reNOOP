//  SleepPageCards.swift
//  NOOP · Sleep — the Sleep highlight card: the category, the sentence, the two figures and the nights
//  behind them, as Health sets a Sleep highlight.
//
//  Presentation only. The highlight arrives resolved from the caller.

import SwiftUI
import StrandDesign

/// A Highlights card as the Health app sets one: the category, the sentence, then two figures side by
/// side over the nights behind them — grey bars, the average as a line, the newest bar in colour.
struct SleepHighlightCard: View {
    let highlight: SleepHighlight

    /// The average a night is read against, in grey as Health draws it; the reading itself in the Sleep hue.
    private let averageTint = StrandPalette.textSecondary
    private let latestTint = StrandPalette.sleepScoreTitle

    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        HighlightCard(icon: "bed.double.fill", title: String(localized: "Sleep"), tint: latestTint,
                      sentence: highlight.sentence, spacing: 10, showsEvidence: highlight.detail != nil) {
            if let detail = highlight.detail { figures(detail) }
        } chart: {
            if let detail = highlight.detail {
                bars(detail)
                    .frame(height: 44)
            }
        }
    }

    /// Side by side; one under the other at accessibility sizes.
    @ViewBuilder private func figures(_ detail: SleepHighlight.Detail) -> some View {
        let stacked = dts.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top))
        switch detail {
        case .bedtime(let usual, let last, _):
            layout {
                figure(String(localized: "sleep.hl.avgBedtime", defaultValue: "Average Bedtime"), .text(SleepMoreDataView.clock(minutesOfNight: usual)),
                       tint: averageTint)
                if !stacked { Spacer() }
                figure(String(localized: "Last Night's Bedtime"), .text(SleepMoreDataView.clock(minutesOfNight: last)),
                       tint: latestTint, trailing: !stacked)
            }
        case .duration(let average, let prior, _):
            layout {
                figure(String(localized: "sleep.hl.avgAsleep", defaultValue: "Average Time Asleep"), .duration(average), tint: averageTint)
                if !stacked { Spacer() }
                figure(String(localized: "Week Before"), .duration(prior), tint: StrandPalette.textSecondary,
                       trailing: !stacked)
            }
        }
    }

    private func figure(_ title: String, _ value: SleepCardValue, tint: Color, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(dts.isAccessibilitySize ? 2 : 1)
            SleepCardValueText(value: value, size: 22, tint: tint)
        }
    }

    /// The nights as bars on their own scale, the average as a line across them.
    private func bars(_ detail: SleepHighlight.Detail) -> some View {
        let values: [Double]
        let average: Double
        switch detail {
        case .bedtime(let usual, _, let nights): values = nights; average = usual
        case .duration(let avg, _, let nights): values = nights; average = avg
        }
        let lo = min(values.min() ?? 0, average), hi = max(values.max() ?? 1, average)
        let floor = lo - max(30, (hi - lo) * 0.6)
        func fraction(_ v: Double) -> CGFloat { CGFloat((v - floor) / max(1, hi - floor)) }
        return GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(i == values.count - 1 ? latestTint : StrandPalette.textTertiary.opacity(0.35))
                            .frame(height: max(3, geo.size.height * fraction(v)))
                            .frame(maxWidth: .infinity)
                    }
                }
                Capsule()
                    .fill(averageTint)
                    .frame(height: 3)
                    .offset(y: -(geo.size.height * fraction(average) - 1.5))
            }
        }
        .accessibilityHidden(true)
    }
}
