//  ShortcutsSettingsPage.swift
//  NOOP · Settings → Shortcuts: the strap's wear events as Shortcut triggers, the Shortcuts-readable
//  Apple Health export, and a link to NOOP's actions in the Shortcuts app. Same keys the old Siri & Shortcuts,
//  Automations (wear) and Shortcuts Export pages wrote.

import SwiftUI
#if os(iOS)
import AppIntents   // ShortcutsLink
#endif
import StrandDesign

struct ShortcutsSettingsPage: View {
    @EnvironmentObject private var behavior: BehaviorStore
    #if os(iOS)
    /// #155: rewrite Documents/noop_sync.txt on every background transition for a Siri Shortcut to log
    /// into Apple Health — the path for sideloads without the HealthKit entitlement. Default OFF.
    @AppStorage(ShortcutHealthExport.enabledKey) private var healthExportEnabled = false
    #endif

    var body: some View {
        Form {
            Section {
                #if os(macOS)
                Toggle("Lock the Mac when I take the strap off", isOn: $behavior.autoLockOnWristOff)
                #endif
                LabeledContent("When taken off") { shortcutField(text: $behavior.wristOffShortcut) }
                LabeledContent("When put back on") { shortcutField(text: $behavior.wristOnShortcut) }
            } header: {
                Text("Run a Shortcut")
            }

            #if os(iOS)
            Section {
                Toggle("Export for Shortcuts", isOn: $healthExportEnabled)
            }

            Section {
                ShortcutsLink()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            #endif
        }
        .settingsPage("Shortcuts")
    }

    /// A Shortcut-name field, right-aligned in its row as Settings draws an editable value.
    private func shortcutField(text: Binding<String>) -> some View {
        TextField("Shortcut", text: text, prompt: Text("Shortcut"))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
    }
}
