//  TrainingLoadView.swift
//  NOOP · Trends → Training Load — the long-horizon load model (CTL / ATL / form) on a page laid out like
//  a metric's: the W / M / 6M / Y picker, then one card with today's form, the period's dates and the two
//  load lines, and the latest fitness and fatigue under a hairline.
//
//  Descriptive only: the loads are NOOP's daily Effort, never TRIMP, and feed no score.

import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The load model read from the day history, and its figures as text.
enum TrainingLoadModel {
    static func evaluate(_ days: [DailyMetric]) -> TrainingLoadEngine.Result {
        TrainingLoadEngine.evaluate(days: days.map { TrainingLoadEngine.DailyLoad(day: $0.day, load: $0.strain) })
    }

    static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.activeLocale))
    }

    static func signed(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()).locale(AppLanguage.activeLocale))
    }
}

struct TrainingLoadView: View {
    @EnvironmentObject private var repo: Repository
    @State private var range: MetricHealthRange = .month
    @State private var result: TrainingLoadEngine.Result?

    private var calendar: Calendar { .current }
    private var locale: Locale { AppLanguage.activeLocale }

    private static let fitnessTint = StrandPalette.activityTitle
    private static let fatigueTint = StrandPalette.healthRespiratory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $range) {
                    ForEach(MetricHealthRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.bottom, 4)
                if let result {
                    if result.isAvailable {
                        card(result)
                    } else {
                        SummaryCard {
                            Text("Needs \(TrainingLoadEngine.Configuration.standard.minimumDays)+ consecutive days of Effort to begin. \(result.contiguousDays) so far.")
                                .font(StrandFont.pro(15))
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, NoopMetrics.space8)
                }
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, NoopMetrics.space2)
            .padding(.bottom, NoopMetrics.space8 + NoopMetrics.tabBarClearance)
            #if os(macOS)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            #endif
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("Training Load"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: repo.refreshSeq) { result = TrainingLoadModel.evaluate(repo.days) }
    }

    private struct Row: Identifiable {
        let date: Date
        let fitness: Double
        let fatigue: Double
        var id: Date { date }
    }

    private func card(_ result: TrainingLoadEngine.Result) -> some View {
        let all = result.points.compactMap { p in
            MetricHealthSeries.date(p.day, calendar: calendar).map { Row(date: $0, fitness: p.chronicLoad, fatigue: p.acuteLoad) }
        }
        let anchor = all.last?.date ?? Date()
        let span = MetricHealthSeries.bounds(range, anchor: anchor, calendar: calendar)
        let rows = all.filter { $0.date >= span.start && $0.date < span.end }
        let latest = result.points.last
        return SummaryCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FORM")
                        .font(StrandFont.pro(13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text(verbatim: latest.map { TrainingLoadModel.signed($0.balance) } ?? "—")
                        .font(StrandFont.pro(34, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let first = rows.first?.date, let last = rows.last?.date {
                        Text(interval(first, last))
                            .font(StrandFont.pro(17, weight: .semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(2)
                    }
                }
                chart(rows)
                    .frame(height: 240)
                    .padding(.top, NoopMetrics.space4)
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    .padding(.top, NoopMetrics.space4)
                legendRow(String(localized: "Fitness · 42 days"), value: latest?.chronicLoad, tint: Self.fitnessTint)
                    .padding(.top, NoopMetrics.space3)
                legendRow(String(localized: "Fatigue · 7 days"), value: latest?.acuteLoad, tint: Self.fatigueTint)
                    .padding(.top, NoopMetrics.space2)
            }
            .padding(.top, 4)
        }
        .animation(StrandMotion.interactive, value: range)
    }

    private func chart(_ rows: [Row]) -> some View {
        let top = max(rows.map { max($0.fitness, $0.fatigue) }.max() ?? 1, 1)
        return Chart {
            ForEach(rows) { r in
                LineMark(x: .value("Day", r.date), y: .value("Load", r.fitness), series: .value("Series", "fitness"))
                    .foregroundStyle(Self.fitnessTint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(rows) { r in
                LineMark(x: .value("Day", r.date), y: .value("Load", r.fatigue), series: .value("Series", "fatigue"))
                    .foregroundStyle(Self.fatigueTint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...(top * 1.1))
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel().font(StrandFont.pro(12)).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(StrandPalette.hairline)
                AxisValueLabel().font(StrandFont.pro(12)).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .accessibilityLabel(Text("Training load: chronic vs acute"))
    }

    private func legendRow(_ title: String, value: Double?, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(title)
                .font(StrandFont.pro(15))
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 8)
            Text(verbatim: value.map(TrainingLoadModel.number) ?? "—")
                .font(StrandFont.pro(17, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func interval(_ from: Date, _ to: Date) -> String {
        let f = DateIntervalFormatter()
        f.calendar = calendar
        f.locale = locale
        f.dateTemplate = range == .year ? "MMMy" : "dMMMy"
        return f.string(from: from, to: to)
    }
}
