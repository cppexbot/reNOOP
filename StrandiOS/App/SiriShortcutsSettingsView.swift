#if os(iOS)
import SwiftUI
import AppIntents
import StrandDesign

/// Surfaces NOOP's already-registered App Intents (see StrandiOS/System/NOOPAppIntents.swift) in the
/// UI so users discover them. `NOOPShortcuts` auto-registers "Sync Strap", "Buzz Strap" and "Mark a Moment" with
/// Siri/Spotlight/Shortcuts, but nothing in-app advertised them — this is the iOS analogue of the
/// Mac's strap-double-tap-runs-a-Shortcut feature. Apple's `SiriTipView`/`ShortcutsLink` (iOS 16+)
/// do exactly that: tip the user on the spoken phrase and deep-link into the Shortcuts app, scoped to
/// this app automatically.
struct SiriShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                // Apple's tip views carry their own rounded chrome, so they fill the row slot on a clear row.
                VStack(spacing: NoopMetrics.space2) {
                    SiriTipView(intent: SyncStrapIntent(), isVisible: .constant(true))
                    SiriTipView(intent: BuzzStrapIntent(), isVisible: .constant(true))
                    SiriTipView(intent: MarkMomentIntent(), isVisible: .constant(true))
                }
                .siriTipViewStyle(.dark)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Ready-made actions")
            }

            Section {
                ShortcutsLink()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("Build your own")
            }
        }
        .settingsPage("Siri & Shortcuts")
    }
}
#endif
