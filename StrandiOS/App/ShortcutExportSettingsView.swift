#if os(iOS)
import SwiftUI
import StrandDesign

/// #155 — the opt-in surface for the Apple-Health-free export. Sideloaded installs (free 7-day
/// signing) can't carry the HealthKit entitlement, so HealthKitBridge never runs for them; this
/// toggle instead has NOOP rewrite Documents/noop_sync.txt on every background transition, and the
/// user's Siri Shortcut reads the file and logs the rows into Apple Health. Default OFF.
struct ShortcutExportSettingsView: View {
    @AppStorage(ShortcutHealthExport.enabledKey) private var enabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Export for Shortcuts (Apple Health)", isOn: $enabled)
            }
        }
        .settingsPage("Shortcuts Export")
    }
}
#endif
