//  MetricStressDay.swift
//  NOOP · the Stress metric page's "Today" card — today's stress hour by hour.
//
//  Health draws a day's readings as one bar per hour under the day's figure (Heart Rate on its Day
//  range). This is the same card for the 0–3 daily stress score: each waking hour scored with the
//  daily score's own proxy (`DaytimeStress`), read through `StressDayCurve` so the page, the widget
//  and the Summary agree on one curve. Hidden when today has nothing scored.

import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics

struct MetricStressDayCard: View {
    @EnvironmentObject private var repo: Repository
    let metric: MetricDescriptor
    let tint: Color
    let units: MetricHealthStyle.Units

    @State private var day: DaytimeStress.Result?

    /// Only the strap's 0–3 score has an intraday read; the imported 0–100 series does not.
    static func applies(to metric: MetricDescriptor) -> Bool {
        metric.key == "stress" && metric.source == "my-whoop"
    }

    var body: some View {
        // A VStack, not a Group: an empty Group is no view at all, and its `.task` would never run.
        VStack(alignment: .leading, spacing: 0) {
            if let day, !day.scored.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Today")
                    SummaryCard { card(day) }
                }
            }
        }
        .task(id: repo.refreshSeq) {
            day = await StressDayCurve.today(repo: repo,
                                             personalBaseline: PuffinExperiment.stressPersonalBaselineEnabled)?.result
        }
    }

    private func card(_ day: DaytimeStress.Result) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AVERAGE")
                    .font(StrandFont.pro(13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                if let mean = day.dayMean {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        ForEach(Array(MetricHealthStyle.tokens(metric, mean, units: units).enumerated()), id: \.offset) { _, t in
                            Text(verbatim: t.text)
                                .font(t.isUnit ? StrandFont.pro(17, weight: .semibold) : StrandFont.pro(34, weight: .bold))
                                .foregroundStyle(t.isUnit ? StrandPalette.textSecondary : StrandPalette.textPrimary)
                        }
                    }
                }
            }
            chart(day)
                .frame(height: 160)
                .padding(.top, NoopMetrics.space4)
        }
        .padding(.top, 4)
    }

    private func chart(_ day: DaytimeStress.Result) -> some View {
        Chart {
            ForEach(day.hours, id: \.hour) { h in
                if let level = h.level {
                    // Centred in its hour; a fixed width because a numeric axis has no band for `.ratio`.
                    BarMark(x: .value("Hour", Double(h.hour) + 0.5), y: .value("Stress", max(level, 0.05)),
                            width: .fixed(7))
                        .foregroundStyle(tint)
                        .cornerRadius(3.5)
                }
            }
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: 0...3)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: NoopMetrics.hairlineWidth, dash: [2, 3]))
                    .foregroundStyle(StrandPalette.hairline)
                AxisValueLabel(anchor: .topLeading) {
                    if let hour = value.as(Int.self) {
                        Text(verbatim: hourLabel(hour))
                            .font(StrandFont.pro(12))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 1, 2, 3]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: NoopMetrics.hairlineWidth))
                    .foregroundStyle(StrandPalette.hairline)
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(verbatim: "\(v)")
                            .font(StrandFont.pro(12))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary(day)))
    }

    /// Hour-of-day tick in the user's clock format ("00", "06", "12", "18" or "12 AM", "6 AM", …).
    private func hourLabel(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(.dateTime.hour().locale(AppLanguage.activeLocale))
    }

    private func accessibilitySummary(_ day: DaytimeStress.Result) -> String {
        day.scored.map { "\(hourLabel($0.hour)) \(StressTrace.formatLevel($0.level ?? 0))" }.joined(separator: ", ")
    }
}
