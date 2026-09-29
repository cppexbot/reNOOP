//  SummarySleepCard.swift
//  NOOP · Summary home — the Sleep card, as the Health Summary shows one: time asleep beside a thumbnail
//  of the night's stages, tapping through to the Sleep page on that same night.
//
//  The Summary loads the night with `SleepNightLoader`, the path the Sleep page itself uses, so the card
//  and the page it opens always show the same night with the same figures.

import SwiftUI
import StrandDesign
import WhoopStore

struct SummarySleepCard: View {
    /// The Summary's picked day ("yyyy-MM-dd"); the card shows the night that ended on it.
    let dayKey: String
    /// That night, loaded by the Summary with `SleepNightLoader.night(repo:wakeDayKey:)`.
    let night: Night

    var body: some View {
        NavigationLink(value: TabRoute.sleepNight(dayKey)) { card(night) }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
    }

    private func card(_ night: Night) -> some View {
        let wake = Date(timeIntervalSince1970: TimeInterval(night.session.endTs))
        return SummaryCard {
            VStack(alignment: .leading, spacing: 10) {
                SummaryCardTitleRow(icon: "bed.double.fill", title: String(localized: "Sleep"),
                                    tint: StrandPalette.healthSleepDeep,
                                    // Health stamps a card with when its value was recorded: the wake time.
                                    trailing: wake.formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale)))
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Time Asleep")
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                        SleepCardValueText(value: .duration(night.stages.asleep), size: 24)
                    }
                    Spacer(minLength: 8)
                    if night.intervals.count >= 2 {
                        SleepStagesChart(intervals: night.intervals, onset: night.onsetDate, compact: true)
                            .frame(width: 132, height: 44)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}
