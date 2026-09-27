//  SleepFreshnessNote.swift
//  NOOP · Sleep — the "is last night's sleep in yet?" notice.

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
            let chunks = live.syncChunksThisSession
            NoticeCard(title: Text("Syncing strap history"),
                       message: chunks > 0 ? Text("\(chunks) chunks so far") : nil,
                       tone: .progress)
        case .calculating:
            NoticeCard(title: Text("Calculating last night's sleep"), tone: .progress)
        case .syncFailed:
            NoticeCard(title: Text("Sleep hasn't synced"),
                       message: Text("Keep the strap nearby and sync again."),
                       systemImage: "exclamationmark.arrow.triangle.2.circlepath", tone: .error)
        case .awaitingSync:
            NoticeCard(title: Text("Waiting for last night's sleep"),
                       message: Text("Connect the strap to sync."),
                       systemImage: "arrow.triangle.2.circlepath", tone: .info)
        case .notDetected:
            NoticeCard(title: Text("No sleep detected last night"),
                       message: Text("The night below is your latest."),
                       systemImage: "moon.zzz.fill", tone: .warning)
        case nil:
            EmptyView()
        }
    }
}
