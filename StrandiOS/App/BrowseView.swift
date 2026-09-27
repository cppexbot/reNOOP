//  BrowseView.swift
//  NOOP · the Browse (search) tab — every screen outside the three main tabs, in one searchable list.
//
//  Modelled on the iOS 26 Health app's search tab: a large title, a bold "Categories" header over one
//  card of rows (a tinted glyph, the name, a chevron) in alphabetical order, and a second, headerless
//  card below it, as Health keeps Clinical Documents apart. The rows push `MoreDestination` values so
//  a re-tap of the tab pops them off its bound path (#135/#198), except Live Session, which opens over
//  the whole display as it does from the Summary "+". Settings is not here: it opens from the Summary
//  avatar (Health's profile sheet).

import SwiftUI
import StrandDesign

struct BrowseView: View {
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true
    @EnvironmentObject private var router: NavRouter
    @State private var query = ""

    struct Entry: Identifiable {
        let id: MoreDestination
        let title: String
        let icon: String
        let tint: Color
    }

    /// Health's categories card: the places to read and log data.
    private var categories: [Entry] {
        var rows = [
            Entry(id: .allMetrics, title: String(localized: "All Metrics"), icon: "square.grid.2x2.fill", tint: StrandPalette.healthOxygen),
            Entry(id: .trends, title: String(localized: "Trends"), icon: HealthTrendsUnits.icon, tint: StrandPalette.accent),
            Entry(id: .journal, title: String(localized: "Journal"), icon: "book.pages.fill", tint: StrandPalette.healthMind),
            Entry(id: .insightsHub, title: String(localized: "What Moves You"), icon: "wand.and.sparkles", tint: StrandPalette.healthTemperature),
            Entry(id: .labBook, title: String(localized: "Lab Book"), icon: "list.clipboard.fill", tint: StrandPalette.healthSleepCore),
        ]
        if coachEnabled {
            rows.append(Entry(id: .coach, title: String(localized: "Coach"), icon: "sparkles", tint: StrandPalette.healthBody))
        }
        return rows.sorted(by: Self.alphabetical)
    }

    /// The second card: tools that act rather than show history.
    private var tools: [Entry] {
        [
            Entry(id: .live, title: String(localized: "Heart Rate"), icon: "waveform.path.ecg", tint: StrandPalette.healthHeart),
            Entry(id: .breathe, title: String(localized: "Mindfulness"), icon: "lungs.fill", tint: StrandPalette.healthRespiratory),
            Entry(id: .devices, title: String(localized: "Devices"), icon: "sensor.tag.radiowaves.forward.fill", tint: StrandPalette.textSecondary),
        ].sorted(by: Self.alphabetical)
    }

    private static func alphabetical(_ a: Entry, _ b: Entry) -> Bool {
        a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    /// Rows whose title contains the query (case- and diacritic-insensitive), as one flat list.
    private var hits: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return (categories + tools)
            .filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted(by: Self.alphabetical)
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        List {
            if searching {
                Section { rows(hits) }
            } else {
                Section {
                    rows(categories)
                } header: {
                    Text("Categories")
                        .font(StrandFont.pro(22, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .textCase(nil)
                        .padding(.bottom, 4)
                }
                Section {
                    rows(tools)
                    if liveSessionsBeta { liveSessionRow }
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
            if searching && hits.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    /// Live Session opens a cover, not a page, so its row is a button (same look, no chevron).
    private var liveSessionRow: some View {
        Button { router.openLiveSession() } label: {
            Label {
                Text("Live Session")
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(StrandPalette.metricCyan)
            }
        }
        .frame(height: 51)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }

    private func rows(_ entries: [Entry]) -> some View {
        ForEach(entries) { entry in
            NavigationLink(value: entry.id) {
                Label {
                    Text(entry.title)
                        .font(StrandFont.pro(17, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                } icon: {
                    Image(systemName: entry.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(entry.tint)
                }
            }
            // Health's rows are 51 pt tall; the default insets on top of the label ran taller.
            .frame(height: 51)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        }
    }
}

/// Every screen the Browse list links to, as a `Hashable` value the tab's `NavigationPath` can carry
/// (#198): a closure-destination push would bypass the path and be un-poppable on tab re-tap. The
/// per-screen chrome lives at the single `navigationDestination(for:)` registration in
/// `RootTabView.browseTab`.
enum MoreDestination: Hashable {
    case allMetrics, trends, journal, insightsHub, labBook, coach
    case live, breathe, devices

    @ViewBuilder var destination: some View {
        switch self {
        case .allMetrics:  AllMetricsView()
        case .trends:      TrendsView()
        case .journal:     JournalView()
        case .insightsHub: InsightsHubView()
        case .labBook:     LabBookView()
        case .coach:       CoachView()
        case .live:        LiveView()
        case .breathe:     BreathingView()
        case .devices:     DevicesView()
        }
    }
}
