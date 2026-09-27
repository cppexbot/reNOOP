import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import WhoopStore
import UserNotifications

// MARK: - OnboardingWizard
//
// First run, drawn as iPhone / Apple Watch setup on iOS 26: one screen per step with a large glyph, a
// bold title, one sentence, whatever the step needs, and one button at the bottom. A glass ‹ goes back.
//
//  1 Welcome
//  2 Put on your strap   — charged, worn, close by (Bluetooth asks on the next step)
//  3 Find your strap     — pick the model, Scan; turns into "Connected" once the strap bonds
//  4 About you           — date of birth / sex / units / weight / height bound to ProfileStore
//  5 Your history        — optional WHOOP / Apple Health import
//  6 Notifications       — leaving it asks the OS once (if not yet determined)
//  7 Done                → onFinished()
//
// Presentation, the legal gate and the keys written on finish stay with the host; this view only calls
// onFinished() when complete.

public struct OnboardingWizard: View {

    /// Called when the user finishes onboarding.
    public var onFinished: () -> Void

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    /// Opens on a later step (the DEBUG screenshot harness).
    init(onFinished: @escaping () -> Void, startAt index: Int) {
        self.onFinished = onFinished
        _step = State(initialValue: Step(rawValue: index) ?? .welcome)
    }

    // NOTE: the root deliberately does NOT observe the fast-updating model/live/profile env objects —
    // doing so re-rendered the whole wizard on every HR tick. Child steps observe what they need.

    private enum Step: Int, CaseIterable {
        case welcome, wear, scan, profile, importData, notifications, done

        var isFirst: Bool { self == .welcome }
        var isLast: Bool { self == .done }
    }

    @State private var step: Step = .welcome

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome:       WelcomeStep()
                case .wear:          WearStep()
                case .scan:          ScanStep()
                case .profile:       ProfileStep()
                case .importData:    ImportStep()
                case .notifications: NotificationsStep()
                case .done:          DoneStep()
                }
            }
            .frame(maxWidth: 540, maxHeight: .infinity)
            .transition(stepTransition)
            .id(step)                       // re-runs the transition per step

            Button(action: primaryAction) {
                Text(verbatim: ctaTitle).frame(maxWidth: .infinity)
            }
            .onboardingPrimaryButton()
            .frame(maxWidth: 540)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if !step.isFirst {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(width: 44, height: 44)
                        .summaryGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
                .padding(.leading, 16)
                .padding(.top, 8)
            }
        }
        .background(StrandPalette.plainPage.ignoresSafeArea())
    }

    private var ctaTitle: String {
        switch step {
        case .welcome: return String(localized: "Get Started")
        case .done:    return String(localized: "Enter NOOP")
        default:       return String(localized: "Continue")
        }
    }

    private func primaryAction() {
        if step.isLast {
            onFinished()
        } else {
            advance()
        }
    }

    // MARK: Navigation

    /// Leaving the Notifications step is the one point in onboarding that asks the OS for notification
    /// permission — the step before only says why. Request only if not already determined (so a re-run
    /// doesn't re-prompt), and advance once the OS dialog is dismissed either way — the per-feature
    /// toggles still handle a later denial on their own.
    private func advance() {
        guard step != .notifications else {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                guard settings.authorizationStatus == .notDetermined else {
                    Task { @MainActor in advanceStep() }
                    return
                }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                    Task { @MainActor in advanceStep() }
                }
            }
            return
        }
        advanceStep()
    }

    private func advanceStep() {
        guard let next = Step(rawValue: step.rawValue + 1) else { onFinished(); return }
        withAnimation(StrandMotion.gentle) { step = next }
    }

    private func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(StrandMotion.gentle) { step = prev }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Page

/// One setup screen: glyph, bold title, one sentence, then the step's own controls.
private struct StepPage<Art: View, Content: View>: View {
    let title: String
    let message: String
    @ViewBuilder var art: () -> Art
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                art()
                    .frame(height: 120)
                    .padding(.bottom, 12)
                Text(verbatim: title)
                    .font(StrandFont.pro(28, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: message)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textSecondary)
                content()
                    .padding(.top, 14)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 96)
            .padding(.bottom, 24)
        }
        #if os(iOS)
        .scrollBounceBehavior(.basedOnSize)
        #endif
    }
}

extension StepPage where Art == StepGlyph {
    init(icon: String, tint: Color, title: String, message: String,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, message: message, art: { StepGlyph(icon: icon, tint: tint) }, content: content)
    }
}

extension StepPage where Art == StepGlyph, Content == EmptyView {
    init(icon: String, tint: Color, title: String, message: String) {
        self.init(icon: icon, tint: tint, title: title, message: message) { EmptyView() }
    }
}

private struct StepGlyph: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 88, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
    }
}

extension View {
    /// The setup screens' one button: a full-width blue capsule (prominent glass on iOS 26).
    @ViewBuilder
    fileprivate func onboardingPrimaryButton() -> some View {
        let styled = self
            .font(StrandFont.pro(17, weight: .semibold))
            .controlSize(.large)
            .tint(StrandPalette.settingsBlue)
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            styled.buttonStyle(.glassProminent)
        } else {
            styled.buttonStyle(.borderedProminent)
        }
        #else
        styled.buttonStyle(.borderedProminent)
        #endif
    }

    /// A secondary choice inside a step: a full-width grey glass capsule.
    @ViewBuilder
    fileprivate func onboardingSecondaryButton() -> some View {
        let styled = self
            .font(StrandFont.pro(17, weight: .semibold))
            .controlSize(.large)
            .tint(StrandPalette.textPrimary)
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            styled.buttonStyle(.glass)
        } else {
            styled.buttonStyle(.bordered)
        }
        #else
        styled.buttonStyle(.bordered)
        #endif
    }
}

// MARK: - 1 · Welcome

private struct WelcomeStep: View {
    var body: some View {
        StepPage(title: String(localized: "Welcome to NOOP"),
                 message: String(localized: "Your strap's data, kept only on \(Platform.deviceNounPhrase)."),
                 art: { BrandMark(size: 110) },
                 content: { EmptyView() })
    }
}

// MARK: - 2 · Put on your strap

private struct WearStep: View {
    var body: some View {
        StepPage(icon: "applewatch.side.right", tint: StrandPalette.textPrimary,
                 title: String(localized: "Put On Your Strap"),
                 message: String(localized: "Charged, snug on your wrist, close to \(Platform.deviceNounPhrase). Bluetooth will ask next."))
    }
}

// MARK: - 3 · Find your strap

private struct ScanStep: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    @State private var scanning = false
    /// Set when a scan ran its calm beat without bonding.
    @State private var notFound = false

    /// Which strap to look for — shared with the Live screen via the same key.
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue
    private var selectedModel: WhoopModel { WhoopModel(rawValue: selectedModelRaw) ?? .whoop4 }

    var body: some View {
        StepPage(title: live.bonded ? String(localized: "Connected") : String(localized: "Find Your Strap"),
                 message: message,
                 art: { art }) {
            if !live.bonded {
                VStack(spacing: 14) {
                    Picker("Strap", selection: Binding(get: { selectedModel }, set: { restartScan(for: $0) })) {
                        ForEach(WhoopModel.allCases, id: \.self) { Text(verbatim: $0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Button { startScan() } label: {
                        Text(scanning ? "Searching…" : "Scan").frame(maxWidth: .infinity)
                    }
                    .onboardingSecondaryButton()
                    .disabled(scanning)
                    // WHOOP leads, but isn't required: other straps and imports live under Devices.
                    Text("No WHOOP? Continue and add a device later.")
                        .font(StrandFont.pro(13))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
        .onDisappear { scanning = false }
    }

    @ViewBuilder private var art: some View {
        if live.bonded {
            StepGlyph(icon: "checkmark.circle.fill", tint: StrandPalette.settingsGreen)
        } else {
            StepGlyph(icon: "dot.radiowaves.left.and.right", tint: StrandPalette.settingsBlue)
                .modifier(ScanPulse(active: scanning || live.connected))
        }
    }

    /// One sentence for where the search stands.
    private var message: String {
        if live.bonded {
            if let pct = live.batteryPct { return String(localized: "Your strap is bonded · \(Int(pct))% battery.") }
            return String(localized: "Your strap is bonded and ready to stream.")
        }
        if notFound {
            // #130: 5.0/MG bonds to one host at a time, so the WHOOP app holding it hides it from a scan.
            return selectedModel == .whoop5mg
                ? String(localized: "Not found. Unpair it in the WHOOP app, close that app and try again.")
                : String(localized: "Not found. Wear it, charge it and close the WHOOP app.")
        }
        if live.connected { return String(localized: "Connecting…") }
        return String(localized: "Choose your strap and tap Scan.")
    }

    private func startScan(model scanModel: WhoopModel? = nil) {
        let modelToScan = scanModel ?? selectedModel
        scanning = true
        notFound = false
        model.scan(model: modelToScan)
        // After a calm beat without a bond, say what usually helps.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if !live.bonded {
                scanning = false
                withAnimation(StrandMotion.gentle) { notFound = true }
            }
        }
    }

    private func restartScan(for newModel: WhoopModel) {
        selectedModelRaw = newModel.rawValue
        guard !live.bonded else { return }
        model.disconnect()
        startScan(model: newModel)
    }
}

/// The radio waves breathe while a search runs (still under Reduce Motion).
private struct ScanPulse: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion, #available(iOS 17.0, macOS 14.0, *) {
            content.symbolEffect(.variableColor.iterative, isActive: true)
        } else {
            content
        }
    }
}

// MARK: - 4 · About you

private struct ProfileStep: View {
    @EnvironmentObject private var profile: ProfileStore

    // The stored profile is always SI. Body measurements and exercise distance can follow the regional
    // conventions independently; an unset distance choice follows the body choice for compatibility.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var distanceUnitSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: unitSystem, override: distanceSystemRaw)
    }
    private var distanceSystemBinding: Binding<String> {
        Binding(get: { distanceUnitSystem.rawValue }, set: { distanceSystemRaw = $0 })
    }

    private let sexes: [(String, String)] = [
        ("male", String(localized: "Male")), ("female", String(localized: "Female")),
        ("nonbinary", String(localized: "Other"))
    ]

    var body: some View {
        StepPage(icon: "person.crop.circle.fill", tint: StrandPalette.settingsGray,
                 title: String(localized: "About You"),
                 message: String(localized: "For your zones, calories and baselines.")) {
            VStack(spacing: 0) {
                // #146: a date of birth, so age advances on its own instead of going stale.
                DatePicker("Date of Birth", selection: $profile.dateOfBirth,
                           in: ProfileStore.dateOfBirthRange, displayedComponents: .date)
                    .padding(.vertical, 8)
                divider
                row("Sex") {
                    Picker("Sex", selection: $profile.sex) {
                        ForEach(sexes, id: \.0) { key, label in Text(label).tag(key) }
                    }
                }
                divider
                // Two explicit choices: "Metric/Imperial" alone cannot describe mixed conventions
                // such as Canadian pounds with kilometres.
                row("Body Measurements") {
                    Picker("Body Measurements", selection: $unitSystemRaw) {
                        Text("Metric").tag(UnitSystem.metric.rawValue)
                        Text("Imperial").tag(UnitSystem.imperial.rawValue)
                    }
                }
                divider
                row("Distance") {
                    Picker("Distance", selection: distanceSystemBinding) {
                        Text("Kilometres").tag(UnitSystem.metric.rawValue)
                        Text("Miles").tag(UnitSystem.imperial.rawValue)
                    }
                }
                divider
                Stepper(value: $profile.weightKg, in: 30...250, step: 0.5) {
                    stepperLabel("Weight", UnitFormatter.massFromKilograms(profile.weightKg, system: unitSystem))
                }
                .padding(.vertical, 8)
                divider
                Stepper(value: $profile.heightCm, in: 120...230, step: 1) {
                    stepperLabel("Height", UnitFormatter.heightFromCentimeters(profile.heightCm, system: unitSystem))
                }
                .padding(.vertical, 8)
            }
            .font(StrandFont.pro(17))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(StrandPalette.plainPageCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var divider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
    }

    private func row<C: View>(_ title: LocalizedStringKey, @ViewBuilder control: () -> C) -> some View {
        HStack {
            Text(title)
            Spacer()
            control()
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
        }
        .padding(.vertical, 4)
    }

    private func stepperLabel(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value).foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

// MARK: - 5 · Your history (optional)

private struct ImportStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false
    @State private var importTarget: ImportTarget = .whoop

    var body: some View {
        StepPage(icon: "square.and.arrow.down", tint: StrandPalette.settingsBlue,
                 title: String(localized: "Bring Your History"),
                 message: String(localized: "Optional. You can import later too.")) {
            VStack(spacing: 10) {
                importButton(.whoop, title: String(localized: "WHOOP Export"))
                importButton(.appleHealth, title: String(localized: "Apple Health Export"))
                if model.hasActiveImport {
                    ProgressView().padding(.top, 4)
                } else if let summary = lastSummary {
                    // Styled off the typed failure flag, not a substring match.
                    Text(summary)
                        .font(StrandFont.pro(15))
                        .foregroundStyle(model.importFailed(importKind) ? StrandPalette.settingsRed : StrandPalette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importTarget.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result, for: importTarget)
        }
    }

    private func importButton(_ target: ImportTarget, title: String) -> some View {
        Button { presentImporter(target) } label: {
            Text(verbatim: title).frame(maxWidth: .infinity)
        }
        .onboardingSecondaryButton()
        .disabled(model.hasActiveImport)
    }

    /// The AppModel source kind matching the last-chosen import target.
    private var importKind: DataSourceImportKind {
        switch importTarget {
        case .whoop: return .whoop
        case .appleHealth: return .appleHealth
        }
    }

    /// The summary for the source the user last imported in this step.
    private var lastSummary: String? {
        switch importTarget {
        case .whoop: return model.whoopImportSummary
        case .appleHealth: return model.appleHealthImportSummary
        }
    }

    private func presentImporter(_ target: ImportTarget) {
        importTarget = target
        showingImporter = true
    }

    private func handleImportResult(_ result: Result<[URL], Error>, for target: ImportTarget) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        switch target {
        case .whoop:
            model.importWhoop(url: url)
        case .appleHealth:
            model.importAppleHealth(url: url)
        }
    }

    private enum ImportTarget {
        case whoop
        case appleHealth

        var allowedContentTypes: [UTType] {
            // See DataSourcesView: `.folder` is a macOS-only affordance (pick an unzipped export
            // directory). On iOS it greys out the .zip in the Files picker (issue #179), so iOS
            // offers only the concrete file types.
            switch self {
            case .whoop:
                #if os(macOS)
                return [.zip, .folder]
                #else
                return [.zip]
                #endif
            case .appleHealth:
                #if os(macOS)
                return [.zip, .xml, .folder]
                #else
                return [.zip, .xml]
                #endif
            }
        }
    }
}

// MARK: - 6 · Notifications

private struct NotificationsStep: View {
    var body: some View {
        StepPage(icon: "bell.badge.fill", tint: StrandPalette.settingsRed,
                 title: String(localized: "Notifications"),
                 message: String(localized: "Your smart alarm and nudges tap your wrist."))
    }
}

// MARK: - 7 · Done

private struct DoneStep: View {
    var body: some View {
        StepPage(icon: "checkmark.circle.fill", tint: StrandPalette.settingsGreen,
                 title: String(localized: "You're All Set"),
                 message: String(localized: "Welcome to NOOP."))
    }
}

// MARK: - Preview

#if DEBUG
private struct OnboardingPreview: View {
    @StateObject private var model = AppModel()
    var body: some View {
        OnboardingWizard(onFinished: {})
            .environmentObject(model)
            .environmentObject(model.live)
            .environmentObject(model.profile)
            .frame(width: 1100, height: 780)
    }
}

#Preview("Onboarding") { OnboardingPreview() }
#endif
