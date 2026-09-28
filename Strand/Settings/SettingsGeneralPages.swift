//  SettingsGeneralPages.swift
//  NOOP · Settings → General, Units.
//
//  Display-only preferences: nothing stored changes, NOOP keeps everything in SI. Keys are the ones the
//  old Settings screen wrote, unchanged. Language, the clock, Reduce Motion and the tab bar's minimise
//  behaviour are the system's (ST-4): NOOP follows them and keeps no copy.

import SwiftUI
#if os(iOS)
import UIKit
#endif
import StrandDesign
import StrandAnalytics

// MARK: - General

struct GeneralSettingsPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    // Alternate app icon (iOS only) — false = Titanium (AppIcon), true = Blue Titanium (AppIcon-Navy).
    @AppStorage("appIcon.alt") private var useNavyIcon = false

    @State private var iconError: String?

    var body: some View {
        Form {
            Section {
                // The system owns the app language (ST-4): the row shows it and opens where it is changed.
                Button {
                    if let url = Self.languageSettingsURL { openURL(url) }
                } label: {
                    LabeledContent("Language", value: AppLanguage.displayName)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Picker("Day starts", selection: Binding(
                    get: { DayCycleMode.persisted(dayCycleModeRaw) },
                    set: { mode in
                        dayCycleModeRaw = mode.rawValue
                        Task { await model.intelligence.analyzeRecent(); await model.repo.refresh() }
                    }
                )) {
                    Text("Main sleep").tag(DayCycleMode.sleepOnset)
                    Text("00:00").tag(DayCycleMode.midnight)
                }
                .settingsPicker()
            }

            #if os(iOS)
            Section {
                Picker("App icon", selection: $useNavyIcon) {
                    Text("Default").tag(false)
                    Text("Navy").tag(true)
                }
                .settingsPicker()
                .onChangeCompat(of: useNavyIcon) { applyAppIcon($0) }
            }
            #endif

            Section {
                NavigationLink("Units", value: SettingsPage.units)
            }
        }
        .settingsPage("General")
        .alert("Couldn't change the app icon", isPresented: Binding(
            get: { iconError != nil }, set: { if !$0 { iconError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(iconError ?? "")
        }
    }

    /// NOOP's page in the Settings app, where iOS keeps its per-app Language; on the Mac, Language & Region.
    private static var languageSettingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")
        #endif
    }

    #if os(iOS)
    /// Apply the alternate-icon choice; on failure revert the picker so it never disagrees with the
    /// Home Screen.
    private func applyAppIcon(_ useNavy: Bool) {
        Task { @MainActor in
            let target = useNavy ? "AppIcon-Navy" : nil
            guard UIApplication.shared.supportsAlternateIcons,
                  UIApplication.shared.alternateIconName != target else { return }
            do {
                try await UIApplication.shared.setAlternateIconName(target)
            } catch {
                useNavyIcon = !useNavy
                iconError = error.localizedDescription
            }
        }
    }
    #endif
}

// MARK: - Units

struct UnitsSettingsPage: View {
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""   // #1846

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    /// Distance follows body measurements until the user picks it explicitly.
    private var distanceSystemBinding: Binding<String> {
        Binding(get: { UnitPrefs.resolveDistance(system: unitSystem, override: distanceSystemRaw).rawValue },
                set: { distanceSystemRaw = $0 })
    }

    var body: some View {
        Form {
            Section {
                Picker("Body measurements", selection: $unitSystemRaw) {
                    Text("Metric").tag(UnitSystem.metric.rawValue)
                    Text("Imperial").tag(UnitSystem.imperial.rawValue)
                }
                .settingsPicker()
                Picker("Exercise distance & pace", selection: distanceSystemBinding) {
                    Text("Kilometres").tag(UnitSystem.metric.rawValue)
                    Text("Miles").tag(UnitSystem.imperial.rawValue)
                }
                .settingsPicker()
            }
            Section {
                // "Follow body" follows body measurements; °C / °F pin it explicitly.
                Picker("Temperature", selection: $temperatureRaw) {
                    Text("Follow body").tag("")
                    Text("°C").tag(TemperatureUnit.celsius.rawValue)
                    Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                }
                .settingsPicker()
                // #1846: a preference only — a night that measured just one of the two still shows it.
                Picker("Skin temperature", selection: $skinTempDisplayRaw) {
                    Text("Absolute").tag("")
                    Text("Deviation").tag(SkinTempDisplay.Kind.deviation.rawValue)
                }
                .settingsPicker()
            }
        }
        .settingsPage("Units")
    }
}

// MARK: - Retired settings

/// Preferences NOOP used to keep its own copy of, now taken from the system (ST-4): the app language
/// (Settings → NOOP → Language), the 12/24-hour clock (`Locale`), Reduce Motion
/// (`accessibilityReduceMotion`) and the iOS 26 tab bar's minimise-on-scroll. Their toggles are gone, so a
/// value stored by an older build would otherwise keep overriding the system with nothing left to turn it
/// off. `purge()` removes them once at launch; every reader already treats a missing key as "follow the
/// system".
enum RetiredSettings {
    static let keys = [
        AppLanguage.retiredStorageKey,
        ClockFormatPreference.defaultsKey,
        QuietMotionPrefs.enabledKey,
        "noop.bottomBarAutoHide",
    ]

    static func purge(_ defaults: UserDefaults = .standard) {
        for key in keys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
    }
}
