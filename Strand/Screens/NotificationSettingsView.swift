import SwiftUI
import AppKit
import StrandDesign

/// Notifications — choose which Mac apps tap your wrist, and how.
/// Real app icons via NSWorkspace; per-app on/off + buzz pattern; quiet hours.
struct NotificationSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @StateObject private var store = NotificationSettingsStore()

    var body: some View {
        // #926: the "every pattern buzzes the same on a 5/MG" note is gone: overallLoop (byte 11 of the
        // maverick haptic body) is now written as `loops - 1` by `MaverickHaptics.notificationBuzz`, so all
        // four patterns are distinct on that family too. The Kotlin twin carries the same change.
        Form {
            Section {
                deliveryNote
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            masterSection
            if store.activeCategories.isEmpty {
                Section {
                    Text("No supported apps found").foregroundStyle(StrandPalette.textSecondary)
                }
            } else {
                ForEach(store.activeCategories) { cat in
                    categorySection(cat, apps: store.apps(in: cat))
                }
            }
            behaviourSection
        }
        .settingsPage("Notifications")
    }

    // MARK: - Master

    private var masterSection: some View {
        Section {
            Toggle("Enable wrist alerts", isOn: $store.masterEnabled)
            LabeledContent("Strap") {
                Text(strapStatus).foregroundStyle(strapStatusColor)
            }
            Button {
                model.buzz(loops: 2)
            } label: {
                Label("Test buzz", systemImage: "waveform.path")
            }
            .disabled(!live.bonded)
            .help(live.bonded ? "Fire a test buzz now" : "Connect your strap to test")
            .accessibilityHint(live.bonded ? "Fires a test buzz on your strap" : "Connect your strap to enable")
        } header: {
            Text("Wrist alerts")
        } footer: {
            Text(store.enabledCount == 1 ? "1 app on" : "\(store.enabledCount) apps on")
        }
    }

    private var deliveryNote: some View {
        NoticeCard(title: Text("Wrist delivery isn't live yet"),
                   message: Text("Your choices apply once it ships."),
                   systemImage: "info.circle.fill", tone: .info)
    }

    /// Strap status — mirrors SettingsView's three-state mapping so the value and its colour always
    /// agree (and never read "connected" while the strap is offline).
    private var strapStatus: LocalizedStringKey {
        if live.connected { return "Connected" }
        if live.bonded { return "Paired" }          // paired but offline — won't deliver
        return "Not connected"
    }
    private var strapStatusColor: Color {
        if live.connected { return StrandPalette.textSecondary }
        if live.bonded { return StrandPalette.statusWarning }
        return StrandPalette.statusCritical
    }

    // MARK: - Category section

    private func categorySection(_ cat: NotifCategory, apps: [NotifApp]) -> some View {
        Section {
            ForEach(apps) { app in appRow(app) }
        } header: {
            Text(cat.rawValue)
        }
        .disabled(!store.masterEnabled)
    }

    private func appRow(_ app: NotifApp) -> some View {
        let enabled = store.isEnabled(app.id)
        return HStack(spacing: 10) {
            appIcon(app)
            Text(app.name)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 8)
            if enabled {
                patternPicker(app)
                testButton(app)
            }
            Toggle("", isOn: Binding(
                get: { store.isEnabled(app.id) },
                set: { store.setEnabled(app.id, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("\(app.name) wrist alerts")
        }
    }

    private func appIcon(_ app: NotifApp) -> some View {
        Group {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(StrandPalette.surfaceInset)
                    .overlay(Image(systemName: app.fallbackSymbol)
                        .foregroundStyle(StrandPalette.textSecondary))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private func patternPicker(_ app: NotifApp) -> some View {
        Picker("", selection: Binding(
            get: { store.pattern(app.id) },
            set: { store.setPattern(app.id, $0) })) {
            ForEach(BuzzPattern.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help("Choose the buzz pattern for \(app.name)")
    }

    private func testButton(_ app: NotifApp) -> some View {
        Button {
            model.buzz(loops: store.pattern(app.id).loops)
        } label: {
            Image(systemName: "play.fill")
        }
        .buttonStyle(.borderless)
        .disabled(!live.bonded)
        .help(live.bonded ? "Test \(app.name) buzz" : "Connect your strap to test")
        .accessibilityLabel("Test \(app.name) buzz")
        .accessibilityHint(live.bonded ? "Fires a test buzz on your strap" : "Connect your strap to enable")
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        Section {
            Toggle("Only buzz when worn", isOn: $store.onlyWhenWorn)
            Toggle("Quiet hours", isOn: $store.quietHoursEnabled)
            if store.quietHoursEnabled {
                DatePicker("From", selection: quietStartBinding, displayedComponents: .hourAndMinute)
                    .accessibilityLabel("Quiet hours start")
                DatePicker("To", selection: quietEndBinding, displayedComponents: .hourAndMinute)
                    .accessibilityLabel("Quiet hours end")
            }
        } header: {
            Text("Behaviour")
        }
    }

    // MARK: - Quiet-hours bindings

    private var quietStartBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: store.quietStartMinutes) },
                set: { store.quietStartMinutes = Self.minutes(from: $0) })
    }
    private var quietEndBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: store.quietEndMinutes) },
                set: { store.quietEndMinutes = Self.minutes(from: $0) })
    }
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Notifications") {
    let model = AppModel()
    model.live.bonded = true
    model.live.connected = true
    return NotificationSettingsView()
        .environmentObject(model)
        .environmentObject(model.live)
        .frame(width: 760, height: 940)
}
#endif
