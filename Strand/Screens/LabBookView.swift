import SwiftUI
import Charts
import Foundation
import UniformTypeIdentifiers
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// MARK: - Lab Book (Health Records pillar — v5)
//
// "Your own logbook", laid out as Health's Lab Results: markers by category, each with its latest value,
// date and the range printed on the user's own report; a marker opens its page (chart, compare with a
// wearable signal, every reading). "+" adds a reading or imports a markers CSV. Everything stays on this
// device: readings live in WhoopStore's `labMarker` table under the strap device id, and every write also
// projects a daily series under the `lab-book` source so Coach and the metric pages see markers.
//
// NON-CLINICAL (load-bearing, spec §"Non-clinical / legal framing"): no word here asserts a clinical
// judgement — never "abnormal/high/low/normal" as NOOP's own statement; any reference range shown is
// EXACTLY what the user typed from their own report; correlation copy says association, not cause. The ⓘ
// in the bar says so.

struct LabBookView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState

    /// All readings, oldest first. Loaded off the store on appear/refresh.
    @State private var markers: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var showingEditor = false

    // Markers CSV import (LabMarkerCsvImport, Phase 2).
    @State private var showingCsvImporter = false   // macOS .fileImporter presentation
    @State private var csvImporting = false
    @State private var csvSummary: String?
    @State private var csvFailed = false
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let csvSummary {
                    Text(verbatim: csvSummary)
                        .font(StrandFont.pro(13))
                        .foregroundStyle(csvFailed ? StrandPalette.settingsRed : StrandPalette.textSecondary)
                        .padding(.horizontal, 4)
                }
                if !loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if markers.isEmpty {
                    EmptyStateView(title: Text("No Readings"), systemImage: "list.clipboard",
                                   description: Text("Add a number from your own report.")) {
                        Button("Add Reading") { showingEditor = true }
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(orderedCategories, id: \.self) { category in
                        SummarySectionHeader(title: LocalizedStringKey(category.displayName))
                        categoryCard(category)
                    }
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
        .refreshable { await load() }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("Lab Results"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                InfoButton(label: "About Lab Results") {
                    Text("A private notebook, not a medical service: NOOP doesn't read or judge these numbers.")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingEditor = true } label: { Label("Add Reading", systemImage: "plus") }
                    Button { presentCsvImporter() } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
                        .disabled(csvImporting)
                } label: {
                    Image(systemName: "plus")
                }
                .barGlyph()
                .accessibilityLabel(Text("Add"))
            }
        }
        .navigationDestination(for: LabMarkerRoute.self) { route in
            MarkerDetailView(markerKey: route.key, readings: readings(for: route.key),
                             onDelete: { id in await delete(id) })
        }
        .task(id: repo.refreshSeq) { await load() }
        .sheet(isPresented: $showingEditor) {
            MarkerEditorView { drafts in await save(drafts) }
        }
        // macOS picker for the markers CSV; iOS goes through DocumentPicker (see presentCsvImporter) for
        // the iCloud download-on-pick behaviour (#179).
        .fileImporter(isPresented: $showingCsvImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importMarkersCsv(url: url) }
            case .failure(let error):
                NSLog("Import: markers CSV picker failed - \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Category cards

    /// Categories present in the data, in the spec's display order.
    private var orderedCategories: [LabMarkerCategory] {
        let present = Set(markers.compactMap { LabMarkerCategory(rawValue: $0.category) })
        return LabBookView.categoryOrder.filter { present.contains($0) }
    }

    private static let categoryOrder: [LabMarkerCategory] = [
        .bloodPanel, .bloodPressure, .bodyMeasurement, .imaging, .appointmentNote, .other,
    ]

    /// Distinct marker keys in a category, alphabetised by display name.
    private func markerKeys(in category: LabMarkerCategory) -> [String] {
        let keys = Set(markers.filter { $0.category == category.rawValue }.map(\.markerKey))
        return keys.sorted { LabBookFormat.name($0) < LabBookFormat.name($1) }
    }

    private func categoryCard(_ category: LabMarkerCategory) -> some View {
        let keys = markerKeys(in: category)
        return SummaryCard {
            VStack(spacing: 0) {
                ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                    NavigationLink(value: LabMarkerRoute(key: key)) { markerRow(key) }
                        .buttonStyle(.plain)
                    if index < keys.count - 1 {
                        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    }
                }
            }
        }
    }

    /// Health's lab-result row: the marker and when it was taken; the latest value and the report's range.
    private func markerRow(_ key: String) -> some View {
        let latest = readings(for: key).last
        let stacked = dts.isAccessibilitySize
        // At accessibility sizes the value moves under the marker's name.
        let columns = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                              : AnyLayout(HStackLayout(spacing: 10))
        return HStack(spacing: 10) {
            columns {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: LabBookFormat.name(key))
                        .font(StrandFont.pro(17, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(stacked ? nil : 1)
                    if let latest {
                        Text(verbatim: LabBookFormat.dayFromKey(latest.day))
                            .font(StrandFont.pro(15))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                if !stacked { Spacer(minLength: 8) }
                VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                    LabValueText(row: latest, key: key, size: 20)
                    if let ref = latest?.referenceText, !ref.isEmpty {
                        Text("Range \(ref)")
                            .font(StrandFont.pro(13))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
            if stacked { Spacer(minLength: 8) }
            Image(systemName: "chevron.right")
                .font(StrandFont.pro(13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - CSV import

    private func presentCsvImporter() {
        #if os(iOS)
        // iOS: UIDocumentPickerViewController with asCopy:true (DocumentPicker) so an undownloaded
        // iCloud file is fetched and handed over readable (#179).
        Task {
            guard let url = await DocumentPicker.importFile([.commaSeparatedText, .plainText]) else { return } // cancelled
            importMarkersCsv(url: url)
        }
        #else
        showingCsvImporter = true
        #endif
    }

    /// Parse a markers CSV (LabMarkerCsvImport) and upsert the readings into the Lab Book
    /// under this device id with the `lab-csv` provenance tag; the daily `lab-book`
    /// projection rides the store's upsert, then a refresh lets Compare/Explore/Coach see
    /// the new markers.
    private func importMarkersCsv(url: URL) {
        csvImporting = true
        csvSummary = nil
        csvFailed = false
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                // A WHOOP biomarker export (its own header signature) routes to the vendor parser —
                // packed units, US 2-digit dates, a Status column carried into note; any other file
                // takes the generic (date,marker,value,unit) path.
                let isWhoop = WhoopBiomarkerExportParser.matches(data: data)
                let result = isWhoop ? WhoopBiomarkerExportParser.parse(data: data)
                                     : LabMarkerCsvImport.parse(data: data)
                let sourceId = isWhoop ? WhoopBiomarkerExportParser.sourceId : LabMarkerCsvImport.sourceId
                guard !result.fileTooLarge else {
                    csvSummary = String(localized: "That file is too large for a markers CSV import.")
                    csvFailed = true
                    csvImporting = false
                    return
                }
                guard result.importedReadings > 0 else {
                    csvSummary = String(localized: "No usable rows found. Check the file has date, marker and value columns.")
                    csvFailed = true
                    logImport("Lab Book CSV: no usable rows (\(result.skippedRows) skipped)")
                    csvImporting = false
                    return
                }
                guard let store = await repo.storeHandle() else {
                    csvSummary = String(localized: "Couldn't open the local store.")
                    csvFailed = true
                    csvImporting = false
                    return
                }
                let rows = result.rows.map { r -> LabMarkerRow in
                    // Local noon of the row's literal day: deterministic, so re-importing
                    // the same file updates in place (natural key
                    // deviceId+markerKey+takenAt+source) instead of duplicating.
                    let epoch = LabBookFormat.noonEpoch(r.day)
                    return LabMarkerRow(
                        id: "\(r.markerKey)-\(epoch)-\(UUID().uuidString.prefix(8))",
                        deviceId: repo.deviceId,
                        markerKey: r.markerKey,
                        category: r.category.rawValue,
                        day: r.day,
                        takenAt: epoch,
                        value: r.value,
                        valueText: nil,
                        unit: r.unit,
                        source: sourceId,
                        note: r.note,
                        referenceText: nil
                    )
                }
                try await store.upsertLabMarkers(rows)
                await repo.refresh()   // re-resolves the lab-book projection into Compare/Explore/Coach
                await load()
                var msg = String(localized: "Imported \(result.importedReadings) readings (\(result.distinctMarkers) markers)")
                if let a = result.earliestDay, let b = result.latestDay, a != b { msg += " · \(a)-\(b)" }
                if result.skippedRows > 0 {
                    // Whole-phrase variants per count; the separator stays outside the localized key.
                    msg += " · " + (result.skippedRows == 1
                                    ? String(localized: "1 row skipped")
                                    : String(localized: "\(result.skippedRows) rows skipped"))
                }
                // A vendor export's not-measured markers ("--" / "No Data Available") are absent by
                // design, not malformed — reported apart so a clean import doesn't look broken.
                if result.notMeasured > 0 {
                    msg += " · " + (result.notMeasured == 1
                                    ? String(localized: "1 not measured")
                                    : String(localized: "\(result.notMeasured) not measured"))
                }
                csvSummary = msg
                csvFailed = false
                logImport("Lab Book CSV: \(result.importedReadings) readings, \(result.distinctMarkers) markers, \(result.skippedRows) rejected")
            } catch {
                csvSummary = String(localized: "Import failed: \(error.localizedDescription)")
                csvFailed = true
                logImport("Lab Book CSV failed: \(error.localizedDescription)")
            }
            csvImporting = false
        }
    }

    /// One privacy-safe line into the SAME exported strap log the other importers use
    /// (issue #421 parity): COUNTS only, never a file name, a path, or any health value.
    /// Same shape as DataSourcesView.logImport.
    private func logImport(_ line: String) {
        live.append(log: "[\(AppModel.logTimeFormatter.string(from: Date()))] Import \(line)")
    }

    /// Readings for one marker, oldest-first (the store already returns them sorted by takenAt).
    private func readings(for key: String) -> [LabMarkerRow] {
        markers.filter { $0.markerKey == key }
    }

    // MARK: - Load / save / delete (through the shared on-device store)

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        // Read by category so we cover them all; markers are stored under the strap device id.
        var all: [LabMarkerRow] = []
        for category in LabMarkerCategory.allCases {
            let rows = (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? []
            all.append(contentsOf: rows)
        }
        markers = all.sorted { $0.takenAt < $1.takenAt }
        loaded = true
    }

    private func save(_ drafts: [LabMarkerRow]) async {
        guard !drafts.isEmpty, let store = await repo.storeHandle() else { return }
        try? await store.upsertLabMarkers(drafts)
        await repo.refresh()   // re-resolves the lab-book projection into Compare/Explore/Coach
        await load()
    }

    private func delete(_ id: String) async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLabMarker(id: id)
        await repo.refresh()
        await load()
    }
}

/// A pushed marker page. A value, so the Browse stack's path can pop it (#198).
struct LabMarkerRoute: Hashable {
    let key: String
}

/// A reading's value in the Health idiom: the figure bold, the unit smaller and grey.
private struct LabValueText: View {
    let row: LabMarkerRow?
    let key: String
    var size: CGFloat = 17
    /// Dynamic Type factor for `size`, which callers pass as any point size.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let scaled = size * scale
        if let row, let v = row.value {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: LabBookFormat.displayValue(v, key: key))
                    .font(.system(size: scaled, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: LabBookFormat.unit(row.unit))
                    .font(.system(size: scaled * 0.75))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        } else {
            Text(verbatim: row?.valueText ?? "—")
                .font(.system(size: scaled, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }
}

// MARK: - Marker page (chart, compare with a signal, every reading)

private struct MarkerDetailView: View {
    let markerKey: String
    let readings: [LabMarkerRow]
    let onDelete: (_ id: String) async -> Void

    @EnvironmentObject var repo: Repository

    /// The wearable metric chosen to correlate against ("" until the user picks one).
    @State private var signalKey = ""
    /// The trailing-window width for the windowed-aggregate pairing.
    @State private var window: LabWindow = .fortnight
    @State private var pairs: [WindowedPair] = []
    @State private var correlation: Correlation?
    @State private var computing = false
    @State private var deleting: LabMarkerRow?
    @Environment(\.dynamicTypeSize) private var dts

    private var signal: MetricDescriptor? { LabBookSignals.options.first { $0.key == signalKey } }
    private var numericReadings: [LabMarkerRow] { readings.filter { $0.value != nil } }
    private var tint: Color {
        LabMarkerCategory(rawValue: readings.last?.category ?? "")?.tint ?? StrandPalette.settingsBlue
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let latest = readings.last {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Latest")
                                .font(StrandFont.pro(13, weight: .semibold))
                                .foregroundStyle(StrandPalette.textSecondary)
                            LabValueText(row: latest, key: markerKey, size: 30)
                            Text(verbatim: LabBookFormat.dayFromKey(latest.day))
                                .font(StrandFont.pro(15))
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    if numericReadings.count > 1 { chart }
                }
                .padding(.vertical, 6)
            } footer: {
                if let ref = readings.last(where: { $0.referenceText?.isEmpty == false })?.referenceText {
                    Text("Range on your report: \(ref)")
                }
            }
            if !numericReadings.isEmpty { compareSection }
            Section("All Readings") {
                ForEach(readings.reversed(), id: \.id) { row in
                    let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                         : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                    layout {
                        VStack(alignment: .leading, spacing: 2) {
                            LabValueText(row: row, key: markerKey)
                            if let note = row.note, !note.isEmpty {
                                Text(verbatim: note)
                                    .font(StrandFont.pro(13))
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                        if !dts.isAccessibilitySize { Spacer() }
                        Text(verbatim: LabBookFormat.dayFromKey(row.day))
                            .font(StrandFont.pro(15))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .contextMenu {
                        Button(role: .destructive) { deleting = row } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    // No destructive role: SwiftUI would slide the row out before the question is answered.
                    .swipeActions(allowsFullSwipe: false) {
                        Button { deleting = row } label: { Label("Delete", systemImage: "trash") }
                            .tint(.red)
                    }
                }
            }
        }
        .confirmationDialog("Delete Reading?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { row in
            Button("Delete", role: .destructive) { Task { await onDelete(row.id) } }
        }
        .settingsPage(LocalizedStringKey(LabBookFormat.name(markerKey)))
        .task(id: "\(signalKey)|\(window.rawValue)|\(repo.refreshSeq)") { await recompute() }
    }

    /// Every numeric reading over time: hollow points joined by a line, the axis on the trailing edge.
    private var chart: some View {
        Chart(numericReadings, id: \.id) { row in
            let date = Date(timeIntervalSince1970: TimeInterval(row.takenAt))
            LineMark(x: .value("Date", date), y: .value("Value", row.value ?? 0))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(x: .value("Date", date), y: .value("Value", row.value ?? 0))
                .symbol {
                    Circle()
                        .strokeBorder(tint, lineWidth: 2)
                        .background(Circle().fill(StrandPalette.summaryCard))
                        .frame(width: 9, height: 9)
                }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks(position: .trailing) }
        .frame(height: 180)
        .accessibilityHidden(true)
    }

    // MARK: Compare with a signal (the Pearson idiom, association not cause)

    private var compareSection: some View {
        Section {
            Picker("Signal", selection: $signalKey) {
                Text("None").tag("")
                ForEach(LabBookSignals.options, id: \.key) { Text(verbatim: $0.title).tag($0.key) }
            }
            if signal != nil {
                Picker("Window", selection: $window) {
                    ForEach(LabWindow.allCases) { Text(verbatim: $0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                resultRow
            }
        } header: {
            Text("Compare")
        } footer: {
            if signal != nil {
                Text("The signal's average over the \(window.phrase) before each reading. Association, not a medical finding.")
            }
        }
    }

    @ViewBuilder
    private var resultRow: some View {
        let n = pairs.count
        if computing {
            ProgressView()
        } else if n < LabBookSignals.floor {
            // Below the floor: the points exist, the conclusion is withheld.
            Text("\(n) of \(LabBookSignals.floor) readings needed line up.")
                .foregroundStyle(StrandPalette.textSecondary)
        } else if let c = correlation {
            Text(verbatim: LabBookSignals.insightSentence(markerName: LabBookFormat.name(markerKey),
                                                          signalName: signal?.title ?? "", r: c.r))
                .font(StrandFont.pro(17, weight: .semibold))
                .padding(.vertical, 2)
        } else {
            Text("Not enough variation to compare.")
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func recompute() async {
        guard let signal else { pairs = []; correlation = nil; return }
        computing = true
        defer { computing = false }
        // The marker series, read from the projected `lab-book` daily series (numeric only).
        let markerSeries = await repo.series(key: markerKey, source: WhoopStore.labBookSourceId)
        // The wearable series, freshest-wins through the Explore read path.
        let wearable = await repo.exploreSeries(key: signal.key, source: signal.source)
        let built = LabBookProjection.pairMarkerToWearable(marker: markerSeries, wearable: wearable,
                                                           windowDays: window.days)
        pairs = built
        correlation = built.count >= LabBookSignals.floor
            ? CorrelationEngine.pearson(LabBookProjection.correlationInput(built))
            : nil
    }
}

// MARK: - Category display names + ordering

extension LabMarkerCategory {
    /// Human label for the Lab Book grouping header. Organisational only — never a clinical panel name.
    var displayName: String {
        switch self {
        case .bloodPanel:      return String(localized: "Blood panel")
        case .bloodPressure:   return String(localized: "Blood pressure")
        case .bodyMeasurement: return String(localized: "Body")
        case .imaging:         return String(localized: "Imaging")
        case .appointmentNote: return String(localized: "Notes")
        case .other:           return String(localized: "Custom")
        }
    }

    /// The Health hue a category's chart is drawn in.
    var tint: Color {
        switch self {
        case .bloodPanel, .bloodPressure: return StrandPalette.healthHeart
        case .bodyMeasurement:            return StrandPalette.healthBody
        case .imaging, .appointmentNote:  return StrandPalette.settingsBlue
        case .other:                      return StrandPalette.settingsGray
        }
    }
}

// MARK: - Shared formatting (decimals from the catalog; UTC day labels)

enum LabBookFormat {
    /// Format a numeric value with the marker's catalog decimals. A custom (non-catalog) marker has no
    /// declared precision, so it is shown at its own precision via `plain` rather than a fixed 1 decimal,
    /// which rounded plateletcrit 0.27 to "0.3" and urine specific gravity 1.020 to "1.0".
    /// Marker definition lookup → display name (catalog, else the key humanised).
    static func name(_ key: String) -> String {
        guard let def = MarkerCatalog.definition(for: key) else {
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return name(def)
    }

    /// A catalog marker's name in the reader's language (the catalog itself is English).
    static func name(_ def: MarkerDefinition) -> String {
        String(localized: String.LocalizationValue(def.displayName))
    }

    static func value(_ v: Double, key: String) -> String {
        guard v.isFinite else { return "—" }
        guard let decimals = MarkerCatalog.definition(for: key)?.decimals else { return plain(v) }
        return decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v)
    }

    /// The value as the screen shows it: `value`'s precision (a custom marker up to 3 decimals, trailing
    /// zeros dropped) in the reader's number format ("14,0" in Russian). Display only: `value` and `plain`
    /// stay the POSIX strings Coach and the cross-platform tests pin.
    static func displayValue(_ v: Double, key: String) -> String {
        guard v.isFinite else { return "—" }
        let decimals = MarkerCatalog.definition(for: key)?.decimals
        let scale = pow(10, Double(decimals ?? 3))
        let rounded = (v * scale).rounded() / scale
        let shown = rounded == 0 ? 0 : rounded   // never "-0"
        let precision: NumberFormatStyleConfiguration.Precision
        if let decimals { precision = .fractionLength(decimals) } else { precision = .fractionLength(0...3) }
        return shown.formatted(.number.precision(precision).locale(AppLanguage.activeLocale))
    }

    /// A unit as the screen shows it: a catalog unit in the reader's language ("mmol/L" → «ммоль/л»); a unit
    /// the user typed that the catalogue does not carry reads as typed. The stored unit is never rewritten.
    static func unit(_ unit: String) -> String {
        let t = unit.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.contains("%") else { return t }
        return String(localized: String.LocalizationValue(t))
    }

    /// Up to 3 decimals with trailing zeros dropped ("0.27", "1.02", "140"), always with a "." separator
    /// whatever the device locale (`String(format:)` without a locale is POSIX). A value that rounds to
    /// zero prints "0", never "-0"; a non-finite value prints "—". Twin: `LabValueFormat.plain` (Android);
    /// both are pinned by the same expected strings in `LabBookFormatTests` / `LabValueFormatTest`.
    static func plain(_ v: Double) -> String {
        guard v.isFinite else { return "—" }
        var s = String(format: "%.3f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    /// "12 Jun 2026" rendered from a stored `yyyy-MM-dd` day string, LOCATION-INDEPENDENTLY: the day key
    /// is parsed in UTC and reformatted in UTC, so the history date never shifts with the device zone the
    /// way `day(takenAt)` (a local render of a stored instant) can near midnight. Falls back to the raw
    /// string if it doesn't parse.
    static func dayFromKey(_ day: String) -> String {
        guard let date = utcKeyFormatter.date(from: day) else { return day }
        return utcDayFormatter.string(from: date)
    }

    /// "d MMM yyyy" in the reader's language, pinned to UTC, paired with `utcKeyFormatter` so `dayFromKey`
    /// round-trips a UTC day.
    private static let utcDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f
    }()

    /// The `yyyy-MM-dd` day key the projection uses (LOCAL day of the reading).
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func dayKey(_ date: Date) -> String { keyFormatter.string(from: date) }

    /// A `yyyy-MM-dd` parser PINNED to UTC, so a day string always maps to the same instant regardless
    /// of the device zone. The local-zone `keyFormatter` above returns nil for a day whose LOCAL midnight
    /// is skipped by a DST transition (e.g. Chile/Cuba, 06 Sep) - which used to collapse `noonEpoch` to
    /// epoch 0 and collide different days on the natural key. UTC never skips midnight.
    private static let utcKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Epoch seconds of UTC noon on a `yyyy-MM-dd` day — the deterministic, LOCATION-INDEPENDENT `takenAt`
    /// for CSV-imported readings, so re-importing the same file (even after travel to another zone) upserts
    /// in place instead of minting a duplicate (natural key deviceId+markerKey+takenAt+source). Pinned to
    /// UTC so a DST-skipped local midnight can never collapse the key to epoch 0. 0 only for a genuinely
    /// unparseable day string. History dates render from the stored `day` string, not this takenAt.
    static func noonEpoch(_ day: String) -> Int {
        guard let midnight = utcKeyFormatter.date(from: day) else { return 0 }
        return Int(midnight.timeIntervalSince1970) + 12 * 3600
    }
}

// MARK: - Trailing window control (7 / 14 / 30 days)

enum LabWindow: String, CaseIterable, Identifiable {
    case week, fortnight, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week:      return String(localized: "7d")
        case .fortnight: return String(localized: "14d")
        case .month:     return String(localized: "30d")
        }
    }
    var days: Int {
        switch self {
        case .week:      return 7
        case .fortnight: return 14
        case .month:     return 30
        }
    }
    var phrase: String {
        switch self {
        case .week:      return String(localized: "7 days")
        case .fortnight: return String(localized: "14 days")
        case .month:     return String(localized: "30 days")
        }
    }
}

// MARK: - Wearable signals offered for correlation + the shared insight language
//
// The pickable wearable metrics + the restrained correlation copy, kept here so the
// Lab Book detail's "Compare with a signal" reads in the exact CompareView idiom
// (strength words, tends-to, association-not-cause) plus the mandatory markers clause.

enum LabBookSignals {
    /// The reading-count floor below which NO conclusion sentence renders. Eight, not four: a line through
    /// four points is mostly chance. Display only; nothing stored depends on it.
    static let floor = 8

    /// The wearable metrics offered to pair a marker against. Strap-source keys read through the
    /// Explore freshest-wins path; weight resolves from Apple/Health-Connect/strap as available.
    static let options: [MetricDescriptor] = [
        descriptor("rhr"),
        descriptor("hrv"),
        descriptor("recovery"),
        descriptor("sleep_performance"),
        descriptor("sleep_total_min"),
        descriptor("strain"),
        descriptor("skin_temp"),
        descriptor("steps"),
        descriptor("weight"),
    ].compactMap { $0 }

    private static func descriptor(_ key: String) -> MetricDescriptor? {
        MetricCatalog.all.first { $0.key == key }
    }

    /// "When LDL is higher, HRV tends to be lower." — descriptive, no causal language.
    /// Whole-phrase variants per direction so translators never see a stitched verb fragment.
    static func insightSentence(markerName: String, signalName: String, r: Double) -> String {
        guard abs(r) >= 0.3 else {
            return String(localized: "Over your readings, \(markerName) and \(signalName.lowercased()) move largely independently. No clear relationship.")
        }
        return r < 0
            ? String(localized: "When \(markerName) is higher, \(signalName.lowercased()) tends to be lower.")
            : String(localized: "When \(markerName) is higher, \(signalName.lowercased()) tends to be higher.")
    }
}
