//  LiveView.swift
//  NOOP · live heart rate, laid out as the watchOS 26 Heart Rate app: a glowing heart, "Now" and the
//  current figure in large type, then today's range as Health draws a Heart Rate day (one min–max bar per
//  hour) with the resting rate under it, and a button that starts a workout. Nothing else unless something
//  is wrong: then one line says what, and opens Devices, where the strap's controls live.
//
//  PERF: the page itself observes neither `AppModel` nor `LiveState`. `bpm` ticks about once a second
//  and LiveState on every packet, so each is read only by a small leaf (`LiveHeartFigure`,
//  `LiveProblemLine`, `LiveWorkoutRow`) — a beat redraws the number, not the page. `LiveView` is the host
//  that picks the model out of the environment and hands it down as a plain reference, which SwiftUI
//  compares by identity, so the host's own 1 Hz re-render never re-evaluates the page.

import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import WhoopStore
import OuraProtocol

struct LiveView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        LivePage(model: model, live: model.live,
                 activeIsOura: LiveConsoleReadout.activeIsOura(devices: model.deviceRegistry?.devices ?? [],
                                                               activeId: model.deviceRegistry?.activeDeviceId))
    }

    /// Whether the low-bandwidth standard-HR fallback note (#80) says anything: LiveState carries a
    /// non-empty note string. Pure so it's unit-testable without standing up a view.
    static func shouldShowStandardHRNote(_ note: String?) -> Bool {
        guard let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }
}

private struct LivePage: View {
    /// Plain references on purpose (see the PERF note above): reading them does not subscribe the page.
    let model: AppModel
    let live: LiveState
    /// Resolved by the host from the device registry (#2305), so a switch of active device reaches the page.
    let activeIsOura: Bool
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter

    /// Which strap the user paired — picks the HRV reading's R-R caveat (#537).
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue

    @State private var day: LiveDay?
    @State private var showLiveWorkout = false
    @State private var showStartSport = false
    @State private var showHRVSnapshot = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LiveProblemLine(activeIsOura: activeIsOura) { router.openDevices() }
                    .padding(.bottom, 8)
                LiveHeartFigure(lastReading: day?.last)
                    .padding(.top, 8)
                todaySection
                LiveWorkoutRow(onOpen: { showLiveWorkout = true }, onStart: { showStartSport = true })
                    .padding(.top, 28)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle("Heart Rate")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showHRVSnapshot = true } label: { Label("HRV reading", systemImage: "waveform.path.ecg") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .barGlyph()
                .accessibilityLabel(Text("More"))
            }
        }
        .task(id: repo.refreshSeq) { day = await LiveDay.load(repo: repo) }
        // Take one count on the realtime stream while this screen is up (#681) — on a WHOOP 5/MG live HR only
        // flows while it is armed. Ref-counted in AppModel and balanced by the single stop on disappear.
        .onAppear {
            model.startRealtimeHR()
            if activeConnection { model.getBattery() }
            consumeActiveWorkoutRequest()
        }
        .onDisappear { model.stopRealtimeHR() }
        // A fresh bond/connection re-arms the stream (Apple must re-send startRealtime on a new connection)
        // WITHOUT another count — these fire several times per appearance against one disappear.
        .onReceive(live.$bonded.removeDuplicates().dropFirst()) { _ in reconnect() }
        .onReceive(live.$connected.removeDuplicates().dropFirst()) { _ in reconnect() }
        // Live workout mode (#238): the in-exercise screen opens the moment a workout starts.
        .onReceive(model.$activeWorkout.map { $0 != nil }.removeDuplicates().dropFirst()) { active in
            if active { showLiveWorkout = true }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showLiveWorkout) {
            LiveWorkoutView(onClose: { showLiveWorkout = false }).environmentObject(live)
        }
        #else
        .sheet(isPresented: $showLiveWorkout) {
            LiveWorkoutView(onClose: { showLiveWorkout = false }).environmentObject(live)
        }
        #endif
        // Pick a sport first (#519); the in-exercise screen then opens off the activeWorkout change above.
        .workoutSelectionCover(isPresented: $showStartSport) {
            StartWorkoutSheet { name in model.startWorkout(sport: name) }
        }
        // Manual HRV snapshot (#127) — a still, seated 60 s R-R reading. A WHOOP 5/MG's R-R is optical
        // (noisier), a WHOOP 4's electrical, so the reading is told which (#537).
        .sheet(isPresented: $showHRVSnapshot) {
            HRVSnapshotView(onClose: { showHRVSnapshot = false },
                            source: WhoopModel(rawValue: selectedModelRaw) == .whoop5mg ? .opticalPPG : .chestStrap)
                .environmentObject(live)
        }
    }

    // MARK: - Today

    @ViewBuilder private var todaySection: some View {
        if let day, !day.hours.isEmpty {
            Text("Today")
                .font(StrandFont.pro(22, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 4)
                .padding(.top, 28)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            SummaryCard { LiveDayCard(day: day) }
        }
    }

    // MARK: - Connection

    /// A trusted WHOOP link — gated on the active device being a WHOOP (#2075).
    private var activeConnection: Bool { live.activeIsWhoop && live.connected && live.bonded }

    private func reconnect() {
        guard activeConnection else { return }
        model.rearmRealtimeIfWanted()
        model.getBattery()
    }

    /// Honour a one-shot "Return to workout" from the Summary indicator: present the in-exercise screen for
    /// a workout already running (the "a workout just started" trigger never fires for one in flight).
    private func consumeActiveWorkoutRequest() {
        guard router.presentActiveWorkout else { return }
        router.presentActiveWorkout = false
        if model.activeWorkout != nil { showLiveWorkout = true }
    }
}

// MARK: - Heart

/// The Heart Rate app's first screen: the glowing heart, then "Now" (or when the last reading was taken)
/// over the figure in large type with a small red BPM. Owns the `AppModel` observation.
private struct LiveHeartFigure: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 64
    let lastReading: LiveDay.Reading?

    var body: some View {
        let bpm = model.bpm
        VStack(alignment: .leading, spacing: 0) {
            LiveHeartGlow(beating: bpm != nil && !motion.poseStill(reduceMotion))
                .frame(maxWidth: .infinity)
                .frame(height: 230)
            Group {
                if bpm != nil || lastReading == nil {
                    Text("Now")
                } else if let lastReading {
                    Text(lastReading.date, format: .relative(presentation: .named))
                }
            }
            .font(StrandFont.pro(20, weight: .semibold))
            .foregroundStyle(StrandPalette.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: (bpm ?? lastReading?.bpm).map(String.init) ?? "--")
                    .font(.system(size: figureSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .contentTransition(.numericText())
                Text("BPM")
                    .font(StrandFont.pro(20, weight: .semibold))
                    .foregroundStyle(StrandPalette.healthHeart)
            }
            .animation(.snappy, value: bpm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate"))
        .accessibilityValue(Text((bpm ?? lastReading?.bpm).map { String(localized: "\($0) bpm") } ?? "–"))
    }
}

/// The heart from the watch's Heart Rate app: a bright heart inside softer, larger copies of itself that
/// fade into the page. Beats once a second while a live reading flows; still otherwise.
private struct LiveHeartGlow: View {
    let beating: Bool
    @State private var beat = false

    var body: some View {
        ZStack {
            // Concentric copies of the heart, each a step larger and fainter, as the watch draws its halo.
            ForEach((1...4).reversed(), id: \.self) { ring in
                Image(systemName: "heart.fill")
                    .font(.system(size: 104))
                    .foregroundStyle(StrandPalette.healthHeart.opacity(0.42 - Double(ring) * 0.08))
                    .scaleEffect((1 + CGFloat(ring) * 0.27) * (beat ? 1 + CGFloat(ring) * 0.015 : 1))
                    .blur(radius: 0.5 + CGFloat(ring) * 0.8)
            }
            Image(systemName: "heart.fill")
                .font(.system(size: 104))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.36, blue: 0.3), Color(red: 0.88, green: 0.08, blue: 0.18)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: StrandPalette.healthHeart.opacity(0.5), radius: 12)
                .scaleEffect(beat ? 1.05 : 1)
        }
        .accessibilityHidden(true)
        .onAppear { setBeat(beating) }
        .onChangeCompat(of: beating) { setBeat($0) }
    }

    private func setBeat(_ on: Bool) {
        if on {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { beat = true }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { beat = false }
        }
    }
}

// MARK: - Today's range

/// Today's heart rate as Health draws a Heart Rate day: RANGE over the figure, one min–max bar per hour,
/// and the resting rate under a hairline.
private struct LiveDayCard: View {
    let day: LiveDay
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RANGE")
                .font(StrandFont.pro(13, weight: .semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            if let lo = day.low, let hi = day.high {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: "\(lo)–\(hi)")
                        .font(StrandFont.pro(34, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("BPM")
                        .font(StrandFont.pro(17, weight: .semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            chart
                .frame(height: 170)
                .padding(.top, 14)
            if let rhr = day.resting {
                Divider().padding(.top, 14).padding(.bottom, 12)
                let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                     : AnyLayout(HStackLayout())
                layout {
                    Text("Resting Heart Rate")
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if !dts.isAccessibilitySize { Spacer() }
                    HStack {
                        Text(verbatim: "\(rhr)")
                            .font(StrandFont.pro(17, weight: .semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("BPM")
                            .font(StrandFont.pro(15))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
    }

    private var chart: some View {
        Chart {
            ForEach(day.hours, id: \.hour) { h in
                BarMark(x: .value("Hour", Double(h.hour) + 0.5),
                        yStart: .value("Low", h.low), yEnd: .value("High", max(h.high, h.low + 1)),
                        width: .fixed(6))
                    .foregroundStyle(StrandPalette.healthHeart)
                    .cornerRadius(3)
            }
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let h = value.as(Int.self) { Text(Self.hourLabel(h)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .accessibilityLabel(Text("Heart rate range by hour"))
    }

    /// Health frames a heart-rate day around its readings, not from zero.
    private var yDomain: ClosedRange<Double> {
        let lo = day.hours.map(\.low).min() ?? 40, hi = day.hours.map(\.high).max() ?? 120
        return (floor(lo / 20) * 20 - 10)...(ceil(hi / 20) * 20 + 10)
    }

    private static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

/// Today's heart rate, read once per refresh: the hourly min–max bars, the range, the resting rate, and
/// the latest stored reading (what the figure shows when nothing is streaming).
struct LiveDay: Equatable {
    struct Hour: Equatable { let hour: Int; let low: Double; let high: Double }
    struct Reading: Equatable { let bpm: Int; let date: Date }

    var hours: [Hour]
    var resting: Int?
    var last: Reading?

    var low: Int? { hours.map(\.low).min().map { Int($0.rounded()) } }
    var high: Int? { hours.map(\.high).max().map { Int($0.rounded()) } }

    /// One bar per clock hour from the hour buckets of `[start of today, now]`.
    static func hours(from buckets: [HRBucket], dayStart: Date, calendar: Calendar = .current) -> [Hour] {
        var byHour: [Int: (lo: Double, hi: Double)] = [:]
        for b in buckets {
            let date = Date(timeIntervalSince1970: TimeInterval(b.ts))
            guard date >= dayStart else { continue }
            let h = calendar.component(.hour, from: date)
            let cur = byHour[h]
            byHour[h] = (min(cur?.lo ?? b.minBpm, b.minBpm), max(cur?.hi ?? b.maxBpm, b.maxBpm))
        }
        return byHour.keys.sorted().map { Hour(hour: $0, low: byHour[$0]!.lo, high: byHour[$0]!.hi) }
    }

    static func load(repo: Repository, now: Date = Date()) async -> LiveDay {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let to = Int(now.timeIntervalSince1970)
        // Five-minute buckets carry each bucket's own min and max, so folding them into hours keeps the
        // day's true extremes (HRBucket.minBpm/maxBpm) without loading the raw ~1 Hz rows.
        let buckets = await repo.hrBuckets(from: Int(start.timeIntervalSince1970), to: to, bucketSeconds: 300)
        let recent = await repo.hrSamples(from: to - 3600, to: to)
        let today = Repository.localDayKey(now)
        let resting = await repo.dailyMetrics(fromDay: today, toDay: today).first?.restingHr
        // The newest reading: a raw sample from the last hour, else the day's newest five-minute bucket.
        let last = recent.last.map { Reading(bpm: $0.bpm, date: Date(timeIntervalSince1970: TimeInterval($0.ts))) }
            ?? buckets.last.map { Reading(bpm: Int($0.bpm.rounded()),
                                          date: Date(timeIntervalSince1970: TimeInterval(min($0.ts + 300, to)))) }
        return LiveDay(hours: hours(from: buckets, dayStart: start), resting: resting, last: last)
    }
}

// MARK: - Workout

/// "Start Workout", or the workout already running with its clock. Owns the `AppModel` observation, so a
/// heartbeat redraws this row, not the page.
private struct LiveWorkoutRow: View {
    @EnvironmentObject private var model: AppModel
    let onOpen: () -> Void
    let onStart: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var chevronSize: CGFloat = 14

    var body: some View {
        if let w = model.activeWorkout {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    WorkoutTypeIcon(workoutType: w.sport, size: 24, weight: .semibold,
                                    color: StrandPalette.activityExerciseText)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WorkoutSource.localizedSport(w.sport))
                            .font(StrandFont.pro(17, weight: .semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(ActiveWorkoutClock.clock(Int(w.elapsed(at: ctx.date))))
                                .font(StrandFont.pro(22, weight: .semibold).monospacedDigit())
                                .foregroundStyle(StrandPalette.activityExerciseText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: chevronSize, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .padding(16)
                .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("View the active workout"))
        } else {
            Button(action: onStart) {
                Label("Start Workout", systemImage: "figure.run")
                    .font(StrandFont.pro(17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .liveProminentButton()
        }
    }
}

private extension View {
    /// iOS 26's prominent Liquid Glass capsule in Exercise green; a bordered prominent capsule before it.
    @ViewBuilder func liveProminentButton() -> some View {
        #if compiler(>=6.2) && os(iOS)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
                .tint(StrandPalette.activityExerciseText)
                .foregroundStyle(StrandPalette.fitnessOnAccent)
                .controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .tint(StrandPalette.activityExerciseText).controlSize(.large)
        }
        #else
        self.buttonStyle(.borderedProminent)
            .tint(StrandPalette.activityExerciseText).controlSize(.large)
        #endif
    }
}

// MARK: - Problem line

/// One line, shown only when something keeps the heart rate from being live: no strap, a link that isn't
/// streaming yet, a partial pairing, the low-bandwidth mode (#80), the strap off the wrist, a failed sync,
/// or a nearly flat battery. Opens Devices. Owns the `LiveState` observation.
private struct LiveProblemLine: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    let activeIsOura: Bool
    let onOpen: () -> Void

    var body: some View {
        if let problem {
            NoticeCard(title: problem.isSyncError ? Text("History sync stopped") : Text(verbatim: problem.text),
                       message: problem.isSyncError ? Text(verbatim: problem.text) : nil,
                       systemImage: problem.icon, tone: problem.tone,
                       actionTitle: "Open Devices", action: onOpen)
                .padding(.top, 8)
        }
    }

    private struct Problem {
        let icon: String
        let text: String
        let tone: NoticeCard.Tone
        /// A sync error is a sentence of its own: it goes under a short title rather than in it.
        var isSyncError = false
    }

    private var ringStreaming: Bool { live.connected && live.streamingLiveHR }

    private var problem: Problem? {
        // A ring reads its OWN link phase (#2305): `live.connected` is whichever source last wrote it.
        if activeIsOura {
            guard !ringStreaming else { return nil }
            return Problem(icon: "antenna.radiowaves.left.and.right.slash",
                           text: LiveRingCopy.status(model.ouraLinkPhase, streaming: false),
                           tone: .warning)
        }
        if !live.connected {
            return Problem(icon: "antenna.radiowaves.left.and.right.slash",
                           text: String(localized: "Strap not connected"), tone: .info)
        }
        if !live.bonded {
            return Problem(icon: "ellipsis.circle", text: String(localized: "Connected, waiting for a streaming state."),
                           tone: .warning)
        }
        if !live.encryptedBond {
            return Problem(icon: "lock.open", text: String(localized: "Live HR (not fully paired)"),
                           tone: .warning)
        }
        if LiveView.shouldShowStandardHRNote(live.standardHRMode) {
            return Problem(icon: "antenna.radiowaves.left.and.right",
                           text: String(localized: "Standard HR mode (low bandwidth)"), tone: .info)
        }
        if !live.worn {
            return Problem(icon: "hand.raised", text: String(localized: "Off wrist"), tone: .warning)
        }
        if let err = live.lastSyncError, !err.isEmpty {
            return Problem(icon: "exclamationmark.arrow.circlepath", text: err, tone: .warning, isSyncError: true)
        }
        if let pct = live.batteryPct, pct <= 15, live.charging != true {
            return Problem(icon: "battery.25percent", text: String(localized: "Battery \(Int(pct.rounded()))%"),
                           tone: .error)
        }
        return nil
    }
}

// MARK: - Ring status copy (#2305)

/// One line per ring link phase, so every surface that names what the ring is doing agrees.
enum LiveRingCopy {
    static func status(_ phase: OuraLiveSource.LinkPhase, streaming: Bool) -> String {
        switch phase {
        case .disconnected:   return String(localized: "Ring not connected.")
        case .connecting:     return String(localized: "Connecting to the ring…")
        case .authenticating: return String(localized: "Connected, authenticating…")
        case .authenticated:
            return streaming
                ? String(localized: "Live heart rate is flowing from the ring.")
                : String(localized: "Connected, waiting for live heart rate.")
        }
    }
}
