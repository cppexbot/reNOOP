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
            Entry(id: .insights, title: String(localized: "Insights"), icon: "lightbulb.fill", tint: StrandPalette.metricAmber),
            Entry(id: .trends, title: String(localized: "Trends"), icon: "chart.line.uptrend.xyaxis", tint: StrandPalette.metricCyan),
            Entry(id: .allMetrics, title: String(localized: "All Metrics"), icon: "list.bullet", tint: StrandPalette.metricCyan),
        ]
        if coachEnabled {
            insights.insert(Entry(id: .coach, title: String(localized: "Coach"), icon: "sparkles",
                                  tint: StrandPalette.metricPurple), at: 0)
        }
        return [
            Category(id: String(localized: "Insights"), entries: insights),
            Category(id: String(localized: "Body"), entries: [
                Entry(id: .live, title: String(localized: "Live"), icon: "waveform.path.ecg", tint: StrandPalette.metricRose),
                Entry(id: .labBook, title: String(localized: "Lab Book"), icon: "books.vertical.fill", tint: StrandPalette.metricAmber),
                Entry(id: .stress, title: String(localized: "Stress"), icon: "bolt.heart.fill", tint: StrandPalette.metricAmber),
                Entry(id: .breathe, title: String(localized: "Breathe"), icon: "wind", tint: StrandPalette.metricCyan),
            ]),
            Category(id: String(localized: "App"), entries: [
                Entry(id: .alarms, title: String(localized: "Alarms"), icon: "alarm.fill", tint: StrandPalette.summaryEffortRing),
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
    case insightsHub, coach, insights, allMetrics
    case trends
    case live, labBook, stress, breathe
    case alarms, settings

    @ViewBuilder var destination: some View {
        switch self {
        case .insightsHub:     InsightsHubView()
        case .coach:           CoachView()
        case .insights:        InsightsView()
        case .allMetrics:      AllMetricsView()
        case .trends:          TrendsView()
        case .live:            LiveView()
        case .labBook:         LabBookView()
        case .stress:          StressView()
        case .breathe:         BreathingView()
        case .alarms:          SmartAlarmView()
        case .settings:        SettingsView()
        }
    }
}
