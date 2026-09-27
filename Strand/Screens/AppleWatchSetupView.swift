import SwiftUI
import StrandDesign

// MARK: - Apple Watch setup
//
// Using NOOP with only an Apple Watch, in two pages:
//   1. What the watch is great at, and where it's lighter than a chest strap, so the permission ask
//      that follows is informed.
//   2. The Health permission, which triggers the existing HealthKitBridge.requestAuthorization. The
//      bridge owns the type list, the entitlement checks, and arming live ingestion once granted.
//
// macOS has no HealthKit, so the permission page there says "this needs an iPhone" rather than
// offering a button that can't work.

struct AppleWatchSetupView: View {
    let onClose: () -> Void

    /// iOS-only: the live HealthKit bridge that owns the real permission request. macOS has no
    /// HealthKit, so this and every `health.*` use stays `#if os(iOS)`-gated.
    #if os(iOS)
    @EnvironmentObject private var health: HealthKitBridge
    #endif

    /// The permission page, pushed from the intro's Continue.
    @State private var showPermission = false

    var body: some View {
        NavigationStack {
            introPage
                .navigationDestination(isPresented: $showPermission) { permissionPage }
        }
        #if os(macOS)
        .frame(width: 520, height: 600)
        #else
        .noopSheetPresentation(largeFirst: true)
        #endif
    }

    // MARK: - Page 1: what to expect

    private var introPage: some View {
        Form {
            Section {
                GuideGlyphRow(icon: "bed.double.fill", tint: StrandPalette.healthSleepCore,
                              title: Text("Sleep & Rest"),
                              detail: Text("Apple's sleep stages drive your Rest score."))
                GuideGlyphRow(icon: "figure.walk", tint: StrandPalette.summaryEffortRing,
                              title: Text("Steps & workouts"),
                              detail: Text("Steps, energy and workouts feed your Effort."))
                GuideGlyphRow(icon: "bolt.heart.fill", tint: StrandPalette.healthHeart,
                              title: Text("Fitness Age"),
                              detail: Text("From the watch's cardio fitness (VO₂ max)."))
            } header: {
                Text("What it's great at")
            }
            Section {
                GuideGlyphRow(icon: "heart.fill", tint: StrandPalette.summaryChargeRing,
                              title: Text("Recovery takes about a week"),
                              detail: Text("Charge needs about seven nights to calibrate."))
                GuideGlyphRow(icon: "drop.degreesign", tint: StrandPalette.healthTemperature,
                              title: Text("A couple of metrics depend on your model"),
                              detail: Text("Wrist temperature needs Series 8 or later."))
            } header: {
                Text("Where it's lighter")
            }
        }
        .settingsForm()
        .navigationTitle(Text(verbatim: "Apple Watch"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                WorkoutSheetCloseButton(action: onClose)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showPermission = true
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .guideProminentButton()
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Goes to the Apple Health permission step")
            .frame(maxWidth: 540)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Page 2: Health permission

    @ViewBuilder private var permissionPage: some View {
        #if os(iOS)
        Form {
            Section {
                GuideGlyphRow(icon: "heart.text.square.fill", tint: StrandPalette.healthHeart,
                              title: Text("Apple Health"),
                              value: Text(healthStatus))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    permissionFooter
                    if let err = health.lastError {
                        Text(verbatim: err).foregroundStyle(StrandPalette.settingsRed)
                    }
                }
            }
        }
        .settingsForm()
        .navigationTitle(Text("Connect Apple Health"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if health.auth == .authorized {
                    WorkoutSheetConfirmButton(tint: StrandPalette.settingsBlue, action: onClose)
                } else {
                    WorkoutSheetCloseButton(action: onClose)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if health.auth == .unknown || health.auth == .denied {
                Button {
                    // The bridge owns the real request: the type list, the entitlement checks, and
                    // arming continuous live ingestion once granted. This only triggers it.
                    Task { await health.requestAuthorization() }
                } label: {
                    Label("Allow Apple Health access", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .guideProminentButton()
                .accessibilityHint("Shows the Apple Health permission sheet")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        #else
        Form {
            Section {
                GuideGlyphRow(icon: "iphone", tint: StrandPalette.settingsBlue,
                              title: Text("Set this up on your iPhone"),
                              detail: Text("Apple Health lives on the iPhone, not the Mac."))
            }
        }
        .settingsForm()
        .navigationTitle(Text("Connect Apple Health"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                WorkoutSheetCloseButton(action: onClose)
            }
        }
        #endif
    }

    #if os(iOS)
    /// The grey value beside "Apple Health".
    private var healthStatus: LocalizedStringKey {
        guard health.auth == .authorized else { return "Not connected" }
        return health.syncing ? "Syncing" : "Connected"
    }

    /// One line under the row for the current authorization state.
    @ViewBuilder private var permissionFooter: some View {
        switch health.auth {
        case .unavailable:
            Text("Apple Health isn't available on this device, so there's nothing to connect here.")
        case .entitlementMissing:
            // The sideload was re-signed without the HealthKit entitlement (free Apple IDs always lack
            // it, and some paid reseller certs do too, #930), so the request can never present.
            Text("This build can't connect to Apple Health. Import a Health export from Data Sources instead.")
        case .unknown:
            Text("Heart, sleep, steps and VO₂ max. It all stays on this iPhone.")
        case .denied:
            Text("If you don't see the prompt, turn NOOP on under Settings › Health › Data Access & Devices.")
        case .authorized:
            Text("Charge calibrates over the first week.")
        }
    }
    #endif
}

#if DEBUG
#Preview("Apple Watch setup") {
    AppleWatchSetupView(onClose: {})
}
#endif
