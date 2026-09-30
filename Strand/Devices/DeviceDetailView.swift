//  DeviceDetailView.swift
//  NOOP · Devices — one device's page, as Settings opens an AirPods page or a Bluetooth device's ⓘ: the
//  device glyph and name on top, then battery, sync and firmware, the name, the controls (connect,
//  buzz, restart), what NOOP reads off it, the strap's own settings, and Disconnect / Forget This Device
//  at the bottom. Every control calls exactly what the old Devices and Live screens called.

import SwiftUI
import StrandDesign
import StrandAnalytics   // ConnectionReadout — the #987 clock-latch / RTC-epoch readout parsers
import WhoopStore
import WhoopProtocol

struct DeviceDetailView: View {
    @ObservedObject var registry: DeviceRegistry
    let deviceId: String
    /// Called after the device was removed; `true` when it was the active one.
    let onRemoved: (Bool) -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dts

    /// The WHOOP family a scan targets — the same key Live's strap picker wrote.
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue

    @State private var confirm: DeviceConfirm?
    @State private var rebootProbeTarget: PairedDevice?
    @State private var batteryProbeTarget: PairedDevice?
    @State private var bodyLocationProbeTarget: PairedDevice?
    @State private var featureFlagProbeTarget: PairedDevice?
    @State private var deviceConfigProbeTarget: PairedDevice?

    private var device: PairedDevice? { registry.devices.first { $0.id == deviceId } }

    var body: some View {
        Group {
            if let device {
                page(device, readout: .make(device, live: live))
            } else {
                // Forgotten from under the page.
                Color.clear.onAppear { dismiss() }
            }
        }
        .settingsForm()
        .navigationTitle(Text(verbatim: device?.displayName ?? ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(DeviceConfirmDialog(confirm: $confirm, perform: perform))
        .modifier(RebootProbeDialog(target: $rebootProbeTarget))
        .modifier(ExtendedBatteryProbeSheets(target: $batteryProbeTarget))
        .modifier(BodyLocationProbeSheets(target: $bodyLocationProbeTarget))
        .modifier(FeatureFlagProbeSheets(target: $featureFlagProbeTarget))
        .modifier(DeviceConfigProbeSheets(target: $deviceConfigProbeTarget))
    }

    private func page(_ device: PairedDevice, readout r: DeviceReadout) -> some View {
        Form {
            Section { hero(device, r) }

            // #221: linked, but the strap refused the bond — the self-service fix right here.
            if r.bondRefused, let hint = live.pairingHint {
                Section { DeviceWarning(title: "Connected, but not paired", message: "Pair it to sync history.", detail: hint) }
            }
            // #987: a strap clock that reads 1970/71 banks no history.
            if r.isActive, let warning = clockState?.warning {
                Section { DeviceWarning(title: "Strap clock not set", message: "History isn't saved until it's set.", detail: warning) }
            }

            Section {
                NavigationLink {
                    DeviceNamePage(registry: registry, device: device)
                } label: {
                    valueRow("Name", device.displayName)
                }
            }

            if device.status == .active { controlsSection(device, r) }

            if device.status == .paired && !device.isImportSource {
                Section {
                    // Reversible, so no confirmation — as a tap in Bluetooth switches the device.
                    Button("Make Active") { registry.setActive(device.id) }
                }
            }

            // The strap's own settings, under the strap as the Watch app keeps a watch's.
            if r.isActive && r.isWhoop { StrapSettingsCard() }

            infoSection(device, r)

            if r.isActive && r.isWhoop && r.isLive && TestCentre.active(.connection) {
                probeSection(device)
            }

            removeSection(device, r)
        }
    }

    // MARK: Hero

    /// The glyph on the page's own background, and under it the charge as a green ring and a figure,
    /// as Settings heads an AirPods page; the link word when there is no charge to show.
    private func hero(_ device: PairedDevice, _ r: DeviceReadout) -> some View {
        VStack(spacing: 6) {
            DeviceArtwork(kind: .of(device), size: 120)
                .padding(.bottom, 8)
            if let pct = r.batteryPct, !r.bondRefused {
                ZStack {
                    Circle().stroke(StrandPalette.hairline, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(pct) / 100)
                        .stroke(pct < 15 ? StrandPalette.settingsRed : StrandPalette.settingsGreen,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 40, height: 40)
                Text(verbatim: pct.formatted(.percent.locale(AppLanguage.activeLocale)))
                    .font(StrandFont.pro(17))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
            } else {
                Text(verbatim: String(localized: String.LocalizationValue(r.pill.label)))
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
        .accessibilityElement(children: .combine)
    }

    // MARK: Battery · sync · firmware

    @ViewBuilder private func infoSection(_ device: PairedDevice, _ r: DeviceReadout) -> some View {
        let firmware = firmware(device, r)
        let sync = r.isActive ? SyncChipState.resolve(live: live) : .hidden
        let testing = TestCentre.active(.connection)
        let layout = r.isLive ? live.strapRange?.firmwareLayout : nil
        Section {
                // #592: pack voltage, for protocol work only.
                if testing, r.isLive, let mv = live.batteryMv {
                    valueRow("Voltage", String(format: "%.2f V", Double(mv) / 1000))
                }
                syncRow(sync)
                if r.isActive && r.isWhoop {
                    Picker("Model", selection: modelSelection) {
                        ForEach(WhoopModel.allCases, id: \.self) { Text(verbatim: $0.displayName).tag($0) }
                    }
                    .settingsPicker()
                    // Switching family while a strap streams would drop it; Live hid the picker then too.
                    .disabled(r.isLive && live.bonded)
                } else if !r.isWhoop {
                    valueRow("Model", device.model)
                }
                if let firmware { valueRow("Firmware", firmware) }
                if testing, let layout { valueRow("History layout", "v\(layout)") }
                if r.isWhoop {
                    NavigationLink {
                        DeviceReadsView(family: DeviceFamily.confirmedRegistryFamily(model: device.model,
                                                                                    brand: device.brand))
                    } label: {
                        Text("What reNOOP Reads").foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                if testing, r.isActive, let line = clockState?.line {
                    Text(verbatim: line)
                        .font(StrandFont.pro(13))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
        } header: {
            Text("About This Device")
        }
    }

    @ViewBuilder private func syncRow(_ sync: SyncChipState) -> some View {
        if sync != .hidden {
            rowLayout {
                Text("Sync").foregroundStyle(StrandPalette.textPrimary)
                if !dts.isAccessibilitySize { Spacer() }
                StrapSyncStatusText(style: .value)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Controls

    @ViewBuilder private func controlsSection(_ device: PairedDevice, _ r: DeviceReadout) -> some View {
        let bondedLink = r.isWhoop && live.connected && live.bonded
        if r.isWhoop || r.isOura {
            Section {
                if r.isWhoop {
                    // The explicit user connect (`model.scan` → `BLEManager.connect`), as Live's Scan was.
                    Button(live.connected ? "Re-scan" : "Connect") { model.scan() }
                    // #921: the confirmed one-shot buzz sequence.
                    Button("Buzz") { model.buzzStrapOnce() }
                        .disabled(!bondedLink)
                    if r.isLive && live.backfilling {
                        // Nothing is lost: unacked records stay on the strap.
                        Button("Stop Sync") { model.ble.abortBackfill() }
                    }
                    // #275: no safe frame reboots a 4.0; a 5.0/MG reboots on the production frame.
                    if r.isLive && !model.ble.isWhoop4 {
                        Button("Restart") { confirm = .restart(device) }
                    }
                }
                if r.isOura {
                    // #2305: drops the ring link, if any, and connects again.
                    Button("Reconnect Ring") { model.reconnectOuraRing() }
                }
            }
        }
    }

    // MARK: Test Centre

    private func probeSection(_ device: PairedDevice) -> some View {
        Section {
            if model.ble.isWhoop4 {
                Button("Reboot probe (4.0 RE)…") { rebootProbeTarget = device }
            }
            Button("Battery-info probe (#592 RE)…") { batteryProbeTarget = device }
            Button("Body-location probe (#690 RE)…") { bodyLocationProbeTarget = device }
            Button("Feature-flag probe (#761 RE)…") { featureFlagProbeTarget = device }
            Button("Device-config read probe (#103 RE)…") { deviceConfigProbeTarget = device }
        } header: {
            Text("Test Centre")
        }
    }

    // MARK: Disconnect · forget

    @ViewBuilder private func removeSection(_ device: PairedDevice, _ r: DeviceReadout) -> some View {
        Section {
            if device.status == .archived {
                if !device.isImportSource {
                    Button("Make Active") { registry.setActive(device.id) }
                }
                Button("Delete Data", role: .destructive) { confirm = .deleteData(device) }
                    .foregroundStyle(StrandPalette.settingsRed)
                Button("Remove Device and Data", role: .destructive) { confirm = .purge(device) }
                    .foregroundStyle(StrandPalette.settingsRed)
            } else {
                if r.isActive && r.isWhoop && (live.connected || live.bonded) {
                    Button("Disconnect") { model.disconnect() }
                }
                Button("Forget This Device") { confirm = .forget(device) }
            }
        }
    }

    // MARK: Actions

    private func perform(_ c: DeviceConfirm) {
        switch c {
        case .restart:
            model.rebootStrap()
        case .forget(let d):
            let wasActive = d.status == .active
            // #78: release the BLE link too, or NOOP keeps re-grabbing the strap and it can never enter
            // pairing mode to be re-paired.
            model.ble.forgetDevice(d.peripheralId)
            registry.archive(d.id)
            dismiss()
            onRemoved(wasActive)
        case .deleteData(let d):
            // The 16+-table delete runs on the WhoopStore actor, off the main thread.
            Task {
                guard let store = await model.repo.storeHandle() else { return }
                await registry.deleteDeviceData(d.id, store: store)
            }
        case .purge(let d):
            // #1193: the only way to get a duplicate/stale strap out of the list for good.
            Task {
                guard let store = await model.repo.storeHandle() else { return }
                await registry.forget(d.id, store: store)
            }
            dismiss()
        }
    }

    // MARK: Readouts

    private var modelSelection: Binding<WhoopModel> {
        Binding(get: { WhoopModel(rawValue: selectedModelRaw) ?? .whoop4 },
                set: { new in
                    guard new.rawValue != selectedModelRaw else { return }
                    selectedModelRaw = new.rawValue
                    // Drop the previous strap's sticky bond so the next scan targets the new family.
                    model.prepareStrapSwitch()
                })
    }

    /// A STABLE property of the strap: the live handshake value, else the last one persisted for THIS
    /// device (#1633), else the legacy global key when only one device is paired. WHOOP only.
    private func firmware(_ d: PairedDevice, _ r: DeviceReadout) -> String? {
        FirmwareAttribution.resolve(
            live: r.isActive ? live.strapFirmware : nil,
            perDevice: r.isWhoop
                ? FirmwareAttribution.prefKey(peripheralId: d.peripheralId)
                    .flatMap { UserDefaults.standard.string(forKey: $0) } : nil,
            legacyGlobal: r.isWhoop ? UserDefaults.standard.string(forKey: "noop.lastFirmware") : nil,
            pairedCount: registry.devices.count)
    }

    /// #987: the connected strap's clock state, from the same pure ConnectionReadout parsers the Test
    /// Centre Connection panel binds. nil until the WHOOP path produced any clock signal. #1818: the
    /// battery term reads this link's `batterySamples`, never the last-known `batteryPct`.
    private var clockState: (line: String, warning: String?)? {
        guard live.connected else { return nil }
        let deviceClock = ConnectionReadout.clockCorrelatedDevice(logLines: live.log)
        guard deviceClock != nil || live.strapRange != nil || live.lastFrameAtUnix != nil else { return nil }
        let latched = ConnectionReadout.clockLatchedLabel(deviceClockUnix: deviceClock,
                                                          strapNewestUnix: live.strapRange?.newestUnix)
        let frame = ConnectionReadout.lastFrameLabel(lastFrameUnix: live.lastFrameAtUnix,
                                                     nowUnix: Int(Date().timeIntervalSince1970))
        let warning = ConnectionReadout.rtcWarning(deviceClockUnix: deviceClock,
                                                   strapNewestUnix: live.strapRange?.newestUnix,
                                                   batteryPct: live.batterySamples.last?.soc)
        return (String(localized: "Clock latched: \(latched) · last frame \(frame)"), warning)
    }

    private func valueRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        rowLayout {
            Text(title).foregroundStyle(StrandPalette.textPrimary)
            if !dts.isAccessibilitySize { Spacer() }
            Text(verbatim: value)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(dts.isAccessibilitySize ? nil : 1)
        }
    }

    /// Title and value side by side, the value under the title at accessibility sizes.
    private var rowLayout: AnyLayout {
        dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                : AnyLayout(HStackLayout())
    }
}

// MARK: - Confirmations

enum DeviceConfirm: Identifiable {
    case restart(PairedDevice), forget(PairedDevice)
    case deleteData(PairedDevice), purge(PairedDevice)

    var id: String {
        switch self {
        case .restart(let d): return "restart-\(d.id)"
        case .forget(let d): return "forget-\(d.id)"
        case .deleteData(let d): return "delete-\(d.id)"
        case .purge(let d): return "purge-\(d.id)"
        }
    }
}

/// One action sheet for every confirmation on the page, as iOS asks from the bottom before it forgets or
/// erases, kept out of the page body so the dialog chain type-checks in its own scope.
private struct DeviceConfirmDialog: ViewModifier {
    @Binding var confirm: DeviceConfirm?
    let perform: (DeviceConfirm) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                                   titleVisibility: .visible, presenting: confirm) { c in
            Button(actionTitle(c), role: isDestructive(c) ? .destructive : nil) {
                confirm = nil
                perform(c)
            }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { c in
            Text(message(c))
        }
    }

    private var title: LocalizedStringKey {
        switch confirm {
        case .restart: return "Restart this strap?"
        case .forget: return "Forget this device?"
        case .deleteData: return "Delete all of this device's data?"
        case .purge: return "Remove from the list?"
        case nil: return ""
        }
    }

    private func actionTitle(_ c: DeviceConfirm) -> LocalizedStringKey {
        switch c {
        case .restart: return "Restart"
        case .forget: return "Forget This Device"
        case .deleteData: return "Delete Data"
        case .purge: return "Remove Device and Data"
        }
    }

    private func isDestructive(_ c: DeviceConfirm) -> Bool {
        switch c {
        case .restart: return false
        default: return true
        }
    }

    private func message(_ c: DeviceConfirm) -> LocalizedStringKey {
        switch c {
        case .restart: return "It reconnects on its own in about 30 seconds."
        case .forget: return "reNOOP stops connecting to it. Its data is kept."
        case .deleteData: return "This can't be undone."
        case .purge: return "Its recorded data is deleted too."
        }
    }
}

// MARK: - Name

/// The device's name as its own page, as Settings renames AirPods: one field with a clear button, and an
/// empty name puts the old one back rather than saving nothing.
private struct DeviceNamePage: View {
    @ObservedObject var registry: DeviceRegistry
    let device: PairedDevice
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var saved: String { device.nickname ?? device.displayName }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField(text: $draft, prompt: Text(verbatim: device.displayName)) { Text("Name") }
                        .focused($focused)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                    if focused && !draft.isEmpty {
                        Button { draft = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Clear text"))
                    }
                }
            }
        }
        .settingsPage("Name")
        .onAppear { draft = saved; focused = true }
        .onDisappear(perform: save)
    }

    private func save() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            draft = saved
            return
        }
        guard draft != saved else { return }
        registry.rename(device.id, to: draft)
    }
}
