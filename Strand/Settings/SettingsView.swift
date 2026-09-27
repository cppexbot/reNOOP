//  SettingsView.swift
//  NOOP · Settings, as Apple's own apps draw theirs on iOS 26 (Health's profile, Fitness's sheets, the
//  Watch app): the photo and name on top, bold section titles, rows led by iOS 26-style icon tiles,
//  values in grey before the chevron.
//
//  Every page pushes a `SettingsPage` VALUE, so the host stack's path can pop it (#198); each host
//  registers the destinations ONCE with `.settingsDestinations()` (a second registration in the same stack
//  double-pushes, #38).

import SwiftUI
import StrandDesign

struct SettingsView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    /// The Coach master switch, under the same `noop.` key Android writes. Read by `RootTabView`, Today
    /// and `CoachBriefScheduler`.
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    /// Hydration tracker (opt-in). Off hides the hydration card + detail.
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false

    var body: some View {
        Form {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                SettingsLink(.profile, "Health Details", icon: "person.text.rectangle.fill", color: StrandPalette.settingsRed)
            }

            Section {
                strapRow
            } header: {
                Text("Strap")
            }

            Section {
                SettingsLink(.general, "General", icon: "gearshape.fill", color: StrandPalette.settingsGray)
                SettingsLink(.display, "Display", icon: "sun.max.fill", color: StrandPalette.settingsBlue)
                SettingsLink(.notifications, "Notifications", icon: "bell.badge.fill", color: StrandPalette.settingsRed)
                SettingsLink(.shortcuts, "Shortcuts", icon: "square.2.layers.3d.fill", color: StrandPalette.settingsPurple)
            } header: {
                Text("App")
            }

            Section {
                SettingsLink(.workouts, "Workouts", icon: "figure.run", color: StrandPalette.settingsGreen)
                SettingsLink(.scores, "Scores", icon: "gauge.with.needle.fill", color: StrandPalette.settingsRed)
                SettingsToggle("AI Coach", icon: "sparkles", color: StrandPalette.settingsPurple, isOn: $coachEnabled)
                SettingsToggle("Hydration tracking", icon: "drop.fill", color: StrandPalette.settingsCyan, isOn: $hydrationEnabled)
            } header: {
                Text("Features")
            }

            Section {
                SettingsLink(.appleHealth, "Apple Health", icon: "heart.fill", color: StrandPalette.settingsPink)
                SettingsLink(.dataSources, "Import", icon: "square.and.arrow.down.fill", color: StrandPalette.settingsIndigo)
                SettingsLink(.backup, "Backup", icon: "clock.arrow.circlepath", color: StrandPalette.settingsTeal)
            } header: {
                Text("Data")
            }

            Section {
                SettingsLink(.about, "About NOOP", icon: "info", color: StrandPalette.settingsGray)
                SettingsLink(.developer, "Developer", icon: "hammer.fill", color: StrandPalette.settingsGray)
            }
        }
        .settingsForm()
        // Bold section titles, as Health and the Watch app head their root lists. Root only: under a
        // `.navigationLink` Picker this environment value crashes SwiftUI (iOS 26.5) on push.
        .headerProminence(.increased)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChangeCompat(of: coachEnabled) { on in
            // Switching the AI off has to TAKE DOWN what the brief already published, not just stop the
            // next one: the widget renders the last brief it was given.
            CoachBriefScheduler.applyMasterSwitch(on)
        }
    }

    /// The active strap by name, its link state and charge on the right, as the Watch app heads its list
    /// with the paired watch. Opens Devices, where the strap's own settings live.
    private var strapRow: some View {
        let name = model.deviceRegistry?.devices.first { $0.status == .active }?.displayName
        var value = String(localized: live.connected ? "Connected" : "Not connected")
        if live.connected, let pct = live.batteryPct { value += " · \(Int(pct.rounded()))%" }
        return NavigationLink(value: SettingsPage.devices) {
            HStack {
                Label {
                    Text(verbatim: name ?? String(localized: "Devices"))
                        .foregroundStyle(StrandPalette.textPrimary)
                } icon: {
                    SettingsIcon(systemName: "dot.radiowaves.left.and.right", color: StrandPalette.settingsBlue)
                }
                Spacer()
                Text(value).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    /// Health's profile header: the photo (or monogram) centred, the name under it.
    private var header: some View {
        VStack(spacing: 10) {
            SummaryAvatar(imageData: profile.avatarImageData, initials: profile.initials, size: 96)
            Text(profile.displayName.isEmpty ? String(localized: "Profile") : profile.displayName)
                .font(StrandFont.pro(28, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        // A whole-point height keeps every card below on the pixel grid; a fractional one leaves a seam
        // between two rows' backgrounds.
        .frame(height: 142)
    }
}

// MARK: - Pages

/// Every page Settings (and the profile sheet) can push, as a `Hashable` value a `NavigationPath` carries.
enum SettingsPage: Hashable {
    case settings
    case profile, heartRateZones
    case general, units, display, notifications, shortcuts
    case workouts, scores
    case devices, appleHealth, dataSources, backup
    case about, developer

    @ViewBuilder var destination: some View {
        switch self {
        case .settings:       SettingsView()
        case .profile:        ProfileDetailsView()
        case .heartRateZones: HeartRateZonesPage()
        case .general:        GeneralSettingsPage()
        case .units:          UnitsSettingsPage()
        case .display:        DisplaySettingsPage()
        case .notifications:  NotificationsSettingsPage()
        case .shortcuts:      ShortcutsSettingsPage()
        case .workouts:       WorkoutsSettingsPage()
        case .scores:         ScoresSettingsPage()
        case .devices:        DevicesView()
        case .appleHealth:    AppleHealthView()
        case .dataSources:    DataSourcesView()
        case .backup:         BackupSyncView()
        case .about:          AboutSettingsPage()
        case .developer:      DeveloperSettingsPage()
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
}

// MARK: - Rows

/// The row icon in the iOS 26 icon look: light appearance is a coloured tile under a white glyph, dark
/// appearance is a dark tile under the coloured glyph, as iOS switches its own icons with the theme. Both
/// carry the thin glass rim of the new icons.
struct SettingsIcon: View {
    let systemName: String
    let color: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let tile = RoundedRectangle(cornerRadius: 8, style: .continuous)
        tile
            .fill(dark ? AnyShapeStyle(LinearGradient(colors: [StrandPalette.settingsIconDarkTop,
                                                               StrandPalette.settingsIconDarkBottom],
                                                      startPoint: .top, endPoint: .bottom))
                       : AnyShapeStyle(color.gradient))
            .frame(width: 30, height: 30)
            .overlay {
                tile.strokeBorder(
                    LinearGradient(colors: [dark ? StrandPalette.settingsIconDarkRim : StrandPalette.settingsIconRim, .clear],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            }
            .overlay {
                // Every glyph fitted into one box, so wide symbols (a card, a battery) stay inside the tile.
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .frame(width: 18, height: 18)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(dark ? color : StrandPalette.onDarkPrimary)
            }
            .accessibilityHidden(true)
    }
}

/// Glyph + title, the label every Settings row shares.
struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let color: Color

    var body: some View {
        Label {
            Text(title).foregroundStyle(StrandPalette.textPrimary)
        } icon: {
            SettingsIcon(systemName: icon, color: color)
        }
    }
}

/// A row that pushes a Settings page, with an optional grey value before the chevron.
struct SettingsLink: View {
    let page: SettingsPage
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    var value: String?

    init(_ page: SettingsPage, _ title: LocalizedStringKey, icon: String, color: Color, value: String? = nil) {
        self.page = page
        self.title = title
        self.icon = icon
        self.color = color
        self.value = value
    }

    var body: some View {
        NavigationLink(value: page) {
            HStack {
                SettingsRowLabel(title: title, icon: icon, color: color)
                if let value {
                    Spacer()
                    Text(value).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }
}

/// A row with a glyph and a switch.
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
