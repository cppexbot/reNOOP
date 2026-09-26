//  SyncChipState.swift
//  NOOP · the strap-sync status the Devices screen's sync card reads.

import Foundation

/// #245: the sync-status state used by the Devices screen's larger sync card, resolved once from
/// `LiveState`. THREE states mean the ABSENCE of active syncing reads as "caught up", not
/// "missing indicator" (the real #245 confusion): actively offloading → `⟳ N`; idle with a known
/// last-sync → `✓ Xm`; a 5/MG whose history sync is experimental (live-connected, no completed offload
/// yet) → `✓ live`. `.hidden` only on a true cold start (the building-scores note owns that case). Twin
/// of Android `SyncStatusChip`.
enum SyncChipState: Equatable {
    /// #689/#815 follow-up: `pagesBehind` is the strap's GET_DATA_RANGE ring backlog, sampled once at
    /// connect (`LiveState.pagesBehindAtConnect`) and never re-polled, so the copy reports it "at
    /// connect" rather than as a live figure. nil when no reply has landed this session, when the frame
    /// did not decode, AND when the backlog is zero: a chip that is actively syncing while claiming
    /// "0 pages behind" contradicts itself, and a zero sample carries nothing a reader can act on.
    /// `resolve` applies that rule so both platforms drop the same case. Twin of Android
    /// `SyncChipState.Syncing`.
    case syncing(chunks: Int, pagesBehind: Int?)
    case synced(agoText: String)
    case experimentalLive
    case hidden

    @MainActor
    static func resolve(live: LiveState) -> SyncChipState {
        if live.backfilling {
            // The zero rule above. Negative cannot come off the wire (the decoder returns a ring delta),
            // but the bound reads the same either way. Android spells this `?.takeIf { it > 0 }`.
            return .syncing(chunks: live.syncChunksThisSession,
                            pagesBehind: live.pagesBehindAtConnect.flatMap { $0 > 0 ? $0 : nil })
        }
        if let ts = live.lastSyncedAt { return .synced(agoText: shortAgo(ts)) }
        if live.historySyncExperimental { return .experimentalLive }
        return .hidden
    }

    /// Compact relative age for the status card ("<1m" / "Nm" / "Nh" / "Nd") — deliberately terse.
    ///
    /// EVERY branch must read correctly with a trailing "ago", because that is the only way this value is
    /// ever consumed (`DevicesView` wraps it in "Synced %@ ago" and "Strap history synced %@ ago"). The
    /// sub-minute branch used to return the word "now", which produced the user-visible "Synced now ago"
    /// for the first minute after any sync (#1472). "<1m" composes; it also needs no catalog entry, being
    /// digits and symbols in every language.
    private static func shortAgo(_ ts: TimeInterval) -> String {
        let secs = max(0, Int(Date().timeIntervalSince1970 - ts))
        if secs < 60 { return "<1m" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        return "\(hrs / 24)d"
    }
}
