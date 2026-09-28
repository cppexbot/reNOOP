import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Manual HRV snapshot — "Take an HRV reading" (#127).
///
/// A short, deliberate seated capture: the user sits still and breathes normally while the strap's
/// live R-R intervals (the reliable 0x2A37 stream) accumulate for ~60 s. We then run the full
/// HRVAnalyzer cleaning pipeline (range filter → Malik ectopic rejection → ≥minBeats) and surface the
/// headline RMSSD plus SDNN, mean HR and the beats used. Saving banks the RMSSD as a single point in
/// the generic metric series ("hrv_snapshot", source "manual-hrv") so it sits beside every other
/// source for the explorer/trends.
///
/// The live ingest uses the shared `onRRPackets` observer; the capture buffer is uncapped (unlike
/// Breathe's rolling 30) because the analysis wants every clean beat. The window is a monotonic
/// 60-second deadline — countdown display and ingest cutoff both derive from it.
struct HRVSnapshotView: View {

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    /// Optional dismissal hook when presented as a sheet (Live → "Take an HRV reading").
    var onClose: (() -> Void)? = nil

    /// Where the live R-R is coming from, so the methodology caveat is honest (#537): a WHOOP 5/MG
    /// derives R-R from the optical pulse signal (noisier) while a WHOOP 4 / chest strap is electrical
    /// R-R. Defaults to `.unknown` for callers that do not pass a strap model, matching the Android twin.
    var source: SpotHrvReading.Source = .unknown

    // MARK: - Capture phase

    private enum Phase: Equatable {
        case idle           // not yet started (or finished and reset)
        case capturing      // accumulating R-R, counting down
        case done           // analysis complete — showing the result
    }

    /// Length of a capture in seconds. Long enough to collect ≥minBeats clean intervals at a resting
    /// rate (≈60 beats at 60 bpm) with headroom for ectopic/range rejection.
    static let captureSeconds = 60

    // MARK: - State

    @State private var phase: Phase = .idle

    /// Every R-R interval (ms) collected during the active capture window — uncapped on purpose; the
    /// analyzer wants the whole window.
    @State private var captureBuffer: [Int] = []
    @State private var secondsRemaining = HRVSnapshotView.captureSeconds

    /// Monotonic start of the active capture — the single time base for the countdown display, the
    /// ingest cutoff, and the finish deadline. Nil outside a capture.
    @State private var captureStart: ContinuousClock.Instant? = nil

    /// Live RMSSD over the beats gathered so far (a running indicator while capturing; the final
    /// figure comes from the cleaned `HRVAnalyzer.analyze`).
    @State private var runningRMSSD: Double? = nil

    /// The completed analysis (nil until `.done`).
    @State private var result: HRVAnalyzer.HRVResult? = nil

    /// Whether the just-finished snapshot has been saved (drives the Save button → "Saved").
    @State private var saved = false
    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title2) private var figureSize: CGFloat = 24

    /// Whether the ⓘ methodology popover is showing.

    private let secondTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var bonded: Bool { live.bonded }

    private var tint: Color { StrandPalette.healthHeart }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if !bonded { notBondedHint }
                    stateArea
                    controls
                    if phase == .done, let result, result.rmssd != nil { resultCard(result) }
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.top, NoopMetrics.space4)
                .padding(.bottom, NoopMetrics.space8)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(StrandPalette.summaryCanvas.ignoresSafeArea())
            .navigationTitle("HRV Reading")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if let close = onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton { close() }
                    }
                }
                ToolbarItem(placement: .primaryAction) { aboutButton }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 600)
        #endif
        // rrSeq-keyed: equal consecutive packets both count (see RRPacketObserver.swift).
        .onRRPackets(live) { rr in
            ingest(rr)
        }
        // Capture countdown — only ticks while capturing.
        .onReceive(secondTimer) { _ in
            guard phase == .capturing else { return }
            tick()
        }
        .onDisappear {
            ScreenIdle.keepAwake(false)
        }
    }

    // MARK: - State area

    /// Idle: a glyph and one line. Capturing and done: the ring, filling over the minute, around the RMSSD.
    @ViewBuilder private var stateArea: some View {
        switch phase {
        case .idle:
            VStack(spacing: 14) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text("Take an HRV reading")
                    .font(StrandFont.pro(22, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
        case .capturing, .done:
            VStack(spacing: 16) {
                captureDial
                    .frame(width: 240, height: 240)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(maxWidth: .infinity)
                if let line = statusLine {
                    Text(line)
                        .font(StrandFont.pro(15))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 24)
        }
    }

    /// The ring: a faint track, the minute's progress over it, and the RMSSD in the middle — the running
    /// figure while capturing, the cleaned result once done.
    private var captureDial: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 14)
            Circle()
                .trim(from: 0, to: captureFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: captureFraction)

            VStack(spacing: 2) {
                DialFigure(value: dialValue)
                Text(verbatim: "\(String(localized: "ms")) RMSSD")
                    .font(StrandFont.pro(15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                if phase == .capturing {
                    Text("\(secondsRemaining)s left · \(captureBuffer.count) beats")
                        .font(StrandFont.pro(13))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .monospacedDigit()
                        .padding(.top, 6)
                }
            }
            .padding(24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dialAccessibilityLabel)
    }

    /// 0…1 capture progress, driving the ring trim.
    private var captureFraction: CGFloat {
        switch phase {
        case .idle:      return 0
        case .capturing: return CGFloat(Self.captureSeconds - secondsRemaining) / CGFloat(Self.captureSeconds)
        case .done:      return 1
        }
    }

    private var dialValue: String {
        switch phase {
        case .idle:
            return "—"
        case .capturing:
            return runningRMSSD.map { String(format: "%.0f", $0) } ?? "…"
        case .done:
            return result?.rmssd.map { String(format: "%.0f", $0) } ?? "—"
        }
    }

    /// The one line under the ring: how to sit while capturing, or why a finished capture has no number.
    private var statusLine: String? {
        switch phase {
        case .idle:
            return nil
        case .capturing:
            return String(localized: "Sit still, breathe normally. Keep your wrist relaxed and steady.")
        case .done:
            if let r = result, r.rmssd == nil {
                return String(localized: "Not enough clean beats. Sit still and try again.")
            }
            return nil
        }
    }

    private var dialAccessibilityLabel: String {
        switch phase {
        case .idle:      return String(localized: "HRV reading not started")
        case .capturing: return String(localized: "Capturing. \(secondsRemaining) seconds remaining, \(captureBuffer.count) beats collected.")
        case .done:
            return result?.rmssd.map { String(localized: "RMSSD \(Int($0.rounded())) milliseconds") } ?? String(localized: "Reading incomplete")
        }
    }

    // MARK: - Controls

    /// Start / Cancel / Take another reading, with Save beside a finished reading.
    private var controls: some View {
        VStack(spacing: 12) {
            if phase == .done, let r = result, r.rmssd != nil {
                Button {
                    save(r)
                } label: {
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        .font(StrandFont.pro(17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(tint)
                .disabled(saved)
                .modifier(CapsuleButtonShape())
            }

            primaryButton
        }
    }

    @ViewBuilder private var primaryButton: some View {
        let button = Button {
            phase == .capturing ? cancel() : start()
        } label: {
            Text(primaryLabel)
                .font(StrandFont.pro(17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .controlSize(.large)
        .disabled(!bonded && phase != .capturing)
        .help(bonded
              ? "Take a 60-second seated HRV reading from the live R-R stream."
              : "Connect your strap first. The reading needs the live R-R stream.")
        .modifier(CapsuleButtonShape())

        switch phase {
        case .idle:
            button.buttonStyle(.borderedProminent).tint(tint)
        case .capturing:
            button.buttonStyle(.bordered).tint(StrandPalette.settingsRed)
        case .done:
            if let r = result, r.rmssd != nil {
                button.buttonStyle(.bordered).tint(tint)
            } else {
                button.buttonStyle(.borderedProminent).tint(tint)
            }
        }
    }

    private var primaryLabel: String {
        switch phase {
        case .idle:      return String(localized: "Start")
        case .capturing: return String(localized: "Cancel")
        case .done:      return String(localized: "Take another reading")
        }
    }

    // MARK: - Result

    /// The rest of the reading as Health figures: SDNN, mean heart rate and the beats it rests on.
    private func resultCard(_ result: HRVAnalyzer.HRVResult) -> some View {
        SummaryCard {
            let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                                 : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            layout {
                figure("SDNN", Self.format(result.sdnn, "%.0f"), unit: String(localized: "ms"))
                if !dts.isAccessibilitySize { divider }
                figure(String(localized: "Mean HR"), Self.format(Self.meanHR(meanNN: result.meanNN), "%.0f"),
                       unit: String(localized: "bpm"))
                if !dts.isAccessibilitySize { divider }
                figure(String(localized: "Beats"), "\(result.nClean)", unit: "")
            }
            .padding(.top, 2)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(StrandPalette.hairline)
            .frame(width: NoopMetrics.hairlineWidth, height: 40)
            .padding(.horizontal, 12)
    }

    private func figure(_ title: String, _ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title)
                .font(StrandFont.pro(13, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(dts.isAccessibilitySize ? nil : 1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(.system(size: figureSize, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if !unit.isEmpty {
                    Text(verbatim: unit)
                        .font(StrandFont.pro(15, weight: .semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Methodology

    /// Source-aware methodology (#537), one tap away: the spot RMSSD uses the SAME cleaned Task-Force math
    /// as the nightly HRV (so the number is comparable to the overnight figure), then
    /// `SpotHrvReading.caveatFor` adds the honest limits — including the noisier optical-PPG note on a
    /// WHOOP 5/MG. Single-sourced with Android via the shared helper.
    private var aboutButton: some View {
        InfoButton(label: "How this is measured") {
            Text("A 60-second snapshot of your beat-to-beat (R-R) intervals from the strap, cleaned (range and ectopic-beat filtering) before computing RMSSD the same way your overnight HRV is computed.")
            Text(SpotHrvReading.caveatFor(source))
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    // MARK: - Not-bonded hint

    private var notBondedHint: some View {
        NoticeCard(title: Text("Strap not streaming"),
                   message: Text("Connect it on the Live screen first."),
                   systemImage: "applewatch.radiowaves.left.and.right", tone: .warning)
    }

    // MARK: - Capture control

    private func start() {
        guard bonded else { return }
        captureStart = ContinuousClock().now
        phase = .capturing
        captureBuffer.removeAll()
        secondsRemaining = Self.captureSeconds
        runningRMSSD = nil
        result = nil
        saved = false
        ScreenIdle.keepAwake(true)      // hold the screen awake through the hands-still capture (no-op on macOS)
    }

    private func cancel() {
        phase = .idle
        captureStart = nil
        secondsRemaining = Self.captureSeconds
        runningRMSSD = nil
        ScreenIdle.keepAwake(false)
    }

    /// Milliseconds of monotonic time since the capture started (nil outside a capture).
    private func captureElapsedMs() -> Int? {
        guard let start = captureStart else { return nil }
        let c = (ContinuousClock().now - start).components
        return Int(c.seconds) * 1000 + Int(c.attoseconds / 1_000_000_000_000_000)
    }

    /// Derive the countdown from the monotonic clock — a late timer fire jumps to the correct
    /// remaining value instead of stretching the window (the old per-callback decrement did).
    private func tick() {
        guard let ms = captureElapsedMs() else { return }
        secondsRemaining = Self.remainingSeconds(elapsedMs: ms)
        if secondsRemaining == 0 {
            finish()
        }
    }

    /// End the capture and run the full cleaning analysis over everything collected.
    private func finish() {
        ScreenIdle.keepAwake(false)
        let captureMs = captureElapsedMs() ?? Self.captureSeconds * 1000
        captureStart = nil
        let raw = captureBuffer.map(Double.init)
        // A capture whose collected beat time exceeds the wall clock it ran for held duplicated
        // beats (e.g. overlapping live sources) — refuse the number rather than publish it.
        if HRVAnalyzer.spotCaptureOverCounted(beatTimeMs: raw.reduce(0, +),
                                              captureMs: Double(captureMs)) {
            result = HRVAnalyzer.HRVResult(rmssd: nil, sdnn: nil, meanNN: nil, pnn50: nil,
                                           nInput: raw.count, nClean: 0)
            phase = .done
            return
        }
        // HRV & Autonomic test mode (Group G): when the mode is on, emit the cleaning trace (nInput /
        // nClean / rejected fraction, the range + Malik ectopic counts, the minBeats + spot gates,
        // RMSSD/SDNN/meanNN) tagged `.hrv`. analyzeTrace returns the SAME HRVResult `analyze` would
        // (it reuses analyze verbatim), so the headline RMSSD is byte-identical with the trace on or off.
        // Zero cost when off: the gate is one UserDefaults bool read and analyzeTrace is never called, so
        // the plain `analyze` path below runs untouched.
        if TestCentre.active(.hrv) {
            let (traced, lines) = HRVAnalyzer.analyzeTrace(
                rawRR: raw, maxRejectedFraction: HRVAnalyzer.defaultSpotMaxRejectedFraction, path: "spot")
            for line in lines { live.append(log: line, domain: .hrv) }
            result = traced
        } else {
            result = HRVAnalyzer.analyze(rawRR: raw,
                                         maxRejectedFraction: HRVAnalyzer.defaultSpotMaxRejectedFraction)
        }
        phase = .done
    }

    // MARK: - Live R-R ingest (mirrors BreathingView)

    /// Append newly-arrived R-R intervals to the capture buffer (only while capturing) and refresh the
    /// running RMSSD indicator. The published `rr` is the latest set of intervals.
    private func ingest(_ rr: [Int]) {
        guard phase == .capturing, !rr.isEmpty,
              let ms = captureElapsedMs(), Self.captureWindowOpen(elapsedMs: ms) else { return }
        captureBuffer.append(contentsOf: rr)
        runningRMSSD = HRVAnalyzer.rmssdRaw(captureBuffer.map(Double.init))
    }

    // MARK: - Save

    /// Persist the snapshot's RMSSD as a single metric point (key "hrv_snapshot", source "manual-hrv",
    /// today's day). Idempotent on (deviceId, day, key) — a second reading the same day overwrites the
    /// earlier one, matching every other importer's upsert semantics.
    private func save(_ result: HRVAnalyzer.HRVResult) {
        guard let rmssd = result.rmssd else { return }
        let day = Repository.dayString(Date())
        let point = MetricPoint(day: day, key: HRVSnapshot.metricKey, value: rmssd)
        saved = true                    // optimistic — the write is local + idempotent
        Task {
            guard let store = await model.repo.storeHandle() else {
                saved = false
                return
            }
            do {
                try await store.upsertMetricSeries([point], deviceId: HRVSnapshot.sourceId)
                await model.repo.refresh()
            } catch {
                saved = false
            }
        }
    }

    // MARK: - Pure formatting helpers (shared with the tests)

    static func format(_ value: Double?, _ fmt: String) -> String {
        guard let value else { return "—" }
        return String(format: fmt, value)
    }

    /// Mean heart rate (bpm) from the mean NN interval (ms): 60000 / meanNN. nil when meanNN is missing
    /// or non-positive.
    static func meanHR(meanNN: Double?) -> Double? {
        guard let meanNN, meanNN > 0 else { return nil }
        return 60_000.0 / meanNN
    }

    /// Whole seconds left for a monotonic elapsed time, never negative. Mirrors Android
    /// `remainingCaptureSeconds`.
    static func remainingSeconds(elapsedMs: Int) -> Int {
        max(0, captureSeconds - elapsedMs / 1000)
    }

    /// The ingest gate: intervals on or after the 60-second deadline stay out, however late the
    /// countdown timer fires. Mirrors Android `captureWindowOpen`.
    static func captureWindowOpen(elapsedMs: Int) -> Bool {
        elapsedMs < captureSeconds * 1000
    }
}

/// Snapshot-write constants — the metric-series key + source id the manual HRV reading banks under.
/// Kept as a tiny namespace so the source id ("manual-hrv") and key ("hrv_snapshot") are single-sourced
/// and match the Android side value-for-value.
enum HRVSnapshot {
    /// Generic metric-series key for a manual HRV reading.
    static let metricKey = "hrv_snapshot"
    /// Source id this manual reading is stored under — its own source so it sits beside WHOOP / Apple
    /// for the per-source explorer, exactly like the other manual/imported sources.
    static let sourceId = "manual-hrv"
}

/// The iOS capsule button of Health's sheets; macOS keeps its native bezel (`.capsule` there is macOS 14).
/// The RMSSD in the middle of the capture ring, scaled within the ring's own Dynamic Type cap.
private struct DialFigure: View {
    let value: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64

    var body: some View {
        Text(verbatim: value)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(StrandPalette.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
            .animation(.snappy, value: value)
    }
}

private struct CapsuleButtonShape: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.buttonBorderShape(.capsule)
        #else
        content
        #endif
    }
}

