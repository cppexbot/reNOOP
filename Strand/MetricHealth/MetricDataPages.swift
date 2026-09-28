//  MetricDataPages.swift
//  NOOP · Metric page — "Show All Data": every reading, newest first, with the source that supplied it,
//  as Health's All Recorded Data.

import SwiftUI
import StrandDesign

// MARK: - All data

struct MetricAllDataView: View {
    let metric: MetricDescriptor
    let series: [(day: String, value: Double)]
    let sourceByDay: [String: String]
    let units: MetricHealthStyle.Units

    @EnvironmentObject private var repo: Repository
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        // The time moves under the reading at accessibility sizes.
        let stacked = dts.isAccessibilitySize
        let rowLayout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        let readings = series.map { VitalReading(day: $0.day, value: $0.value, source: sourceByDay[$0.day] ?? metric.source) }
        // The unit rides the formatter (#1942): `vitalReadingRows` appends its own only when given one.
        let rows = vitalReadingRows(readings: readings, unit: "", strapDeviceId: repo.deviceId) {
            MetricHealthStyle.text(metric, $0, units: units)
        }
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    rowLayout {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: row.value)
                                .font(StrandFont.pro(17, weight: .semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(verbatim: row.source)
                                .font(StrandFont.pro(13))
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        if !stacked { Spacer(minLength: 8) }
                        Text(verbatim: row.time)
                            .font(StrandFont.pro(15))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                    if index < rows.count - 1 {
                        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(StrandPalette.summaryCard,
                        in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, NoopMetrics.space3)
            .padding(.bottom, NoopMetrics.space8 + NoopMetrics.tabBarClearance)
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("All Data"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
