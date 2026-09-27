//  DevicesView.swift
//  NOOP · Devices — the paired bands as Bluetooth and the Watch app's "All Watches" list them: a product
//  picture, the name, "Connected · 82 %", a checkmark on the active one, then "Add Device". A row opens
//  the device's page (`DeviceDetailView`), where everything about that one device lives.
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
    /// After removing the ACTIVE device with others still paired, ask which one becomes active.
    @State private var pickNewActive = false
    /// The device whose page is pushed.
    @State private var opened: String?

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
                Section { DeviceWarning(title: "Can't connect: your strap's pairing was reset", detail: guide) }
            }

            if !current.isEmpty {
                Section {
                    ForEach(current) { device in
                        DeviceRow(device: device, readout: .make(device, live: live)) { opened = device.id }
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
                        DeviceRow(device: device, readout: .make(device, live: live)) { opened = device.id }
                            .opacity(0.6)
                    }
                } header: {
                    Text("Removed")
                }
            }
        }
        .navigationDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened {
                DeviceDetailView(registry: registry, deviceId: opened, onRemoved: removedDevice)
            }
        }
        .sheet(isPresented: $showAddWizard) {
            AddDeviceWizard(live: live) { showAddWizard = false }
                .environmentObject(model)
                .environmentObject(live)
        }
        .confirmationDialog("Pick a new active strap", isPresented: $pickNewActive, titleVisibility: .visible) {
            ForEach(activatable) { device in
                Button(device.displayName) { registry.setActive(device.id) }
            }
            Button("Leave none active", role: .cancel) { }
        }
    }

    /// A device page removed its device; if it was the active one and others remain, ask for a new one.
    private func removedDevice(wasActive: Bool) {
        if wasActive && !activatable.isEmpty { pickNewActive = true }
    }
}

// MARK: - Row

/// As the Watch app's "All Watches" lists a watch: a checkmark on the active one, the product picture,
/// the name over "Connected · 82 %", and ⓘ. The row opens the device's page.
struct DeviceRow: View {
    let device: PairedDevice
    let readout: DeviceReadout
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .opacity(readout.isActive ? 1 : 0)
                    .accessibilityHidden(!readout.isActive)
                    .accessibilityLabel(Text("Active"))
                DeviceArtwork(kind: .of(device), size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: device.displayName)
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: readout.statusLine)
                        .font(StrandFont.pro(15))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "info.circle")
                    .font(StrandFont.pro(22))
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// A problem that stops the device working, in the warning hue: a bold line and the fix under it.
struct DeviceWarning: View {
    let title: LocalizedStringKey
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StrandPalette.settingsOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(StrandFont.pro(15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: detail)
                    .font(StrandFont.pro(13))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
