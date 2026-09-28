import XCTest
@testable import Strand

/// #245: `SyncChipState.resolve` is the one place the sync status is decided, so a mistake here changes
/// what every consumer shows. Covers priority order (backfilling wins over a stale last-sync, which wins
/// over the 5/MG experimental fallback) and the cold-start `.hidden` case.
///
/// The time is carried as a date and worded by `SyncChipState.ago` ("Just Now" under a minute, #1472).
@MainActor
final class SyncChipStateTests: XCTestCase {

    func testBackfilling_isSyncingWithChunkCount() {
        let live = LiveState()
        live.backfilling = true
        live.syncChunksThisSession = 7
        XCTAssertEqual(SyncChipState.resolve(live: live), .syncing(chunks: 7, pagesBehind: nil))
    }

    func testLastSyncedAt_isSyncedAtThatTime() {
        let live = LiveState()
        let ts = Date().timeIntervalSince1970 - 65
        live.lastSyncedAt = ts
        XCTAssertEqual(SyncChipState.resolve(live: live), .synced(at: Date(timeIntervalSince1970: ts)))
    }

    /// #1472 regression guard: the first minute after a sync reads "Just Now", never "now ago".
    func testUnderAMinuteReadsJustNow() {
        let now = Date()
        XCTAssertEqual(SyncChipState.ago(now.addingTimeInterval(-5), now: now), String(localized: "Just Now"))
    }

    func testHistorySyncExperimental_withNoLastSync_isExperimentalLive() {
        let live = LiveState()
        live.historySyncExperimental = true
        XCTAssertEqual(SyncChipState.resolve(live: live), .experimentalLive)
    }

    func testColdStart_noBackfillNoSyncNoExperimental_isHidden() {
        let live = LiveState()
        XCTAssertEqual(SyncChipState.resolve(live: live), .hidden)
    }

    func testBackfilling_takesPriorityOverLastSyncedAt() {
        let live = LiveState()
        live.backfilling = true
        live.syncChunksThisSession = 2
        live.lastSyncedAt = Date().timeIntervalSince1970 - 5
        XCTAssertEqual(SyncChipState.resolve(live: live), .syncing(chunks: 2, pagesBehind: nil))
    }

    func testLastSyncedAt_takesPriorityOverHistorySyncExperimental() {
        let live = LiveState()
        live.lastSyncedAt = Date().timeIntervalSince1970 - 5
        live.historySyncExperimental = true
        if case .synced = SyncChipState.resolve(live: live) {
            // expected
        } else {
            XCTFail("A known last-sync should win over the experimental fallback")
        }
    }

    // #689/#815: the connect-time backlog sample. Twin of the Android cases in `SyncChipStateTest`.

    @MainActor
    func testBackfillingWithBacklogCarriesThePagesFigure() {
        let live = LiveState()
        live.backfilling = true
        live.syncChunksThisSession = 3
        live.pagesBehindAtConnect = 120
        XCTAssertEqual(SyncChipState.resolve(live: live), .syncing(chunks: 3, pagesBehind: 120))
    }

    /// A zero backlog is dropped rather than rendered: "0 pages behind at connect" beside a running
    /// sync contradicts itself, and a zero sample gives a reader nothing to act on. The rule lives in
    /// `resolve` on both platforms so neither view layer decides it alone.
    @MainActor
    func testBackfillingWithZeroBacklogDropsTheDetail() {
        let live = LiveState()
        live.backfilling = true
        live.syncChunksThisSession = 3
        live.pagesBehindAtConnect = 0
        XCTAssertEqual(SyncChipState.resolve(live: live), .syncing(chunks: 3, pagesBehind: nil))
    }

    /// No reply yet this session, or a frame that did not decode.
    @MainActor
    func testBackfillingWithoutASampleIsUnchanged() {
        let live = LiveState()
        live.backfilling = true
        live.syncChunksThisSession = 3
        XCTAssertEqual(SyncChipState.resolve(live: live), .syncing(chunks: 3, pagesBehind: nil))
    }

    /// The backlog only qualifies an in-progress sync; a stale figure must not survive into `.synced`.
    @MainActor
    func testNotBackfillingIgnoresTheBacklog() {
        let live = LiveState()
        live.backfilling = false
        let ts = Date().timeIntervalSince1970 - 65
        live.lastSyncedAt = ts
        live.pagesBehindAtConnect = 120
        XCTAssertEqual(SyncChipState.resolve(live: live), .synced(at: Date(timeIntervalSince1970: ts)))
    }
}
