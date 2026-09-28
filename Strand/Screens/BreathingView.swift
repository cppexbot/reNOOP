//  BreathingView.swift
//  NOOP · Breathe, laid out as Apple's Mindfulness: a card per mode (Breathe, Resonance, Calm) with a ▶,
//  and the options under them. A session runs full screen and dark around the Mindfulness flower — it
//  opens on the inhale and closes on the exhale, "Breathe in" / "Breathe out" under it, heart rate and
//  HRV small at the bottom — with ⌄ to put it away and ✕ to end. It ends on one summary card.
//
//  The strap both measures HRV (R-R) and buzzes, so the pace is felt as well as seen: one pulse on the
//  inhale, two on the exhale (`BreathProtocolPlayer.loops`), through the same `AppModel.buzz` every haptic
//  uses, gated by the Breathing haptics toggle. Resonance (find your pace) and Calm (a metronome just
//  below the heart) run in `BiofeedbackController`, unchanged; the passive stress check-in asks its one
//  question in a short sheet.
//
//  PERF: the page observes nothing that ticks. `BreathHub` owns the running session (published at most
//  once a second plus once per breath) and only the leaves read it — the running row, the cover and its
//  readouts — while `bpm` is read by the readouts and the Calm card alone.

import SwiftUI
import Foundation
import Combine
import AVFoundation
import StrandDesign
import StrandAnalytics

struct BreathingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BreathingPage(model: model, live: model.live)
    }
}

// MARK: - Choices

/// A pace from the catalog, or the pace the Resonance sweep locked.
enum BreathPace: Hashable {
    case catalog(String)
    case resonance

    var label: String {
        switch self {
        case .catalog(let id):
            return String(localized: String.LocalizationValue(BreathProtocolCatalog.protocolById(id)?.title ?? id))
        case .resonance:
            return String(localized: "Resonance")
        }
    }
}

enum BreathLength: Hashable, CaseIterable {
    case open, five, ten, fifteen

    var label: String {
        switch self {
        case .open: return String(localized: "No Limit")
        case .five: return String(localized: "5 min")
        case .ten: return String(localized: "10 min")
        case .fifteen: return String(localized: "15 min")
        }
    }

    var targetSeconds: Int? {
        switch self {
        case .open: return nil
        case .five: return 5 * 60
        case .ten: return 10 * 60
        case .fifteen: return 15 * 60
        }
    }

    static func from(recommendedMs: Int) -> BreathLength {
        switch recommendedMs {
        case ..<(7 * 60_000): return .five
        case ..<(12 * 60_000): return .ten
        default: return .fifteen
        }
    }
}

// MARK: - Page

private struct BreathingPage: View {
    /// Plain references: the page reads them without subscribing (see the PERF note above).
    let model: AppModel
    let live: LiveState

    @StateObject private var box = BreathHubBox()
    /// The passive check-in surface — the app injects its shared instance; this keeps one present otherwise.
    @StateObject private var fallbackNudge = StressNudgeCenter()
    @Environment(\.stressNudgeCenter) private var injectedNudge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Opt-in soft tone on each phase (rising in, falling out); ambient, so the silent switch mutes it.
    @AppStorage("breathe.audioCues") private var audioCues = false

    @State private var pace: BreathPace = .catalog("coherence_5_5")
    @State private var length: BreathLength = .ten
    @State private var showEdu = false
    @State private var askSweep = false
    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .title2) private var modeGlyphSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var flowerGlyphSize: CGFloat = 34

    private var hub: BreathHub { box.hub(model: model, live: live) }
    private var nudgeCenter: StressNudgeCenter { injectedNudge ?? fallbackNudge }
    private var lockedBpm: Double? { BiofeedbackPrefs.lockedPace }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BreathRunningRow(hub: hub)
                modeCard(title: "Breathe", detail: "\(pace.label) · \(length.label)",
                         tint: StrandPalette.healthRespiratory,
                         glyph: AnyView(BreathFlower(progress: 1, tint: StrandPalette.healthRespiratory).frame(width: flowerGlyphSize, height: flowerGlyphSize))) {
                    hub.startPaced(pace: pace, targetSeconds: length.targetSeconds, lockedBpm: lockedBpm,
                                   reduceMotion: reduceMotion, audio: audioCues)
                }
                modeCard(title: "Resonance",
                         detail: lockedBpm.map { String(localized: "Your pace · \(Self.bpmText($0)) br/min") }
                             ?? String(localized: "Find your pace"),
                         tint: StrandPalette.healthMind,
                         glyph: AnyView(Image(systemName: "waveform.path").font(.system(size: modeGlyphSize, weight: .semibold))
                             .foregroundStyle(StrandPalette.healthMind))) {
                    askSweep = true
                }
                BreathCalmCard(hub: hub, reduceMotion: reduceMotion)
                Text("Options")
                    .font(StrandFont.pro(22, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
                options
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle("Mindfulness")
        .background {
            BreathCoverHost(hub: hub)
            StressCheckInSheetHost(center: nudgeCenter) {
                // "Breathe now": one minute at the locked resonance pace (or 5.5, coherence).
                let bpm = lockedBpm ?? ResonanceEngine.fallbackBpm
                hub.startResonanceCue(bpm: bpm, cycles: max(1, Int(bpm.rounded())), reduceMotion: reduceMotion)
            }
            // rrSeq-keyed: equal consecutive packets both count (see RRPacketObserver.swift).
            BreathRRFeed(live: live) { hub.ingest($0) }
        }
        .onChangeCompat(of: pace) { newPace in
            if case .catalog(let id) = newPace, let proto = BreathProtocolCatalog.protocolById(id) {
                length = BreathLength.from(recommendedMs: proto.recommendedDurationMs)
            }
        }
        .onChangeCompat(of: audioCues) { on in
            // Spin the engine up the moment the pacer is wanted, so the first tone isn't lost to start-up.
            on ? hub.tones.activate() : hub.tones.deactivate()
        }
        // One realtime-HR count while the screen is up. A full-screen session hides this page without
        // leaving it, so the count and the running session survive the cover; leaving the screen ends both.
        .onAppear {
            guard !box.armed else { return }
            box.armed = true
            model.startRealtimeHR()
            if audioCues { hub.tones.activate() }
            #if DEBUG
            demoLaunch()
            #endif
        }
        .onDisappear {
            guard !hub.presented, box.armed else { return }
            box.armed = false
            model.stopRealtimeHR()
            hub.stopAll()
            hub.tones.deactivate()
        }
        .sheet(isPresented: $showEdu) { BreathEduSheet(pace: pace) { showEdu = false } }
        .confirmationDialog("Resonance", isPresented: $askSweep, titleVisibility: .hidden) {
            Button("Quick · ~7 min") { hub.startSweep(quick: true, reduceMotion: reduceMotion) }
            Button("Full · ~13 min") { hub.startSweep(quick: false, reduceMotion: reduceMotion) }
            if let bpm = lockedBpm {
                Button("Breathe at \(Self.bpmText(bpm)) br/min") {
                    pace = .resonance
                    hub.startPaced(pace: .resonance, targetSeconds: length.targetSeconds, lockedBpm: bpm,
                                   reduceMotion: reduceMotion, audio: audioCues)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    #if DEBUG
    /// DEBUG screenshots: `--breathe-demo session|summary` opens the session or its summary, and
    /// `--breathe-demo stress` raises the stress check-in.
    private func demoLaunch() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--breathe-demo"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "session":
            hub.startPaced(pace: pace, targetSeconds: length.targetSeconds, lockedBpm: lockedBpm,
                           reduceMotion: reduceMotion, audio: false)
        case "summary": hub.demoSummary()
        case "stress": nudgeCenter.present(fastRMSSD: 28, baselineRMSSD: 46)
        default: break
        }
    }
    #endif

    static func bpmText(_ bpm: Double) -> String { bpm.formatted(.number.precision(.fractionLength(1))) }

    // MARK: Cards

    private func modeCard(title: LocalizedStringKey, detail: String, tint: Color, glyph: AnyView,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BreathModeRow(title: title, detail: detail, tint: tint, glyph: glyph, enabled: true)
        }
        .buttonStyle(.plain)
    }

    private var options: some View {
        SummaryCard {
            VStack(spacing: 0) {
                Menu {
                    Picker("Pace", selection: $pace) {
                        Section {
                            ForEach(BreathProtocolCatalog.pickerProtocols.filter { $0.category != .presence }) { p in
                                Text(String(localized: String.LocalizationValue(p.title))).tag(BreathPace.catalog(p.id))
                            }
                        }
                        Section {
                            ForEach(BreathProtocolCatalog.pickerProtocols.filter { $0.category == .presence }) { p in
                                Text(String(localized: String.LocalizationValue(p.title))).tag(BreathPace.catalog(p.id))
                            }
                        }
                        if lockedBpm != nil {
                            Text(BreathPace.resonance.label).tag(BreathPace.resonance)
                        }
                    }
                    Divider()
                    Button { showEdu = true } label: { Label("About this pace", systemImage: "info.circle") }
                } label: {
                    optionRow("Pace", value: pace.label)
                }
                Divider().padding(.leading, 2)
                Menu {
                    Picker("Duration", selection: $length) {
                        ForEach(BreathLength.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } label: {
                    optionRow("Duration", value: length.label)
                }
                Divider().padding(.leading, 2)
                Toggle(isOn: $audioCues) {
                    Text("Audio cues")
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .tint(StrandPalette.accent)
                .padding(.vertical, 10)
            }
        }
    }

    private func optionRow(_ title: LocalizedStringKey, value: String) -> some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                             : AnyLayout(HStackLayout())
        return layout {
            Text(title)
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.textPrimary)
            if !dts.isAccessibilitySize { Spacer() }
            HStack {
                Text(value)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(dts.isAccessibilitySize ? nil : 1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(StrandFont.pro(12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// One Mindfulness card: the mode's glyph, its name and a line under it, and the ▶ that starts it.
private struct BreathModeRow: View {
    let title: LocalizedStringKey
    let detail: String
    let tint: Color
    let glyph: AnyView
    let enabled: Bool
    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .title3) private var glyphBox: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var playSize: CGFloat = 44

    var body: some View {
        Group {
            // At accessibility sizes the text takes the full width under the glyph and ▶.
            if dts.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        glyphView
                        Spacer(minLength: 8)
                        playButton
                    }
                    labels
                }
            } else {
                HStack(spacing: 14) {
                    glyphView
                    labels
                    Spacer(minLength: 8)
                    playButton
                }
            }
        }
        .padding(16)
        .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
        .opacity(enabled ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var glyphView: some View {
        glyph.frame(width: glyphBox, height: glyphBox)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.pro(20, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
            Text(detail)
                .font(StrandFont.pro(15))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(dts.isAccessibilitySize ? nil : 2)
        }
    }

    private var playButton: some View {
        Image(systemName: "play.fill")
            .font(StrandFont.pro(17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: playSize, height: playSize)
            .background(Circle().fill(enabled ? tint : StrandPalette.textTertiary))
            .accessibilityHidden(true)
    }
}

/// Calm: a felt rhythm just below the heart, so it needs a bonded strap and a resting-band heart rate.
/// Its own view because it reads `bpm` (≈1 Hz) and the bond.
private struct BreathCalmCard: View {
    @ObservedObject var hub: BreathHub
    let reduceMotion: Bool
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 24
    @AppStorage(HapticPrefs.breathing) private var breathingHaptics = true

    private var restingBand: Bool { model.bpm.map { $0 >= 55 && $0 <= 120 } ?? false }
    private var canRun: Bool { hub.controller.canBuzz && breathingHaptics && restingBand }

    var body: some View {
        Button { hub.startCalm(reduceMotion: reduceMotion) } label: {
            BreathModeRow(title: "Calm", detail: detail, tint: StrandPalette.healthBody,
                          glyph: AnyView(Image(systemName: "heart.fill").font(.system(size: glyphSize, weight: .semibold))
                              .foregroundStyle(StrandPalette.healthBody)),
                          enabled: canRun)
        }
        .buttonStyle(.plain)
        .disabled(!canRun)
    }

    private var detail: String {
        if !hub.controller.canBuzz { return String(localized: "Needs a connected strap") }
        if !breathingHaptics { return String(localized: "Turn on breathing haptics") }
        if !restingBand { return String(localized: "Waiting for a resting heart rate") }
        return String(localized: "3 min · a rhythm just below your pulse")
    }
}

/// A session put away with ⌄: its name and running clock, tap to bring it back.
private struct BreathRunningRow: View {
    @ObservedObject var hub: BreathHub

    var body: some View {
        if hub.kind != nil, !hub.presented {
            Button { hub.presented = true } label: {
                HStack(spacing: 12) {
                    BreathFlower(progress: 1, tint: StrandPalette.healthRespiratory).frame(width: 28, height: 28)
                    Text(hub.title)
                        .font(StrandFont.pro(17, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Text(BreathHub.clock(hub.seconds))
                        .font(StrandFont.pro(17, weight: .semibold).monospacedDigit())
                        .foregroundStyle(StrandPalette.healthRespiratory)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Image(systemName: "chevron.right")
                        .font(StrandFont.pro(13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .padding(16)
                .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Return to the session"))
        }
    }
}

/// Feeds live R-R packets to the hub. Observes `LiveState` itself so a packet re-renders only this.
private struct BreathRRFeed: View {
    @ObservedObject var live: LiveState
    let ingest: ([Int]) -> Void

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onRRPackets(live, perform: ingest)
            .accessibilityHidden(true)
    }
}

/// Presents the session full screen (a sheet on the Mac) whenever the hub asks for it.
private struct BreathCoverHost: View {
    @ObservedObject var hub: BreathHub
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            #if os(iOS)
            .fullScreenCover(isPresented: $hub.presented) {
                BreathSessionView(hub: hub, controller: hub.controller).environmentObject(model)
            }
            #else
            .sheet(isPresented: $hub.presented) {
                BreathSessionView(hub: hub, controller: hub.controller).environmentObject(model)
                    .frame(minWidth: 480, minHeight: 640)
            }
            #endif
    }
}

// MARK: - Session screen

/// The running session: always dark, the flower in the middle, the phase word under it, heart rate and HRV
/// small at the bottom; ⌄ puts it away, ✕ ends it. After the end, the summary card.
private struct BreathSessionView: View {
    @ObservedObject var hub: BreathHub
    @ObservedObject var controller: BiofeedbackController

    var body: some View {
        VStack(spacing: 0) {
            if let summary = hub.summary {
                BreathSummaryView(summary: summary) { hub.closeSummary() }
            } else {
                HStack {
                    RecordingButton(symbol: "chevron.down", size: 44, label: "Minimize") { hub.presented = false }
                    Spacer()
                    RecordingButton(symbol: "xmark", size: 44, label: "End") { hub.end() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer(minLength: 12)
                BreathFlower(progress: hub.progress, tint: StrandPalette.healthRespiratory)
                    .frame(width: 280, height: 280)
                    .opacity(hub.flowerOpacity)
                Text(hub.phaseWord)
                    .font(StrandFont.pro(34, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 36)
                    .padding(.horizontal, 24)
                    .animation(.easeInOut(duration: 0.3), value: hub.phaseWord)
                if hub.kind == .sweep {
                    sweepProgress.padding(.top, 14)
                }
                Spacer(minLength: 12)
                BreathReadouts(hub: hub, controller: controller)
                    .padding(.bottom, 24)
            }
        }
        // The flower's diameter is fixed; its words stop growing where the page still fits one screen.
        .dynamicTypeSize(...(hub.summary == nil ? DynamicTypeSize.xxxLarge : .accessibility5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var sweepProgress: some View {
        VStack(spacing: 8) {
            Text(controller.sweepLabel ?? String(localized: "Sweeping…"))
                .font(StrandFont.pro(15))
                .foregroundStyle(.white.opacity(0.6))
            ProgressView(value: controller.sweepProgress)
                .tint(StrandPalette.healthMind)
                .frame(width: 180)
        }
    }
}

/// Heart rate and HRV in small type with the session clock — its own view, so a beat redraws just this.
private struct BreathReadouts: View {
    @ObservedObject var hub: BreathHub
    @ObservedObject var controller: BiofeedbackController
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 22) {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill").foregroundStyle(StrandPalette.healthHeart)
                    Text(model.bpm.map(String.init) ?? "--")
                    if hub.kind == .calm, let target = controller.calmTargetBpm {
                        Image(systemName: "arrow.right").font(StrandFont.pro(12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(verbatim: "\(Int(target.rounded()))")
                    }
                }
                if hub.kind != .calm {
                    HStack(spacing: 5) {
                        Text("HRV").foregroundStyle(.white.opacity(0.6))
                        Text(hub.rmssd.map { "\(Int($0.rounded()))" } ?? "--")
                        Text("ms").foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .font(StrandFont.pro(17, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            Text(hub.clockLine)
                .font(StrandFont.pro(15).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The one card a session ends on: how long, the heart rate before and after, and what the session found.
private struct BreathSummaryView: View {
    let summary: BreathHub.Summary
    let onDone: () -> Void
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        if dts.isAccessibilitySize {
            ScrollView { card.padding(.top, 24) }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Spacer()
            BreathFlower(progress: 1, tint: StrandPalette.healthRespiratory)
                .frame(width: 72, height: 72)
            Text(summary.title)
                .font(StrandFont.pro(28, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 16)
            VStack(spacing: 0) {
                row(String(localized: "Time"), BreathHub.clock(summary.seconds))
                if let start = summary.hrStart, let end = summary.hrEnd {
                    Divider().overlay(Color.white.opacity(0.15))
                    row(String(localized: "Heart rate"), "\(start) → \(end) \(String(localized: "bpm"))")
                }
                ForEach(summary.lines, id: \.self) { line in
                    Divider().overlay(Color.white.opacity(0.15))
                    row(line.title, line.value)
                }
            }
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 28)
            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(StrandPalette.healthRespiratory))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Text(title).foregroundStyle(.white.opacity(0.6))
            if !dts.isAccessibilitySize { Spacer(minLength: 12) }
            Text(value).foregroundStyle(.white)
                .multilineTextAlignment(dts.isAccessibilitySize ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(StrandFont.pro(17))
        .padding(.vertical, 13)
    }
}

// MARK: - The flower

/// The Mindfulness flower: six translucent petals around the centre. At 0 they fold into one small bud;
/// at 1 they open into the full flower, turned a sixth. Driven by an animated `progress`, so a breath
/// is one transform animation, not a per-frame redraw.
struct BreathFlower: View, Animatable {
    var progress: CGFloat
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let petal = side * (0.28 + 0.22 * progress)
            // Never fully closed: at the end of an exhale the petals still show as a small bud.
            let reach = side * (0.05 + 0.2 * progress)
            ZStack {
                ForEach(0..<6) { i in
                    Circle()
                        .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: petal, height: petal)
                        .offset(y: -reach)
                        .rotationEffect(.degrees(Double(i) * 60))
                        // Petals add up to light where they overlap on the dark session; on a light page
                        // that would wash out to white, so there they simply layer.
                        .blendMode(scheme == .dark ? .plusLighter : .normal)
                        .opacity(scheme == .dark ? 0.42 : 0.4)
                }
            }
            .rotationEffect(.degrees(Double(progress) * 60))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The session model

/// Holds the page's `BreathHub`, built once from the environment's model on first use. Publishes nothing,
/// so owning it re-renders nothing.
@MainActor
private final class BreathHubBox: ObservableObject {
    private var made: BreathHub?
    /// Whether this screen holds its realtime-HR count (see the page's appear / disappear).
    var armed = false

    func hub(model: AppModel, live: LiveState) -> BreathHub {
        if let made { return made }
        let hub = BreathHub(model: model, live: live)
        made = hub
        return hub
    }
}

/// The session in progress, whichever mode runs it: the fixed-pace trainer (a catalog protocol, or the
/// locked resonance pace) walked here, or Resonance / Calm walked by `BiofeedbackController`. Everything
/// a session screen shows comes from here, so the cover, the running row and the summary never disagree.
@MainActor
final class BreathHub: ObservableObject {
    enum Kind: Equatable { case paced, resonance, sweep, calm }

    struct Line: Hashable { let title: String; let value: String }
    struct Summary: Equatable {
        let title: String
        let seconds: Int
        let hrStart: Int?
        let hrEnd: Int?
        let lines: [Line]
    }

    @Published private(set) var kind: Kind?
    @Published var presented = false
    @Published private(set) var summary: Summary?
    @Published private(set) var title = ""
    @Published private(set) var phase: BreathPhase = .inhale
    @Published private(set) var phaseLabel: String?
    /// The flower: 0 folded, 1 open. Set inside `withAnimation` for the stage's length.
    @Published private(set) var progress: CGFloat = 0
    /// Calm's beat under Reduce Motion, which pulses the flower's light instead of its size.
    @Published private(set) var flowerOpacity: Double = 1
    @Published private(set) var seconds = 0
    @Published private(set) var rmssd: Double?

    let controller: BiofeedbackController
    let tones = BreathTonePlayer()
    private unowned let model: AppModel

    // Fixed-pace trainer state.
    private var protocolStages: [BreathStage] = []
    private var guided = false
    private var targetSeconds: Int?
    private var stageIndex = 0
    private var breathCount = 0
    private var stageItem: DispatchWorkItem?
    private var secondTimer: AnyCancellable?
    private var reduceMotion = false
    private var audio = false
    private var hrStart: Int?

    // RMSSD over the latest R-R window.
    private let rrWindow = 30
    private var rrBuffer: [Int] = []
    private var baselineRmssd: Double?
    private var sessionRmssdSum = 0.0
    private var sessionRmssdCount = 0
    private var sessionRmssdPeak = 0.0

    private var subs: Set<AnyCancellable> = []
    /// Whether the controller has reported a running session since this hub started one — its `stop()`
    /// on start publishes `.none` first, which must not read as the end.
    private var controllerRunning = false

    init(model: AppModel, live: LiveState) {
        self.model = model
        self.controller = BiofeedbackController(model: model, live: live)
        // `sink`s run inside willSet: use the emitted values, not the controller's properties.
        controller.$session
            .sink { [weak self] session in self?.controllerSessionChanged(session) }
            .store(in: &subs)
        controller.$phase
            .sink { [weak self] phase in self?.controllerPhaseChanged(phase) }
            .store(in: &subs)
        controller.$elapsedSeconds
            .sink { [weak self] s in
                guard let self, let kind = self.kind, kind != .paced else { return }
                self.seconds = s
            }
            .store(in: &subs)
        controller.$calmBeat
            .dropFirst()
            .sink { [weak self] _ in self?.pulseCalm() }
            .store(in: &subs)
    }

    // MARK: Read-outs

    var phaseWord: String {
        switch kind {
        case .calm: return String(localized: "Follow the rhythm on your wrist")
        case .none: return ""
        default: break
        }
        if let phaseLabel, !phaseLabel.isEmpty { return String(localized: String.LocalizationValue(phaseLabel)) }
        switch phase {
        case .inhale: return String(localized: "Breathe in")
        case .hold: return String(localized: "Hold")
        case .exhale: return String(localized: "Breathe out")
        case .textOnly: return String(localized: "Follow the cue…")
        }
    }

    var clockLine: String {
        if kind == .paced, let targetSeconds { return "\(Self.clock(seconds)) / \(Self.clock(targetSeconds))" }
        return Self.clock(seconds)
    }

    static func clock(_ total: Int) -> String { String(format: "%d:%02d", total / 60, total % 60) }

    // MARK: Starting

    /// A fixed-pace session: the catalog protocol's stages (or the locked resonance pace, 40:60), paced by
    /// flower, buzz and optional tone; a guided protocol shows its name and runs the clock only.
    func startPaced(pace: BreathPace, targetSeconds: Int?, lockedBpm: Double?, reduceMotion: Bool, audio: Bool) {
        stopRunning()
        if controller.running { controller.stop() }
        self.reduceMotion = reduceMotion
        self.audio = audio
        self.targetSeconds = targetSeconds
        switch pace {
        case .resonance:
            let bpm = lockedBpm ?? ResonanceEngine.fallbackBpm
            let cycleMs = Int((60_000.0 / bpm).rounded())
            let inhaleMs = Int((Double(cycleMs) * BreathPacer.defaultInhaleFraction).rounded())
            protocolStages = [BreathStage(type: .inhale, durationMs: inhaleMs),
                              BreathStage(type: .exhale, durationMs: max(1, cycleMs - inhaleMs))]
            guided = false
        case .catalog(let id):
            let proto = BreathProtocolCatalog.protocolById(id)
            protocolStages = proto?.stages.filter { $0.durationMs > 0 } ?? []
            guided = proto?.mode == .guided
        }
        begin(.paced, title: pace.label)
        stageIndex = 0
        breathCount = 0
        baselineRmssd = rmssd
        sessionRmssdSum = 0
        sessionRmssdCount = 0
        sessionRmssdPeak = 0
        ScreenIdle.keepAwake(true)
        if guided {
            phase = .textOnly
            phaseLabel = pace.label
            if !reduceMotion { progress = 0.5 }
        } else {
            armStage(from: Date(), buzz: true)
        }
        secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    /// One minute at a resonance pace — the stress check-in's "Breathe now".
    func startResonanceCue(bpm: Double, cycles: Int, reduceMotion: Bool) {
        stopRunning()
        self.reduceMotion = reduceMotion
        begin(.resonance, title: String(localized: "Resonance"))
        controller.startResonanceSession(bpm: bpm, cycles: cycles)
    }

    /// The find-your-pace sweep: 3 paces (~7 min) or 6 (~13 min).
    func startSweep(quick: Bool, reduceMotion: Bool) {
        stopRunning()
        self.reduceMotion = reduceMotion
        begin(.sweep, title: String(localized: "Resonance"))
        controller.startSweep(quick: quick)
    }

    /// The below-HR metronome. The controller refuses without a bond and a resting-band HR; then this ends
    /// at once and the summary carries the controller's reason.
    func startCalm(reduceMotion: Bool) {
        stopRunning()
        self.reduceMotion = reduceMotion
        begin(.calm, title: String(localized: "Calm"))
        progress = 0.35
        controller.startCalmMe()
        if controller.session == .none { finish() }
    }

    private func begin(_ kind: Kind, title: String) {
        summary = nil
        controllerRunning = false
        self.kind = kind
        self.title = title
        phase = .inhale
        phaseLabel = nil
        seconds = 0
        flowerOpacity = 1
        hrStart = model.bpm
        presented = true
    }

    // MARK: Ending

    /// ✕: end whatever runs and show its summary.
    func end() {
        guard let kind else { return }
        if kind == .paced { finish() } else { controller.stop() }   // the controller's `.none` finishes it
    }

    /// Leave without a summary (the screen went away): stop everything, quietly — the controller always,
    /// as leaving Breathe always did (#769's stop-haptics clear).
    func stopAll() {
        stopRunning()
        controller.stop()
        presented = false
    }

    /// End the fixed-pace trainer if it runs, without a summary. (Starting a controller flow stops the
    /// controller's own previous flow itself.)
    private func stopRunning() {
        let was = kind
        kind = nil
        if was == .paced { stopPaced() }
    }

    func closeSummary() {
        summary = nil
        presented = false
    }

    private func finish() {
        guard let kind else { return }
        var lines: [Line] = []
        switch kind {
        case .paced:
            let outcome = stopPaced()
            if let outcome {
                lines.append(Line(title: String(localized: "HRV"),
                                  value: outcome == "—" ? String(localized: "Not enough R-R data") : outcome))
            }
        case .sweep:
            if let result = controller.lastSweep {
                lines.append(Line(title: String(localized: "Your pace"),
                                  value: result.didLock
                                      ? "\(result.lockedBpm.formatted(.number.precision(.fractionLength(1)))) \(String(localized: "br/min"))"
                                      : String(localized: "No pace found today")))
            }
        case .calm:
            if let outcome = controller.calmOutcome {
                lines.append(Line(title: String(localized: "Calm"), value: outcome))
            }
        case .resonance:
            break
        }
        let end = model.bpm
        self.kind = nil
        summary = Summary(title: title, seconds: seconds, hrStart: hrStart, hrEnd: end, lines: lines)
        presented = true
    }

    #if DEBUG
    func demoSummary() {
        title = String(localized: "Breathe")
        summary = Summary(title: title, seconds: 300, hrStart: 74, hrEnd: 66,
                          lines: [Line(title: String(localized: "HRV"), value: String(localized: "\("+14%") vs start · peak \("58") ms"))])
        presented = true
    }
    #endif

    private func controllerSessionChanged(_ session: BiofeedbackController.SessionKind) {
        guard let kind, kind != .paced else { return }
        if session != .none {
            controllerRunning = true
        } else if controllerRunning {
            finish()
        }
    }

    // MARK: Pacing

    /// Calm: each metronome beat shows on the flower too, so the rhythm does not live on the wrist alone.
    private func pulseCalm() {
        guard kind == .calm else { return }
        let still = reduceMotion
        withAnimation(.easeInOut(duration: 0.15)) {
            if still { flowerOpacity = 0.6 } else { progress = 0.45 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                if still { self.flowerOpacity = 1 } else if self.kind == .calm { self.progress = 0.35 }
            }
        }
    }

    /// Resonance and the sweep: the controller publishes each cue's phase; the flower takes the rest of it.
    private func controllerPhaseChanged(_ phase: BreathPhase) {
        guard let kind, kind == .resonance || kind == .sweep else { return }
        self.phase = phase
        let bpm: Double
        switch controller.session {
        case .resonanceSession(let b): bpm = b
        case .resonanceSweep(let b, _, _): bpm = b
        default: bpm = ResonanceEngine.fallbackBpm
        }
        let cycle = 60.0 / max(bpm, 1)
        let inhale = cycle * BreathPacer.defaultInhaleFraction
        animate(to: phase == .inhale ? 1 : 0, over: phase == .inhale ? inhale : cycle - inhale)
    }

    private func animate(to value: CGFloat, over duration: Double) {
        if reduceMotion {
            progress = 0.5
        } else {
            withAnimation(.easeInOut(duration: duration)) { progress = value }
        }
    }

    private func tick() {
        guard kind == .paced else { return }
        seconds += 1
        if let targetSeconds, seconds >= targetSeconds { finish() }
    }

    private func armStage(from now: Date, buzz: Bool) {
        guard !protocolStages.isEmpty else { return }
        let stage = protocolStages[stageIndex % protocolStages.count]
        phase = stage.type
        phaseLabel = stage.label
        let duration = Double(stage.durationMs) / 1000.0
        switch stage.type {
        case .inhale: animate(to: 1, over: duration)
        case .exhale: animate(to: 0, over: duration)
        case .hold, .textOnly: if reduceMotion { progress = 0.5 }
        }
        if buzz {
            let loops = BreathProtocolPlayer.loops(for: stage.type)
            if loops > 0 { model.buzz(loops: UInt8(clamping: loops), gate: HapticPrefs.breathing) }
            if audio {
                switch stage.type {
                case .inhale: tones.play(.inhale)
                case .exhale: tones.play(.exhale)
                case .hold, .textOnly: break
                }
            }
        }
        let item = DispatchWorkItem { [weak self] in self?.advance() }
        stageItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func advance() {
        guard kind == .paced, !guided, !protocolStages.isEmpty else { return }
        if protocolStages[stageIndex % protocolStages.count].type == .exhale { breathCount += 1 }
        stageIndex += 1
        armStage(from: Date(), buzz: true)
    }

    /// Stops the fixed-pace trainer and returns its HRV outcome ("+12% vs start · peak 64 ms", "—" when
    /// R-R was too thin, nil under two minutes), which is also kept as the last outcome.
    @discardableResult
    private func stopPaced() -> String? {
        stageItem?.cancel()
        stageItem = nil
        secondTimer?.cancel()
        secondTimer = nil
        ScreenIdle.keepAwake(false)
        phaseLabel = nil
        // #769: halt a pattern the strap may be mid-way through, not only the pulses still queued.
        model.stopHaptics()
        if reduceMotion { progress = 0 } else { withAnimation(.easeInOut(duration: 0.8)) { progress = 0 } }
        guard seconds >= 120 else { return nil }
        guard let base = baselineRmssd, base > 0, sessionRmssdCount > 0 else { return "—" }
        let mean = sessionRmssdSum / Double(sessionRmssdCount)
        let pct = Int(((mean - base) / base * 100).rounded())
        let core = String(localized: "\(String(format: "%+d%%", pct)) vs start · peak \(String(format: "%.0f", sessionRmssdPeak)) ms")
        UserDefaults.standard.set(core, forKey: "breathe.lastOutcome")
        return core
    }

    // MARK: HRV

    func ingest(_ rr: [Int]) {
        guard !rr.isEmpty else { return }
        rrBuffer.append(contentsOf: rr)
        if rrBuffer.count > rrWindow { rrBuffer.removeFirst(rrBuffer.count - rrWindow) }
        rmssd = Self.rmssd(rrBuffer)
        if kind == .paced, let r = rmssd {
            if baselineRmssd == nil && seconds <= 60 { baselineRmssd = r }
            sessionRmssdSum += r
            sessionRmssdCount += 1
            sessionRmssdPeak = max(sessionRmssdPeak, r)
        }
    }

    static func rmssd(_ intervals: [Int]) -> Double? {
        guard intervals.count >= 2 else { return nil }
        var sumSq = 0.0
        for i in 1..<intervals.count {
            let d = Double(intervals[i] - intervals[i - 1])
            sumSq += d * d
        }
        return (sumSq / Double(intervals.count - 1)).squareRoot()
    }
}

// MARK: - About this pace

private struct BreathEduSheet: View {
    let pace: BreathPace
    let onClose: () -> Void

    private var proto: BreathProtocol? {
        if case .catalog(let id) = pace { return BreathProtocolCatalog.protocolById(id) }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let proto {
                        Text(String(localized: String.LocalizationValue(proto.title)))
                            .font(StrandFont.title2)
                        Text(String(localized: String.LocalizationValue(proto.subtitle)))
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                        if proto.category == .presence {
                            Text(String(localized: String.LocalizationValue(BreathProtocolCatalog.presenceIntroTitle)))
                                .font(StrandFont.headline)
                            Text(String(localized: String.LocalizationValue(BreathProtocolCatalog.presenceIntroBody)))
                                .font(StrandFont.body)
                        }
                        Text(String(localized: String.LocalizationValue(proto.edu)))
                            .font(StrandFont.body)
                        if let hint = proto.sessionHint {
                            Text(String(localized: String.LocalizationValue(hint)))
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        if let caution = proto.caution {
                            Text(String(localized: String.LocalizationValue(caution)))
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.statusWarning)
                        }
                    } else {
                        Text(String(localized: "Your locked resonance pace from the Resonance sweep."))
                            .font(StrandFont.body)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(String(localized: "About this pace"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton(action: onClose)
                }
            }
        }
    }
}

// MARK: - Audio pacer (opt-in soft phase tones)

/// A tiny on-device tone player for the opt-in audio pacer: a short, soft sine "ding" per phase (higher on
/// the inhale, lower on the exhale) through an **ambient** session, so the silent switch mutes it and it
/// never interrupts other audio. No bundled assets — the buffers are generated once and reused.
@MainActor
final class BreathTonePlayer: ObservableObject {

    enum Tone { case inhale, exhale }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inhaleBuffer: AVAudioPCMBuffer?
    private var exhaleBuffer: AVAudioPCMBuffer?
    private var active = false

    private let inhaleHz: Double = 440   // A4, brighter for "in"
    private let exhaleHz: Double = 330   // E4, lower for "out"
    private let toneSeconds: Double = 0.45
    private let sampleRate: Double = 44_100

    /// Bring the engine and audio session up. Idempotent.
    func activate() {
        guard !active else { return }
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
#endif
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        if inhaleBuffer == nil { inhaleBuffer = makeTone(frequency: inhaleHz, format: format) }
        if exhaleBuffer == nil { exhaleBuffer = makeTone(frequency: exhaleHz, format: format) }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.play()
            active = true
        } catch {
            // Audio is a nicety, never load-bearing — if it can't start we just stay silent.
            active = false
        }
    }

    /// Stop and release the engine + session so nothing lingers when the pacer is off.
    func deactivate() {
        guard active else { return }
        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)
        engine.detach(player)
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
#endif
        active = false
    }

    /// Play the phase tone; a no-op if the engine isn't up (the haptic + visual cues still carry the pace).
    func play(_ tone: Tone) {
        guard active, let buffer = (tone == .inhale) ? inhaleBuffer : exhaleBuffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    /// One soft sine tone with a short attack and a longer release, so it fades rather than clicks.
    private func makeTone(frequency: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(toneSeconds * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        let total = Int(frameCount)
        let attack = Int(0.02 * sampleRate)
        let release = Int(0.18 * sampleRate)
        let peak: Float = 0.28
        for i in 0..<total {
            let t = Double(i) / sampleRate
            let sample = Float(sin(2.0 * Double.pi * frequency * t))
            var env: Float = 1.0
            if i < attack {
                env = Float(i) / Float(max(attack, 1))
            } else if i > total - release {
                env = Float(total - i) / Float(max(release, 1))
            }
            channel[i] = sample * env * peak
        }
        return buffer
    }
}

// MARK: - Stress check-in injection point

private struct StressNudgeCenterKey: EnvironmentKey {
    static let defaultValue: StressNudgeCenter? = nil
}
extension EnvironmentValues {
    /// The shared passive check-in center (`model.stressNudgeCenter`); nil → Breathe keeps a local one.
    var stressNudgeCenter: StressNudgeCenter? {
        get { self[StressNudgeCenterKey.self] }
        set { self[StressNudgeCenterKey.self] = newValue }
    }
}
