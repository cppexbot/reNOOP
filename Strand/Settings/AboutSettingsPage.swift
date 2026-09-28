//  AboutSettingsPage.swift
//  NOOP · Settings → About NOOP, laid out like Settings → General → About: plain value rows, then the
//  help sheets, updates, the project link and the upstream credits.

import SwiftUI
import StrandDesign

struct AboutSettingsPage: View {
    @State private var showWhatsNew = false
    @State private var showHowNoopWorks = false
    #if os(iOS)
    /// Days until the sideload signature expires (negative once it has), when readable.
    private let signingDaysLeft = IOSDiagnostics.capture().expiryDaysRemaining()
    #endif

    /// User-initiated GitHub release check behind "Check for updates".
    @StateObject private var updateChecker = UpdateChecker()
    /// #1659. Default comes from `UpdateAvailability.defaultEnabled` so the toggle and the launch check
    /// agree about what "unset" means.
    @AppStorage(UpdateWatch.Keys.enabled) private var autoCheckUpdates = UpdateAvailability.defaultEnabled
    @Environment(\.openURL) private var openURL

    /// ST-9: Settings shows Developer only after seven taps here, as Android's build number unlocks its
    /// developer options. Stored, so the section stays once found.
    @AppStorage(DeveloperUnlock.key) private var developerUnlocked = false
    @State private var versionTaps = 0

    /// The real bundle version (CFBundleShortVersionString), never a hand-edited constant.
    private var bundleVersionString: String { UpdateWatch.installedVersion }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: bundleVersionString)
                    .contentShape(Rectangle())
                    .onTapGesture { countVersionTap() }
                #if os(iOS)
                if let days = signingDaysLeft {
                    LabeledContent("Signing expires") {
                        Text(Self.relativeDays(days))
                            .foregroundStyle(days <= 3 ? StrandPalette.statusWarning : StrandPalette.textSecondary)
                    }
                }
                #endif
            }

            Section {
                Button("What's new") { showWhatsNew = true }
                    .foregroundStyle(StrandPalette.textPrimary)
                Button("How NOOP works") { showHowNoopWorks = true }
                    .foregroundStyle(StrandPalette.textPrimary)
                Link(destination: URL(string: "https://github.com/ryanbr/noop")!) {
                    Text(verbatim: "GitHub").foregroundStyle(StrandPalette.textPrimary)
                }
            }

            Section {
                Button {
                    // The INSTALLED bundle version against GitHub's latest (#697-adjacent).
                    updateChecker.check(currentVersion: bundleVersionString)
                } label: {
                    LabeledContent {
                        updateStatus
                    } label: {
                        Text("Check for updates").foregroundStyle(StrandPalette.accent)
                    }
                }
                .disabled(updateChecker.state == .checking)
                if case .available(let v, let url, _) = updateChecker.state {
                    Button {
                        openURL(url)
                    } label: {
                        LabeledContent {
                            Image(systemName: "arrow.down.circle.fill")
                        } label: {
                            Text("Version \(v) is available").foregroundStyle(StrandPalette.accent)
                        }
                    }
                }
                // #1659: iOS cannot auto-update a sideloaded build, so noticing and saying so is all there is.
                Toggle("Check automatically", isOn: $autoCheckUpdates)
            } header: {
                Text("Updates")
            }

            Section {
                LabeledContent("johnmiddleton12/my-whoop", value: String(localized: "WHOOP 4.0 protocol"))
                LabeledContent("b-nnett/goose", value: String(localized: "WHOOP 5.0 protocol"))
            } header: {
                Text("Built on")
            }
        }
        .settingsPage("About NOOP")
        .sheet(isPresented: $showWhatsNew) { WhatsNewView(onClose: { showWhatsNew = false }) }
        .sheet(isPresented: $showHowNoopWorks) { HowNoopWorksView(onClose: { showHowNoopWorks = false }) }
    }

    private func countVersionTap() {
        guard !DeveloperUnlock.isAlwaysOn, !developerUnlocked else { return }
        versionTaps += 1
        if versionTaps >= DeveloperUnlock.taps {
            developerUnlocked = true
            Confirmation.shared.show(String(localized: "Developer settings on"), systemImage: "hammer.fill")
        }
    }

    @ViewBuilder private var updateStatus: some View {
        switch updateChecker.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Text("Up to date")
        case .failed:
            Text("Couldn't check. Try again.")
        default:
            EmptyView()
        }
    }

    /// "in 5 days" / "2 days ago", in the app language.
    private static func relativeDays(_ days: Int) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = AppLanguage.activeLocale
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        return f.localizedString(from: DateComponents(day: days))
    }
}

/// Where the Developer section's unlock lives (ST-9): shown in debug builds, and in a release build after
/// `taps` taps on the version in About NOOP.
enum DeveloperUnlock {
    static let key = "noop.developerUnlocked"
    static let taps = 7

    static var isAlwaysOn: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
