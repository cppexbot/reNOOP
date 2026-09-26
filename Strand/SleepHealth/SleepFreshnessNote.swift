//  SleepFreshnessNote.swift
//  NOOP · Sleep — the "is last night's sleep in yet?" status banner.

import SwiftUI
import StrandDesign

/// The states the Sleep status banner can be in, resolved by `resolveSleepFreshness`.
enum SleepFreshnessStatus: Equatable {
    case syncing, calculating, syncFailed, awaitingSync, notDetected
}

/// Pure priority ladder behind the Sleep status banner. "Missing" is deliberately held until morning so
/// opening Sleep during the night does not claim a still-in-progress night was missed.
func resolveSleepFreshness(hasCurrentNight: Bool, morningReady: Bool, syncing: Bool,
                           calculating: Bool, syncedSinceDayStart: Bool,
                           syncFailed: Bool) -> SleepFreshnessStatus? {
    if syncing { return .syncing }
    // #2108: a night already in hand outranks .calculating. It used to sit below, so `hasCurrentNight`
    // could only silence the missing-night states and a finished night was structurally unable to
    // silence this one: the banner said "detecting and staging the night now" directly above that same
    // night scored, timed and staged on screen. A note that contradicts the content beside it is worse
    // than no note, and one that is always on is read by nobody the day it matters. .syncing stays
    // above, because data still arriving can genuinely change what is shown.
    if hasCurrentNight { return nil }
    if calculating { return .calculating }
    if !morningReady { return nil }
    if syncFailed { return .syncFailed }
    return syncedSinceDayStart ? .notDetected : .awaitingSync
}

/// Explicit state for the expected current night. Older sleep can remain available underneath, but it is
/// never left to impersonate today's result while a sync, calculation, or failed detection is unresolved.
struct SleepFreshnessNote: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var intelligence: IntelligenceEngine
    let latestWakeTs: Int?

    var body: some View {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let current = latestWakeTs.map {
            calendar.isDate(Date(timeIntervalSince1970: TimeInterval($0)), inSameDayAs: now)
        } ?? false
        // AppModel intentionally waits two quiet seconds after HISTORY_COMPLETE before starting the
        // scoring pass. Treat that debounce as calculation too; otherwise the banner can flash the final
        // "wasn't detected" verdict between sync completion and `intelligence.computing` becoming true.
        let calculationQueued = live.lastSyncedAt.map {
            (0..<5).contains(now.timeIntervalSince1970 - $0)
        } ?? false
        let status = resolveSleepFreshness(
            hasCurrentNight: current,
            morningReady: calendar.component(.hour, from: now) >= 6,
            syncing: live.backfilling,
            calculating: intelligence.computing || calculationQueued,
            syncedSinceDayStart: (live.lastSyncedAt ?? 0) >= start.timeIntervalSince1970,
            syncFailed: live.lastSyncError != nil
        )
        switch status {
        case .syncing:
            SyncingHistoryNote(chunks: live.syncChunksThisSession)
        case .calculating:
            DataPendingNote(title: "Calculating last night's sleep…",
                            message: "Your strap history is in. NOOP is detecting and staging the night now.",
                            symbol: "waveform.path.ecg")
        case .syncFailed:
            DataPendingNote(title: "Last night's sleep hasn't synced",
                            message: "The history sync stopped before it finished. Keep the strap nearby and try Sync again.",
                            symbol: "exclamationmark.arrow.triangle.2.circlepath")
        case .awaitingSync:
            DataPendingNote(title: "Waiting for last night's sleep",
                            message: "Connect the strap and sync its history. NOOP will calculate the night when the overnight data arrives.",
                            symbol: "arrow.triangle.2.circlepath")
        case .notDetected:
            DataPendingNote(title: "Last night's sleep wasn't detected",
                            message: "Sync finished, but NOOP couldn't confidently identify a sleep window. Keep the strap connected and try Sync again; the older night below is still your latest detected sleep.",
                            symbol: "moon.zzz")
        case nil:
            EmptyView()
        }
    }
}
