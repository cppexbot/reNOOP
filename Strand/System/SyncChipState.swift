//  SyncChipState.swift
//  NOOP · the strap-sync status, resolved once for every place that shows it, and the one quiet line that
//  shows it — as Mail and Photos on iOS 26 say "Updated Just Now" under their lists.

import SwiftUI
import StrandDesign

/// #245: the sync status, resolved once from `LiveState`. The ABSENCE of active syncing reads as "caught up",
/// not "missing indicator" (the real #245 confusion): actively offloading → syncing; idle with a known last
/// sync → synced at that time; a 5/MG whose history sync is experimental (live-connected, no completed offload
/// yet) → experimental. `.hidden` only on a true cold start. A sync error is not a state here: its text says
/// what happened (a denied Bluetooth grant, a sync that finished with undecodable records…), and Live's
/// problem line shows it in those words rather than a guess at one.
enum SyncChipState: Equatable {
    /// #689/#815 follow-up: `pagesBehind` is the strap's GET_DATA_RANGE ring backlog, sampled once at
    /// connect (`LiveState.pagesBehindAtConnect`) and never re-polled. nil when no reply has landed this
    /// session, when the frame did not decode, AND when the backlog is zero: a sync claiming "0 pages behind"
    /// contradicts itself, and a zero sample carries nothing a reader can act on.
    case syncing(chunks: Int, pagesBehind: Int?)
    case synced(at: Date)
    case experimentalLive
    case hidden

    @MainActor
    static func resolve(live: LiveState) -> SyncChipState {
        if live.backfilling {
            return .syncing(chunks: live.syncChunksThisSession,
                            pagesBehind: live.pagesBehindAtConnect.flatMap { $0 > 0 ? $0 : nil })
        }
        if let ts = live.lastSyncedAt { return .synced(at: Date(timeIntervalSince1970: ts)) }
        if live.historySyncExperimental { return .experimentalLive }
        return .hidden
    }

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }

    /// "Just Now" under a minute, otherwise the relative time ("5 minutes ago"), in the app's language.
    static func ago(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return String(localized: "Just Now") }
        return date.formatted(Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
            .locale(AppLanguage.activeLocale))
    }
}

/// The sync status as quiet text. `.footer` is the centred line under a list, as Mail and Photos put theirs
/// ("Updated Just Now", "Syncing…" with a small spinner); `.value` is the trailing value of a "Sync" row.
/// A leaf: it alone observes `LiveState`, rides the shared chunk debounce, and ticks once a minute.
struct StrapSyncStatusText: View {
    enum Style { case footer, value }
    var style: Style = .footer

    @EnvironmentObject private var live: LiveState
    @State private var syncing = false

    var body: some View {
        let state = SyncChipState.resolve(live: live)
        TimelineView(.everyMinute) { context in
            content(state, now: context.date)
        }
        .font(style == .footer ? StrandFont.footnote : StrandFont.pro(17))
        .foregroundStyle(StrandPalette.textSecondary)
        .lineLimit(1)
        .debouncedSyncSignal(live.backfilling, into: $syncing)
    }

    @ViewBuilder
    private func content(_ state: SyncChipState, now: Date) -> some View {
        if syncing || state.isSyncing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…")
            }
        } else {
            switch state {
            case .syncing:
                EmptyView()
            case .synced(let at):
                Text(verbatim: style == .footer
                     ? String(localized: "Updated \(SyncChipState.ago(at, now: now))")
                     : SyncChipState.ago(at, now: now))
            case .experimentalLive:
                if style == .value { Text("Experimental") }
            case .hidden:
                EmptyView()
            }
        }
    }
}
