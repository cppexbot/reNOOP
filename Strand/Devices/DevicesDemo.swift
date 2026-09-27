//  DevicesDemo.swift
//  NOOP · Devices — DEBUG-only: every kind of device row with a fixed state (`--demo-screen
//  devicescatalog`), so the pictures and status lines can be screenshotted without hardware.

#if DEBUG
import SwiftUI
import StrandDesign
import WhoopStore

struct DeviceCardCatalog: View {
    private struct Mock: Identifiable {
        let device: PairedDevice
        let readout: DeviceReadout
        var id: String { device.id }
    }

    private static func device(_ id: String, _ brand: String, _ model: String, _ kind: SourceKind,
                               _ status: DeviceStatus = .paired) -> PairedDevice {
        PairedDevice(id: id, brand: brand, model: model, nickname: nil, peripheralId: nil, sourceKind: kind,
                     capabilities: [.hr, .hrv], status: status, addedAt: 0, lastSeenAt: 0)
    }

    private static func readout(active: Bool = false, whoop: Bool = false, oura: Bool = false, live: Bool = false,
                                refused: Bool = false, pct: Int? = nil, archived: Bool = false) -> DeviceReadout {
        DeviceReadout(isActive: active, isWhoop: whoop, isOura: oura, isLive: live, bondRefused: refused,
                      reconnecting: false, batteryPct: pct,
                      pill: .resolve(isArchived: archived, isActive: active, isReconnecting: false,
                                     bondRefused: refused, isLiveConnected: live))
    }

    private let mocks: [Mock] = [
        Mock(device: device("whoop-4", "WHOOP", "4.0", .liveBLE, .active),
             readout: readout(active: true, whoop: true, live: true, pct: 82)),
        Mock(device: device("whoop-5", "WHOOP", "5.0 MG", .liveBLE), readout: readout(whoop: true)),
        Mock(device: device("whoop-5r", "WHOOP", "5.0 MG", .liveBLE, .active),
             readout: readout(active: true, whoop: true, live: true, refused: true, pct: 64)),
        Mock(device: device("strap-h10", "Polar", "H10", .liveBLE), readout: readout()),
        Mock(device: device("oura-3", "Oura", "Oura Ring 3", .oura), readout: readout(oura: true)),
        Mock(device: device("apple-health", "Apple", "Apple Watch", .liveAppleWatch), readout: readout()),
        Mock(device: device("ftms-1", "Gym equipment", "Kickr", .ftms), readout: readout()),
        Mock(device: device("oura-cloud", "Oura", "Oura (import)", .cloudImport, .archived),
             readout: readout(archived: true)),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(mocks) { m in
                    DeviceRow(device: m.device, readout: m.readout) {}
                }
            } header: {
                Text("My Devices")
            }
        }
        .settingsPage("Devices")
    }
}
#endif
