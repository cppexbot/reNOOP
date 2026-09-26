//  BrowseView.swift
//  NOOP · the Browse (search) tab — every screen outside the three main tabs, in one searchable list.
//
//  Modelled on the iOS 26 Health app: the search tab sits apart from the tab capsule as its own glass
//  circle, and opens a large-title list of categories with a search field. The rows push
//  `MoreDestination` values so a re-tap of the tab pops them off its bound path (#135/#198).

import SwiftUI
import StrandDesign

struct BrowseView: View {
    @EnvironmentObject private var router: NavRouter
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true
    @State private var query = ""

    struct Entry: Identifiable {
        let id: MoreDestination
        let title: String
        let icon: String
        let tint: Color
    }

    struct Category: Identifiable {
        let id: String
        let entries: [Entry]
    }

    private var groups: [Category] {
        var insights = [
            Entry(id: .insightsHub, title: String(localized: "What Moves You"), icon: "wand.and.sparkles", tint: StrandPalette.metricPurple),
            Entry(id: .intelligence, title: String(localized: "Intelligence"), icon: "brain.head.profile", tint: StrandPalette.metricPurple),
            Entry(id: .insights, title: String(localized: "Insights"), icon: "lightbulb.fill", tint: StrandPalette.metricAmber),
            Entry(id: .explore, title: String(localized: "Explore"), icon: "square.grid.2x2.fill", tint: StrandPalette.metricCyan),
            Entry(id: .compare, title: String(localized: "Compare"), icon: "rectangle.split.2x1.fill", tint: StrandPalette.metricCyan),
        ]
        if coachEnabled {
            insights.insert(Entry(id: .coach, title: String(localized: "Coach"), icon: "sparkles",
                                  tint: StrandPalette.metricPurple), at: 0)
        }
        return [
            Category(id: String(localized: "Insights"), entries: insights),
            Category(id: String(localized: "Body"), entries: [
                Entry(id: .live, title: String(localized: "Live"), icon: "waveform.path.ecg", tint: StrandPalette.metricRose),
                Entry(id: .workouts, title: String(localized: "Workouts"), icon: "figure.run", tint: StrandPalette.summaryEffortRing),
                Entry(id: .liftLog, title: String(localized: "Lift Log"), icon: "dumbbell.fill", tint: StrandPalette.summaryEffortRing),
                Entry(id: .health, title: String(localized: "Health"), icon: "heart.text.square.fill", tint: StrandPalette.metricRose),
                Entry(id: .labBook, title: String(localized: "Lab Book"), icon: "books.vertical.fill", tint: StrandPalette.metricAmber),
                Entry(id: .stress, title: String(localized: "Stress"), icon: "bolt.heart.fill", tint: StrandPalette.metricAmber),
                Entry(id: .breathe, title: String(localized: "Breathe"), icon: "wind", tint: StrandPalette.metricCyan),
                Entry(id: .intervals, title: String(localized: "Intervals"), icon: "timer", tint: StrandPalette.summaryEffortRing),
                Entry(id: .rhythm, title: String(localized: "Rhythm"), icon: "waveform.path", tint: StrandPalette.metricRose),
            ]),
            Category(id: String(localized: "Data"), entries: [
                Entry(id: .fusedRecord, title: String(localized: "Your Data, Fused"), icon: "square.stack.3d.up.fill", tint: StrandPalette.accent),
                Entry(id: .appleHealth, title: String(localized: "Apple Health"), icon: "heart.fill", tint: StrandPalette.metricRose),
                Entry(id: .miBand, title: String(localized: "Mi Band"), icon: "figure.walk.motion", tint: StrandPalette.summaryChargeRing),
                Entry(id: .dataSources, title: String(localized: "Data Sources"), icon: "externaldrive.fill", tint: StrandPalette.accent),
                Entry(id: .backupSync, title: String(localized: "Backup & Sync"), icon: "externaldrive.fill.badge.icloud", tint: StrandPalette.accent),
                // #155: HealthKit-free Apple Health path for sideloaded installs.
                Entry(id: .shortcutsExport, title: String(localized: "Shortcuts Export"), icon: "square.and.arrow.up.fill", tint: StrandPalette.accent),
                Entry(id: .noopLimitations, title: String(localized: "NOOP Limitations"), icon: "list.bullet.rectangle", tint: StrandPalette.textSecondary),
            ]),
            Category(id: String(localized: "App"), entries: [
                Entry(id: .alarms, title: String(localized: "Alarms"), icon: "alarm.fill", tint: StrandPalette.summaryEffortRing),
                Entry(id: .automations, title: String(localized: "Automations"), icon: "wand.and.stars", tint: StrandPalette.metricPurple),
                Entry(id: .testCentre, title: String(localized: "Test Centre"), icon: "stethoscope", tint: StrandPalette.metricCyan),
                Entry(id: .siriShortcuts, title: String(localized: "Siri & Shortcuts"), icon: "mic.fill", tint: StrandPalette.metricPurple),
                Entry(id: .powerSaving, title: String(localized: "Power saving"), icon: "battery.25", tint: StrandPalette.summaryChargeRing),
                Entry(id: .settings, title: String(localized: "Settings"), icon: "gearshape.fill", tint: StrandPalette.textSecondary),
            ]),
        ]
    }

    /// Groups narrowed to rows whose title contains the query (case- and diacritic-insensitive).
    private var visibleGroups: [Category] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            let hits = group.entries.filter {
                $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            return hits.isEmpty ? nil : Category(id: group.id, entries: hits)
        }
    }

    var body: some View {
        List {
            // Live Session owns the whole display, so it is an action (the shell's full-screen cover)
            // rather than a pushed row. Hidden while searching and when its beta switch is off.
            if liveSessionsBeta && query.isEmpty {
                Section {
                    Button { router.requestedDestination = .liveSession } label: {
                        Label {
                            Text("Start session").foregroundStyle(StrandPalette.textPrimary)
                        } icon: {
                            Image(systemName: "shield.lefthalf.filled").foregroundStyle(StrandPalette.metricCyan)
                        }
                    }
                }
            }
            ForEach(visibleGroups) { group in
                Section(group.id) {
                    ForEach(group.entries) { entry in
                        NavigationLink(value: entry.id) {
                            Label {
                                Text(entry.title)
                                    .foregroundStyle(StrandPalette.textPrimary)
                            } icon: {
                                Image(systemName: entry.icon)
                                    .foregroundStyle(entry.tint)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query)
        .overlay {
            if visibleGroups.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}

/// Every screen the More index links to, as a `Hashable` value the tab's `NavigationPath` can carry
/// (#198): a closure-destination push would bypass the path and be un-poppable on tab re-tap. The
/// per-screen chrome the old inline links applied lives at the single `navigationDestination(for:)`
/// registration in `RootTabView.browseTab`.
enum MoreDestination: Hashable {
    case insightsHub, intelligence, coach, insights, explore, compare
    case live, workouts, liftLog, health, labBook, stress, breathe, intervals, rhythm
    case fusedRecord, appleHealth, miBand, dataSources, backupSync, shortcutsExport, noopLimitations
    case alarms, automations, testCentre, siriShortcuts, powerSaving, settings

    @ViewBuilder var destination: some View {
        switch self {
        case .insightsHub:     InsightsHubView()
        case .intelligence:    IntelligenceView()
        case .coach:           CoachView()
        case .insights:        InsightsView()
        case .explore:         MetricExplorerView()
        case .compare:         CompareView()
        case .live:            LiveView()
        case .workouts:        WorkoutsView()
        case .liftLog:         LiftLogView()
        case .health:          HealthView()
        case .labBook:         LabBookView()
        case .stress:          StressView()
        case .breathe:         BreathingView()
        case .intervals:       IntervalTimerView()
        case .rhythm:          RhythmHost()
        case .fusedRecord:     FusedRecordHost()
        case .appleHealth:     AppleHealthView()
        case .miBand:          XiaomiBandView()
        case .dataSources:     DataSourcesView()
        case .noopLimitations: NoopLimitationsView()
        case .backupSync:      BackupSyncView()
        case .shortcutsExport: ShortcutExportSettingsView()
        case .alarms:          SmartAlarmView()
        case .automations:     AutomationsView()
        case .testCentre:      TestCentreView()
        case .siriShortcuts:   SiriShortcutsSettingsView()
        case .powerSaving:     PowerSavingView()
        case .settings:        SettingsView()
        }
    }
}
