//  SummaryView.swift
//  NOOP · Summary — the home screen, modelled on the iOS 26 Apple Health Summary.
//
//  Large title (with the profile photo on its row, as in Health) over a warm → cool wash, a ‹ day › pager
//  (the same one the Sleep page uses), then Health's two
//  sections: "Pinned" (the Activity card for Charge / Effort / Rest, the Sleep card, the user's pinned
//  metrics) and "Highlights". Every card stamps when its value is from ("Today", "Yesterday", a date). All
//  data arrives in one `SummarySnapshot` from `SummaryLoader`; this view only lays it out and routes taps.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

struct SummaryView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    /// 0 = today's logical day (rolls at 04:00), 1 = yesterday, …
    @State private var dayOffset = 0
    @State private var showDayPicker = false
    @State private var snapshot = SummarySnapshot()
    /// The night that ended on the picked day, for the Sleep card.
    @State private var sleepNight: Night?

    @State private var showSettings = false
    @State private var customization: TodayCustomizationDestination?
    #if os(macOS)
    @State private var showLiveSession = false
    #endif

    // The pinned list is the shared Key Metrics selection; the editor sheet needs every Today binding.
    @AppStorage(KeyMetricPrefs.layoutKey) private var keyMetricsRaw = ""
    @AppStorage("today.keyMetricsDetailed") private var keyMetricsDetailed = false
    @AppStorage("today.keyMetricsWindowDays") private var keyMetricsWindowDays = 14
    @AppStorage(TodayLayoutPrefs.orderKey) private var sectionOrderRaw = ""
    @AppStorage(TodayLayoutPrefs.hiddenKey) private var hiddenSectionsRaw = ""
    @AppStorage(DashboardCardPrefs.selectionKey) private var dashboardCardsRaw = ""
    @AppStorage(HostedCardPrefs.selectionKey) private var hostedCardsRaw = ""

    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.skinTempDisplayKey) private var skinTempDisplayRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    private static let topAnchorID = "summary.top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Color.clear.frame(height: 0).id(Self.topAnchorID)
                    #if os(macOS)
                    header
                    #endif
                    // Raised health alerts and a running workout stay pinned above everything else, as on
                    // every earlier home: neither may be scrolled or reordered out of sight.
                    HealthAlertBanner()
                    ActiveWorkoutIndicatorSection()
                    DayPager(title: dayTitle,
                             canGoBack: dayOffset < SummaryDay.maxOffset(repo: repo), canGoForward: dayOffset > 0,
                             onBack: { dayOffset += 1 }, onForward: { dayOffset -= 1 },
                             showPicker: $showDayPicker) { dayPicker }
                        .padding(.horizontal, -8)
                    pinnedSection
                    highlightsSection
                    Color.clear.frame(height: NoopMetrics.tabBarClearance)
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .background(alignment: .top) { wash }
                #if os(macOS)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                #endif
            }
            .background(StrandPalette.summaryCanvas.ignoresSafeArea())
            #if os(iOS)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(Self.topAnchorID, anchor: .top) }
            }
            #endif
        }
        #if os(iOS)
        // Health's chrome: a native large title that folds into the bar on scroll.
        .navigationTitle(Text("Summary"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar { avatarToolbarItem }
        #endif
        .refreshable { await refresh() }
        .task(id: "sleep-\(repo.refreshSeq)-\(dayOffset)") {
            sleepNight = await SleepNightLoader.night(repo: repo, wakeDayKey: selectedKey)
        }
        .sensoryFeedbackCompat(trigger: dayOffset)
        .task(id: "\(repo.refreshSeq)-\(dayOffset)-\(dayCycleModeRaw)-\(unitSystemRaw)-\(temperatureRaw)-\(skinTempDisplayRaw)") {
            await reload()
        }
        .sheet(item: $customization) { destination in
            TodayCustomizationSheet(
                initialDestination: destination,
                sectionOrderRaw: $sectionOrderRaw,
                hiddenSectionsRaw: $hiddenSectionsRaw,
                keyMetricsRaw: $keyMetricsRaw,
                keyMetricsDetailed: $keyMetricsDetailed,
                keyMetricsWindowDays: $keyMetricsWindowDays,
                dashboardCardsRaw: $dashboardCardsRaw,
                hostedCardsRaw: $hostedCardsRaw
            )
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                                .foregroundStyle(StrandPalette.accent)
                        }
                    }
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showLiveSession) {
            LiveSessionView(onClose: { showLiveSession = false })
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        #endif
    }

    // MARK: - Header

    #if os(macOS)
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Summary")
                .font(StrandFont.rounded(34, weight: .heavy))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            SummaryStrapStatus()
            HStack(spacing: 10) {
                addButton
                avatarButton
            }
            .summaryGlassGroup(spacing: 10)
        }
        .padding(.top, NoopMetrics.space4)
        .padding(.bottom, NoopMetrics.space2)
    }
    #endif

    #if os(iOS)
    /// iOS 26: the profile photo on the large title's own row, as Health places it, folding away with the
    /// title on scroll. Earlier systems keep it as a bar item.
    @ToolbarContentBuilder private var avatarToolbarItem: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .largeTitle) {
                HStack(alignment: .center) {
                    Text("Summary")
                        .font(.largeTitle.bold())
                        .foregroundStyle(StrandPalette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    avatarButton
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { avatarButton }
        }
        #else
        ToolbarItem(placement: .topBarTrailing) { avatarButton }
        #endif
    }
    #endif

    #if os(macOS)
    @ViewBuilder private var addButton: some View {
        if liveSessionsBeta {
            headerButton(systemImage: "plus", label: "Start session") { showLiveSession = true }
        }
    }
    #endif

    private var avatarButton: some View {
        Button { showSettings = true } label: {
            SummaryAvatar(imageData: profile.avatarImageData, initials: profile.initials,
                          size: NoopMetrics.compactControlSize)
                .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .summaryGlassCircle()
        #endif
        .accessibilityLabel(Text("Profile and settings"))
    }

    #if os(macOS)
    private func headerButton(systemImage: String, label: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .summaryGlassCircle()
        .accessibilityLabel(Text(label))
    }
    #endif

    /// Health's Summary top: warm on the leading side, violet in the middle, cool on the trailing side,
    /// fading down into the canvas by the first cards.
    private var wash: some View {
        LinearGradient(
            colors: [StrandPalette.summaryWashWarm, StrandPalette.summaryWashViolet, StrandPalette.summaryWashCool],
            startPoint: .leading, endPoint: .trailing
        )
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: 0.55),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(height: 520)
        .padding(.horizontal, -NoopMetrics.screenHPadding)
        .offset(y: -300)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Rings

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    private var ringsCard: some View {
        let charge = snapshot.charge
        let chargeCaption: String? = {
            switch charge {
            case .carried(_, let caption): return caption
            case .calibrating: return charge.stateLabel
            case .scored, .noData: return nil
            }
        }()
        // Apple Watch's three hues, outermost first: Move red for Charge, Exercise green for Effort,
        // Stand cyan for Rest.
        let rings = [
            ActivityRing(id: "charge", fraction: RingFraction.of(charge.pct, max: 100),
                         start: StrandPalette.activityMoveStart, end: StrandPalette.activityMoveEnd),
            ActivityRing(id: "effort", fraction: RingFraction.of(snapshot.effort, max: 100),
                         start: StrandPalette.activityExerciseStart, end: StrandPalette.activityExerciseEnd),
            ActivityRing(id: "rest", fraction: RingFraction.of(snapshot.rest, max: 100),
                         start: StrandPalette.activityStandStart, end: StrandPalette.activityStandEnd),
        ]
        let rows = [
            SummaryRingRow(id: "charge", title: String(localized: "Charge"),
                           value: SummaryMetricReading.int(charge.pct), unit: charge.pct == nil ? "" : "%",
                           caption: chargeCaption, color: StrandPalette.activityMoveText,
                           route: .metric(HeroRingMetric.charge)),
            SummaryRingRow(id: "effort", title: String(localized: "Effort"),
                           value: SummaryMetricReading.decimal(
                               snapshot.effort.map { UnitFormatter.effortValue($0, scale: effortScale) }),
                           unit: "", caption: nil, color: StrandPalette.activityExerciseText,
                           route: .metric(HeroRingMetric.effort)),
            SummaryRingRow(id: "rest", title: String(localized: "Rest"),
                           value: SummaryMetricReading.int(snapshot.rest), unit: snapshot.rest == nil ? "" : "%",
                           caption: nil, color: StrandPalette.activityStandText,
                           // Rest is last night's sleep: it opens the Sleep page on that night.
                           route: .sleepNight(selectedKey)),
        ]
        return SummaryRingsCard(rings: rings, rows: rows,
                                stamp: stamp(dayKey: selectedKey))
    }


    // MARK: - Pinned

    private var pinnedMetrics: [KeyMetric] {
        KeyMetricPrefs.decodeEnabled(keyMetricsRaw).filter { ![.charge, .effort, .rest].contains($0) }
    }

    /// Today's logical day key (rolls at 04:00), following the live `repo.today` row.
    private var todayKey: String { SummaryDay.key(offset: 0, repo: repo) }
    /// The picked day's key.
    private var selectedKey: String { SummaryDay.key(offset: dayOffset, repo: repo) }

    private var selectedDay: Binding<Date> {
        Binding(
            get: { SummaryDay.logicalDay(offset: dayOffset) },
            set: { picked in
                dayOffset = LiquidTodayView.pickedDayOffset(pickedDate: picked,
                                                            anchorLogicalDay: SummaryDay.logicalDay(offset: 0))
                showDayPicker = false
            }
        )
    }

    /// The pager's title: "Today", "Yesterday", else "Thursday, 24 September".
    private var dayTitle: String {
        switch dayOffset {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        default:
            let text = SummaryDay.logicalDay(offset: dayOffset)
                .formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.activeLocale))
            return text.prefix(1).uppercased(with: AppLanguage.activeLocale) + text.dropFirst()
        }
    }

    /// Tapping the pager's title: a calendar for jumping further than a few days.
    private var dayPicker: some View {
        DatePicker("", selection: selectedDay,
                   in: SummaryDay.logicalDay(offset: SummaryDay.maxOffset(repo: repo))...SummaryDay.logicalDay(offset: 0),
                   displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(12)
            .frame(minWidth: 320, minHeight: 360)
            #if os(iOS)
            .presentationCompactAdaptation(.popover)
            #endif
    }


    private func stamp(_ reading: SummaryMetricReading) -> String? { stamp(dayKey: reading.stampDay) }

    /// A card's stamp. On a past day the subtitle already names the day, so a value from that very day
    /// says nothing more; only a value carried from another day is stamped. Today keeps Health's "Today".
    private func stamp(dayKey: String?) -> String? {
        guard dayOffset == 0 || dayKey != selectedKey else { return nil }
        return SummaryStamp.text(dayKey: dayKey, todayKey: todayKey)
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SummarySectionHeader(title: "Pinned", actionTitle: "Edit") { customization = .keyMetrics }
                .padding(.top, -NoopMetrics.space2)
            ringsCard
            if let sleepNight, sleepNight.stages.asleep > 0 {
                SummarySleepCard(dayKey: selectedKey, night: sleepNight)
            }
            if pinnedMetrics.isEmpty {
                Button { customization = .keyMetrics } label: {
                    SummaryCard {
                        Label("Pin metrics you care about", systemImage: "pin.fill")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
                .buttonStyle(.plain)
            } else if let inputs = snapshot.metrics {
                ForEach(pinnedMetrics) { metric in
                    if let reading = SummaryMetricReading.resolve(metric, inputs) {
                        SummaryMetricCard(metric: metric, reading: reading,
                                          series: snapshot.series[reading.seriesKey] ?? [],
                                          stamp: stamp(reading))
                    }
                }
            }
            // Health's "Show All Health Data": the whole metric catalog, one tap away.
            NavigationLink(value: TabRoute.metricExplorer) {
                SummaryCard {
                    HStack {
                        Text("Show all metrics")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Highlights

    @ViewBuilder private var highlightsSection: some View {
        if !snapshot.highlights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SummarySectionHeader(title: "Highlights")
                ForEach(snapshot.highlights) {
                    SummaryHighlightCard(highlight: $0, effortWeek: snapshot.series["effort"] ?? [])
                }
            }
        }
    }

    // MARK: - Loading

    private func reload() async {
        let unitSystem = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        let prefs = SummaryLoader.Prefs(
            dayCycleMode: DayCycleMode.persisted(dayCycleModeRaw),
            unitSystem: unitSystem,
            fahrenheit: UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw) == .fahrenheit,
            skinTempKind: SkinTempDisplay.Kind(rawValue: skinTempDisplayRaw) ?? .absolute
        )
        let loaded = await SummaryLoader.load(repo: repo, profile: profile, offset: dayOffset, prefs: prefs)
        guard !Task.isCancelled else { return }
        snapshot = loaded
    }

    /// A pull asks the strap for its history (when the link can serve one), then re-reads the store.
    private func refresh() async {
        if ble.state.historyReady { ble.syncNow() }
        await repo.refresh()
        await reload()
    }
}


private extension View {
    /// A light tick when the picked day changes; iOS 17 / macOS 14 API, a no-op before that.
    @ViewBuilder
    func sensoryFeedbackCompat(trigger: Int) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.sensoryFeedback(.selection, trigger: trigger)
        } else {
            self
        }
    }
}

/// Health's profile circle: the user's photo, else their initials on Contacts' grey monogram gradient,
/// else — with no name either — a white silhouette on the same grey.
private struct SummaryAvatar: View {
    let imageData: Data?
    var initials: String = ""
    let size: CGFloat

    var body: some View {
        if imageData != nil {
            ProfileAvatarView(imageData: imageData, size: size)
        } else {
            Circle()
                .fill(LinearGradient(colors: [StrandPalette.summaryAvatarTop, StrandPalette.summaryAvatarBottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    if initials.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.52, weight: .medium))
                            .foregroundStyle(StrandPalette.onDarkPrimary)
                            .offset(y: size * 0.06)
                    } else {
                        Text(verbatim: initials)
                            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                            .foregroundStyle(StrandPalette.onDarkPrimary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .padding(size * 0.12)
                    }
                }
                .clipShape(Circle())
                .frame(width: size, height: size)
        }
    }
}
