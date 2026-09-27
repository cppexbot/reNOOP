//  SleepHealthView.swift
//  NOOP · Sleep — the tab root, laid out like the Sleep page of the iOS 26 Health app.
//
//  A ‹ date › pager names the picked night once; its card carries the Sleep score ring, time asleep and
//  the stages. Then "Show More Sleep Data" (`SleepMoreDataView`: the D / W / M / 6M chart with Stages ·
//  Amounts · Comparisons), sleep-schedule and vitals tiles two to a row, and Highlights. The ••• menu edits the night, adds a nap and logs sleep marks. The
//  night data comes from the same `SleepModel` pipeline every other sleep surface reads.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

struct SleepHealthView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    @State private var range: SleepRange = Self.initialRange
    /// 0 = the newest night, 1 = the one before, … (days in `navDays`).
    @State private var nightOffset = 0
    @State private var showNightPicker = false
    @State private var showMoreData = Self.initialShowMore
    @State private var wakeEdit: WakeEdit?
    @State private var addNap: AddNapSeed?
    @State private var sleepUndo: SleepUndo?
    @State private var sleepUndoTask: Task<Void, Never>?

    // Loaded inputs, as the full Sleep screen loads them.
    @State private var allSessions: [CachedSleepSession] = []
    @State private var habitualMidsleepSec: Int?
    @State private var motionByStart: [Int: [Double]] = [:]
    @State private var navDays: [[CachedSleepSession]] = []
    @State private var model: SleepModel?
    @State private var night: Night?
    @State private var entries: [SleepNightEntry] = []
    /// Bumped on appear so the schedule card re-reads the reminder's per-day times after an edit.
    @State private var scheduleRevision = 0

    private static let topAnchorID = "sleepHealth.top"

    /// The night to open on ("yyyy-MM-dd", the day it ended), when a link names one — the Summary's Sleep
    /// card on a past day. nil opens on the newest night.
    private let initialWakeDay: String?
    @State private var appliedInitialWakeDay = false

    init(initialWakeDay: String? = nil) {
        self.initialWakeDay = initialWakeDay
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topAnchorID)
                    pageContent
                        .padding(.horizontal, NoopMetrics.screenHPadding)
                        .padding(.top, NoopMetrics.space3)
                    Color.clear.frame(height: NoopMetrics.tabBarClearance)
                }
                #if os(macOS)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                #endif
            }
            .background(StrandPalette.summaryCanvas.ignoresSafeArea())
            #if os(iOS)
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(Self.topAnchorID, anchor: .top) }
            }
            #endif
        }
        .navigationTitle(Text("Sleep"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) { moreMenu }
        }
        .sheet(isPresented: $showMoreData) {
            SleepMoreDataView(navDays: navDays, habitualMidsleepSec: habitualMidsleepSec,
                              motionByStart: motionByStart, typicalStageMin: typicalStageMin,
                              sleepDebtLedger: model?.sleepDebtLedger,
                              range: range, nightOffset: nightOffset, tab: Self.initialMoreTab)
                .environmentObject(repo)
        }
        .sheet(item: $wakeEdit) { edit in editSheet(edit) }
        .sheet(item: $addNap) { seed in napSheet(seed) }
        .refreshable { await repo.refresh() }
        .task(id: repo.refreshSeq) { await load() }
        .onAppear { scheduleRevision += 1 }
        .onChangeCompat(of: nightOffset) { offset in
            night = offset == 0 ? model?.night
                : SleepModel.decodedNight(at: offset, navDays: navDays,
                                          habitualMidsleepSec: habitualMidsleepSec, motionByStart: motionByStart)
        }
    }

    // MARK: - Night navigation

    /// Right = an older night, left = a newer one; clamped to the nights on record.
    private var nightSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 50, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                let next = min(max(0, nightOffset + (dx > 0 ? 1 : -1)), max(0, navDays.count - 1))
                if next != nightOffset { withAnimation(StrandMotion.interactive) { nightOffset = next } }
            }
    }

    private var nightPicker: some View {
        DatePicker("", selection: Binding(
            get: { night.map { Date(timeIntervalSince1970: TimeInterval($0.session.endTs)) } ?? Date() },
            set: { picked in
                let day = Calendar.current.startOfDay(for: picked)
                if let idx = navDays.firstIndex(where: { group in
                    group.last.map { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.endTs))) } == day
                }) {
                    nightOffset = idx
                }
                showNightPicker = false
            }
        ), in: ...Date(), displayedComponents: [.date])
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(12)
        .frame(minWidth: 320, minHeight: 360)
        #if os(iOS)
        .presentationCompactAdaptation(.popover)
        #endif
    }

    // MARK: - Ranges

    /// "20 Sep – 26 Sep 2026": the span a range window covers.
    static func rangeLabel(_ window: SleepRangeWindow) -> String {
        guard let first = window.slotStarts.first else { return "" }
        let last = window.range == .sixMonths ? Date() : (window.slotStarts.last ?? first)
        let locale = AppLanguage.activeLocale
        return "\(first.formatted(.dateTime.day().month(.abbreviated).locale(locale))) – \(last.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)))"
    }

    // MARK: - Page

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sleepUndo { undoBanner(sleepUndo) }
            SleepFreshnessNote(latestWakeTs: model?.night.session.endTs)
            nightPager
            Group {
                if let night, night.stages.asleep > 0 {
                    SleepNightCard(score: score(for: night), source: scoreSource(for: night),
                                   stages: night.stages, bedtime: night.onsetDate,
                                   wake: Date(timeIntervalSince1970: TimeInterval(night.session.endTs)),
                                   intervals: nightOffset == 0 ? (model?.intervals ?? night.intervals) : night.intervals)
                } else {
                    SummaryCard {
                        Text("No sleep data")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(nightSwipe)
            Button { showMoreData = true } label: {
                Text("Show More Sleep Data")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NoopMetrics.space2)
            }
            .buttonStyle(.plain)
            let schedule = scheduleTiles
            if !schedule.isEmpty {
                SummarySectionHeader(title: "Sleep Schedule")
                SleepTileGrid(tiles: schedule)
            }
            scheduleSection
            if let night {
                // Draws nothing until the body-clock estimate is readable.
                BodyClockDialSection(actualBedHour: SleepNightDecoding.localClockHour(night.session.effectiveStartTs),
                                     actualWakeHour: SleepNightDecoding.localClockHour(night.session.endTs),
                                     plain: true)
            }
            let vitals = vitalTiles
            if !vitals.isEmpty {
                SummarySectionHeader(title: "Vitals")
                SleepTileGrid(tiles: vitals)
            }
            highlightsSection
        }
    }

    /// ‹ date › — the one place the picked night is named; the arrows step through the nights on record
    /// and the date opens a calendar.
    private var nightPager: some View {
        DayPager(title: night.map { Self.pagerLabel($0.session, offset: nightOffset) } ?? " ",
                 canGoBack: nightOffset < navDays.count - 1, canGoForward: nightOffset > 0,
                 onBack: { nightOffset += 1 }, onForward: { nightOffset -= 1 },
                 backLabel: "Previous night", forwardLabel: "Next night",
                 showPicker: $showNightPicker) { nightPicker }
    }

    /// "Last Night" for the newest night, else its date.
    static func pagerLabel(_ session: CachedSleepSession, offset: Int) -> String {
        offset == 0 ? String(localized: "Last Night") : shortDayLabel(session)
    }

    // MARK: - Tiles

    /// The picked night against its need, plus the running debt and regularity. One need throughout: the
    /// night's own (imported, else personal), the figure "Hours vs needed" reads.
    private var scheduleTiles: [SleepMetricTile] {
        let tint = StrandPalette.healthSleepDeep
        var tiles: [SleepMetricTile] = []
        if let night, night.stages.asleep > 0,
           let need = SleepMoreData.needMin(dayKeys: [wakeDayKey(night)], days: repo.days,
                                            imported: repo.importedSleep) {
            tiles.append(SleepMetricTile(id: "need", icon: "target", title: String(localized: "sleep.tile.need", defaultValue: "Sleep Need"), tint: tint,
                                         value: .duration(need),
                                         caption: String(localized: "\(SleepMoreDataView.percent(night.stages.asleep / need)) of need slept")))
        }
        if let model, !model.sleepDebtLedger.nights.isEmpty {
            let ledger = model.sleepDebtLedger
            tiles.append(SleepMetricTile(id: "debt", icon: "hourglass", title: String(localized: "Sleep Debt"), tint: tint,
                                         value: ledger.isDebt ? .duration(ledger.magnitudeMin) : .text(String(localized: "No debt")),
                                         caption: String(localized: "Last \(ledger.nightCount) nights")))
        }
        let recent = entries.suffix(14)
        if !recent.isEmpty {
            let bed = recent.map(\.onsetOfNightMin).reduce(0, +) / Double(recent.count)
            let wake = recent.map(\.wakeOfNightMin).reduce(0, +) / Double(recent.count)
            tiles.append(SleepMetricTile(id: "bedtime", icon: "moon.stars.fill", title: String(localized: "sleep.tile.bedtime", defaultValue: "Bedtime"),
                                         tint: tint, value: .text(SleepMoreDataView.clock(minutesOfNight: bed)),
                                         caption: String(localized: "Up at \(SleepMoreDataView.clock(minutesOfNight: wake))")))
        }
        if let pct = model?.consistency.latest {
            tiles.append(SleepMetricTile(id: "regularity", icon: "clock.arrow.circlepath", title: String(localized: "Regularity"),
                                         tint: tint, value: .number(Self.percentNumber(pct / 100), unit: "%")))
        }
        if let night {
            let napMin = Self.napMinutes(night)
            if napMin > 0 {
                tiles.append(SleepMetricTile(id: "naps", icon: "powersleep", title: String(localized: "Naps"), tint: tint,
                                             value: .duration(napMin)))
            }
        }
        return tiles
    }

    /// The picked night's vitals, from its own row.
    private var vitalTiles: [SleepMetricTile] {
        guard let night, let row = dailyRow(for: night) else { return [] }
        var tiles: [SleepMetricTile] = []
        if let hr = row.restingHr {
            tiles.append(SleepMetricTile(id: "rhr", icon: "heart.fill", title: String(localized: "Resting HR"),
                                         tint: StrandPalette.healthHeart,
                                         value: .number("\(hr)", unit: String(localized: "sleep.unit.bpm", defaultValue: "BPM"))))
        }
        if let hrv = row.avgHrv {
            tiles.append(SleepMetricTile(id: "hrv", icon: "waveform.path.ecg", title: String(localized: "sleep.tile.hrv", defaultValue: "HRV"),
                                         tint: StrandPalette.healthHeart,
                                         value: .number("\(Int(hrv.rounded()))", unit: String(localized: "sleep.unit.ms", defaultValue: "ms"))))
        }
        if let resp = row.respRateBpm {
            tiles.append(SleepMetricTile(id: "resp", icon: "lungs.fill", title: String(localized: "sleep.tile.resp", defaultValue: "Respiratory"),
                                         tint: StrandPalette.healthRespiratory,
                                         value: .number(resp.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.activeLocale)),
                                                        unit: String(localized: "br/min"))))
        }
        if let spo2 = row.spo2Pct {
            tiles.append(SleepMetricTile(id: "spo2", icon: "drop.fill", title: String(localized: "sleep.tile.spo2", defaultValue: "Blood Oxygen"),
                                         tint: StrandPalette.healthOxygen,
                                         value: .number(Self.percentNumber(spo2 / 100), unit: "%")))
        }
        if let skin = SkinTempDisplay.leadReading(absC: row.skinTempC, devC: row.skinTempDevC,
                                                  prefer: SkinTempDisplay.Kind(rawValue: skinTempDisplayRaw) ?? .absolute) {
            tiles.append(SleepMetricTile(id: "skin", icon: "thermometer.medium", title: String(localized: "sleep.tile.skin", defaultValue: "Skin Temp"),
                                         tint: StrandPalette.healthTemperature,
                                         value: .number(SkinTempDisplay.numberString(skin.value, kind: skin.kind, fahrenheit: fahrenheit),
                                                        unit: SkinTempDisplay.unitSymbol(kind: skin.kind, fahrenheit: fahrenheit))))
        }
        return tiles
    }

    /// "85" for 0.85: the number of a percentage, its sign set apart as a unit.
    static func percentNumber(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))"
    }

    /// The day's blocks outside the bridged main night: its naps (#508, #555).
    static func naps(_ night: Night) -> [CachedSleepSession] {
        let groupStarts = night.mainGroupStarts
        return night.sourceBlocks
            .filter { !groupStarts.contains($0.startTs) }
            .sorted { $0.effectiveStartTs < $1.effectiveStartTs }
    }

    static func napMinutes(_ night: Night) -> Double {
        naps(night).reduce(0) { $0 + Double($1.endTs - $1.effectiveStartTs) / 60 }
    }

    private var fahrenheit: Bool {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                     override: temperatureRaw) == .fahrenheit
    }

    private func wakeDayKey(_ night: Night) -> String {
        Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(night.session.endTs)))
    }

    private func dailyRow(for night: Night) -> DailyMetric? {
        let key = wakeDayKey(night)
        return repo.days.last(where: { $0.day == key })
    }

    /// The night's score as every other surface reads it: the imported figure for its wake-day, else the
    /// Rest composite of that day's row (`SleepModel.performanceSeries`).
    private func score(for night: Night) -> SleepScore? {
        SleepScore.make(daily: dailyRow(for: night),
                        importedPct: repo.importedSleep[wakeDayKey(night)]?.performancePct)
    }

    private func scoreSource(for night: Night) -> String {
        if repo.importedSleep[wakeDayKey(night)]?.performancePct != nil { return String(localized: "Whoop") }
        return repo.activeDeviceIsOura ? String(localized: "Oura") : String(localized: "On-device")
    }

    private var typicalStageMin: [SleepStage: Double] {
        guard let model else { return [:] }
        var out: [SleepStage: Double] = [:]
        out[.deep] = model.typicalDeepMin
        out[.rem] = model.typicalRemMin
        out[.light] = model.typicalLightMin
        return out
    }

    // MARK: - Editing (sheets from the ••• menu)

    private func edit(_ block: CachedSleepSession, userEdited: Bool) {
        wakeEdit = WakeEdit(detectedStartTs: block.startTs, bedTs: block.effectiveStartTs, wakeTs: block.endTs,
                            stagesJSON: block.stagesJSON, userEdited: userEdited)
    }

    private func editSheet(_ edit: WakeEdit) -> some View {
        // The night's RECORDED coverage for the #940 guards: from the detected onset (or an earlier
        // hand-set one) through the current wake.
        let coverageLo = min(edit.detectedStartTs, edit.bedTs)
        return SleepTimeEditor(bedTs: edit.bedTs, wakeTs: edit.wakeTs,
                               coverage: coverageLo...max(edit.wakeTs, coverageLo + 1),
                               suppressesReDetection: !edit.userEdited,
                               onSave: { newBedTs, newWakeTs in
            await repo.editSleepTimes(detectedStartTs: edit.detectedStartTs, oldEndTs: edit.wakeTs,
                                      storedStagesJSON: edit.stagesJSON,
                                      newStartTs: newBedTs, newEndTs: newWakeTs)
            // Re-score so Rest / recovery honour the corrected window, then refresh the read cache.
            await intelligence.analyzeRecent()
            await repo.refresh()
        }, onDelete: {
            // Durably tombstoned so a re-detect does not bring it back (#68); undoable for a few seconds (#65).
            let snapshot = await repo.deleteSleepSession(detectedStartTs: edit.detectedStartTs, endTs: edit.wakeTs)
            await intelligence.analyzeRecent()
            await repo.refresh()
            if let snapshot { presentUndo(snapshot, displayStart: edit.bedTs, windowEnd: edit.wakeTs) }
        })
    }

    /// A missed nap is staged from raw as its own session, never folded into the night (#508).
    private func napSheet(_ seed: AddNapSeed) -> some View {
        SleepTimeEditor(bedTs: seed.bedTs, wakeTs: seed.wakeTs,
                        title: "Add a nap",
                        blurb: "Pick when the nap started and ended. NOOP stages it from your data as its own session, separate from the night's sleep.",
                        bedLabel: "Nap started", wakeLabel: "Nap ended") { startTs, endTs in
            await repo.addManualNap(startTs: startTs, endTs: endTs)
            await intelligence.analyzeRecent()
            await repo.refresh()
        }
    }

    // MARK: - Delete undo (#65)

    struct SleepUndo {
        let snapshot: SleepDeletionSnapshot
        let message: String
    }

    private func presentUndo(_ snapshot: SleepDeletionSnapshot, displayStart: Int, windowEnd: Int) {
        sleepUndoTask?.cancel()
        // A hand-edited / added night writes no tombstone, so only a detected one promises no re-detection.
        let message = snapshot.session.userEdited
            ? String(localized: "Sleep deleted.")
            : String(localized: "Sleep deleted. NOOP won't detect sleep between \(Self.clock(displayStart)) and \(Self.clock(windowEnd)) again.")
        withAnimation(.easeOut(duration: 0.2)) { sleepUndo = SleepUndo(snapshot: snapshot, message: message) }
        let armed = snapshot.session.startTs
        sleepUndoTask = Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if sleepUndo?.snapshot.session.startTs == armed {
                    withAnimation(.easeOut(duration: 0.2)) { sleepUndo = nil }
                }
            }
        }
    }

    private func undoBanner(_ undo: SleepUndo) -> some View {
        NoticeCard(title: Text(verbatim: undo.message), systemImage: "trash.fill", tone: .info,
                   actionTitle: "Undo", action: {
                       Task {
                           sleepUndoTask?.cancel()
                           await repo.undoDeleteSleepSession(undo.snapshot)
                           await intelligence.analyzeRecent()
                           await repo.refresh()
                           withAnimation(.easeOut(duration: 0.2)) { sleepUndo = nil }
                       }
                   },
                   onDismiss: {
                       sleepUndoTask?.cancel()
                       withAnimation(.easeOut(duration: 0.2)) { sleepUndo = nil }
                   })
            .transition(.opacity)
    }

    // MARK: - Your schedule

    /// Health's "Your Schedule": the next wake, and the way into the Full Schedule.
    private var scheduleSection: some View {
        let _ = scheduleRevision
        return VStack(alignment: .leading, spacing: 10) {
            SummarySectionHeader(title: "Your Schedule")
            NavigationLink(value: TabRoute.sleepSchedule) {
                SleepNextWakeCard(inputs: SleepScheduleStore.inputs(behavior: behavior, model: appModel),
                                  trailing: AnyView(fullScheduleRow))
            }
            .buttonStyle(.plain)
        }
    }

    private var fullScheduleRow: some View {
        VStack(spacing: 10) {
            Divider().overlay(StrandPalette.hairline)
            HStack {
                Text("Full Schedule & Options")
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    // MARK: - Highlights (grouped canvas)

    @ViewBuilder private var highlightsSection: some View {
        let highlights = SleepHighlights.make(entries: entries, anchor: Date())
        if !highlights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SummarySectionHeader(title: "Highlights")
                ForEach(highlights) { SleepHighlightCard(highlight: $0) }
            }
        }
    }

    // MARK: - Menu

    private var moreMenu: some View {
        Menu {
            if let target = night?.editTarget {
                Button { edit(target, userEdited: target.userEdited) } label: {
                    Label("Edit sleep times", systemImage: "pencil")
                }
            }
            if let night {
                let naps = Self.naps(night)
                if naps.isEmpty {
                    Button { addNap = AddNapSeed(forNight: night) } label: { Label("Add a nap", systemImage: "powersleep") }
                } else {
                    // Each of the day's naps opens the same editor as the night: change its times or delete it.
                    Menu {
                        ForEach(naps, id: \.startTs) { nap in
                            Button { edit(nap, userEdited: true) } label: {
                                Text(verbatim: "\(Self.clock(nap.effectiveStartTs)) – \(Self.clock(nap.endTs))")
                            }
                        }
                        Divider()
                        Button { addNap = AddNapSeed(forNight: night) } label: { Label("Add a nap", systemImage: "plus") }
                    } label: {
                        Label("Naps", systemImage: "powersleep")
                    }
                }
            }
            Divider()
            Button { logMark(.bedtime) } label: { Label("Going to sleep", systemImage: "moon.zzz.fill") }
            Button { logMark(.wake) } label: { Label("I'm awake", systemImage: "sun.max.fill") }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text("More"))
    }

    private func logMark(_ type: SleepMarkType) {
        SleepMark.log(SleepMark(type: type), repo: repo, live: live)
    }

    // MARK: - Loading

    private func load() async {
        allSessions = await repo.allSleepSessions()
        habitualMidsleepSec = await repo.habitualMidsleepSec()
        motionByStart = await repo.sessionMotions(sessions: allSessions)
        let sessions = allSessions.isEmpty ? repo.sleeps : allSessions
        navDays = SleepModel.navDays(navSessions: sessions)
        model = SleepModel.build(SleepModelInputs(
            days: repo.days, sleeps: repo.sleeps, allSessions: allSessions,
            importedSleep: repo.importedSleep, habitualMidsleepSec: habitualMidsleepSec,
            motionByStart: motionByStart))
        entries = SleepHistory.entries(navDays: navDays, habitualMidsleepSec: habitualMidsleepSec)
        nightOffset = 0
        night = model?.night
        if let key = initialWakeDay, !appliedInitialWakeDay {
            appliedInitialWakeDay = true
            if let i = SleepNightLoader.index(ofWakeDay: key, in: navDays), i != 0 { nightOffset = i }
        }
    }

    static func clock(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale))
    }

    /// "Fri 26 Sep" — the Sleep score card's date.
    static func shortDayLabel(_ session: CachedSleepSession) -> String {
        Date(timeIntervalSince1970: TimeInterval(session.endTs))
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguage.activeLocale))
    }

    /// DEBUG screenshot runs open "Show More Sleep Data" with `--sleep-more [stages|amounts|comparisons]`.
    private static var initialShowMore: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("--sleep-more")
        #else
        return false
        #endif
    }

    private static var initialMoreTab: SleepMoreTab {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--sleep-more"), i + 1 < args.count,
           let tab = SleepMoreTab(rawValue: args[i + 1]) {
            return tab
        }
        #endif
        return .stages
    }

    /// Day view, unless a DEBUG screenshot run asks for another with `--sleep-range week|month|sixMonths`.
    private static var initialRange: SleepRange {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--sleep-range"), i + 1 < args.count,
           let range = SleepRange(rawValue: args[i + 1]) {
            return range
        }
        #endif
        return .day
    }
}

extension SleepMark {
    /// Record a mark: a timestamped log line and metric point, never a change to detected sleep. Shared
    /// by the Sleep marks card and the Sleep page's menu so both write the same thing.
    @MainActor
    static func log(_ mark: SleepMark, repo: Repository, live: LiveState) {
        live.append(log: mark.logLine)
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.upsertMetricSeries([mark.metricPoint], deviceId: repo.deviceId)
        }
    }
}
