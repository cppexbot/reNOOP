//  AppearanceLock.swift
//  NOOP · one fixed look, Apple-Health style.
//
//  The only appearance choice left to the user is System / Light / Dark. Everything the removed theme
//  controls used to vary is pinned here at launch, before any view reads it: Titanium chart colours, the
//  system-blue accent, no day-cycle sky or custom photo behind the screens, and solid cards. Writing the
//  stored keys (rather than ignoring them at each read site) keeps every existing reader correct, and
//  re-applies after a backup restore on the next launch.

import Foundation
import StrandDesign

enum AppearanceLock {
    static func apply(_ defaults: UserDefaults = .standard) {
        defaults.set(ChartStyle.titanium.rawValue, forKey: ChartStyle.storageKey)
        defaults.set(AccentColor.system.rawValue, forKey: AccentColor.storageKey)
        defaults.set(false, forKey: SceneBackgroundPrefs.enabledKey)
        defaults.set(false, forKey: SkyBehindCardsPrefs.enabledKey)
        defaults.set(CardAppearancePrefs.defaultPercent, forKey: CardAppearancePrefs.opacityKey)
        defaults.set(false, forKey: BackgroundImagePrefs.enabledKey)
    }
}
