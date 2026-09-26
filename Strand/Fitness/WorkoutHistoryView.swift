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
            ForEach(months, id: \.title) { month in
                Section {
                    ForEach(month.rows) { row in
                        NavigationLink {
                            WorkoutDetailView(row: row)
                        } label: {
                            WorkoutHistoryRow(row: row)
                        }
                        .swipeActions {
                            Button(role: .destructive) { delete(row) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu { rowMenu(row) }
                    }
                } header: {
                    Text(month.title)
                        .font(StrandFont.pro(20, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .textCase(nil)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(sportFilter.map(WorkoutSource.localizedSport) ?? String(localized: "All Workouts"))
        .toolbarTitleMenu {
            Button { sportFilter = nil } label: {
                if sportFilter == nil { Label("All Workouts", systemImage: "checkmark") } else { Text("All Workouts") }
            }
            ForEach(sports, id: \.self) { sport in
                Button { sportFilter = sport } label: {
                    let title = WorkoutSource.localizedSport(sport)
                    if sportFilter == sport { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        }
        .overlay {
            if loaded && visible.isEmpty, #available(macOS 14.0, *) {
                ContentUnavailableView("No Workouts", systemImage: "figure.run",
                                       description: Text("Workouts you record or import appear here."))
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
        HStack(spacing: 12) {
            WorkoutTypeIcon(workoutType: row.sport, size: 22, weight: .semibold,
                            color: StrandPalette.activityExerciseText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(StrandPalette.fitnessCard))
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutSource.localizedSport(row.sport))
                    .font(StrandFont.pro(15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(headline)
                    .font(StrandFont.pro(22, weight: .semibold))
                    .foregroundStyle(StrandPalette.activityExerciseText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Date(timeIntervalSince1970: TimeInterval(row.startTs)), format: .dateTime.day().month(.abbreviated))
                .font(StrandFont.pro(15))
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Distance for a route sport, else active energy, else duration — the one figure Fitness leads with.
    private var headline: String {
        if let m = row.distanceM, m > 0 {
            let system = UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                                   override: distanceSystemRaw)
            let unit: UnitLength = system == .imperial ? .miles : .kilometers
            return Measurement(value: m, unit: UnitLength.meters).converted(to: unit)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(2))))
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
