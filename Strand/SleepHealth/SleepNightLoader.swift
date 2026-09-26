//  SleepNightLoader.swift
//  NOOP · Sleep — the nights on record, grouped and decoded the way the Sleep page reads them, so any
//  other surface that names a night (the Summary's Sleep card) shows the same one with the same figures.

import Foundation
import WhoopStore

enum SleepNightLoader {
    /// Every night's blocks, newest first (`SleepModel.navDays`), from the full un-deduplicated session
    /// list the Sleep page loads, falling back to the dashboard's one-per-night list until that loads.
    @MainActor
    static func navDays(repo: Repository) async -> (navDays: [[CachedSleepSession]], habitualMidsleepSec: Int?) {
        let all = await repo.allSleepSessions()
        let habitual = await repo.habitualMidsleepSec()
        return (SleepModel.navDays(navSessions: all.isEmpty ? repo.sleeps : all), habitual)
    }

    /// The local day a night's blocks ended on ("yyyy-MM-dd"), the day a night is filed under.
    static func wakeDayKey(_ blocks: [CachedSleepSession]) -> String? {
        blocks.map(\.endTs).max().map { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0))) }
    }

    /// Index into `navDays` of the night that ended on `dayKey`.
    static func index(ofWakeDay dayKey: String, in navDays: [[CachedSleepSession]]) -> Int? {
        navDays.firstIndex { wakeDayKey($0) == dayKey }
    }

    /// The night that ended on `dayKey`, decoded as the Sleep page decodes it (`SleepModel.decodedNight`).
    @MainActor
    static func night(repo: Repository, wakeDayKey dayKey: String) async -> Night? {
        let (navDays, habitual) = await navDays(repo: repo)
        guard let i = index(ofWakeDay: dayKey, in: navDays) else { return nil }
        return SleepModel.decodedNight(at: i, navDays: navDays, habitualMidsleepSec: habitual, motionByStart: [:])
    }
}
