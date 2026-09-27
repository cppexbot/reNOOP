import SwiftUI
import StrandDesign
import WhoopStore
import Foundation

// MARK: - Apple Health (Settings → Apple Health)
//
// The live HealthKit connection (iOS): its state, enable, last sync and Sync now. The data itself is read
// where every other source is, on the metric pages.

/// #833/v7.7.2 (Apple Health per-source freeze): the snapshot AppleHealthView.load() builds, parked on the
/// long-lived Repository so a re-mount (macOS keys the NavigationSplitView detail with `.id`, so every sidebar
/// switch cold-mounts the screen) can RESTORE it in-memory instead of re-running the whole apple-health history
/// read on the @MainActor. The exact twin of `InsightsLoadCache` for #833; holds load()'s three `@State`
/// outputs. Consumed only when the seq AND the dayKey still match (see `Repository.appleHealthLoadedSeq` /
/// `appleHealthLoadedDayKey`).
struct AppleHealthLoadCache {
    let appleRows: [AppleDaily]
    let workoutCount: Int
    let series: [String: [(day: String, value: Double)]]
}

/// #833/v7.7.2: `.task(id:)` key for the Apple Health load, the data-refresh seq PLUS today's local day-key, so
/// the load re-runs both on a data change AND on a calendar-day rollover while the screen stays mounted across
/// midnight (keying on `refreshSeq` alone left the inside-load dayKey guard unreachable). The exact twin of
/// InsightsView's `InsightsLoadKey`.
struct AppleHealthLoadKey: Equatable {
    let seq: Int
    let dayKey: String
}

struct AppleHealthView: View {
    // iOS-only: the live two-way HealthKit bridge, injected at StrandiOSApp. macOS has no HealthKit, so
    // every `health.*` use stays inside `#if os(iOS)`.
    #if os(iOS)
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var model: AppModel
    #endif

    var body: some View {
        Form {
            #if os(iOS)
            liveSyncSection
            #else
            Section {
                Text("Import a Health export .zip in Import.")
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            #endif
        }
        .settingsPage("Apple Health")
    }

    #if os(iOS)
    private var liveSyncSection: some View {
        Section {
            HStack(spacing: 8) {
                Circle()
                    .fill(liveStatusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(liveStatusText)
            }

            switch health.auth {
            case .unavailable, .entitlementMissing:
                EmptyView()

            case .unknown, .denied:
                Button("Enable Apple Health") {
                    Task {
                        await health.requestAuthorization()
                        await HealthSyncRefreshCoordinator.run(
                            sync: { await health.sync() },
                            refresh: {
                                await model.refreshAfterAppleHealthSync(
                                    authorized: health.auth == .authorized)
                            }
                        )
                    }
                }

            case .authorized:
                if let last = health.lastSync {
                    LabeledContent("Last sync", value: relativeAgo(last.timeIntervalSince1970))
                }
                Button("Sync now") {
                    Task {
                        await HealthSyncRefreshCoordinator.run(
                            sync: { await health.sync() },
                            refresh: {
                                await model.refreshAfterAppleHealthSync(
                                    authorized: health.auth == .authorized)
                            }
                        )
                    }
                }
                .disabled(health.syncing)
            }

            if let err = health.lastError {
                Text(err)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusCritical)
            }
        } footer: {
            liveSyncFooter
        }
    }

    private var liveStatusText: LocalizedStringKey {
        switch health.auth {
        case .unavailable, .entitlementMissing: return "Not available"
        case .unknown, .denied:                 return "Not connected"
        case .authorized:                       return health.syncing ? "Syncing" : "Connected"
        }
    }

    private var liveStatusColor: Color {
        switch health.auth {
        case .authorized:                       return StrandPalette.settingsGreen
        case .denied, .entitlementMissing:      return StrandPalette.settingsOrange
        case .unknown, .unavailable:            return StrandPalette.settingsGray
        }
    }

    @ViewBuilder
    private var liveSyncFooter: some View {
        switch health.auth {
        case .unavailable:
            Text("Apple Health isn't available on \(Platform.deviceNounPhrase).")
        case .entitlementMissing:
            // #348 / #930: the sideload was re-signed WITHOUT the HealthKit entitlement (free
            // Apple IDs always lack it; some paid reseller certs do too), so "Enable Apple Health"
            // can never work and the app can never appear under Settings › Health › Data Access
            // & Devices.
            Text("This install can't connect to Apple Health directly.")
        case .denied:
            Text("If you don't see the prompt, enable NOOP under Settings › Health › Data Access & Devices.")
        case .unknown, .authorized:
            EmptyView()
        }
    }
    #endif

}
