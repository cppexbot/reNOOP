//  WorkoutHistoryView.swift
//  NOOP · every workout, newest first, grouped by month — the Fitness app's "All Workouts" list. The title
//  is a menu that narrows the list to one activity, as Fitness does.

import SwiftUI
import StrandDesign
import WhoopStore

struct WorkoutHistoryView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine

    @State private var rows: [WorkoutRow] = []
    @State private var loaded = false
    /// nil = every activity.
    @State private var sportFilter: String?
    @State private var editing: EditTarget?

    /// `.some(nil)` never happens here: adding lives on the Workouts tab. `isCopy` pre-fills without
    /// replacing, as `Repository.saveManualWorkout` requires for an imported row.
    private struct EditTarget: Identifiable {
        let row: WorkoutRow
        var isCopy = false
        let id = UUID()
    }

    private var sports: [String] {
        var counts: [String: Int] = [:]
        for r in rows { counts[WorkoutSource.displaySport(r.sport), default: 0] += 1 }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    private var visible: [WorkoutRow] {
        guard let sportFilter else { return rows }
        return rows.filter { WorkoutSource.displaySport($0.sport) == sportFilter }
    }

    private var months: [(title: String, rows: [WorkoutRow])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: visible) { row -> Date in
            let d = Date(timeIntervalSince1970: TimeInterval(row.startTs))
            return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
        }
        // Standalone month name plus the bare year ("Сентябрь 2026"), without the "г." a year template adds.
        let f = DateFormatter()
        f.dateFormat = "LLLL"
        return groups.keys.sorted(by: >).map { month in
            let title = f.string(from: month).capitalized + " \(cal.component(.year, from: month))"
            return (title, groups[month]!.sorted { $0.startTs > $1.startTs })
        }
    }

    var body: some View {
        List {
            if sports.count > 1 {
                filterChips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(months, id: \.title) { month in
                Section {
                    ForEach(month.rows) { row in
                        NavigationLink(value: TabRoute.workout(row)) {
                            WorkoutHistoryRow(row: row)
                        }
                        .listRowBackground(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(StrandPalette.summaryCard))
                        .listRowSeparator(.hidden)
                        .swipeActions {
                            Button(role: .destructive) { delete(row) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu { rowMenu(row) }
                    }
                } header: {
                    Text(month.title)
                        .font(StrandFont.pro(22, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        .listRowSpacing(12)
        #endif
        .scrollContentBackground(.hidden)
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("All Workouts"))
        .overlay {
            if loaded && visible.isEmpty {
                EmptyStateView(title: Text("No Workouts"), systemImage: "figure.run")
            }
        }
        .task(id: repo.refreshSeq) {
            rows = await repo.workoutRows(days: 4000).sorted { $0.startTs > $1.startTs }
            loaded = true
        }
        .sheet(item: $editing) { target in
            ManualWorkoutSheet(editing: target.row) { row, replacing in
                Task {
                    await repo.saveManualWorkout(row, replacing: target.isCopy ? nil : replacing)
                    await intelligence.analyzeRecent()
                    await repo.refresh()
                }
            }
        }
    }

    /// Fitness's filter capsules: "All" first, then each activity the history holds, most frequent first.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(String(localized: "All"), selected: sportFilter == nil) { sportFilter = nil }
                ForEach(sports, id: \.self) { sport in
                    chip(WorkoutSource.localizedSport(sport), selected: sportFilter == sport) { sportFilter = sport }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.pro(15, weight: .semibold))
                .foregroundStyle(selected ? StrandPalette.fitnessOnAccent : StrandPalette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected ? StrandPalette.activityExerciseText : StrandPalette.summaryCard))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func rowMenu(_ row: WorkoutRow) -> some View {
        if row.sport == "detected" {
            Menu("Label as…") {
                ForEach(WorkoutQuickStart.defaults + ["HIIT", "Yoga", "Hiking", "Tennis"], id: \.self) { sport in
                    Button(WorkoutSource.localizedSport(sport)) {
                        Task { await repo.relabelDetected(row, sport: sport); await repo.refresh() }
                    }
                }
            }
            Button("Not a Workout", systemImage: "xmark.circle") {
                Task { await repo.dismissDetected(row); await repo.refresh() }
            }
        } else if WorkoutSource.classify(row.source) == .manual {
            Button("Edit", systemImage: "pencil") { editing = EditTarget(row: row) }
        } else {
            Button("Duplicate as Manual", systemImage: "plus.square.on.square") {
                editing = EditTarget(row: row, isCopy: true)
            }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { delete(row) }
    }

    private func delete(_ row: WorkoutRow) {
        // #524: also drop the on-device GPS route stored under this session's natural key.
        RouteStore.remove(startTs: row.startTs, sport: row.sport)
        Task { await repo.deleteWorkout(row); await repo.refresh() }
    }
}

// MARK: - Row

/// One session as Fitness lists it: the activity glyph in a tinted circle, the name, the headline figure in
/// the Exercise green, and the date on the trailing edge.
struct WorkoutHistoryRow: View {
    let row: WorkoutRow
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            WorkoutTypeIcon(workoutType: row.sport, size: 22, weight: .semibold,
                            color: StrandPalette.activityExerciseText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(StrandPalette.fitnessCard))
            VStack(alignment: .leading, spacing: 0) {
                Text(WorkoutSource.localizedSport(row.sport))
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(headline)
                    .font(StrandFont.pro(28, weight: .semibold))
                    .foregroundStyle(StrandPalette.activityExerciseText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Text(dateLabel)
                .font(StrandFont.pro(13))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// "Today" / "Yesterday" for the last two days, else the short date, as Fitness labels sessions.
    private var dateLabel: String {
        let d = Date(timeIntervalSince1970: TimeInterval(row.startTs))
        let cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "Today") }
        if cal.isDateInYesterday(d) { return String(localized: "Yesterday") }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Distance for a route sport, else active energy, else duration — the one figure Fitness leads with.
    private var headline: String {
        if let m = row.distanceM, m > 0 {
            let system = UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                                   override: distanceSystemRaw)
            return WorkoutDetailView.distance(m, system: system)
        }
        if let kcal = row.energyKcal, kcal > 0 {
            return Measurement(value: kcal, unit: UnitEnergy.kilocalories)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        let seconds = row.durationS ?? Double(row.endTs - row.startTs)
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
