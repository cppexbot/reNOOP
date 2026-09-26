//  SettingsView.swift
//  NOOP · Settings, as the iOS 26 Settings app draws it.
//
//  A native grouped list: a profile row on top (Settings' Apple Account row), then rows with coloured
//  square icons that push their own pages. Every page pushes a `SettingsPage` VALUE, so the host stack's
//  path can pop it (#198); each host registers the destinations ONCE with `.settingsDestinations()` (a
//  second registration in the same stack double-pushes, #38).

import SwiftUI
import StrandDesign

struct SettingsView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var model: AppModel

    /// The Coach master switch, under the same `noop.` key Android writes. Read by `RootTabView`, Today
    /// and `CoachBriefScheduler`.
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    /// Hydration tracker (opt-in). Off hides the hydration card + detail.
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false

    var body: some View {
        Form {
            Section {
                NavigationLink(value: SettingsPage.profile) { profileRow }
            }

            Section {
                SettingsLink(.devices, "Devices", icon: "applewatch.radiowaves.left.and.right", color: StrandPalette.settingsBlue)
                SettingsLink(.dataSources, "Data Sources", icon: "tray.and.arrow.down.fill", color: StrandPalette.settingsBlue)
                SettingsLink(.appleHealth, "Apple Health", icon: "heart.fill", color: StrandPalette.settingsPink, style: .appTile)
                #if os(iOS)
                SettingsLink(.shortcutsExport, "Shortcuts Export", icon: "square.and.arrow.up", color: StrandPalette.settingsBlue)
                #endif
            }

            Section {
                SettingsLink(.general, "General", icon: "gearshape", color: StrandPalette.settingsGray)
                SettingsLink(.display, "Display", icon: "sun.max.fill", color: StrandPalette.settingsBlue)
                #if os(macOS)
                SettingsLink(.notifications, "Notifications", icon: "bell.badge.fill", color: StrandPalette.settingsRed)
                #endif
                SettingsLink(.powerSaving, "Power saving", icon: "battery.100percent", color: StrandPalette.settingsGreen)
                #if os(iOS)
                SettingsLink(.siri, "Siri & Shortcuts", icon: "square.2.layers.3d.fill", color: StrandPalette.settingsIndigo)
                #endif
                SettingsLink(.automations, "Automations", icon: "clock.badge.checkmark.fill", color: StrandPalette.settingsOrange)
            }

            Section {
                SettingsToggle("AI Coach", icon: "sparkles", color: StrandPalette.settingsPurple, isOn: $coachEnabled)
                SettingsToggle("Hydration tracking", icon: "drop.fill", color: StrandPalette.settingsCyan, isOn: $hydrationEnabled)
                SettingsLink(.workouts, "Workouts", icon: "figure.run", color: StrandPalette.settingsGreen)
                #if os(iOS)
                SettingsLink(.sync, "Sync", icon: "arrow.triangle.2.circlepath", color: StrandPalette.settingsTeal)
                #endif
                SettingsLink(.scores, "Scores", icon: "gauge.with.dots.needle.67percent", color: StrandPalette.settingsRed)
            }

            Section {
                SettingsLink(.backup, "Backup", icon: "clock.arrow.circlepath", color: StrandPalette.settingsGreen)
            }

            Section {
                SettingsLink(.about, "About NOOP", icon: "info.circle", color: StrandPalette.settingsGray)
                SettingsLink(.developer, "Developer", icon: "hammer.fill", color: StrandPalette.settingsGray)
            }
        }
        .settingsForm()
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .onChangeCompat(of: coachEnabled) { on in
            // Switching the AI off has to TAKE DOWN what the brief already published, not just stop the
            // next one: the widget renders the last brief it was given.
            CoachBriefScheduler.applyMasterSwitch(on)
        }
    }

    /// Settings' Apple Account row: the photo (or monogram), the name, and what the row opens.
    private var profileRow: some View {
        HStack(spacing: 14) {
            SummaryAvatar(imageData: profile.avatarImageData, initials: profile.initials, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName.isEmpty ? String(localized: "Profile") : profile.displayName)
                    .font(StrandFont.pro(20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text("Health Details")
                    .font(StrandFont.pro(13))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pages

/// Every page Settings (and the profile sheet) can push, as a `Hashable` value a `NavigationPath` carries.
enum SettingsPage: Hashable {
    case settings
    case profile, heartRateZones
    case general, units, display, workouts, sync, scores, backup, about, iphone, developer
    case devices, dataSources, appleHealth, shortcutsExport, notifications, powerSaving, siri, automations
    case storage, appleWatch, limitations, testCentre

    @ViewBuilder var destination: some View {
        switch self {
        case .settings:        SettingsView()
        case .profile:         ProfileDetailsView()
        case .heartRateZones:  HeartRateZonesPage()
        case .general:         GeneralSettingsPage()
        case .units:           UnitsSettingsPage()
        case .display:         DisplaySettingsPage()
        case .workouts:        WorkoutsSettingsPage()
        case .sync:            SyncSettingsPage()
        case .scores:          ScoresSettingsPage()
        case .backup:          BackupSyncView()
        case .about:           AboutSettingsPage()
        case .iphone:          IPhoneNotesPage()
        case .developer:       DeveloperSettingsPage()
        // Screens that keep their own look: pushed with the plain inline bar Browse gave them.
        case .devices:         DevicesView().settingsLegacyChrome()
        case .dataSources:     DataSourcesView().settingsLegacyChrome()
        case .appleHealth:     AppleHealthView().settingsLegacyChrome()
        case .powerSaving:     PowerSavingView().settingsLegacyChrome()
        case .automations:     AutomationsView().settingsLegacyChrome()
        case .storage:         StorageView().settingsLegacyChrome()
        case .appleWatch:      AppleWatchAboutHost().settingsLegacyChrome()
        case .limitations:     NoopLimitationsView().settingsLegacyChrome()
        case .testCentre:      TestCentreView().settingsLegacyChrome()
        #if os(iOS)
        case .shortcutsExport: ShortcutExportSettingsView().settingsLegacyChrome()
        case .siri:            SiriShortcutsSettingsView().settingsLegacyChrome()
        case .notifications:   EmptyView()
        #else
        case .notifications:   NotificationSettingsView().settingsLegacyChrome()
        case .shortcutsExport, .siri: EmptyView()
        #endif
        }
    }
}

extension View {
    /// Registers the Settings pages on the enclosing stack. Call once per `NavigationStack`.
    func settingsDestinations() -> some View {
        navigationDestination(for: SettingsPage.self) { $0.destination }
    }

    /// A Settings page: the native grouped list on the Health canvas.
    func settingsForm() -> some View {
        self
            .formStyle(.grouped)

            .scrollContentBackground(.hidden)
            .background(StrandPalette.summaryCanvas.ignoresSafeArea())
    }

    /// A choice row as Settings draws it: the value on the right, a pushed checkmark list (iOS).
    func settingsPicker() -> some View {
        #if os(iOS)
        self.pickerStyle(.navigationLink)
        #else
        self
        #endif
    }

    /// A pushed Settings sub-page: grouped list, inline title as the Settings app shows it.
    func settingsPage(_ title: LocalizedStringKey) -> some View {
        self
            .settingsForm()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    /// Chrome for the screens that still draw their own title and cards.
    func settingsLegacyChrome() -> some View {
        self
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
    }
}

/// Apple Watch data needs its setup sheet, which a value route can't carry as a closure.
private struct AppleWatchAboutHost: View {
    @State private var showSetup = false
    var body: some View {
        AppleWatchAboutView(onStartSetup: { showSetup = true })
            .sheet(isPresented: $showSetup) {
                AppleWatchSetupView(onClose: { showSetup = false })
            }
    }
}

// MARK: - Rows

/// The Settings row icon: a white glyph on a coloured continuous-corner square with Settings' soft
/// top-to-bottom gradient. `.appTile` is an app's own icon (white tile, coloured glyph), as Settings lists
/// Health.
struct SettingsIcon: View {
    enum Style { case system, appTile }

    let systemName: String
    let color: Color
    var style: Style = .system

    var body: some View {
        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
            .fill(style == .appTile ? AnyShapeStyle(StrandPalette.settingsAppearanceLightCard)
                                    : AnyShapeStyle(color.gradient))
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(style == .appTile ? color : StrandPalette.onDarkPrimary)
            }
            .overlay {
                if style == .appTile {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 0.5)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Icon + title, the label every Settings row shares.
struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    var style: SettingsIcon.Style = .system

    var body: some View {
        Label {
            Text(title).foregroundStyle(StrandPalette.textPrimary)
        } icon: {
            SettingsIcon(systemName: icon, color: color, style: style)
        }
    }
}

/// A row that pushes a Settings page, with an optional grey value before the chevron.
struct SettingsLink: View {
    let page: SettingsPage
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    var style: SettingsIcon.Style
    var value: String?

    init(_ page: SettingsPage, _ title: LocalizedStringKey, icon: String, color: Color,
         style: SettingsIcon.Style = .system, value: String? = nil) {
        self.page = page
        self.title = title
        self.icon = icon
        self.color = color
        self.style = style
        self.value = value
    }

    var body: some View {
        NavigationLink(value: page) {
            if let value {
                LabeledContent {
                    Text(value)
                } label: {
                    SettingsRowLabel(title: title, icon: icon, color: color, style: style)
                }
            } else {
                SettingsRowLabel(title: title, icon: icon, color: color, style: style)
            }
        }
    }
}

/// A row with an icon and a switch (Settings' Airplane Mode row).
struct SettingsToggle: View {
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, icon: String, color: Color, isOn: Binding<Bool>) {
        self.title = title
        self.icon = icon
        self.color = color
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(title: title, icon: icon, color: color)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Settings") {
    let model = AppModel()
    return NavigationStack {
        SettingsView().settingsDestinations()
    }
    .environmentObject(model)
    .environmentObject(model.live)
    .environmentObject(model.profile)
}
#endif
