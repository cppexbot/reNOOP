//  TrendsView.swift
//  NOOP · Trends — Health's "Show All Health Trends" page: one card per metric whose recent readings have
//  clearly moved (`HealthTrendDetector`), each opening that metric's page, then training load, which no
//  other page shows. The toolbar's share button exports the PDF trends report.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

struct TrendsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""

    @State private var snapshot: HealthTrendsSnapshot?
    @State private var trainingLoad: TrainingLoadEngine.Result?

    private var units: MetricHealthStyle.Units {
        HealthTrendsUnits.resolve(system: unitSystemRaw, temperature: temperatureRaw, effortScale: effortScaleRaw)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let snapshot {
                    if snapshot.items.isEmpty {
                        emptyState(judged: snapshot.anyJudged)
                    } else {
                        ForEach(snapshot.items) { item in
                            NavigationLink(value: TabRoute.metricSourced(key: item.metric.key, source: item.metric.source)) {
                                HealthTrendCard(metric: item.metric, trend: item.trend, units: units)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let trainingLoad, trainingLoad.isAvailable, let latest = trainingLoad.points.last {
                        TrainingLoadRow(balance: latest.balance)
                            .padding(.top, snapshot.items.isEmpty ? 0 : NoopMetrics.space4)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, NoopMetrics.space8)
                }
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.bottom, NoopMetrics.space8 + NoopMetrics.tabBarClearance)
            #if os(macOS)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            #endif
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("Trends"))
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) { TrendsReportMenu(days: repo.days).barGlyph() }
        }
        .refreshable { await repo.refresh() }
        .task(id: "\(repo.refreshSeq)|\(skinTempDisplayRaw)") {
            let prefer = SkinTempDisplay.Kind(rawValue: skinTempDisplayRaw) ?? .absolute
            guard let loaded = await HealthTrendLoader.load(repo: repo, skinTemp: prefer) else { return }
            snapshot = loaded
            trainingLoad = TrainingLoadModel.evaluate(repo.days)
        }
    }

    /// "Not Enough Data Yet" until some metric has readings enough to judge; "No Trends" once they have and
    /// nothing moved.
    private func emptyState(judged: Bool) -> some View {
        EmptyStateView(title: Text(judged ? String(localized: "No Trends") : String(localized: "Not Enough Data Yet")),
                       systemImage: "chart.line.uptrend.xyaxis")
            .padding(.top, 80)
    }
}

/// Health's trends glyph: three arrows fanning out from one point — up, ahead and down.
struct HealthTrendsGlyph: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, box in
            // Drawn on a 24-point grid, scaled to the box.
            let k = min(box.width, box.height) / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            var path = Path()
            func head(at tip: CGPoint, from: CGPoint) {
                let dx = tip.x - from.x, dy = tip.y - from.y
                let len = max((dx * dx + dy * dy).squareRoot(), 1e-6)
                let ux = dx / len, uy = dy / len
                let l = 5 * k, c = cos(0.7), sn = sin(0.7)
                path.move(to: CGPoint(x: tip.x - l * (ux * c - uy * sn), y: tip.y - l * (uy * c + ux * sn)))
                path.addLine(to: tip)
                path.addLine(to: CGPoint(x: tip.x - l * (ux * c + uy * sn), y: tip.y - l * (uy * c - ux * sn)))
            }
            // Ahead.
            path.move(to: p(2, 12))
            path.addLine(to: p(21, 12))
            head(at: p(21, 12), from: p(2, 12))
            // Up and down: level at first, then turning away.
            for sign: CGFloat in [-1, 1] {
                let tip = p(20, 12 + sign * 9)
                let control = p(14, 12 + sign * 3)
                path.move(to: p(2, 12 + sign * 3))
                path.addLine(to: p(8, 12 + sign * 3))
                path.addQuadCurve(to: tip, control: control)
                head(at: tip, from: control)
            }
            context.stroke(path, with: .foreground,
                           style: StrokeStyle(lineWidth: 2.2 * k, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The trends' shared bits: the units every card reads in, and the SF Symbol lists name Trends by.
enum HealthTrendsUnits {
    static let icon = "chart.line.uptrend.xyaxis"

    static func resolve(system: String, temperature: String, effortScale: String) -> MetricHealthStyle.Units {
        let unitSystem = UnitSystem(rawValue: system) ?? .metric
        return .init(system: unitSystem,
                     temperature: UnitPrefs.resolveTemperature(system: unitSystem, override: temperature),
                     effortScale: UnitPrefs.resolveEffortScale(effortScale))
    }
}

/// Training load as one row under the trends: its name, today's form, and the page with the chart.
private struct TrainingLoadRow: View {
    let balance: Double

    var body: some View {
        NavigationLink(value: TabRoute.trainingLoad) {
            SummaryCard {
                VStack(alignment: .leading, spacing: 10) {
                    SummaryCardTitleRow(icon: "flame.fill", title: String(localized: "Training Load"),
                                        tint: StrandPalette.activityTitle)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: TrainingLoadModel.signed(balance))
                            .font(StrandFont.number(24, weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("Form")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
