//  SleepVitalsView.swift
//  NOOP · Sleep — the Vitals page Health opens from its Vitals tile (iOS 26): the verdict and the night's
//  date over a chart of every vital against its typical range (a column each, High / Typical / Low
//  zones, the vital's glyph under it), then each vital's reading beside its range, opening its own page.

import SwiftUI
import StrandDesign
import StrandAnalytics

struct SleepVitalsView: View {
    /// The night's wake-day key ("yyyy-MM-dd") and its wake time.
    let day: String
    let date: Date

    @EnvironmentObject private var repo: Repository
    private var vitals: SleepVitals { SleepVitals.make(rows: repo.days, day: day) }

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if vitals.nightsRemaining > 0 {
                    SummaryCard {
                        Text("\(vitals.nightsRemaining) sleep sessions until results")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                } else {
                    SummaryCard {
                        SleepVitalsChart(readings: vitals.readings)
                            .frame(height: 220)
                    }
                    readingsCard
                }
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, NoopMetrics.space3)
            .padding(.bottom, NoopMetrics.space8)
        }
        .background(StrandPalette.sleepScoreCanvas.ignoresSafeArea())
        .environment(\.summaryCardFill, StrandPalette.sleepScoreCard)
        .navigationTitle(Text(String(localized: "vitals.title", defaultValue: "Vitals")))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if vitals.nightsRemaining == 0 {
                SleepVitalsVerdict(outliers: vitals.outliers, size: 28)
            }
            Text(date, format: .dateTime.day().month(.abbreviated).year().locale(AppLanguage.activeLocale))
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    private var readingsCard: some View {
        SummaryCard(insets: .summaryCardList) {
            VStack(spacing: 0) {
                ForEach(Array(vitals.readings.enumerated()), id: \.element.id) { index, reading in
                    if index > 0 {
                        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                            .padding(.leading, 34)
                    }
                    NavigationLink(value: TabRoute.metric(reading.metric.catalogKey)) {
                        row(reading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ reading: SleepVitals.Reading) -> some View {
        let tint = reading.isOutlier ? StrandPalette.vitalsOutlier : StrandPalette.vitalsTypical
        return HStack(spacing: 12) {
            Image(systemName: reading.metric.symbol)
                .font(StrandFont.pro(17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.metric.title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Typical: \(bare(reading.range.lowerBound, reading.metric))–\(format(reading.range.upperBound, reading.metric))")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 8)
            Text(verbatim: format(reading.value, reading.metric))
                .font(StrandFont.body.weight(.semibold))
                .foregroundStyle(reading.isOutlier ? StrandPalette.vitalsOutlier : StrandPalette.textPrimary)
            Image(systemName: "chevron.right")
                .font(StrandFont.pro(14, weight: .semibold))
                .foregroundStyle(StrandPalette.healthChevron)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var fahrenheit: Bool {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                     override: temperatureRaw) == .fahrenheit
    }

    /// A range's low end: the number alone where the high end carries the unit ("50–62 BPM").
    private func bare(_ value: Double, _ metric: SleepVitals.Metric) -> String {
        let locale = AppLanguage.activeLocale
        switch metric {
        case .heartRate, .oxygen: return "\(Int(value.rounded()))"
        case .respiratory: return value.formatted(.number.precision(.fractionLength(1)).locale(locale))
        case .temperature:
            return SkinTempDisplay.numberString(value, kind: SkinTempDisplay.kind(of: value), fahrenheit: fahrenheit)
        case .sleepDuration: return SleepFormat.duration(minutes: value)
        }
    }

    private func format(_ value: Double, _ metric: SleepVitals.Metric) -> String {
        let locale = AppLanguage.activeLocale
        switch metric {
        case .heartRate:
            return "\(Int(value.rounded())) \(String(localized: "sleep.unit.bpm", defaultValue: "BPM"))"
        case .respiratory:
            return "\(value.formatted(.number.precision(.fractionLength(1)).locale(locale))) \(String(localized: "br/min"))"
        case .temperature:
            return SkinTempDisplay.formatReading(.init(value: value, kind: SkinTempDisplay.kind(of: value)),
                                                 fahrenheit: fahrenheit)
        case .oxygen:
            return "\(Int(value.rounded())) %"
        case .sleepDuration:
            return SleepFormat.duration(minutes: value)
        }
    }
}

/// Health's Vitals chart: a column per vital between thin rules, three zones (High, Typical, Low) named
/// down the trailing edge, a ring where the night fell in each vital's range, and each vital's glyph
/// under its column.
struct SleepVitalsChart: View {
    let readings: [SleepVitals.Reading]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Canvas { ctx, size in draw(ctx, size: size) }
                VStack(alignment: .leading, spacing: 0) {
                    zoneName(String(localized: "vitals.zone.high", defaultValue: "High"))
                    zoneName(String(localized: "vitals.zone.typical", defaultValue: "Typical"))
                    zoneName(String(localized: "vitals.zone.low", defaultValue: "Low"))
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(SleepVitals.Metric.allCases) { metric in
                        Image(systemName: metric.symbol)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.healthChartAxisLabel)
                            .frame(maxWidth: .infinity)
                    }
                }
                zoneName(String(localized: "vitals.zone.typical", defaultValue: "Typical")).hidden().frame(height: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(readings.map { "\($0.metric.title) \($0.isOutlier ? String(localized: "outside typical range") : String(localized: "within typical range"))" }
            .joined(separator: ", ")))
    }

    private func zoneName(_ text: String) -> some View {
        Text(text)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.healthChartAxisLabel)
            .frame(maxHeight: .infinity)
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let columns = CGFloat(SleepVitals.Metric.allCases.count)
        let zone = size.height / 3
        let rule = GraphicsContext.Shading.color(StrandPalette.healthChartGrid)
        ctx.fill(Path(CGRect(x: 0, y: zone, width: size.width, height: zone)),
                 with: .color(StrandPalette.vitalsTypicalBand.opacity(0.25)))
        for i in 0...3 {
            let y = min(max(0.5, CGFloat(i) * zone), size.height - 0.5)
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                       with: rule, lineWidth: 1)
        }
        for i in 0...Int(columns) {
            let x = min(max(0.5, size.width * CGFloat(i) / columns), size.width - 0.5)
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                       with: rule, lineWidth: 1)
        }
        let ring: CGFloat = 12
        for reading in readings {
            guard let slot = SleepVitals.Metric.allCases.firstIndex(of: reading.metric) else { continue }
            let x = size.width * (CGFloat(slot) + 0.5) / columns
            // Inside the range the ring moves through the middle zone; outside it, it sits in its zone.
            let p = min(max(reading.position, -0.5), 1.5)
            let y = 2 * zone - CGFloat(p) * zone
            let color = reading.isOutlier ? StrandPalette.vitalsOutlier : StrandPalette.vitalsTypical
            let rect = CGRect(x: x - ring / 2, y: y - ring / 2, width: ring, height: ring)
            ctx.fill(Path(ellipseIn: rect), with: .color(StrandPalette.sleepScoreCard))
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1.25, dy: 1.25)), with: .color(color), lineWidth: 2.5)
        }
    }
}
