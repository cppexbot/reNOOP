//  LiveSessionView.swift
//  NOOP · Live Sessions (silent guardian, beta) on the shared recording screen — the one a workout, a gym
//  session and an interval timer use (`RecordingChrome`): always dark, the phase in the heading with one
//  line of intent under it, then the heart rate and today's Charge as large figures, and the dark panel
//  with the running clock, the time held in band and ✕ to end. ⌄ puts the screen away while the session
//  keeps guarding; a bar above the tab bar brings it back. It ends on one summary card.
//
//  Every value on screen is the engine's `Output` verbatim (via `LiveSessionRunner`) — this file renders,
//  it never decides. Coaching is silence while in band: the strap buzzes only to push or ease off.
//
//  PERF: the runner publishes about once a second, so only leaves observe it (`LiveSessionFigures`,
//  `LiveSessionHeldRing`, the bar's read-out); the screen itself observes the holder, which changes only
//  when a session starts, ends or is shown.
//
//  Design contract: docs/superpowers/specs/2026-07-04-live-sessions-design.md.

import SwiftUI
import Combine
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Holder

/// The session outlives its screen: ⌄ hides the screen, the runner keeps guarding. Held by `AppModel`, so
/// the Summary "+", Browse and the bar all reach the same one.
@MainActor
final class LiveSessionHolder: ObservableObject {
    @Published private(set) var runner: LiveSessionRunner?
    @Published var isPresented = false
    private var endWatch: AnyCancellable?

    /// Show the running session, or start a new one.
    func open() {
        if runner == nil || runner?.finalRow != nil {
            let fresh = LiveSessionRunner()
            runner = fresh
            // Both end paths (✕ and the ten-minute stale auto-end) bring the summary up, even minimised.
            endWatch = fresh.$finalRow.sink { [weak self] row in
                if row != nil { self?.isPresented = true }
            }
        }
        isPresented = true
    }

    /// The summary was read: forget the session.
    func finish() {
        isPresented = false
        runner = nil
        endWatch = nil
    }
}

/// A shell's Live Session: the cover, and the `.liveSession` route (a deep link) opening it. Reads the
/// holder off `AppModel` in this leaf, so the shell itself never observes the model.
struct LiveSessionShellHost: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: NavRouter

    var body: some View {
        LiveSessionCoverHost(holder: model.liveSession)
            .onChangeCompat(of: router.requestedDestination) { dest in
                guard dest == .liveSession else { return }
                router.requestedDestination = nil
                model.liveSession.open()
            }
    }
}

/// The minimised bar for a shell, reading the holder off `AppModel` the same way.
struct LiveSessionShellBar: View {
    @EnvironmentObject private var model: AppModel
    var insets = EdgeInsets()

    var body: some View { LiveSessionBar(holder: model.liveSession, insets: insets) }
}

/// Presents the session full screen (a sheet on the Mac) whenever the holder asks.
struct LiveSessionCoverHost: View {
    @ObservedObject var holder: LiveSessionHolder

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            #if os(iOS)
            .fullScreenCover(isPresented: $holder.isPresented) { content }
            #else
            .sheet(isPresented: $holder.isPresented) { content.frame(minWidth: 480, minHeight: 680) }
            #endif
    }

    @ViewBuilder private var content: some View {
        if let runner = holder.runner {
            LiveSessionView(runner: runner, holder: holder)
        }
    }
}

// MARK: - Session screen

struct LiveSessionView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    let runner: LiveSessionRunner
    @ObservedObject var holder: LiveSessionHolder

    /// Whether the session has ended — the one runner change this screen itself follows.
    @State private var ended = false
    @State private var guardedCount: Int?

    var body: some View {
        Group {
            if ended, let row = runner.finalRow {
                LiveSessionSummaryView(row: row, guardedCount: guardedCount) { holder.finish() }
            } else {
                recording
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            // No-op for a runner already guarding (a re-opened session) or already ended.
            runner.start(model: model, repo: repo, ble: model.ble, profile: profile)
            ended = runner.finalRow != nil
            if ended { loadGuardedCount() }
        }
        .onReceive(runner.$finalRow.dropFirst()) { row in
            guard row != nil else { return }
            loadGuardedCount()
            ended = true
        }
    }

    private var recording: some View {
        VStack(spacing: 0) {
            RecordingTopBar { holder.isPresented = false }
            LiveSessionFigures(runner: runner)
                .padding(.horizontal, 28)
            RecordingPanel(
                glyph: AnyView(Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(StrandPalette.metricCyan)),
                clock: {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        RecordingClockText(text: ActiveWorkoutClock.clock(LiveSessionView.elapsed(runner, at: ctx.date)),
                                           tint: StrandPalette.metricCyan)
                    }
                    .accessibilityLabel(Text("Elapsed time"))
                },
                trailing: { LiveSessionHeldRing(runner: runner) },
                leading: { Color.clear.frame(width: 76, height: 76) },
                center: {
                    RecordingButton(symbol: "xmark", size: 112, tint: StrandPalette.statusCritical,
                                    label: "End session") { runner.end() }
                },
                right: { Color.clear.frame(width: 76, height: 76) })
        }
    }

    /// Seconds since the session started (0 before it has).
    static func elapsed(_ runner: LiveSessionRunner, at date: Date) -> Int {
        runner.startTs > 0 ? max(0, Int(date.timeIntervalSince1970) - runner.startTs) : 0
    }

    /// "N sessions guarded" — completed sessions in the recent look-back, this one included (its final
    /// row is upserted before `finalRow` publishes).
    private func loadGuardedCount() {
        let deviceId = repo.deviceId
        Task {
            guard let store = await repo.storeHandle() else { return }
            let rows = (try? await store.recentLiveSessions(deviceId: deviceId, limit: 50)) ?? []
            guardedCount = rows.filter { $0.endTs != nil }.count
        }
    }
}

/// The phase and its line of intent, then the engine's smoothed heart rate against today's band and the
/// Charge the band was drawn from. Observes the runner, so a tick redraws these and nothing around them.
private struct LiveSessionFigures: View {
    @ObservedObject var runner: LiveSessionRunner

    private var out: LiveSessionEngine.Output? { runner.output }
    private var reading: Bool { out?.smoothedBpm != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordingHeading(caption: phase, tint: tint, title: intent)
                .padding(.top, 12)
            Spacer(minLength: 16)
            LiveFigure(value: out?.smoothedBpm.map { "\(Int($0.rounded()))" } ?? "--",
                       label: positionLabel, tint: reading ? tint : .white)
            Spacer(minLength: 8)
            LiveFigure(value: runner.chargeAtStart.map { "\(Int($0.rounded()))" } ?? "--",
                       unit: runner.chargeAtStart == nil ? "" : "%",
                       label: String(localized: "CHARGE\nTODAY"))
            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phase: String {
        switch out?.status {
        case .active: return String(localized: "Guarding")
        case .warmup: return String(localized: "Warming up")
        case .stale, .none: return String(localized: "No live reading")
        }
    }

    /// One line, honest per status — a stale stream never claims guarding.
    private var intent: String {
        switch out?.status {
        case .stale, .none: return String(localized: "Coaching pauses until the strap is back.")
        case .warmup: return String(localized: "Cues stay quiet for the first minute.")
        case .active: return String(localized: "Silence means you're on track.")
        }
    }

    private var tint: Color {
        guard let out, out.smoothedBpm != nil else { return .white.opacity(0.6) }
        switch out.position {
        case .inBand: return StrandPalette.metricCyan
        case .below: return StrandPalette.metricCyan.opacity(0.55)
        case .above: return StrandPalette.statusCritical
        }
    }

    /// Where the heart sits against today's band, with the band itself: "IN BAND 118–142".
    private var positionLabel: String {
        let band = out?.band ?? runner.baseBand
        let range = band.map { "\(Int($0.floorBpm.rounded()))–\(Int($0.ceilingBpm.rounded()))" } ?? ""
        let word: String
        switch (reading, out?.position) {
        case (true, .inBand?): word = String(localized: "In band")
        case (true, .below?): word = String(localized: "Below band")
        case (true, .above?): word = String(localized: "Above band")
        default: word = String(localized: "Band")
        }
        return "\(word)\n\(range)"
    }
}

/// Time held in band this session, filling toward an hour — the ring beside the clock.
private struct LiveSessionHeldRing: View {
    @ObservedObject var runner: LiveSessionRunner

    var body: some View {
        let held = min((runner.output?.inBandSeconds ?? 0) / 3600, 1)
        ZStack {
            Circle().stroke(StrandPalette.metricCyan.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: held)
                .stroke(StrandPalette.metricCyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: held)
        }
        .padding(3)
        .accessibilityElement()
        .accessibilityLabel(Text("Time in band"))
        .accessibilityValue(Text(LiveSessionSummaryView.clock(runner.output?.inBandSeconds ?? 0)))
    }
}

// MARK: - Summary

/// The end-of-session card: a plain verdict, time in / below / above the band, the cues sent, the band,
/// and the streak line. Everything comes off the banked `LiveSessionRow` — the record history reads, so
/// the two can never disagree.
struct LiveSessionSummaryView: View {
    let row: LiveSessionRow
    let guardedCount: Int?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(StrandPalette.metricCyan)
            Text("Live Session")
                .font(StrandFont.pro(28, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 14)
            Text(Self.verdict(row: row))
                .font(StrandFont.pro(17))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 6)
            VStack(spacing: 0) {
                bandRow(String(localized: "In band"), row.inBandSec, StrandPalette.metricCyan)
                divider
                bandRow(String(localized: "Below band"), row.belowSec, .white.opacity(0.4))
                divider
                bandRow(String(localized: "Above band"), row.aboveSec, StrandPalette.statusCritical)
                divider
                line(String(localized: "Cues sent"), cueLine)
                divider
                line(String(localized: "Band"), "\(Int(row.floorBpm.rounded()))–\(Int(row.ceilingBpm.rounded())) \(String(localized: "bpm"))")
            }
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 24)
            if let n = guardedCount, n > 0 {
                Text(n == 1 ? String(localized: "1 session guarded") : String(localized: "\(n) sessions guarded"))
                    .font(StrandFont.pro(15))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 14)
            }
            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(StrandPalette.metricCyan))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var divider: some View { Divider().overlay(Color.white.opacity(0.15)) }

    private func bandRow(_ label: String, _ seconds: Double, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(Self.clock(seconds)).monospacedDigit().foregroundStyle(.white)
        }
        .font(StrandFont.pro(17))
        .padding(.vertical, 13)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.white).multilineTextAlignment(.trailing)
        }
        .font(StrandFont.pro(17))
        .padding(.vertical, 13)
    }

    private var cueLine: String {
        if row.pushCount == 0 && row.easeCount == 0 { return String(localized: "None") }
        var parts: [String] = []
        if row.pushCount > 0 { parts.append(String(localized: "\(row.pushCount) push")) }
        if row.easeCount > 0 { parts.append(String(localized: "\(row.easeCount) ease-off")) }
        return parts.joined(separator: " · ")
    }

    /// Pure + honest — fractions of the banked totals, nothing beyond them.
    static func verdict(row: LiveSessionRow) -> String {
        let total = row.inBandSec + row.belowSec + row.aboveSec
        guard total >= 300 else {
            return String(localized: "Too short to judge — the band needs a few minutes to mean anything.")
        }
        let inFrac = row.inBandSec / total
        if inFrac >= 0.7 { return String(localized: "You held the band. Right where today wanted you.") }
        if inFrac >= 0.4 { return String(localized: "In and out, but the band won more than it lost.") }
        return row.belowSec >= row.aboveSec
            ? String(localized: "Mostly under the band — there was more in the tank today.")
            : String(localized: "Mostly over the band — harder than today's Charge could pay for.")
    }

    /// m:ss off the banked seconds (sessions are an hour-scale affair).
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Minimised bar

/// The session put away with ⌄, as a bar above the tab bar (the gym session's bar): the shield, the phase,
/// the heart rate and the clock. Tap to bring the screen back.
struct LiveSessionBar: View {
    @ObservedObject var holder: LiveSessionHolder
    /// Applied only while the bar shows, so a hidden bar takes no room.
    var insets = EdgeInsets()

    var body: some View {
        if let runner = holder.runner, !holder.isPresented, runner.finalRow == nil {
            Button { holder.isPresented = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StrandPalette.metricCyan)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(StrandPalette.metricCyan.opacity(0.18)))
                        .accessibilityHidden(true)
                    LiveSessionBarReadout(runner: runner)
                }
                .padding(8)
                .liveSessionBarGlass()
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open the running session"))
            .padding(insets)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct LiveSessionBarReadout: View {
    @ObservedObject var runner: LiveSessionRunner

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Live Session")
                    .font(StrandFont.pro(15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(runner.output?.status == .active ? String(localized: "Guarding")
                     : runner.output?.status == .warmup ? String(localized: "Warming up")
                     : String(localized: "No live reading"))
                    .font(StrandFont.pro(13))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill").font(.system(size: 11, weight: .semibold))
                    Text(runner.output?.smoothedBpm.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(StrandFont.pro(15, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(runner.output?.smoothedBpm == nil ? StrandPalette.textTertiary : StrandPalette.healthHeart)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ActiveWorkoutClock.clock(LiveSessionView.elapsed(runner, at: ctx.date)))
                        .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(StrandPalette.metricCyan)
                }
            }
            .padding(.trailing, 8)
        }
    }
}

private extension View {
    /// Interactive Liquid Glass on iOS 26 / macOS 26, a material capsule before.
    @ViewBuilder func liveSessionBarGlass() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
        #else
        self.background(.ultraThinMaterial, in: Capsule())
        #endif
    }
}
