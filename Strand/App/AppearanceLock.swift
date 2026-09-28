//  AppearanceLock.swift
//  NOOP · one fixed look, Apple-Health style.
//
//  NOOP follows the system's Light / Dark setting, as Apple's own apps do; there is no in-app appearance
//  choice. Everything the removed theme controls used to vary is pinned here at launch, before any view
//  reads it: Titanium chart colours, the system-blue accent, no day-cycle sky or custom photo behind the
//  screens, and solid cards. Writing the stored keys (rather than ignoring them at each read site) keeps
//  every existing reader correct, and re-applies after a backup restore on the next launch.

import SwiftUI
import StrandDesign

enum AppearanceLock {
    static func apply(_ defaults: UserDefaults = .standard) {
        defaults.set(ChartStyle.titanium.rawValue, forKey: ChartStyle.storageKey)
        defaults.set(AccentColor.system.rawValue, forKey: AccentColor.storageKey)
        defaults.set(false, forKey: SceneBackgroundPrefs.enabledKey)
        defaults.set(false, forKey: SkyBehindCardsPrefs.enabledKey)
        defaults.set(CardAppearancePrefs.defaultPercent, forKey: CardAppearancePrefs.opacityKey)
        defaults.set(false, forKey: BackgroundImagePrefs.enabledKey)
        // The retired Light / Dark override: a choice an earlier build stored would otherwise pin the app
        // against the system setting with nothing left on screen to undo it. Only the persistent value
        // goes; a `-theme.appearance` launch argument lives in the argument domain and survives this.
        defaults.removeObject(forKey: AppearanceMode.storageKey)
    }

    /// The scheme every root forces: none in release, where the system decides. DEBUG builds honour
    /// `-theme.appearance light|dark` in the launch arguments, so screenshot tooling can shoot either.
    static var colorScheme: ColorScheme? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: AppearanceMode.storageKey)
            .flatMap(AppearanceMode.init(rawValue:))?.colorScheme
        #else
        return nil
        #endif
    }
}
