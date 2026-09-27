//  DeviceProbeSheets.swift
//  NOOP · Devices — the Test Centre → Connection read-only protocol probes: each confirm dialog and its
//  result sheet (raw reply, selectable, with Copy). Reached from a device page only while that test mode
//  is on and the WHOOP is live. Unchanged from the old Devices screen.

import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - #592 extended-battery probe result

/// The #592 probe reply (raw hex + payload triage + capture diff), or a "waiting…" state while in flight.
/// Read-only; the text is selectable and a Copy button puts it on the clipboard so a capture pastes into
/// the issue without a full strap-log export. Twin of the Android BatteryInfoProbeResultDialog.
private struct ExtendedBatteryProbeResultView: View {
    let text: String
    let onClose: () -> Void
    private var waiting: Bool { text == BLEManager.extendedBatteryProbeWaiting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Battery-info probe result (#592)")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            if waiting {
                Text("Waiting for the strap's reply…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if os(iOS)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #endif
            }
            HStack {
                if !waiting {
                    Button("Copy") { PlatformPasteboard.copy(text) }
                }
                Spacer()
                Button("Close") { onClose() }
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 260)
        .background(NoopChromeSurface())
    }
}


/// #690: the body-location probe's confirm + result dialogs as one ViewModifier, so they're type-checked
/// in isolation instead of extending the DevicesView `.confirmationDialog`/`.sheet` chain (which is already
/// near the iOS Swift type-checker's budget). `model`/`live` auto-inject from the parent's environment.
struct BodyLocationProbeSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @Binding var target: PairedDevice?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Body-location probe (#690 RE)",
                                isPresented: Binding(get: { target != nil },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible,
                                presenting: target) { _ in
                Button("Send probe (read-only)") { model.probeBodyLocationAndStatus(); target = nil }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text("Sends the read-only GET_BODY_LOCATION_AND_STATUS (0x54) and shows the strap's full raw reply, decoding the body-location record (revision / location / confidence / status) on WHOOP 4.0. Nothing is written to the strap, and it never changes wear detection or scoring.")
            }
            .sheet(isPresented: Binding(get: { live.bodyLocationProbe != nil },
                                        set: { if !$0 { model.clearBodyLocationProbe() } })) {
                BodyLocationProbeResultView(
                    text: live.bodyLocationProbe ?? "",
                    onClose: { model.clearBodyLocationProbe() })
            }
    }
}

/// The #690 body-location probe reply (raw hex + decoded record + capture diff), or a "waiting…" state
/// while in flight. Read-only; selectable text + a Copy button. Twin of the Android BodyLocationProbe
/// result dialog and structurally identical to ExtendedBatteryProbeResultView.
private struct BodyLocationProbeResultView: View {
    let text: String
    let onClose: () -> Void
    private var waiting: Bool { text == BLEManager.bodyLocationProbeWaiting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Body-location probe result (#690)")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            if waiting {
                Text("Waiting for the strap's reply…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if os(iOS)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #endif
            }
            HStack {
                if !waiting {
                    Button("Copy") { PlatformPasteboard.copy(text) }
                }
                Spacer()
                Button("Close") { onClose() }
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 260)
        .background(NoopChromeSurface())
    }
}

/// #761: the READ-ONLY feature-flag enumeration probe's confirm + result dialogs, isolated into a
/// ViewModifier for the same reason `BodyLocationProbeSheets` is — keeping the DevicesView
/// `.confirmationDialog`/`.sheet` chain inside the iOS Swift type-checker's budget.
struct FeatureFlagProbeSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @Binding var target: PairedDevice?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Feature-flag probe (#761 RE)",
                                isPresented: Binding(get: { target != nil },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible,
                                presenting: target) { _ in
                Button("Send probe (read-only)") { model.probeFeatureFlags(); target = nil }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text("Asks the strap to list the feature-flag NAMES its own firmware knows: START_FF_KEY_EXCHANGE (0x75) then SEND_NEXT_FF (0x76) until the strap says it's done. Read-only — no flag value is written, and the SET commands are never sent from this probe. The list is shown here and written to the strap log.")
            }
            .sheet(isPresented: Binding(get: { live.featureFlagProbe != nil },
                                        set: { if !$0 { model.clearFeatureFlagProbe() } })) {
                FeatureFlagProbeResultView(
                    text: live.featureFlagProbe ?? "",
                    onClose: { model.clearFeatureFlagProbe() })
            }
    }
}

/// The #761 enumeration report (the strap's own flag-name list + the exchange trace), or a "waiting…"
/// state while the walk runs. Selectable text + a Copy button, structurally identical to the #592/#690
/// result views. Twin of the Android feature-flag probe result dialog.
private struct FeatureFlagProbeResultView: View {
    let text: String
    let onClose: () -> Void
    private var waiting: Bool { text == BLEManager.featureFlagProbeWaiting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Feature-flag probe result (#761)")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            if waiting {
                // Reuses the #592/#690 waiting copy — the walk sends one 118 per reply, so at any moment
                // it is waiting on exactly one strap reply, and the catalog keeps a single translation.
                Text("Waiting for the strap's reply…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if os(iOS)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #endif
            }
            HStack {
                if !waiting {
                    Button("Copy") { PlatformPasteboard.copy(text) }
                }
                Spacer()
                Button("Close") { onClose() }
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 260)
        .background(NoopChromeSurface())
    }
}

/// #103: the READ-ONLY device-config read probe's confirm + result dialogs, isolated into a
/// ViewModifier for the same reason `FeatureFlagProbeSheets` is — keeping the DevicesView
/// `.confirmationDialog`/`.sheet` chain inside the iOS Swift type-checker's budget.
struct DeviceConfigProbeSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @Binding var target: PairedDevice?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Device-config read probe (#103 RE)",
                                isPresented: Binding(get: { target != nil },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible,
                                presenting: target) { _ in
                Button("Send probe (read-only)") { model.probeDeviceConfigValues(); target = nil }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text("Asks the strap for config VALUES: GET_DEVICE_CONFIG_VALUE (0x79) and GET_FF_VALUE (0x80), one key per round-trip. Both commands may simply not exist in this firmware — finding that out is the point. Read-only — no value is written, and the SET commands are never sent from this probe. The result is shown here and written to the strap log.")
            }
            .sheet(isPresented: Binding(get: { live.deviceConfigProbe != nil },
                                        set: { if !$0 { model.clearDeviceConfigProbe() } })) {
                DeviceConfigProbeResultView(
                    text: live.deviceConfigProbe ?? "",
                    onClose: { model.clearDeviceConfigProbe() })
            }
    }
}

/// The #103 read report (per-verb verdict, the values read, the exchange transcript), or a "waiting…"
/// state while the plan runs. Selectable text + a Copy button, structurally identical to the #592/#690/
/// #761 result views. Twin of the Android device-config probe result dialog.
private struct DeviceConfigProbeResultView: View {
    let text: String
    let onClose: () -> Void
    private var waiting: Bool { text == BLEManager.deviceConfigProbeWaiting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Device-config read probe result (#103)")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            if waiting {
                // Reuses the #592/#690/#761 waiting copy — the plan sends one read per reply, so at any
                // moment it is waiting on exactly one strap reply, and the catalog keeps one translation.
                Text("Waiting for the strap's reply…")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if os(iOS)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                #endif
            }
            HStack {
                if !waiting {
                    Button("Copy") { PlatformPasteboard.copy(text) }
                }
                Spacer()
                Button("Close") { onClose() }
            }
        }
        .padding(20)
        .frame(minWidth: 340, minHeight: 260)
        .background(NoopChromeSurface())
    }
}

/// #592: the extended-battery probe's confirm + result, isolated the same way as the probes above.
struct ExtendedBatteryProbeSheets: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @Binding var target: PairedDevice?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Battery-info probe (#592 RE)",
                                isPresented: Binding(get: { target != nil },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible,
                                presenting: target) { _ in
                Button("Send probe (read-only)") { model.probeExtendedBatteryInfo(); target = nil }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text("Two independent protocol tables disagree on the extended-battery opcode (98 vs 87). This sends the curated read-only 98 and shows the strap's full raw reply. A battery-style payload confirms 98 on your firmware; a short stub means it stays ambiguous. Nothing is written to the strap.")
            }
            .sheet(isPresented: Binding(get: { live.extendedBatteryProbe != nil },
                                        set: { if !$0 { model.clearExtendedBatteryProbe() } })) {
                ExtendedBatteryProbeResultView(
                    text: live.extendedBatteryProbe ?? "",
                    onClose: { model.clearExtendedBatteryProbe() })
            }
    }
}

/// WHOOP 4.0 reboot probe (#235): each candidate frame, one at a time, so the strap log shows which one
/// actually reboots.
struct RebootProbeDialog: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var target: PairedDevice?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("WHOOP 4.0 reboot probe",
                                isPresented: Binding(get: { target != nil },
                                                     set: { if !$0 { target = nil } }),
                                titleVisibility: .visible,
                                presenting: target) { _ in
                ForEach(RebootProbeVariant.allCases, id: \.self) { variant in
                    Button(variant.menuLabel) { model.rebootProbe(variant); target = nil }
                }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text("The WHOOP 4.0 reboot frame isn't confirmed — a normal Restart is ignored (#235). Send each candidate and watch BOTH the strap log and the strap itself. “no disconnect within 12s” means the strap ignored the frame. A “link dropped” line means the frame reached the strap — but a dropped link alone isn't a reboot: a real reboot also switches the strap's sensor light off for a few seconds, so if the light stayed on it was just a dropped connection, not a reboot. Non-destructive — your data is kept. Please share the log so we can pin the real frame.")
            }
    }
}
