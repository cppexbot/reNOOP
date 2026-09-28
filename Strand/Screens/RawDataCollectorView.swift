import SwiftUI
import StrandDesign
import WhoopStore

/// iOS/macOS parity twin of Android's 5/MG Raw Data Collector screen.
struct RawDataCollectorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @StateObject private var store = RawDataSessionStore()

    @State private var exportingId: String?
    @State private var deleteCandidate: RawDataSessionStore.Session?
    @State private var confirmDeleteAll = false
    @State private var exportError: String?
    @State private var deleteError: String?
    @State private var imuCoverage: [String: String] = [:]
    @State private var historicalFrom = Date().addingTimeInterval(-3_600)
    @State private var historicalTo = Date()
    @State private var markerDraft: MarkerDraft?

    private struct MarkerDraft: Identifiable {
        let id = UUID()
        let sessionId: String
        let markerId: String?
        var at: Date
        var type: String
        var text: String
    }

    var body: some View {
        Form {
            captureSection
            historicalSection
            sessionsSections
        }
        .settingsPage("5/MG Raw Data Collector")
        .task {
            // Restore a session after navigation/process lifecycle changes. The BLE layer rejects a
            // duplicate arm, so this is safe when capture never stopped.
            if let active = store.active, live.bonded { _ = model.ble.startGroundTruthRawCapture(sessionId: active.id) }
            await refreshImuCoverage()
        }
        .onChangeCompat(of: live.bonded) { bonded in
            if bonded, let active = store.active { _ = model.ble.startGroundTruthRawCapture(sessionId: active.id) }
        }
        .confirmationDialog("Delete this session?", isPresented: Binding(
            get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let session = deleteCandidate else { return }
                deleteCandidate = nil
                Task { await delete(session) }
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            if let session = deleteCandidate {
                Text("The session \(Self.range(session)) and its captured raw data will be deleted permanently.")
            }
        }
        .confirmationDialog("Delete all sessions?", isPresented: $confirmDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { Task { await deleteAll() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All \(store.sessions.count) recorded sessions and their captured raw data will be deleted permanently.")
        }
        .alert("Couldn't export session", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "Unknown error") }
        .alert("Couldn't delete session", isPresented: Binding(
            get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: { Text(deleteError ?? "Unknown error") }
        .sheet(item: $markerDraft) { draft in markerSheet(draft) }
    }

    private var captureSection: some View {
        Section {
            LabeledContent("Strap") {
                Text(live.connected ? (live.bonded ? "Connected" : "Pairing…") : "Not connected")
                    .foregroundStyle(live.connected ? StrandPalette.textSecondary : StrandPalette.statusCritical)
            }
            LabeledContent("History sync") {
                if live.backfilling {
                    Text("Syncing") + Text(verbatim: " · \(live.syncChunksThisSession)")
                } else {
                    Text("Idle")
                }
            }
            if let active = store.active {
                LabeledContent("Recording", value: Self.time(active.startedAtMs))
                Button(role: .destructive) { Task { await stop() } } label: {
                    Label("Stop session", systemImage: "stop.fill")
                }
            } else {
                Button { start() } label: {
                    Label("Start raw-data session", systemImage: "record.circle")
                }
                .disabled(!live.bonded)
            }
        }
    }

    private var historicalSection: some View {
        Section {
            DatePicker("From", selection: $historicalFrom)
            DatePicker("To", selection: $historicalTo, in: historicalFrom...)
            Button {
                _ = store.createHistorical(deviceId: model.ble.deviceId,
                                           from: historicalFrom, to: historicalTo)
            } label: {
                Label("Add historical session", systemImage: "clock.arrow.circlepath")
            }
            .disabled(historicalTo <= historicalFrom || historicalTo.timeIntervalSince(historicalFrom) > 7 * 86_400)
        } header: {
            Text("Historical export window")
        }
    }

    @ViewBuilder private var sessionsSections: some View {
        if store.sessions.isEmpty {
            Section {
                Text("No sessions recorded yet.").foregroundStyle(StrandPalette.textSecondary)
            } header: {
                Text("Recorded sessions")
            }
        } else {
            ForEach(store.sessions) { session in sessionSection(session) }
            Section {
                Button(role: .destructive) { confirmDeleteAll = true } label: {
                    Label("Delete all sessions", systemImage: "trash")
                }
                .disabled(store.active != nil)
            }
        }
    }

    private func sessionSection(_ session: RawDataSessionStore.Session) -> some View {
        let coverageText = imuCoverage[session.id, default: "no complete seconds"]
        let markers = session.events.filter { $0.kind == "marker" }.sorted { $0.atMs < $1.atMs }
        return Section {
            if !session.active, let endMs = session.endedAtMs {
                DatePicker("From", selection: Binding(
                    get: { Date(timeIntervalSince1970: Double(session.startedAtMs) / 1_000) },
                    set: { store.setRange(sessionId: session.id, from: $0,
                                          to: Date(timeIntervalSince1970: Double(endMs) / 1_000)) }
                ))
                DatePicker("To", selection: Binding(
                    get: { Date(timeIntervalSince1970: Double(endMs) / 1_000) },
                    set: { store.setRange(sessionId: session.id,
                                          from: Date(timeIntervalSince1970: Double(session.startedAtMs) / 1_000), to: $0) }
                ))
            }
            LabeledContent {
                if session.active {
                    Text("Recording").foregroundStyle(StrandPalette.statusWarning)
                } else {
                    Text(coverageText)
                }
            } label: {
                Text(verbatim: "IMU")
            }
            if let exportedAt = session.lastExportedAtMs {
                LabeledContent("Last exported", value: Self.time(exportedAt))
            }
            TextField("Session comment", text: Binding(
                get: { store.sessions.first(where: { $0.id == session.id })?.comment ?? session.comment },
                set: { store.setComment($0, sessionId: session.id) }
            ), axis: .vertical)
                .lineLimit(2...4)
            ForEach(markers) { marker in
                Button { editMarker(marker, in: session) } label: {
                    LabeledContent {
                        Text(Self.time(marker.atMs))
                    } label: {
                        Text(Self.markerLabel(marker.markerType)).foregroundStyle(StrandPalette.textPrimary)
                        if let text = marker.text, !text.isEmpty {
                            Text(text)
                        }
                    }
                }
            }
            Button { editMarker(nil, in: session) } label: {
                Label("Add marker", systemImage: "mappin.and.ellipse")
            }
            Button { Task { await export(session) } } label: {
                Label(exportingId == session.id ? "Building export…" : "Export session",
                      systemImage: "square.and.arrow.up")
            }
            .disabled(session.active || exportingId != nil)
            Button(role: .destructive) { deleteCandidate = session } label: {
                Label("Delete session", systemImage: "trash")
            }
            .disabled(session.active || exportingId != nil)
        } header: {
            Text(verbatim: Self.range(session))
        }
    }

    private func markerSheet(_ initial: MarkerDraft) -> some View {
        NavigationStack {
            if let binding = Binding($markerDraft) {
                let session = store.sessions.first(where: { $0.id == binding.wrappedValue.sessionId })
                Form {
                    Section {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            let current = Self.markerCurrentTime(session: session, now: timeline.date)
                            Text("Marker: \(binding.wrappedValue.at.formatted(date: .omitted, time: .standard))")
                            Text("Current time: \(current.formatted(date: .omitted, time: .standard))")
                                .foregroundStyle(StrandPalette.textSecondary)
                            HStack {
                                Button { binding.wrappedValue.at.addTimeInterval(-10) } label: { Text(verbatim: "−10 s") }
                                Spacer()
                                Button("0") {
                                    binding.wrappedValue.at = Self.markerCurrentTime(session: session, now: Date())
                                }
                                Spacer()
                                Button { binding.wrappedValue.at.addTimeInterval(10) } label: { Text(verbatim: "+10 s") }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Section("Marker type") {
                        Picker("Marker type", selection: binding.type) {
                            ForEach(RawDataSessionStore.markerTypes, id: \.self) { type in
                                Text(Self.markerLabel(type)).tag(type)
                            }
                        }.pickerStyle(.segmented)
                    }
                    Section("Marker note") {
                        TextField("Marker note", text: binding.text, axis: .vertical).lineLimit(2...4)
                    }
                    if let markerId = binding.wrappedValue.markerId {
                        Section {
                            Button("Delete marker", role: .destructive) {
                                store.deleteMarker(sessionId: binding.wrappedValue.sessionId, markerId: markerId)
                                markerDraft = nil
                            }
                        }
                    }
                }
                .settingsPage(initial.markerId == nil ? "Add marker" : "Edit marker")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { SheetCloseButton { markerDraft = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        SheetConfirmButton(tint: StrandPalette.settingsBlue) { saveMarker(binding.wrappedValue) }
                    }
                }
            }
        }
    }

    private func editMarker(_ marker: RawDataSessionStore.Event?, in session: RawDataSessionStore.Session) {
        let currentMs = session.endedAtMs ?? Int64(Date().timeIntervalSince1970 * 1_000)
        markerDraft = MarkerDraft(sessionId: session.id, markerId: marker?.markerId,
                                  at: Date(timeIntervalSince1970: Double(marker?.atMs ?? currentMs) / 1_000),
                                  type: marker?.markerType ?? "moment", text: marker?.text ?? "")
    }

    private func saveMarker(_ draft: MarkerDraft) {
        if let markerId = draft.markerId {
            store.updateMarker(sessionId: draft.sessionId, markerId: markerId,
                               at: draft.at, type: draft.type, text: draft.text)
        } else {
            store.addMarker(sessionId: draft.sessionId, at: draft.at, type: draft.type, text: draft.text)
        }
        markerDraft = nil
    }

    private func start() {
        guard let session = store.start(deviceId: model.ble.deviceId) else { return }
        guard model.ble.startGroundTruthRawCapture(sessionId: session.id) else {
            store.stop(); store.removeMetadata(session.id); return
        }
    }

    private func stop() async {
        await model.ble.stopGroundTruthRawCapture()
        store.stop()
        await refreshImuCoverage()
    }

    private func export(_ session: RawDataSessionStore.Session) async {
        guard let end = session.endedAtMs else { return }
        exportingId = session.id
        let bounds = Self.fullSecondBounds(fromMs: session.startedAtMs, toMs: end)
        let from = bounds?.from ?? 1, to = bounds?.to ?? 0
        let segments = bounds.map {
            ImuSessionFileStore.shared.exportSegments(session.id, from: $0.from, to: $0.to)
        } ?? []
        let history = bounds == nil ? Data("stream,unix_s,v1,v2,v3,v4\n".utf8)
            : await model.ble.groundTruthHistoryCSV(from: from, to: to)
        let sensorAvailable = !segments.isEmpty || history.split(separator: 0x0A).count > 1
        var entries = store.exportEntries(for: session, sensorAvailable: sensorAvailable)
        entries.append(.init(name: "history-sensors.csv", data: history))
        // A live capture can only produce its first complete one-second frame after startup.
        // Historical windows must still cover the exact requested start.
        let firstImuTs = segments.map(\.startTs).min().flatMap { $0 <= from + 1 ? $0 : nil }
        let coverageFrom = session.capturedStartedAtMs == nil ? from : max(from, firstImuTs ?? from)
        let imuComplete = Self.covers(segments, from: coverageFrom, to: to)
        let coverage: [String: Any] = [
            "requested_start_ts": from, "requested_end_ts": to,
            "required_start_ts": coverageFrom,
            "startup_seconds": max(0, coverageFrom - from),
            "complete": imuComplete,
            "segments": segments.map { ["file": $0.name, "start_ts": $0.startTs, "end_ts": $0.endTs,
                                         "sample_count": $0.sampleCount] }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: coverage, options: [.prettyPrinted, .sortedKeys]) {
            entries.append(.init(name: "imu-coverage.json", data: data))
        }
        for segment in segments { entries.append(.init(name: "imu/\(segment.name)", data: segment.data)) }
        let result = await FileExport.exportBundle(entries: entries,
                                                    suggestedName: "noop-5mg-raw-\(session.id).zip")
        if result == nil { exportError = "The export file could not be created or shared." }
        else {
            store.markExported(session.id)
        }
        exportingId = nil
    }

    private func delete(_ session: RawDataSessionStore.Session) async {
        guard session.endedAtMs != nil else { return }
        guard store.removeMetadata(session.id) else {
            deleteError = "The captured data could not be deleted. The session was kept so you can retry."
            return
        }
        imuCoverage[session.id] = nil
    }

    private func deleteAll() async {
        for session in store.sessions where !session.active { await delete(session) }
    }

    private func refreshImuCoverage() async {
        for session in store.sessions {
            guard let end = session.endedAtMs,
                  let bounds = Self.fullSecondBounds(fromMs: session.startedAtMs, toMs: end) else { continue }
            let stats = ImuSessionFileStore.shared.stats(session.id, from: bounds.from, to: bounds.to)
            let first = stats.firstTs.flatMap { $0 <= Int64(bounds.from + 1) ? Int($0) : nil }
            let from = session.capturedStartedAtMs == nil ? bounds.from : max(bounds.from, first ?? bounds.from)
            let expected = max(0, bounds.to - from + 1)
            let bytes = ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file)
            let readiness = expected > 0 && stats.coveredSeconds == expected ? "ready" : "incomplete"
            imuCoverage[session.id] = "\(stats.coveredSeconds)/\(expected) s · \(bytes) · \(readiness)"
        }
    }

    private static func time(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1_000)
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(AppClock.formattingLocale))   // #1821
    }

    static func fullSecondBounds(fromMs: Int64, toMs: Int64) -> (from: Int, to: Int)? {
        let from = Int((fromMs + 999) / 1_000), to = Int(toMs / 1_000) - 1
        return from <= to ? (from, to) : nil
    }

    static func markerCurrentTime(session: RawDataSessionStore.Session?, now: Date) -> Date {
        session?.endedAtMs.map { Date(timeIntervalSince1970: Double($0) / 1_000) } ?? now
    }

    private static func range(_ session: RawDataSessionStore.Session) -> String {
        let start = Date(timeIntervalSince1970: Double(session.startedAtMs) / 1_000)
        let date = start.formatted(date: .numeric, time: .omitted)
        let end = session.endedAtMs.map(time) ?? "…"
        return "\(date) · \(time(session.startedAtMs))–\(end)"
    }

    private static func markerLabel(_ type: String?) -> LocalizedStringKey {
        switch type {
        case "start": "Start"
        case "end": "End"
        case "issue": "Issue"
        default: "Moment"
        }
    }

    private static func covers(_ chunks: [ImuSessionFileStore.ExportSegment], from: Int, to: Int) -> Bool {
        var cursor = from
        for chunk in chunks.sorted(by: { $0.startTs < $1.startTs }) {
            let start = chunk.startTs, end = chunk.endTs
            if chunk.sampleCount < (end - start + 1) * ImuSessionFileStore.sampleRate { continue }
            if start > cursor { return false }
            if end >= cursor { cursor = end + 1 }
            if cursor > to { return true }
        }
        return cursor > to
    }
}
