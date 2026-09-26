//  StrapBatteryDisplay.swift
//  NOOP · Summary home — what the strap status in the Summary's bar may honestly say, and the one
//  debounce for the raw "a sync is happening" signal it reflects.

import SwiftUI
import StrandDesign

/// What the strap status can honestly say, resolved from the three live signals it has.
/// Pure + static so the truth table is testable with no strap (`StrapBatteryDisplayTests`).
///
/// The three signals are INDEPENDENT and land separately, which is the whole reason this exists:
///  • `connected` — the CoreBluetooth link.
///  • `batteryPct` — standard 0x2A19 (5/MG) or the GET_BATTERY_LEVEL response (4.0).
///  • `charging` — a different source entirely: the strap's BATTERY_LEVEL event (~every 8 min),
///    which keeps arriving live even mid-offload (`FrameRouter`, "flag only — battery % keeps its
///    family-specific source", #77).
///
/// So "charging, but no % yet" is REACHABLE, not hypothetical. The old code nested the bolt inside
/// `if let pct`, so that state rendered as `bolt.slash` — a crossed-out bolt at a wearer whose strap
/// was on the charger, which reads as "battery dead". And it drew the charge on `batteryPct` alone with
/// no `connected` gate: `LiveState.batteryPct` is never cleared (`clearBiometrics` deliberately leaves
/// it), so a dead strap kept showing its last % as if live — a 21 h old reading rendered identically
/// to a fresh one.
///
/// (A3/B2, docs/bugs/2026-07-15-strap-battery-backfill-observability.md)
enum StrapBatteryDisplay: Equatable {
    /// No link — say nothing about charge. A stale % is worse than no %.
    case offline
    /// Linked, but no charge reading has landed yet. `charging` is still knowable on its own.
    case pending(charging: Bool)
    /// A reading from the current link. `isRing` says whose: the ring's own charge under an active
    /// ring, the strap's under an active strap — the label names the device the number belongs to.
    case charge(pct: Double, charging: Bool, isRing: Bool)
    /// The active device is neither the strap nor a ring that has reported its charge this link, so
    /// this control has nothing to say and is not drawn.
    ///
    /// Distinct from [offline], which asserts a strap that IS active is not connected. Collapsing the
    /// two put a crossed-out bolt and "strap not connected" on the header of a wearer whose ring was
    /// streaming, which is a different false claim from the one #2208 is about rather than a fix for
    /// it, and the only one a ring-only wearer would see every day. (@pipiche38 on #2216)
    case notActiveDevice

    /// #2208: `activeIsWhoop` is required, not defaulted. `connected` alone was never enough: it is
    /// true the moment ANY source streams, `batteryPct` is the strap's and is never cleared, so under
    /// an active ring both halves of the old gate passed and this drew the strap's charge. Charging
    /// is strap-only for the same reason, so a non-WHOOP active device reports neither of the strap's.
    ///
    /// A ring reports its OWN charge into `ringPct` (`LiveState.ouraBatteryPct`), cleared with the
    /// link, so under a non-WHOOP active device a non-nil `ringPct` is a reading from the ring that is
    /// live right now and is drawn as such; nil (no ring, or none has reported yet) keeps the control
    /// off the header. `ringCharging` is the ring's charger state (`OuraWearState.charging`), the only
    /// charging evidence a ring gives. Same resolution `LiveConsoleReadout.batteryPercent` applies.
    ///
    /// No default values on purpose. A defaulted flag is one a future call site can forget, and
    /// forgetting it reinstates exactly this bug in a form that still compiles.
    static func resolve(activeIsWhoop: Bool, connected: Bool,
                        batteryPct: Double?, charging: Bool?,
                        ringPct: Int?, ringCharging: Bool) -> StrapBatteryDisplay {
        guard activeIsWhoop else {
            guard let ringPct else { return .notActiveDevice }
            return .charge(pct: Double(ringPct), charging: ringCharging, isRing: true)
        }
        guard connected else { return .offline }
        guard let pct = batteryPct else { return .pending(charging: charging == true) }
        return .charge(pct: pct, charging: charging == true, isRing: false)
    }
}

/// The ONE debounce for the raw "a sync is happening" signal, for any surface that reflects it.
///
/// `live.backfilling` toggles false→true between EVERY offload chunk (`exitBackfilling` at each
/// HISTORY_END → auto-continue re-kick → `beginBackfill`), with a real BLE round-trip gap in between, and
/// a deep backlog is up to ~24 chunks in ONE connection (#594 raised the auto-continue cap 6→24). Bound
/// straight to that signal, an indicator strobes in and out on every chunk boundary. (The MenuBar header
/// pins a constant height for the same reason — see MenuBarContent.)
///
/// Rises INSTANTLY, and falls only after riding out `syncIndicatorSignalDebounceNanoseconds` with no new
/// chunk. Written once on purpose: this existed as two hand-rolled copies with the delay spelled two
/// different ways, and the failure mode of letting them drift — an indicator that flickers only against a
/// strap carrying hours of history — is not reproducible at a desk.
private struct DebouncedSyncSignal: ViewModifier {
    let raw: Bool
    @Binding var debounced: Bool
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear { apply(raw) }
            .onChangeCompat(of: raw) { apply($0) }
            .onDisappear { hideTask?.cancel() }
    }

    private func apply(_ raw: Bool) {
        hideTask?.cancel()
        guard !raw else {
            debounced = true                        // a sync is active — show at once
            return
        }
        guard debounced else { return }
        // Might just be the gap between two chunks — wait it out; a new chunk cancels this.
        hideTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: StrandMotion.syncIndicatorSignalDebounceNanoseconds
            )
            guard !Task.isCancelled else { return }
            debounced = false
        }
    }
}

extension View {
    /// Drive `debounced` from the raw sync signal through the shared debounce above, so a status control
    /// never flashes between the chunks of one logical sync.
    func debouncedSyncSignal(_ raw: Bool, into debounced: Binding<Bool>) -> some View {
        modifier(DebouncedSyncSignal(raw: raw, debounced: debounced))
    }
}
