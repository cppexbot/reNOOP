//  SettingsGeneralPages.swift
//  NOOP · Settings → General, Units, Display.
//
//  Display-only preferences: nothing stored changes, NOOP keeps everything in SI. Keys are the ones the
//  old Settings screen wrote, unchanged.

import SwiftUI
#if os(iOS)
import UIKit
#endif
import StrandDesign
import StrandAnalytics

// MARK: - General

struct GeneralSettingsPage: View {
    @EnvironmentObject private var model: AppModel

    /// App-owned copy language. Apple binds a bundle localization at process launch, so this writes the
    /// standard AppleLanguages override and takes effect after the user reopens NOOP.
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.system.rawValue
    /// #1821: Clock format. Defaults to `.system`, so upgrading changes nobody's displayed times.
    @AppStorage(ClockFormatPreference.defaultsKey) private var clockFormatRaw = ClockFormatPreference.system.rawValue
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $appLanguageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language == .system ? String(localized: "System default") : language.autonym)
                            .tag(language.rawValue)
                    }
                }
                .settingsPicker()
                .onChangeCompat(of: appLanguageRaw) { AppLanguage.apply($0) }
            } footer: {
                Text("Language changes take effect after you reopen NOOP.")
            }

            Section {
                // #1829: the resolved clock is memoised, so the write has to drop the memo.
                Picker("Clock", selection: $clockFormatRaw) {
                    Text("System default").tag(ClockFormatPreference.system.rawValue)
                    Text("12-hour").tag(ClockFormatPreference.twelveHour.rawValue)
                    Text("24-hour").tag(ClockFormatPreference.twentyFourHour.rawValue)
                }
                .settingsPicker()
                .onChangeCompat(of: clockFormatRaw) { _ in AppClock.invalidate() }

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

            Section {
                NavigationLink("Units", value: SettingsPage.units)
            }
        }
        .settingsPage("General")
    }
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
                    Text("Temperature").tag("")
                    Text("vs baseline").tag(SkinTempDisplay.Kind.deviation.rawValue)
                }
                .settingsPicker()
            }
        }
        .settingsPage("Units")
    }
}

// MARK: - Display

struct DisplaySettingsPage: View {
    // Light/Dark/System theme. Read by both app roots' .preferredColorScheme; default follows the OS.
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(UnitPrefs.trendChartStyleKey) private var trendChartStyleRaw = TrendChartStyle.line.rawValue
    /// Pose every looping animation still and stop the tilt sensor, without system Low Power Mode or
    /// Reduce Motion. Read by `LiquidMotion` and `NoopMotionState`.
    @AppStorage(QuietMotionPrefs.enabledKey) private var quietMotion = false
    /// #1841: iOS 26 minimises the tab bar to a pill on scroll down (`noopTabBarAutoHide`).
    @AppStorage("noop.bottomBarAutoHide") private var bottomBarAutoHide = false
    // Alternate app icon (iOS only) — false = Titanium (AppIcon), true = Blue Titanium (AppIcon-Navy).
    @AppStorage("appIcon.alt") private var useNavyIcon = false

    @State private var iconError: String?
    @Environment(\.colorScheme) private var colorScheme

    private var mode: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    appearanceOption(.light)
                    appearanceOption(.dark)
                }
                .padding(.vertical, 6)
                Toggle("Automatic", isOn: Binding(
                    get: { mode == .system },
                    set: { on in
                        appearanceRaw = on ? AppearanceMode.system.rawValue
                                           : (colorScheme == .dark ? AppearanceMode.dark : .light).rawValue
                    }
                ))
            } header: {
                Text("Appearance")
            }

            Section {
                Picker("Trend charts", selection: $trendChartStyleRaw) {
                    ForEach(TrendChartStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .settingsPicker()
                #if os(iOS)
                Picker("App icon", selection: $useNavyIcon) {
                    Text("Default").tag(false)
                    Text("Navy").tag(true)
                }
                .settingsPicker()
                .onChangeCompat(of: useNavyIcon) { applyAppIcon($0) }
                #endif
            }

            Section {
                Toggle("Reduce motion in NOOP", isOn: $quietMotion)
                #if os(iOS)
                if #available(iOS 26.0, *) {
                    Toggle("Hide bar when scrolling", isOn: $bottomBarAutoHide)
                }
                #endif
            }
        }
        .settingsPage("Display")
        .alert("Couldn't change the app icon", isPresented: Binding(
            get: { iconError != nil }, set: { if !$0 { iconError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(iconError ?? "")
        }
    }

    /// One of Display & Brightness's two appearance thumbnails: a small screen, its name, a check circle.
    private func appearanceOption(_ option: AppearanceMode) -> some View {
        // With Automatic on, the check follows what the system is showing now, as Settings does.
        let selected = mode == option || (mode == .system && (option == .dark) == (colorScheme == .dark))
        return Button {
            appearanceRaw = option.rawValue
        } label: {
            VStack(spacing: 8) {
                AppearanceThumbnail(dark: option == .dark)
                Text(option.label)
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textPrimary)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? StrandPalette.settingsBlue : StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

/// A phone screen in miniature, light or dark, as Display & Brightness shows the two appearances.
private struct AppearanceThumbnail: View {
    let dark: Bool

    var body: some View {
        let page = dark ? StrandPalette.settingsAppearanceDarkPage : StrandPalette.settingsAppearanceLightPage
        let card = dark ? StrandPalette.settingsAppearanceDarkCard : StrandPalette.settingsAppearanceLightCard
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(page)
            .frame(width: 64, height: 128)
            .overlay(alignment: .top) {
                VStack(spacing: 6) {
                    Text(verbatim: "9:41")
                        .font(StrandFont.pro(13, weight: .semibold))
                        .foregroundStyle(dark ? StrandPalette.settingsAppearanceDarkText
                                              : StrandPalette.settingsAppearanceLightText)
                        .padding(.top, 12)
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(card).frame(height: 22)
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(card).frame(height: 22)
                }
                .padding(.horizontal, 7)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(StrandPalette.hairline, lineWidth: 1)
            )
    }
}
