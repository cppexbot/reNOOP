//  DeveloperSettingsPage.swift
//  NOOP · Settings → Developer: the Test Centre (test modes, bug report, strap log, protocol tools,
//  experiments) with this page's own rows after its diagnostics: the iOS environment dump, raw export, the
//  WHOOP 4.0 rename and continuous HRV capture. Same keys and the same BLE wiring the old pages had.

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
import StrandDesign
import StrandAnalytics
import WhoopStore
import WhoopProtocol

struct DeveloperSettingsPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    /// Keep the dense beat-to-beat stream armed 24/7 (battery cost). See `PuffinExperiment`.
    @AppStorage(PuffinExperiment.keepRealtimeForDataKey) private var continuousHrvEnabled = false
    /// #927: arm it only inside the quiet-hours window. The default MUST match
    /// `PuffinExperiment.continuousHrvOvernightOnlyEnabled` (#1008).
    @AppStorage(PuffinExperiment.continuousHrvOvernightOnlyKey) private var continuousHrvOvernightOnly = true
    /// The strap model last picked; gates the WHOOP 4.0-only rename.
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue

    @State private var strapNameDraft = ""
    @State private var rawCsvBusy = false
    @State private var lastRawCsvURL: URL?
    @State private var exportError: String?
    #if os(iOS)
    @State private var showDiagnostics = false
    #endif

    var body: some View {
        TestCentreView(extra: AnyView(developerRows))
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportError ?? "")
        }
        #if os(iOS)
        .sheet(isPresented: $showDiagnostics) { DiagnosticsSheet(onClose: { showDiagnostics = false }) }
        #endif
    }

    @ViewBuilder private var developerRows: some View {
        Section {
            #if os(iOS)
            Button("Diagnostics") { showDiagnostics = true }
            #endif
            Button {
                exportRawSensorCSV()
            } label: {
                HStack {
                    Text(rawCsvBusy ? "Exporting…" : "Export raw sensor data (CSV)")
                    if rawCsvBusy { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(rawCsvBusy)
            #if os(macOS)
            if let url = lastRawCsvURL {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            #endif
        }

        if live.connected && selectedWhoopModelRaw == WhoopModel.whoop4.rawValue {
            strapNameSection
        }

        Section {
            Toggle("Continuous HRV capture", isOn: $continuousHrvEnabled)
                .onChangeCompat(of: continuousHrvEnabled) { on in model.ble.setKeepRealtimeForData(on) }
            if continuousHrvEnabled {
                Toggle("Overnight only", isOn: $continuousHrvOvernightOnly)
                    .onChangeCompat(of: continuousHrvOvernightOnly) { _ in
                        model.ble.setKeepRealtimeForData(PuffinExperiment.keepRealtimeForDataEnabled)
                    }
            }
        } header: {
            Text("HRV")
        }
    }

    // MARK: Strap

    /// Rename the WHOOP 4.0's BLE advertising name (Harvard command set). The strap reboots to apply.
    private var strapNameSection: some View {
        Section {
            LabeledContent("Strap name", value: live.advertisingName ?? "—")
            HStack {
                TextField("New strap name", text: $strapNameDraft)
                    .disableAutocorrection(true)
                Button("Rename") { model.ble.renameStrap(strapNameDraft) }
                    .disabled(strapNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } footer: {
            if let status = live.renameStatus { Text(status) }
        }
    }

    // MARK: Raw export

    /// Last 24 h of decoded streams for the ACTIVE strap (`repo.deviceId`, not the hardcoded
    /// `model.deviceId` — #814), then save (macOS) or share (iOS).
    private func exportRawSensorCSV() {
        rawCsvBusy = true
        let strapId = model.repo.deviceId
        Task {
            let since = Date().timeIntervalSince1970 - 24 * 60 * 60
            guard let store = await model.repo.storeHandle() else {
                await MainActor.run {
                    rawCsvBusy = false
                    exportError = String(localized: "Couldn't open the local store.")
                }
                return
            }
            do {
                let url = try await store.exportRawCSV(deviceId: strapId, since: since)
                await MainActor.run {
                    rawCsvBusy = false
                    lastRawCsvURL = url
                    #if os(macOS)
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.commaSeparatedText]
                    panel.nameFieldStringValue = url.lastPathComponent
                    panel.canCreateDirectories = true
                    guard panel.runModal() == .OK, let dest = panel.url else { return }
                    let fm = FileManager.default
                    do {
                        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                        try fm.copyItem(at: url, to: dest)
                    } catch {
                        exportError = error.localizedDescription
                    }
                    #else
                    FileExport.exportFile(at: url)
                    #endif
                }
            } catch {
                await MainActor.run {
                    rawCsvBusy = false
                    exportError = error.localizedDescription
                }
            }
        }
    }
}

#if os(iOS)
// MARK: - Diagnostics sheet

/// A read-only environment dump for bug reports: device, iOS+build, Data Protection (#222), background
/// refresh, low-power, sideload + cert expiry — with a one-tap Copy.
struct DiagnosticsSheet: View {
    let onClose: () -> Void

    /// Captured once at presentation; a snapshot, not a live monitor.
    private let lines: [String] = IOSDiagnostics.capture().summaryLines()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if lines.isEmpty {
                        Text("No iOS diagnostics available.").foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(StrandFont.mono(12))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .settingsPage("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Copy") { PlatformPasteboard.copy(lines.joined(separator: "\n")) }
                        .disabled(lines.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(tint: StrandPalette.accent, action: onClose)
                }
            }
        }
    }
}
#endif
