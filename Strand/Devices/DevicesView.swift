//  DevicesView.swift
//  NOOP · Devices — the paired bands as Bluetooth and the Watch app's "All Watches" list them: the device
//  glyph, the name, "Connected · 82 %", a checkmark on the active one, then "Add Device". Tapping a row
//  makes that device the active one; its ⓘ opens the device's page (`DeviceDetailView`), where everything
//  about that one device lives.
//
//  A thin UI over `DeviceRegistry`: every mutation is a registry op, and the `SourceCoordinator` (wired
//  in AppModel) reacts to the active-device change — this screen never drives BLE itself beyond the calls
//  the old Devices and Live screens made.

import SwiftUI
import StrandDesign
import WhoopStore

struct DevicesView: View {
    @EnvironmentObject var model: AppModel
    // PERF: this outer view does NOT observe `LiveState`; `DevicesList` does, so a 1 Hz strap tick
    // re-renders only the list.

    var body: some View {
        Group {
            if let registry = model.deviceRegistry {
                DevicesList(registry: registry)
            } else {
                // The registry opens a beat after launch.
                Form {
                    Section {
                        Text("Getting your devices ready")
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
        .settingsPage("Devices")
    }
}

// MARK: - List

private struct DevicesList: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState

    @State private var showAddWizard = false
    /// The wizard's "Import a File": the sheet closes first, then the import page is pushed here.
    @State private var importAfterWizard = false
    @State private var showImport = false
    /// After removing the ACTIVE device with others still paired, ask which one becomes active.
    @State private var pickNewActive = false

    private var current: [PairedDevice] {
        registry.devices.filter { $0.status != .archived }
            .sorted { ($0.status == .active ? 0 : 1) < ($1.status == .active ? 0 : 1) }
    }
    private var removed: [PairedDevice] { registry.devices.filter { $0.status == .archived } }
    /// I-1: import sources are data partitions, never an active-device candidate.
    private var activatable: [PairedDevice] { current.filter { !$0.isImportSource } }
    private var activeIsWhoop: Bool {
        registry.devices.contains { $0.status == .active && SourceCoordinator.isWhoop($0) }
    }

    var body: some View {
        Form {
            // #802: a strap whose bond the strap wiped can't connect until it's re-paired; say so where
            // devices are fixed.
            if let guide = live.reconnectGuide {
                Section { DeviceWarning(title: "Strap pairing was reset", message: "Re-pair it to reconnect.", detail: guide) }
            }

            if !current.isEmpty {
                Section {
                    ForEach(current) { device in
                        DeviceRow(device: device, readout: .make(device, live: live), onSelect: select(device))
                    }
                } header: {
                    Text("My Devices")
                }
            }

            Section {
                Button {
                    showAddWizard = true
                } label: {
                    Text("Add Device").foregroundStyle(StrandPalette.accent)
                }
            }

            // The strap's own settings sit on the active WHOOP's page; with no WHOOP active they stay here.
            if !activeIsWhoop { StrapSettingsCard() }

            if !removed.isEmpty {
                Section {
                    ForEach(removed) { device in
                        DeviceRow(device: device, readout: .make(device, live: live), onSelect: select(device))
                            .opacity(0.6)
                    }
                } header: {
                    Text("Removed")
                }
            }
        }
        // A value route, so the page's own pushes (its SettingsPage rows) stay on the same path.
        .navigationDestination(for: DeviceRoute.self) { route in
            DeviceDetailView(registry: registry, deviceId: route.id, onRemoved: removedDevice)
        }
        // The import page has no pushes of its own, so a flag-driven destination is enough here.
        .navigationDestination(isPresented: $showImport) { DataSourcesView() }
        .sheet(isPresented: $showAddWizard, onDismiss: {
            if importAfterWizard { importAfterWizard = false; showImport = true }
        }) {
            AddDeviceWizard(live: live, onClose: { showAddWizard = false },
                            onImport: { importAfterWizard = true; showAddWizard = false })
                .environmentObject(model)
                .environmentObject(live)
        }
        .confirmationDialog("Pick a new active strap", isPresented: $pickNewActive, titleVisibility: .visible) {
            ForEach(activatable) { device in
                Button(device.displayName) { registry.setActive(device.id) }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    /// A row's tap: make that device the active one, as Bluetooth and "All Watches" switch on a tap. An
    /// import source is never active (I-1), so its row opens its page instead.
    private func select(_ device: PairedDevice) -> (() -> Void)? {
        guard !device.isImportSource else { return nil }
        return {
            guard device.status != .active else { return }
            registry.setActive(device.id)
        }
    }

    /// A device page removed its device; if it was the active one and others remain, ask for a new one.
    private func removedDevice(wasActive: Bool) {
        if wasActive && !activatable.isEmpty { pickNewActive = true }
    }
}

// MARK: - Row

/// As the Watch app's "All Watches" lists a watch: a checkmark on the active one, the device glyph,
/// the name over "Connected · 82 %", and ⓘ. The row makes the device active; ⓘ opens its page.
struct DeviceRow: View {
    let device: PairedDevice
    let readout: DeviceReadout
    /// The row's tap. nil: the whole row opens the device's page.
    var onSelect: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        ZStack {
            // The value link without its chevron. It takes every tap the row's button doesn't — ⓘ's, and
            // the whole row's when there is no button — and pushes by value, so the page's own Settings
            // rows stay on the same path.
            NavigationLink(value: DeviceRoute(id: device.id)) { EmptyView() }
                .opacity(0)
                .accessibilityHidden(true)
            HStack(spacing: 12) {
                if let onSelect {
                    Button(action: onSelect) { summary }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(readout.isActive ? .isSelected : [])
                } else {
                    summary
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                }
                Image(systemName: "info.circle")
                    .font(StrandFont.pro(22))
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Details"))
                    .accessibilityAddTraits(.isButton)
            }
            .padding(.vertical, 6)
        }
    }

    /// Checkmark, glyph, name and status: everything left of ⓘ.
    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(StrandFont.pro(17, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .opacity(readout.isActive ? 1 : 0)
                .accessibilityHidden(true)
            DeviceArtwork(kind: .of(device), size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: device.displayName)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(dts.isAccessibilitySize ? nil : 1)
                Text(verbatim: readout.statusLine)
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(dts.isAccessibilitySize ? nil : 1)
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}

/// The page a device row pushes.
struct DeviceRoute: Hashable {
    let id: String
}

/// A problem that stops the device working: the shared warning notice, set in a Form section as its own
/// card. The notice says it in one line; the full step-by-step fix opens from "How to Fix".
struct DeviceWarning: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let detail: String

    @State private var showFix = false

    var body: some View {
        NoticeCard(title: Text(title), message: Text(message),
                   systemImage: "exclamationmark.triangle.fill", tone: .warning,
                   actionTitle: "How to Fix", action: { showFix = true })
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .sheet(isPresented: $showFix) {
                NavigationStack {
                    ScrollView {
                        Text(verbatim: detail)
                            .font(StrandFont.pro(17))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .background(StrandPalette.summaryCanvas.ignoresSafeArea())
                    .navigationTitle(Text(title))
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            SheetCloseButton { showFix = false }
                        }
                    }
                }
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
            }
    }
}
