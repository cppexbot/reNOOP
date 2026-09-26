//  SleepPageCards.swift
//  NOOP · Sleep — the night card that heads the Sleep page: the Sleep score ring (iOS 26 Health's Sleep
//  Score ring) beside its word, then time asleep, time in bed, the bed → wake span and a thumbnail of the
//  night's stages.
//
//  Presentation only. The score and the night arrive from the caller, resolved as every other surface
//  resolves them.

import SwiftUI
import StrandDesign

struct SleepNightCard: View {
    /// nil when the night has no score (no scored row for its day).
    let score: SleepScore?
    /// "On-device" / "Whoop" / "Oura": where the score came from.
    let source: String?
    let stages: Stages
    let bedtime: Date
    let wake: Date
    /// The night's hypnogram, seconds from `bedtime`; the card draws it as a thumbnail when present.
    var intervals: [SleepInterval] = []

    var body: some View {
        SummaryCard {
            VStack(alignment: .leading, spacing: 14) {
                if let score {
                    HStack(spacing: 18) {
                        SleepScoreRing(score: score, lineWidth: 12)
                            .frame(width: 104, height: 104)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sleep Score")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                            Text(SleepScore.word(score.value))
                                .font(StrandFont.rounded(28, weight: .bold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let source {
                                Text(source)
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time Asleep")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    SleepCardValueText(value: .duration(stages.asleep), size: 34)
                    Text("In bed \(SleepFormat.duration(minutes: stages.total)) · \(Self.clock(bedtime)) – \(Self.clock(wake))")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if intervals.count >= 2 {
                    SleepStagesChart(intervals: intervals, onset: bedtime, compact: true)
                        .frame(height: 64)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale))
    }
}

/// A Highlights card as the Health app sets one: the category, the sentence, then two figures side by
/// side over the nights behind them — grey bars, the average as a line, the newest bar in colour.
struct SleepHighlightCard: View {
    let highlight: SleepHighlight

    private let averageTint = StrandPalette.sleepScoreRestorative
    private let latestTint = StrandPalette.healthSleepDeep

    var body: some View {
        SummaryCard {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Sleep").font(StrandFont.headline)
                } icon: {
                    Image(systemName: "bed.double.fill")
                }
                .foregroundStyle(StrandPalette.healthSleepDeep)
                Text(highlight.sentence)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = highlight.detail {
                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    figures(detail)
                    bars(detail)
                        .frame(height: 44)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func figures(_ detail: SleepHighlight.Detail) -> some View {
        switch detail {
        case .bedtime(let usual, let last, _):
            HStack(alignment: .top) {
                figure(String(localized: "sleep.hl.avgBedtime", defaultValue: "Average Bedtime"), .text(SleepMoreDataView.clock(minutesOfNight: usual)),
                       tint: averageTint)
                Spacer()
                figure(String(localized: "Last Night's Bedtime"), .text(SleepMoreDataView.clock(minutesOfNight: last)),
                       tint: latestTint, trailing: true)
            }
        case .duration(let average, let prior, _):
            HStack(alignment: .top) {
                figure(String(localized: "sleep.hl.avgAsleep", defaultValue: "Average Time Asleep"), .duration(average), tint: averageTint)
                Spacer()
                figure(String(localized: "Week Before"), .duration(prior), tint: StrandPalette.textSecondary,
                       trailing: true)
            }
        }
    }

    private func figure(_ title: String, _ value: SleepCardValue, tint: Color, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
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
