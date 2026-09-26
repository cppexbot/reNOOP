//  AboutSettingsPage.swift
//  NOOP · Settings → About NOOP, laid out like Settings → General → About: plain value rows, then the
//  help sheets, updates, the project link and the upstream credits.

import SwiftUI
import StrandDesign

struct AboutSettingsPage: View {
    @State private var showWhatsNew = false
    @State private var showScoringGuide = false
    @State private var showHowNoopWorks = false
    #if os(iOS)
    @State private var showDiagnostics = false
    #endif

    /// User-initiated GitHub release check behind "Check for updates".
    @StateObject private var updateChecker = UpdateChecker()
    /// #1659. Default comes from `UpdateAvailability.defaultEnabled` so the toggle and the launch check
    /// agree about what "unset" means.
    @AppStorage(UpdateWatch.Keys.enabled) private var autoCheckUpdates = UpdateAvailability.defaultEnabled
    @Environment(\.openURL) private var openURL

    /// The real bundle version (CFBundleShortVersionString), never a hand-edited constant.
    private var bundleVersionString: String { UpdateWatch.installedVersion }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: "NOOP")
                LabeledContent("Version", value: bundleVersionString)
            }

            Section {
                Button("What's new") { showWhatsNew = true }
                Button("How NOOP works") { showHowNoopWorks = true }
                Button("How your scores work") { showScoringGuide = true }
                NavigationLink("About Apple Watch data", value: SettingsPage.appleWatch)
                NavigationLink("NOOP Limitations", value: SettingsPage.limitations)
            }
            .foregroundStyle(StrandPalette.textPrimary)

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
            } footer: {
                Text("Checks the project's home (GitHub) for the latest version when you tap. Nothing else is sent.")
            }

            #if os(iOS)
            Section {
                Button("Diagnostics") { showDiagnostics = true }
                    .foregroundStyle(StrandPalette.textPrimary)
                NavigationLink("Using NOOP on iPhone", value: SettingsPage.iphone)
            }
            #endif

            Section {
                Link("Project home & source", destination: URL(string: "https://github.com/ryanbr/noop")!)
            } footer: {
                Text("NOOP is not a medical device. It is for informational and personal-insight purposes only and is not intended to diagnose, treat, cure or prevent any condition. Talk to a clinician for medical advice.")
            }

            Section {
                LabeledContent("johnmiddleton12/my-whoop", value: String(localized: "WHOOP 4.0 protocol"))
                LabeledContent("b-nnett/goose", value: String(localized: "WHOOP 5.0 protocol"))
            } header: {
                Text("Built on")
            } footer: {
                Text("Open-source BLE reverse-engineering work. Thank you.")
            }
        }
        .settingsPage("About NOOP")
        .sheet(isPresented: $showWhatsNew) { WhatsNewView(onClose: { showWhatsNew = false }) }
        .sheet(isPresented: $showScoringGuide) { ScoringGuideView(onClose: { showScoringGuide = false }) }
        .sheet(isPresented: $showHowNoopWorks) { HowNoopWorksView(onClose: { showHowNoopWorks = false }) }
        #if os(iOS)
        .sheet(isPresented: $showDiagnostics) { DiagnosticsSheet(onClose: { showDiagnostics = false }) }
        #endif
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
}

#if os(iOS)
// MARK: - Using NOOP on iPhone

/// What to expect from a sideloaded iPhone build, and the live sideload-cert expiry when readable.
struct IPhoneNotesPage: View {
    private let expiry = IOSDiagnostics.capture().expiryDaysRemaining()

    var body: some View {
        Form {
            if let days = expiry {
                Section {
                    Label {
                        Text(expiryMessage(days))
                    } icon: {
                        Image(systemName: days <= 3 ? "exclamationmark.triangle.fill" : "clock.badge.checkmark")
                            .foregroundStyle(days <= 3 ? StrandPalette.statusWarning : StrandPalette.textSecondary)
                    }
                }
            }
            Section {
                Text("This is a sideloaded build, installed outside the App Store. It needs re-signing periodically: roughly every 7 days on a free Apple ID, about a year on a paid developer account.")
                Text("After your iPhone reboots, unlock it once. Until you do, iOS keeps NOOP's files locked (Data Protection), so new history can't be written or synced.")
                Text("Background Bluetooth has OS limits: iOS may pause NOOP when it's not in the foreground, so keep it open while syncing a fresh strap.")
                Text("On a beta version of iOS, things can break that work on the release build.")
            }
            .font(StrandFont.pro(15))
        }
        .settingsPage("Using NOOP on iPhone")
    }

    private func expiryMessage(_ days: Int) -> String {
        if days < 0 {
            let expired = -days
            return expired == 1
                ? String(localized: "This sideloaded build expired 1 day ago. Re-sign it to keep it running.")
                : String(localized: "This sideloaded build expired \(expired) days ago. Re-sign it to keep it running.")
        }
        return days == 1
            ? String(localized: "This sideloaded build expires in 1 day. Re-sign to keep it running.")
            : String(localized: "This sideloaded build expires in \(days) days. Re-sign to keep it running.")
    }
}

// MARK: - Diagnostics sheet

/// A read-only environment dump for bug reports: device, iOS+build, Data Protection (#222), background
/// refresh, low-power, sideload + cert expiry — with a one-tap Copy.
private struct DiagnosticsSheet: View {
    let onClose: () -> Void

    /// Captured once at presentation; a snapshot, not a live monitor.
    private let lines: [String] = IOSDiagnostics.capture().summaryLines()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if lines.isEmpty {
                        Text("No iOS diagnostics available.").foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(StrandFont.mono(12))
                                .textSelection(.enabled)
                        }
                    }
                } footer: {
                    Text("Attach this to a bug report.")
                }
            }
            .settingsPage("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Copy") { PlatformPasteboard.copy(lines.joined(separator: "\n")) }
                        .disabled(lines.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }
}
#else
/// iPhone-only page; macOS never routes here.
struct IPhoneNotesPage: View {
    var body: some View { EmptyView() }
}
#endif
