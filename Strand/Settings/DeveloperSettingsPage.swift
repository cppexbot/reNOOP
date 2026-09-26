//  DeveloperSettingsPage.swift
//  NOOP · Settings → Developer: Test Centre, the strap log and link, raw export, HRV capture tuning and
//  the experiments. Same keys and the same BLE + re-score wiring the old Settings cards had.

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
    /// #141: whole night or deep sleep only. Changes the number, so a switch re-scores.
    @AppStorage(UnitPrefs.hrvWindowKey) private var hrvWindowRaw = HrvWindow.whole.rawValue
    /// Live Sessions (beta): the Start-session control. Same key the Browse entry reads.
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true
    /// Sleep staging V2 (default ON). Read at the staging call site in `Repository`.
    @AppStorage(PuffinExperiment.experimentalSleepV2Key) private var experimentalSleepV2Enabled = true
    /// #364 follow-up (default OFF): fold a wake block with no locomotion back into light sleep.
    @AppStorage(PuffinExperiment.motionAwareWakeKey) private var motionAwareWakeEnabled = false
    /// #103: surface the unverified strap SpO₂ estimate when no calibrated reading exists.
    @AppStorage(PuffinExperiment.spo2CandidateDisplayKey) private var spo2CandidateDisplayEnabled = false
    /// The strap model last picked; gates the WHOOP 4.0-only rename and the 5/MG-only SpO₂ estimate.
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue

    @State private var strapNameDraft = ""
    @State private var rawCsvBusy = false
    @State private var lastRawCsvURL: URL?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                NavigationLink(value: SettingsPage.testCentre) {
                    SettingsRowLabel(title: "Test Centre", icon: "stethoscope", color: StrandPalette.settingsTeal)
                }
            }

            strapSection
            if live.connected && selectedWhoopModelRaw == WhoopModel.whoop4.rawValue {
                strapNameSection
            }

            Section {
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
            } footer: {
                Text("The last 24 hours of decoded sensor streams in one CSV. Nothing is written to your strap or uploaded.")
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
                Picker("HRV window", selection: $hrvWindowRaw) {
                    Text("Night").tag(HrvWindow.whole.rawValue)
                    Text("Deep sleep").tag(HrvWindow.deep.rawValue)
                }
                .settingsPicker()
                .onChangeCompat(of: hrvWindowRaw) { _ in
                    // #201/#195: analyzeRecent re-scores and re-folds the baseline in one pass — don't
                    // re-anchor the baseline epoch.
                    Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
                }
            } header: {
                Text("HRV")
            } footer: {
                Text("Continuous capture keeps the beat-to-beat stream running and uses more battery. Deep sleep reads lower and matches WHOOP.")
            }

            Section {
                Toggle("Live Sessions (beta)", isOn: $liveSessionsBeta)
                Toggle("Sleep staging (V2)", isOn: $experimentalSleepV2Enabled)
                Toggle("Motion-aware wake refinement", isOn: $motionAwareWakeEnabled)
                // Split out of the old 5/MG card so an Oura-only install can reach it too.
                if selectedWhoopModelRaw == WhoopModel.whoop5mg.rawValue || model.repo.activeDeviceIsOura {
                    Toggle("Blood Oxygen: strap estimate (WHOOP 5/MG, Oura)", isOn: $spo2CandidateDisplayEnabled)
                        .onChangeCompat(of: spo2CandidateDisplayEnabled) { _ in
                            Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
                        }
                }
            } header: {
                Text("Experiments")
            }
        }
        .settingsPage("Developer")
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: Strap

    /// The strap log (#507/#509) and the connect controls the old Strap card carried.
    private var strapSection: some View {
        Section {
            Button("Copy strap log") { PlatformPasteboard.copy(live.exportableLogText()) }
            Button("Save strap log…") {
                Task {
                    let extra = await DebugDataDiagnostics.dynamicLines(repo: model.repo)
                    FileExport.exportText(live.exportableLogText(extraHeaderLines: extra),
                                          suggestedName: FileExport.timestampedName("noop-strap-log", ext: "txt"))
                }
            }
            Button("Re-scan") { model.scan() }
            Button("Disconnect", role: .destructive) { model.disconnect() }
                .disabled(!live.connected && !live.bonded)
        } header: {
            Text("Strap")
        }
    }

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
