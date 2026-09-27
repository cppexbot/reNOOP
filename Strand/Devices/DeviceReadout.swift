//  DeviceReadout.swift
//  NOOP · Devices — what one registered device is doing right now, resolved once so the list row and
//  the device page can never disagree: the link word, the battery, and the flags the page's controls
//  are gated on.

import SwiftUI
import WhoopStore

/// The link word, as a priority-ordered pure decision (#221): archived beats everything; on the active
/// device, reconnecting > bond-refused > live > not connected; any other device reads "Not connected".
/// Pinned by `DevicePillStateTests`.
struct DevicePillState: Equatable {
    let label: String

    static func resolve(isArchived: Bool, isActive: Bool, isReconnecting: Bool,
                        bondRefused: Bool, isLiveConnected: Bool) -> DevicePillState {
        if isArchived { return DevicePillState(label: "Removed") }
        guard isActive else { return DevicePillState(label: "Not connected") }
        if isReconnecting { return DevicePillState(label: "Reconnecting…") }
        if bondRefused { return DevicePillState(label: "Connected · not paired") }
        if isLiveConnected { return DevicePillState(label: "Connected") }
        return DevicePillState(label: "Not connected")
    }
}

/// One device's live state, read off `LiveState` for THIS row only: the live link, its battery and its
/// bond belong to whichever device is active, never to the others.
struct DeviceReadout {
    let isActive: Bool
    let isWhoop: Bool
    let isOura: Bool
    /// Active and linked.
    let isLive: Bool
    /// #221: linked, but the encrypted bond was refused (#78) — no data flows.
    let bondRefused: Bool
    /// A user restart is in flight and the link is down (#166).
    let reconnecting: Bool
    /// The live charge: a WHOOP, a generic strap and an FTMS machine funnel into `batteryPct`, a ring
    /// reports its own (#2075).
    let batteryPct: Int?
    let pill: DevicePillState

    @MainActor
    static func make(_ d: PairedDevice, live: LiveState) -> DeviceReadout {
        let isActive = d.status == .active
        let isWhoop = SourceCoordinator.isWhoop(d)
        let isLive = isActive && live.connected
        let bondRefused = isLive && live.pairingHint != nil
        let reconnecting = isActive && live.rebootInProgress && !live.connected
        let pct = isLive
            ? LiveConsoleReadout.batteryPercent(activeIsWhoop: isWhoop, whoopPct: live.batteryPct,
                                                ringPct: live.ouraBatteryPct)
            : nil
        return DeviceReadout(
            isActive: isActive, isWhoop: isWhoop, isOura: d.sourceKind == .oura,
            isLive: isLive, bondRefused: bondRefused, reconnecting: reconnecting, batteryPct: pct,
            pill: .resolve(isArchived: d.status == .archived, isActive: isActive,
                           isReconnecting: reconnecting, bondRefused: bondRefused, isLiveConnected: isLive))
    }

    /// "Connected · 82 %", as Bluetooth and the Watch app caption a device.
    var statusLine: String {
        let word = String(localized: String.LocalizationValue(pill.label))
        guard let batteryPct, !bondRefused else { return word }
        return "\(word) · \(batteryPct.formatted(.percent.locale(AppLanguage.activeLocale)))"
    }
}

/// A battery glyph for a charge, in the same buckets as the menu bar and the Summary.
func deviceBatterySymbol(_ pct: Int) -> String {
    switch pct {
    case ..<13: return "battery.0percent"
    case ..<38: return "battery.25percent"
    case ..<63: return "battery.50percent"
    case ..<88: return "battery.75percent"
    default: return "battery.100percent"
    }
}
