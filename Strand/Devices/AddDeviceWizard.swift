//  AddDeviceWizard.swift
//  NOOP · Devices → Add Device — pairing as Apple's pairing card does it: one step per sheet, a big device
//  glyph, a title with at most one line under it, one capsule button, ✕ in the corner.
//
//  Different bands pair completely differently, so the first step asks the device TYPE, then runs the
//  right scan/register path for it:
//    • WHOOP 4.0 / 5.0 (MG) → BLEManager's present-scan (`model.presentWhoopScan(model:)`), listing
//      `ble.discoveredWhoops` (a present-only mode that never auto-connects).
//    • Heart-rate strap / Garmin broadcast → its own isolated `StandardHRSource` (0x180D).
//    • Gym equipment → `FTMSSource`; Amazfit / Mi Band → `HuamiHRSource`.
//    • Oura → the factory-reset-and-adopt sub-flow with its two irreversible gates.
//  Registration goes through `model.registerDevice(_:makeActive:)` → DeviceRegistry; the SourceCoordinator
//  reacts and connects. The wizard never touches BLEManager beyond the AppModel pass-throughs.

import SwiftUI
import StrandDesign
import WhoopStore
import OuraProtocol

struct AddDeviceWizard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @Environment(\.dynamicTypeSize) private var dts
    let onClose: () -> Void

    // MARK: Flow

    /// What the user is adding. Drives the prep copy AND which scan/register path runs.
    enum DeviceType: Identifiable, Hashable {
        case whoop5mg
        case whoop4
        case hrStrap
        case gymEquipment
        // EXPERIMENTAL tier — best-effort, clean-room, can't be hardware-verified here. Each fails to an
        // honest message and never fabricates data.
        case amazfit       // Amazfit / Zepp incl. Helio (Huami custom or standard HR)
        case miBand        // Xiaomi Mi Band (Huami; no-auth live HR path, honest message if auth needed)
        case garmin        // Garmin watch (standard Broadcast HR path + an enable hint)
        case oura          // Oura ring (factory-reset-and-adopt: NOOP installs its own key, becomes owner)
        var id: Self { self }

        var isWhoop: Bool { self == .whoop4 || self == .whoop5mg }
        var whoopModel: WhoopModel? {
            switch self {
            case .whoop4:   return .whoop4
            case .whoop5mg: return .whoop5mg
            default:        return nil
            }
        }

        /// True for the EXPERIMENTAL tier (shown under a clearly-labelled "Experimental" heading).
        var isExperimental: Bool {
            switch self {
            case .amazfit, .miBand, .garmin, .oura: return true
            default:                                return false
            }
        }

        /// The experimental-tier brand this type registers as, or nil for the non-experimental types
        /// (WHOOP / generic strap / gym). Bridges the wizard's type picker to the `DeviceBrandCatalog`
        /// facts (stored brand string, `sourceKind`, id prefix) so those are no longer hardcoded per branch.
        var experimentalBrand: ExperimentalBrand? {
            switch self {
            case .amazfit: return .amazfit
            case .miBand:  return .miBand
            case .garmin:  return .garmin
            case .oura:    return .oura
            default:       return nil
            }
        }
    }

    enum Step { case type, prep, pick, confirm }

    /// The Oura factory-reset-and-adopt sub-flow's own step machine (section 2 of the onboarding UX spec).
    /// The Oura type does NOT use the generic prep/pick/confirm shape: it owns this machine, entered from the
    /// type list. PARITY: byte-for-byte the same step set + copy as the Android `OuraStep`.
    ///   - gate     What you get / what you lose + the irreversible red consent gate (or the Advanced key field).
    ///   - prep     Factory-reset the ring in the Oura app first (single-owner warning).
    ///   - pick     Live scan + pick a ring; an unreset ring surfaces honestly.
    ///   - confirm  Detected generation + per-gen capability checklist + the SECOND destructive "Take over" gate.
    ///   - adopting Honest key-install progress (no fake percent), driven by the live source's adopt phase.
    ///   - failed   An honest dead-end when adoption fails, with the file-import + Advanced-key fallbacks.
    enum OuraStep { case gate, prep, pick, confirm, adopting, failed }

    @State private var step: Step = .type
    @State private var type: DeviceType?
    /// The Oura sub-flow step (only meaningful while `type == .oura`). Reset to `.gate` on each Oura entry.
    @State private var ouraStep: OuraStep = .gate
    /// The destructive "Take over this ring?" confirm alert (the SECOND irreversible gate, after the consent
    /// tick). Mirrors the Android `ouraConfirmAdopt`. Only the standard adopt path raises it; the Advanced
    /// key path is non-destructive and skips it.
    @State private var ouraConfirmAdopt = false

    // The chosen strap, in whichever shape its path produces.
    /// A WHOOP picked from `discoveredWhoops` (uuid / advertised name / rssi).
    @State private var pickedWhoop: (uuid: String, name: String, rssi: Int)?
    /// A generic HR strap picked from the StandardHRSource scan.
    @State private var pickedStrap: StandardHRSource.DiscoveredStrap?
    /// An FTMS gym machine picked from the FTMSSource scan.
    @State private var pickedMachine: FTMSSource.DiscoveredMachine?
    /// An EXPERIMENTAL Huami device (Amazfit / Zepp / Mi Band) picked from the HuamiHRSource scan.
    @State private var pickedHuami: HuamiHRSource.DiscoveredDevice?
    /// An EXPERIMENTAL Oura ring picked from the OuraLiveSource scan, plus its detected generation
    /// (best-effort from the advertised name; the user confirms by picking). The `gen` here defaults to
    /// `.gen3` when the scan couldn't guess one, so the registered command set is always usable.
    @State private var pickedOura: (ring: OuraLiveSource.DiscoveredRing, gen: OuraRingGen)?

    @State private var nameDraft = ""
    /// The Apple Watch's own setup (Apple Health permissions), opened from the type list.
    @State private var showWatchSetup = false
    /// After registering, ask whether to make the new device active.
    @State private var askMakeActive = false

    /// The mandatory irreversible-consent gate (Oura factory-reset-and-adopt). The user must tick this
    /// before the wizard will scan, because adoption installs NOOP's key and the Oura app stops working
    /// with the ring. Mirrors the spec's red `statusCritical` gate. Reset whenever the type changes.
    @State private var ouraConsented = false
    /// The Advanced "I already have my ring's key" power-user path: when true, the prep step swaps to a
    /// hex-key field and we authenticate with the supplied key WITHOUT a factory reset (the Oura app keeps
    /// working). Off by default; only the small Advanced link on the gate turns it on.
    @State private var ouraAdvancedKeyMode = false
    /// The 32-hex-character ring key typed on the Advanced path. Validated to 16 bytes before scan.
    @State private var ouraKeyDraft = ""

    /// Discovery-only HR source for the strap path. Never persists (no-op closure) and is never asked
    /// to `connect` — we only read its `@Published discovered` / `scanning` while scanning. Built once.
    @StateObject private var hrScanner: StandardHRSource
    /// Discovery-only FTMS source for the gym-equipment path. `feedsLive: false` so it never writes
    /// LiveState; we only read its `discovered` / `scanning` while scanning. Built once.
    @StateObject private var ftmsScanner: FTMSSource
    /// Discovery-only EXPERIMENTAL Huami scanner (Amazfit / Zepp / Mi Band). `feedsLive: false`, never
    /// persists; the wizard only reads its `discovered` / `scanning`. Built once.
    @StateObject private var huamiScanner: HuamiHRSource
    /// Discovery-only EXPERIMENTAL Oura scanner. A real `OuraLiveSource` built in discovery-only mode
    /// (`feedsLive: false`, deviceId "scan-preview", no-op persist, no install key), so the wizard only reads
    /// its `@Published discovered` / `scanning` / `needsPairing` while scanning. The chosen ring is adopted
    /// for real on `finishAdd`, where the registered `PairedDevice` carries the ring generation. Built once.
    @StateObject private var ouraScanner: OuraLiveSource

    /// - Parameter startAt: DEBUG-only deep-link into a specific (type, step) so a seeded simulator build
    ///   can screenshot one wizard step deterministically (e.g. the Oura onboarding gate) without tapping
    ///   through. nil in production: the wizard starts on the type list. Pre-seeds the `@State` so the first
    ///   render is already on that step.
    init(live: LiveState, onClose: @escaping () -> Void,
         startAt: (type: DeviceType, step: Step)? = nil) {
        self.onClose = onClose
        if let startAt {
            _type = State(initialValue: startAt.type)
            _step = State(initialValue: startAt.step)
        }
        // Route each throwaway scanner's diagnostics into the SAME exported strap log the active source
        // path uses (issue #421 parity), so a tester's wizard scan, including the Oura discovery scan and
        // any honest needs-pairing outcome, is captured in a shared debug bundle. The sources already
        // self-prefix their lines ("HR-strap: " / "FTMS: " / "Huami: " / "Oura: "); we add the same
        // "[HH:mm:ss]" stamp AppModel's `straplog` uses so wizard lines read identically. Each source is
        // @MainActor and only calls this from the main actor, so the forward into @MainActor LiveState is
        // safe. Privacy-safe: statuses / service UUIDs / counts only, never a device address.
        let wizardLog: (String) -> Void = { line in
            MainActor.assumeIsolated {
                live.append(log: "[\(AppModel.logTimeFormatter.string(from: Date()))] \(line)")
            }
        }
        _hrScanner = StateObject(wrappedValue: StandardHRSource(
            live: live, deviceId: "scan-preview", persist: { _ in }, log: wizardLog))
        _ftmsScanner = StateObject(wrappedValue: FTMSSource(live: live, log: wizardLog, feedsLive: false))
        _huamiScanner = StateObject(wrappedValue: HuamiHRSource(
            live: live, deviceId: "scan-preview", log: wizardLog, feedsLive: false))
        // Discovery-only Oura source: gen defaults to gen3 for the scan-preview command clamp (the real
        // gen is fixed once the user picks), no install key (we never auth during discovery), and
        // `feedsLive: false` so it never writes LiveState or persists. Same shared strap-log sink (#421).
        _ouraScanner = StateObject(wrappedValue: OuraLiveSource(
            live: live, deviceId: "scan-preview", ringGen: .gen3, authKey: { nil },
            persist: { _ in }, log: wizardLog, feedsLive: false))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: ""))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    if showBack {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: goBack) { Image(systemName: "chevron.left") }
                                .barGlyph()
                                .accessibilityLabel(Text("Back"))
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        SheetCloseButton { stopAllScans(); onClose() }
                    }
                }
        }
        #if os(iOS)
        .presentationDetents(isList || dts.isAccessibilitySize ? [.large] : [.height(Self.cardHeight), .large])
        .presentationCornerRadius(40)
        #else
        .frame(minWidth: 440, minHeight: 620)
        #endif
        // Stop whichever scan is live whenever the sheet goes away, so no central keeps scanning.
        .onDisappear { stopAllScans() }
        // After adding, offer to make the new device active (generic non-Oura paths only).
        .alert("Make this your active device?", isPresented: $askMakeActive) {
            Button("Not now", role: .cancel) { finishAdd(makeActive: false) }
            Button("Make active") { finishAdd(makeActive: true) }
        } message: {
            Text("It will provide your live data. You can change this any time.")
        }
        // The SECOND irreversible gate (after the consent toggle): grants adopt consent and registers the
        // ring active; the live source then runs the one-time key install.
        .alert("Take over this ring?", isPresented: $ouraConfirmAdopt) {
            Button("Cancel", role: .cancel) { }
            Button("Take over", role: .destructive) { commitOuraAdopt() }
        } message: {
            Text("The Oura app will no longer work with this ring. NOOP can't undo this.")
        }
        // Drive the Adopting step to success (streaming → close) or to the honest Failed step. Only acts
        // while Adopting, so a later steady-state needs-pairing never reopens this.
        .onChange(of: model.ouraAdoptPhase) { phase in
            guard type == .oura, ouraStep == .adopting else { return }
            switch phase {
            case .streaming:        stopAllScans(); onClose()
            case .failed:           ouraStep = .failed
            case .idle, .installingKey: break
            }
        }
        .onChange(of: model.ouraNeedsPairing) { msg in
            guard type == .oura, ouraStep == .adopting, msg != nil else { return }
            ouraStep = .failed
        }
        #if os(iOS)
        .sheet(isPresented: $showWatchSetup) {
            AppleWatchSetupView(onClose: { showWatchSetup = false; onClose() })
        }
        #endif
    }

    /// The pairing card's height, as the AirPods card rises part-way up the screen.
    private static let cardHeight: CGFloat = 600

    /// Steps that list things take the whole sheet; the rest are a card.
    private var isList: Bool {
        if type == .oura { return ouraStep == .pick || (ouraStep == .gate && ouraAdvancedKeyMode) }
        return step == .type || step == .pick || type == nil
    }

    @ViewBuilder private var content: some View {
        if type == .oura {
            switch ouraStep {
            case .gate:     if ouraAdvancedKeyMode { ouraKeyStep } else { ouraGateStep }
            case .prep:     ouraPrepStep
            case .pick:     ouraPickStep
            case .confirm:  ouraConfirmStep
            case .adopting: ouraAdoptingStep
            case .failed:   ouraFailedStep
            }
        } else {
            switch step {
            case .type:    typeStep
            case .prep:    prepStep
            case .pick:    pickStep
            case .confirm: confirmStep
            }
        }
    }

    /// Back on every step but the first, and never while a ring's key install is in flight.
    private var showBack: Bool {
        if type == .oura { return ouraStep != .adopting }
        return step != .type
    }

    // MARK: Type

    private var typeStep: some View {
        Form {
            Section {
                PairingTitle(title: "Add Device")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                typeRow(.whoop5mg)
                typeRow(.whoop4)
            } header: {
                Text(verbatim: "WHOOP")
            }
            Section {
                typeRow(.hrStrap)
                typeRow(.gymEquipment)
                #if os(iOS)
                // The watch reaches NOOP through Apple Health, so it has its own setup, not a scan.
                Button { showWatchSetup = true } label: {
                    typeLabel(title: "Apple Watch", art: .appleWatch)
                }
                .buttonStyle(.plain)
                #endif
            } header: {
                Text("Other")
            }
            Section {
                typeRow(.oura)
                typeRow(.amazfit)
                typeRow(.miBand)
                typeRow(.garmin)
            } header: {
                Text("Beta")
            }
        }
        .settingsForm()
    }

    private func typeRow(_ t: DeviceType) -> some View {
        Button { choose(t) } label: { typeLabel(title: typeTitle(t), art: art(t)) }
            .buttonStyle(.plain)
    }

    private func typeLabel(title: String, art: DeviceArtworkKind) -> some View {
        HStack(spacing: 12) {
            DeviceArtwork(kind: art, size: 40)
            Text(verbatim: title)
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(StrandFont.pro(13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .contentShape(Rectangle())
    }

    private func choose(_ t: DeviceType) {
        type = t
        nameDraft = ""
        // The Oura adopt gate is destructive, so every fresh entry re-requires the consent and clears any
        // stale Advanced-key / adopt state.
        if t == .oura {
            ouraConsented = false
            ouraAdvancedKeyMode = false
            ouraKeyDraft = ""
            ouraConfirmAdopt = false
            pickedOura = nil
            ouraStep = .gate
        } else {
            step = .prep
        }
    }

    // MARK: Prep

    @ViewBuilder private var prepStep: some View {
        if let type {
            PairingCard(title: typeTitle(type), detail: prepLine(type), art: art(type), beta: type.isExperimental) {
                PairingButton(title: "Find") {
                    startScan(for: type)
                    step = .pick
                }
            }
        }
    }

    /// The one thing to do before a scan — the step most pairings fail on.
    private func prepLine(_ t: DeviceType) -> LocalizedStringKey {
        switch t {
        case .whoop4:       return "Put it on and close the WHOOP app."
        case .whoop5mg:     return "Unpair it in the WHOOP app, then put it in pairing mode."
        case .hrStrap:      return "Put it on so it wakes up."
        case .gymEquipment: return "Start moving so the machine turns on Bluetooth."
        case .amazfit:      return "Close the Zepp app."
        case .miBand:       return "Close the Mi Fitness app."
        case .garmin:       return "Turn on Broadcast Heart Rate on the watch."
        case .oura:         return "Reset the ring in the Oura app, then close it."
        }
    }

    private func art(_ t: DeviceType) -> DeviceArtworkKind {
        switch t {
        case .whoop4, .whoop5mg: return .whoop(registryModel: t.whoopModel?.rawValue)
        case .amazfit, .miBand: return .wristband
        case .hrStrap:      return .heartRateStrap
        case .gymEquipment: return .gymMachine
        case .garmin:       return .sportsWatch
        case .oura:         return .ring
        }
    }

    // MARK: Pick

    @ViewBuilder private var pickStep: some View {
        if let type {
            if type.isWhoop {
                WhoopPickList(ble: model.ble) { strap in
                    pickedWhoop = strap
                    pickedStrap = nil
                    pickedMachine = nil
                    pickedHuami = nil
                    nameDraft = strap.name.isEmpty ? typeTitle(type) : strap.name
                    model.stopWhoopScan()
                    step = .confirm
                } onRescan: {
                    model.presentWhoopScan(model: type.whoopModel ?? .whoop4)
                }
            } else if type == .gymEquipment {
                FTMSPickList(scanner: ftmsScanner) { machine in
                    pickedMachine = machine
                    clearOtherPicks(except: .gymEquipment)
                    nameDraft = machine.name
                    ftmsScanner.stopScan()
                    step = .confirm
                } onRescan: {
                    ftmsScanner.scan()
                }
            } else if type == .amazfit || type == .miBand {
                HuamiPickList(scanner: huamiScanner) { dev in
                    pickedHuami = dev
                    clearOtherPicks(except: type)
                    nameDraft = dev.name
                    huamiScanner.stopScan()
                    step = .confirm
                } onRescan: {
                    huamiScanner.scan()
                }
            } else {
                // Heart-rate strap AND Garmin (Broadcast HR is the standard 0x180D path).
                HRPickList(scanner: hrScanner) { strap in
                    pickedStrap = strap
                    clearOtherPicks(except: type)
                    nameDraft = strap.name
                    hrScanner.stopScan()
                    step = .confirm
                } onRescan: {
                    hrScanner.scan()
                }
            }
        }
    }

    /// Clear every "picked" selection except the one for `keep`'s path, so re-entering the pick step or
    /// switching device types never leaves a stale pick of another shape.
    private func clearOtherPicks(except keep: DeviceType) {
        if keep.isWhoop == false { pickedWhoop = nil }
        switch keep {
        case .hrStrap, .garmin:    pickedHuami = nil; pickedMachine = nil; pickedOura = nil
        case .gymEquipment:        pickedStrap = nil; pickedHuami = nil; pickedOura = nil
        case .amazfit, .miBand:    pickedStrap = nil; pickedMachine = nil; pickedOura = nil
        case .oura:                pickedStrap = nil; pickedMachine = nil; pickedHuami = nil
        default:                   pickedStrap = nil; pickedMachine = nil; pickedHuami = nil; pickedOura = nil
        }
    }

    // MARK: Confirm

    private var confirmStep: some View {
        PairingCard(title: confirmAdvertisedName, detail: nil, art: type.map(art) ?? .heartRateStrap,
                    beta: type?.isExperimental == true) {
            PairingNameField(text: $nameDraft)
            PairingButton(title: "Connect") { askMakeActive = true }
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var confirmName: String {
        let n = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? confirmAdvertisedName : n
    }

    private var confirmAdvertisedName: String {
        if let pickedWhoop { return pickedWhoop.name.isEmpty ? (type.map(typeTitle) ?? String(localized: "Device")) : pickedWhoop.name }
        if let pickedStrap { return pickedStrap.name }
        if let pickedMachine { return pickedMachine.name }
        if let pickedHuami { return pickedHuami.name }
        if let pickedOura { return pickedOura.ring.name }
        return type.map(typeTitle) ?? String(localized: "Device")
    }

    // MARK: Oura — factory-reset-and-adopt

    /// The honest gate: what taking the ring over costs, a consent toggle, then Continue. The two
    /// non-destructive lanes (file import, the user's own key) stay one tap away.
    /// The two lanes side by side, one under the other at accessibility sizes.
    private var laneLayout: AnyLayout {
        dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 20))
    }

    private var ouraGateStep: some View {
        PairingCard(title: typeTitle(.oura), detail: "NOOP installs its own key on the ring. The Oura app stops working with it.",
                    art: .ring, beta: true) {
            Toggle(isOn: $ouraConsented) {
                Text("I understand this can't be undone")
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .tint(StrandPalette.settingsRed)
            .padding(.horizontal, 4)
            PairingButton(title: "Continue") { ouraStep = .prep }
                .disabled(!ouraConsented)
            laneLayout {
                // Keep the Oura app and import a file instead.
                Button("Import a File") { stopAllScans(); onClose() }
                Button("I Have a Key") { ouraAdvancedKeyMode = true }
            }
            .font(StrandFont.pro(15))
            .buttonStyle(.plain)
            .foregroundStyle(StrandPalette.accent)
        }
    }

    private var ouraPrepStep: some View {
        PairingCard(title: typeTitle(.oura), detail: prepLine(.oura), art: .ring, beta: true) {
            PairingButton(title: "Find") {
                startScan(for: .oura)
                ouraStep = .pick
            }
        }
    }

    /// The Advanced path: authenticate with the user's own 16-byte key, no reset — the Oura app keeps
    /// working. Validates 32 hex characters before Scan.
    private var ouraKeyStep: some View {
        Form {
            Section {
                PairingTitle(title: "Ring Key", detail: "32 hex characters. NOOP keeps it on this device only.")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                TextField(text: $ouraKeyDraft, prompt: Text(verbatim: "0123456789abcdef0123456789abcdef")) { EmptyView() }
                    .font(StrandFont.mono)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityLabel("Ring key, 32 hexadecimal characters")
            } footer: {
                if !ouraKeyDraft.isEmpty && ouraKeyBytes == nil {
                    Text("That is not a 32-character hex key.").foregroundStyle(StrandPalette.settingsRed)
                }
            }
            Section {
                Button("Find") {
                    startScan(for: .oura)
                    ouraStep = .pick
                }
                .disabled(ouraKeyBytes == nil)
            }
        }
        .settingsForm()
    }

    private var ouraPickStep: some View {
        OuraPickList(scanner: ouraScanner,
                     onSelect: { ring in
                         let gen = ring.detectedGen ?? .gen3
                         pickedOura = (ring: ring, gen: gen)
                         clearOtherPicks(except: .oura)
                         nameDraft = String(localized: "Oura ring")
                         ouraScanner.stopScan()
                         ouraStep = .confirm
                     },
                     onRescan: { ouraScanner.scan() },
                     onUseImport: {
                         ouraScanner.stop()
                         onClose()
                     })
    }

    /// The detected generation, a name, then the adopt action: the red "Take Over" (which raises the
    /// SECOND irreversible confirm) on the standard path, a plain Connect on the non-destructive key path.
    private var ouraConfirmStep: some View {
        PairingCard(title: (pickedOura?.gen ?? .gen3).displayName, detail: nil, art: .ring, beta: true) {
            PairingNameField(text: $nameDraft)
            if ouraAdvancedKeyMode {
                PairingButton(title: "Connect") { finishAdvancedOura() }
            } else {
                PairingButton(title: "Take Over Ring", destructive: true) { ouraConfirmAdopt = true }
            }
        }
    }

    /// Shown ONLY while a real key install is in flight; the live source's adopt phase drives it on.
    private var ouraAdoptingStep: some View {
        PairingCard(title: typeTitle(.oura), detail: "Keep the ring close. Don't open the Oura app.", art: .ring, beta: true) {
            ProgressView().controlSize(.large).padding(.bottom, 8)
        }
    }

    /// An honest dead-end, never a fabricated success: the source's own message, Try Again, file import.
    private var ouraFailedStep: some View {
        PairingCard(title: "Couldn't Take Over the Ring", detail: nil, art: .ring, beta: true) {
            Text(verbatim: model.ouraNeedsPairing ?? String(localized: "Reset the ring in the Oura app, close it, and try again. The ring isn't damaged: re-pair it in the Oura app to recover it."))
                .font(StrandFont.pro(15))
                .foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            PairingButton(title: "Try Again") {
                pickedOura = nil
                ouraScanner.scan()
                ouraStep = .pick
            }
            Button("Import a File") { ouraScanner.stop(); onClose() }
                .font(StrandFont.pro(15))
                .buttonStyle(.plain)
                .foregroundStyle(StrandPalette.accent)
        }
    }

    /// The Advanced key parsed into 16 raw bytes, or nil when it is not exactly 32 hex characters.
    private var ouraKeyBytes: Data? {
        let hex = ouraKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hex.count == OuraKeyStore.keyLength * 2 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(OuraKeyStore.keyLength)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        return Data(bytes)
    }

    // MARK: Actions

    private func goBack() {
        // The Oura type walks its own step machine; back falls out to the type list from the gate.
        if type == .oura {
            ouraGoBack()
            return
        }
        switch step {
        case .type:    break
        case .prep:    step = .type
        case .pick:    stopAllScans(); step = .prep
        case .confirm:
            // Re-enter the pick step and restart its scan so the user can choose a different device.
            if let type { startScan(for: type) }
            pickedWhoop = nil; pickedStrap = nil; pickedMachine = nil; pickedHuami = nil; pickedOura = nil
            step = .pick
        }
    }

    /// Back inside the Oura adopt sub-flow. Adopting has no meaningful back (a key install is in flight, and
    /// `showBack` already hides it there); from Failed, back returns to the pick step to try again, so the
    /// user is never trapped. Mirrors the Android `ouraGoBack`.
    private func ouraGoBack() {
        switch ouraStep {
        case .gate:
            // From the Advanced key field, back returns to the standard consent gate; from the standard gate,
            // back exits to the device-type list.
            if ouraAdvancedKeyMode {
                ouraAdvancedKeyMode = false
                ouraKeyDraft = ""
            } else {
                type = nil
                ouraConsented = false
            }
        case .prep:
            ouraStep = .gate
        case .pick:
            ouraScanner.stop()
            pickedOura = nil
            ouraStep = ouraAdvancedKeyMode ? .gate : .prep
        case .confirm:
            ouraScanner.scan()
            pickedOura = nil
            ouraStep = .pick
        case .adopting, .failed:
            ouraScanner.scan()
            pickedOura = nil
            ouraStep = .pick
        }
    }

    private func startScan(for type: DeviceType) {
        switch type {
        case .whoop4, .whoop5mg: model.presentWhoopScan(model: type.whoopModel ?? .whoop4)
        case .gymEquipment:      ftmsScanner.scan()
        case .amazfit, .miBand:  huamiScanner.scan()
        case .oura:              ouraScanner.scan()
        // Heart-rate strap AND Garmin both use the standard 0x180D scanner (Garmin Broadcast HR).
        case .hrStrap, .garmin:  hrScanner.scan()
        }
    }

    private func stopAllScans() {
        model.stopWhoopScan()
        hrScanner.stopScan()
        ftmsScanner.stopScan()
        huamiScanner.stopScan()
        ouraScanner.stop()
    }

    /// Build the right `PairedDevice` for the chosen path, register it, optionally activate, then close.
    private func finishAdd(makeActive: Bool) {
        stopAllScans()
        let now = Int(Date().timeIntervalSince1970)
        let name = confirmName
        let device: PairedDevice

        if let pickedWhoop, let type, let wm = type.whoopModel {
            // WHOOP: honest live capability set (no calibrated SpO₂ % — import-only; #548);
            // id namespaced by uuid; model "4.0" / "5.0 MG". Steps only on 5.0/MG.
            let modelLabel = (wm == .whoop4) ? "4.0" : "5.0 MG"
            device = PairedDevice(
                id: "whoop-\(pickedWhoop.uuid)",
                brand: "WHOOP",
                model: modelLabel,
                nickname: name,
                peripheralId: pickedWhoop.uuid,
                sourceKind: .liveBLE,
                capabilities: WhoopLiveCapabilities.metrics(forModel: modelLabel),
                status: .paired,
                addedAt: now, lastSeenAt: now)
        } else if let pickedStrap {
            // Generic HR strap OR a Garmin broadcasting standard HR. Garmin's brand + id prefix come from
            // the catalog (via the type→brand bridge); it still stores `.liveBLE` (its live HR IS the
            // standard 0x180D path). A non-Garmin strap keeps the advertised-name brand guess + "strap"
            // prefix. Both are HR + HRV.
            let garmin = (type == .garmin) ? ExperimentalBrand.garmin : nil
            device = PairedDevice(
                id: "\(garmin?.idPrefix ?? "strap")-\(pickedStrap.id.uuidString)",
                brand: garmin?.displayBrand ?? brandGuess(from: pickedStrap.name),
                model: pickedStrap.name,
                nickname: name == pickedStrap.name ? nil : name,
                peripheralId: pickedStrap.id.uuidString,
                sourceKind: .liveBLE,
                capabilities: [.hr, .hrv],
                status: .paired,
                addedAt: now, lastSeenAt: now)
        } else if let pickedHuami {
            // EXPERIMENTAL Amazfit / Zepp / Mi Band. Brand string, id prefix, and the `.huami` routing all
            // come from the catalog via the type→brand bridge (was: `(type == .miBand) ? "Mi Band" : …`).
            // HR only (the Huami custom characteristic carries no R-R).
            let brand = type?.experimentalBrand ?? .amazfit
            device = PairedDevice(
                id: "\(brand.idPrefix)-\(pickedHuami.id.uuidString)",
                brand: brand.displayBrand,
                model: pickedHuami.name,
                nickname: name == pickedHuami.name ? nil : name,
                peripheralId: pickedHuami.id.uuidString,
                sourceKind: brand.sourceKind,
                capabilities: [.hr],
                status: .paired,
                addedAt: now, lastSeenAt: now)
        } else if let pickedMachine {
            // FTMS gym machine: a live machine + (when reported) HR session, recorded via the existing
            // live-workout path. sourceKind `.ftms` routes the SourceCoordinator to the FTMSSource.
            device = PairedDevice(
                id: "ftms-\(pickedMachine.id.uuidString)",
                brand: "Gym equipment",
                model: pickedMachine.name,
                nickname: name == pickedMachine.name ? nil : name,
                peripheralId: pickedMachine.id.uuidString,
                sourceKind: .ftms,
                capabilities: [.hr],
                status: .paired,
                addedAt: now, lastSeenAt: now)
        } else {
            // The Oura type commits through its own `commitOuraAdopt` / `finishAdvancedOura`, never here.
            onClose(); return
        }

        model.registerDevice(device, makeActive: makeActive)
        onClose()
    }

    // MARK: Oura commit (the two Oura paths, NOT the generic finishAdd)

    /// Build the `.oura` `PairedDevice` for the picked ring. sourceKind `.oura` routes the SourceCoordinator
    /// to the OuraLiveSource (its OWN central, never the WHOOP path). The generation rides `model`
    /// (OuraRingGen.from(model:) recovers it), and the capability set is gen-filtered. NOOP computes its own
    /// Charge/Rest from the ring's raw signals; it never reads Oura's encrypted readiness/sleep scores, and a
    /// signal it can't read stays "-" (honest-data invariant). Returns nil when no ring is picked.
    private func buildOuraDevice() -> PairedDevice? {
        guard let pickedOura else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let gen = pickedOura.gen
        let uuid = pickedOura.ring.id.uuidString
        let name = confirmName
        // Brand string, id prefix, and the `.oura` routing come from the catalog via the type→brand bridge.
        let oura = ExperimentalBrand.oura
        return PairedDevice(
            id: "\(oura.idPrefix)-\(uuid)",
            brand: oura.displayBrand,
            model: gen.displayName,
            nickname: name == String(localized: "Oura ring") ? nil : name,
            peripheralId: uuid,
            sourceKind: oura.sourceKind,
            capabilities: ouraCapabilities(for: gen),
            status: .paired,
            addedAt: now, lastSeenAt: now)
    }

    /// COMMIT the standard destructive adopt: reached ONLY from the "Take over" confirm (the SECOND
    /// irreversible gate, after the consent tick). It grants the coordinator adopt consent for THIS ring and
    /// registers it active; the live source then runs the one-time key install (s3.2). The wizard moves to its
    /// honest Adopting step, which the live source's adopt phase drives to success (close) or Failed. NO key is
    /// stored here: the live install persists NOOP's freshly-generated key only on an OK `0x25` ack.
    private func commitOuraAdopt() {
        guard let device = buildOuraDevice() else { onClose(); return }
        stopAllScans()
        ouraStep = .adopting
        model.adoptOuraRing(device)   // grants adopt consent + registers active; never prompts make-active
    }

    /// COMMIT the non-destructive Advanced-key path: persist the user-supplied 16-byte key, register the ring
    /// active (it authenticates with that key, no reset, no install), then close. This path NEVER installs a
    /// key and NEVER passes through the Adopting/Take-over gates. Validates the key first (the Scan button was
    /// already gated on a valid key, so this is belt-and-braces).
    private func finishAdvancedOura() {
        guard let device = buildOuraDevice(), let key = ouraKeyBytes else { onClose(); return }
        stopAllScans()
        OuraKeyStore.save(key, deviceId: device.id)
        // The user supplied their own key; this is their new live source. Register active (no adopt consent,
        // so the live source can NEVER install a key on this path).
        model.registerDevice(device, makeActive: true)
        onClose()
    }

    /// Map the protocol package's per-gen `OuraMetric` set onto the app's `Metric` set for registration.
    /// Gen3+ all expose the same dictionary, so this is currently uniform, but it is gen-filtered so a
    /// future gen-specific gate is a one-line change (per OURA_PROTOCOL.md s7.2). SpO2 registers as the
    /// `.spo2` capability for the RAW ADC signal only; NO absolute SpO2 percentage is ever claimed.
    private func ouraCapabilities(for gen: OuraRingGen) -> Set<Metric> {
        var caps: Set<Metric> = []
        for m in gen.capabilities {
            switch m {
            case .hr:       caps.insert(.hr)
            case .hrv:      caps.insert(.hrv)
            case .spo2:     caps.insert(.spo2)
            case .skinTemp: caps.insert(.skinTemp)
            case .sleep:    caps.insert(.sleep)
            }
        }
        return caps
    }

    // MARK: Copy / helpers

    private func typeTitle(_ t: DeviceType) -> String {
        switch t {
        case .whoop5mg:     return "WHOOP 5.0 / MG"
        case .whoop4:       return "WHOOP 4.0"
        case .hrStrap:      return String(localized: "Heart-rate strap")
        case .gymEquipment: return String(localized: "Gym equipment")
        case .amazfit:      return "Amazfit / Zepp"
        case .miBand:       return "Xiaomi Mi Band"
        case .garmin:       return String(localized: "Garmin watch")
        case .oura:         return String(localized: "Oura ring")
        }
    }

    /// Best-effort brand from the advertised name; neutral fallback for unknown straps. Delegates to the
    /// pure `DeviceBrandCatalog` (single source of truth), so the token table lives once.
    private func brandGuess(from name: String) -> String {
        DeviceBrandCatalog.spec(forAdvertisedName: name)?.brand ?? String(localized: "Heart-rate strap")
    }
}

// MARK: - Pairing card pieces

/// A step as Apple's pairing card lays it out: a bold centred title and at most one line under it, the
/// device's glyph in the middle, the action at the bottom.
private struct PairingCard<Actions: View>: View {
    let title: String
    let detail: LocalizedStringKey?
    let art: DeviceArtworkKind
    var beta = false
    @ViewBuilder var actions: Actions
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        // The card's detent is a fixed height; at accessibility sizes it scrolls instead of clipping.
        if dts.isAccessibilitySize {
            ScrollView { card }
                .background(StrandPalette.summaryCard.ignoresSafeArea())
        } else {
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            PairingTitle(title: title, detail: detail, beta: beta)
            Spacer(minLength: 16)
            DeviceArtwork(kind: art, size: 140)
            Spacer(minLength: 16)
            VStack(spacing: 14) { actions }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StrandPalette.summaryCard.ignoresSafeArea())
    }
}

private struct PairingTitle: View {
    let title: String
    var detail: LocalizedStringKey? = nil
    var beta = false

    var body: some View {
        VStack(spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(StrandFont.pro(28, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .multilineTextAlignment(.center)
            if beta {
                Text("Beta")
                    .font(StrandFont.pro(13, weight: .semibold))
                    .foregroundStyle(StrandPalette.settingsOrange)
            }
            if let detail {
                Text(detail)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// The one full-width capsule a pairing card ends with.
private struct PairingButton: View {
    let title: LocalizedStringKey
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.pro(17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        #if os(iOS)
        .buttonBorderShape(.capsule)
        #endif
        .controlSize(.large)
        .tint(destructive ? StrandPalette.settingsRed : StrandPalette.accent)
    }
}

/// The device's name, editable in place before it's added.
private struct PairingNameField: View {
    @Binding var text: String

    var body: some View {
        TextField("Name", text: $text)
            .font(StrandFont.pro(17))
            .multilineTextAlignment(.center)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(StrandPalette.deviceField, in: Capsule())
            .accessibilityLabel("Device name")
    }
}

// MARK: - Pick lists

/// "Choose Your Device": a searching spinner until something answers, then one row per device found,
/// strongest signal first.
private struct PickScreen<Rows: View>: View {
    let isEmpty: Bool
    var hint: LocalizedStringKey = "Make sure it's awake and not connected elsewhere."
    let onRescan: () -> Void
    @ViewBuilder var rows: Rows

    var body: some View {
        Form {
            Section {
                PairingTitle(title: "Choose Your Device")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                if isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching…").foregroundStyle(StrandPalette.textSecondary)
                    }
                } else {
                    rows
                }
            } footer: {
                if isEmpty { Text(hint) }
            }
            Section {
                Button("Search Again", action: onRescan)
            }
        }
        .settingsForm()
    }
}

private struct DiscoveredRow: View {
    let name: String
    let rssi: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(verbatim: name)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                SignalBars(rssi: rssi)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), signal \(SignalBars.level(for: rssi)) of 4")
    }
}

/// Observes BLEManager's present-scan, so the list grows as straps answer.
private struct WhoopPickList: View {
    @ObservedObject var ble: BLEManager
    let onSelect: ((uuid: String, name: String, rssi: Int)) -> Void
    let onRescan: () -> Void

    var body: some View {
        let found = ble.discoveredWhoops.sorted { $0.rssi > $1.rssi }
        PickScreen(isEmpty: found.isEmpty,
                   hint: "Not showing up? Close the WHOOP app.", onRescan: onRescan) {
            ForEach(found, id: \.uuid) { strap in
                DiscoveredRow(name: strap.name.isEmpty ? "WHOOP" : strap.name, rssi: strap.rssi) { onSelect(strap) }
            }
        }
    }
}

private struct HRPickList: View {
    @ObservedObject var scanner: StandardHRSource
    let onSelect: (StandardHRSource.DiscoveredStrap) -> Void
    let onRescan: () -> Void

    var body: some View {
        PickScreen(isEmpty: scanner.discovered.isEmpty, onRescan: onRescan) {
            ForEach(scanner.discovered.sorted { $0.rssi > $1.rssi }) { strap in
                DiscoveredRow(name: strap.name, rssi: strap.rssi) { onSelect(strap) }
            }
        }
    }
}

private struct FTMSPickList: View {
    @ObservedObject var scanner: FTMSSource
    let onSelect: (FTMSSource.DiscoveredMachine) -> Void
    let onRescan: () -> Void

    var body: some View {
        PickScreen(isEmpty: scanner.discovered.isEmpty, onRescan: onRescan) {
            ForEach(scanner.discovered.sorted { $0.rssi > $1.rssi }) { machine in
                DiscoveredRow(name: machine.name, rssi: machine.rssi) { onSelect(machine) }
            }
        }
    }
}

private struct HuamiPickList: View {
    @ObservedObject var scanner: HuamiHRSource
    let onSelect: (HuamiHRSource.DiscoveredDevice) -> Void
    let onRescan: () -> Void

    var body: some View {
        PickScreen(isEmpty: scanner.discovered.isEmpty, onRescan: onRescan) {
            ForEach(scanner.discovered.sorted { $0.rssi > $1.rssi }) { dev in
                DiscoveredRow(name: dev.name, rssi: dev.rssi) { onSelect(dev) }
            }
        }
    }
}

/// The ring pick step. A ring that won't answer (still Oura-owned, not reset, key rejected) shows the
/// source's honest message and the file-import lane instead of a list — never a fabricated reading.
private struct OuraPickList: View {
    @ObservedObject var scanner: OuraLiveSource
    let onSelect: (OuraLiveSource.DiscoveredRing) -> Void
    let onRescan: () -> Void
    let onUseImport: () -> Void

    var body: some View {
        if let msg = scanner.needsPairing {
            Form {
                Section {
                    PairingTitle(title: "Choose Your Device")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section { Text(verbatim: msg) }
                Section { Button("Import a File") { onUseImport() } }
            }
            .settingsForm()
        } else {
            PickScreen(isEmpty: scanner.discovered.isEmpty,
                       hint: "Not showing up? Reset the ring in the Oura app and close it.", onRescan: onRescan) {
                ForEach(scanner.discovered.sorted { $0.rssi > $1.rssi }) { ring in
                    DiscoveredRow(name: ring.name, rssi: ring.rssi) { onSelect(ring) }
                }
            }
        }
    }
}

// MARK: - Signal indicator

/// Four Wi-Fi-style bars from RSSI (negative dBm; closer to 0 is stronger). Coarse on purpose.
struct SignalBars: View {
    let rssi: Int

    static func level(for rssi: Int) -> Int {
        switch rssi {
        case (-55)...:    return 4
        case (-67)...:    return 3
        case (-80)...:    return 2
        case (-90)...:    return 1
        default:          return 0
        }
    }

    var body: some View {
        let level = Self.level(for: rssi)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(i < level ? StrandPalette.textSecondary : StrandPalette.hairlineStrong)
                    .frame(width: 3, height: 6 + CGFloat(i) * 3)
            }
        }
        .frame(width: 22, height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Add device wizard") {
    let model = AppModel()
    return AddDeviceWizard(live: model.live, onClose: {})
        .environmentObject(model)
        .environmentObject(model.live)
}
#endif
