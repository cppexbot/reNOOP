//  WorkoutHistoryView.swift
//  NOOP · every workout, newest first, grouped by month — the Fitness app's "All Workouts" list. The title
//  is a menu that narrows the list to one activity, as Fitness does.

import SwiftUI
import StrandDesign
import WhoopStore

struct WorkoutHistoryView: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.undoManager) private var undoManager

    @State private var rows: [WorkoutRow] = []
    @State private var loaded = false
    /// nil = every activity.
    @State private var sportFilter: String?
    @State private var editing: WorkoutEditTarget?

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
                        .swipeActions(allowsFullSwipe: false) {
                            Button(role: .destructive) { WorkoutRowMenu.delete(row, repo: repo, undo: undoManager) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu { WorkoutRowMenu(row: row) { editing = WorkoutEditTarget(row: row, isCopy: $0) } }
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
                EmptyStateView(title: Text("No Workouts"), systemImage: "figure.run") {
                    if sportFilter != nil {
                        Button("Show All") { sportFilter = nil }
                            .tint(StrandPalette.activityExerciseText)
                    }
                }
            }
        }
        .task(id: repo.refreshSeq) {
            rows = await repo.workoutRows(days: 4000).sorted { $0.startTs > $1.startTs }
            loaded = true
        }
        .workoutEditor($editing)
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
                // The capsule stays its size; the tap target is the 44 pt minimum around it.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Actions

/// What editing a workout opens: the row, and whether to duplicate it rather than replace it (an imported
/// row, as `Repository.saveManualWorkout` requires).
struct WorkoutEditTarget: Identifiable {
    let row: WorkoutRow
    var isCopy = false
    let id = UUID()
}

extension View {
    /// The manual-workout editor for `target`, saved the way every workout list saves one. `onSaved` runs
    /// after the save lands (the detail page steps back, its row being replaced).
    func workoutEditor(_ target: Binding<WorkoutEditTarget?>, onSaved: @escaping () -> Void = {}) -> some View {
        modifier(WorkoutEditorSheet(target: target, onSaved: onSaved))
    }
}

private struct WorkoutEditorSheet: ViewModifier {
    @Binding var target: WorkoutEditTarget?
    let onSaved: () -> Void
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine

    func body(content: Content) -> some View {
        content.sheet(item: $target) { target in
            ManualWorkoutSheet(editing: target.row) { row, replacing in
                Task {
                    await repo.saveManualWorkout(row, replacing: target.isCopy ? nil : replacing)
                    await intelligence.analyzeRecent()
                    await repo.refresh()
                    onSaved()
                }
            }
        }
    }
}

/// The actions one workout offers wherever it is shown, so they are the same everywhere: a row's context
/// menu (All Workouts, Recent) and the ⋯ on its detail page.
struct WorkoutRowMenu: View {
    let row: WorkoutRow
    /// Opens the editor; `true` duplicates the row as a manual one instead of replacing it.
    let onEdit: (_ isCopy: Bool) -> Void
    /// After the row is deleted (the detail page steps back).
    var onDeleted: () -> Void = {}

    @EnvironmentObject private var repo: Repository
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if row.sport == "detected" {
            Menu {
                ForEach(WorkoutQuickStart.defaults + ["HIIT", "Yoga", "Hiking", "Tennis"], id: \.self) { sport in
                    Button(WorkoutSource.localizedSport(sport)) {
                        Task { await repo.relabelDetected(row, sport: sport); await repo.refresh() }
                    }
                }
            } label: {
                Label("Label as…", systemImage: "tag")
            }
            Button("Not a Workout", systemImage: "xmark.circle") {
                Task { await repo.dismissDetected(row); await repo.refresh() }
            }
        } else if WorkoutSource.classify(row.source) == .manual {
            Button("Edit", systemImage: "pencil") { onEdit(false) }
        } else {
            Button("Duplicate as Manual", systemImage: "plus.square.on.square") { onEdit(true) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            Self.delete(row, repo: repo, undo: undoManager)
            onDeleted()
        }
    }

    /// Shake (or Edit ▸ Undo) puts the session and its route back.
    @MainActor
    static func delete(_ row: WorkoutRow, repo: Repository, undo: UndoManager?) {
        Task {
            let snapshot = await repo.deleteWorkout(row, route: true)
            await repo.refresh()
            undo?.registerUndo(withTarget: repo) { r in Task { await r.restoreWorkout(snapshot) } }
            undo?.setActionName(String(localized: "Delete Workout"))
        }
    }
}

// MARK: - Row

/// One session as Fitness lists it: the activity glyph in a tinted circle, the name, the headline figure in
/// the Exercise green, and the date on the trailing edge.
struct WorkoutHistoryRow: View {
    let row: WorkoutRow
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""

    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 22
    @ScaledMetric(relativeTo: .largeTitle) private var iconCircle: CGFloat = 44

    var body: some View {
        let layout = dts.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            WorkoutTypeIcon(workoutType: row.sport, size: iconSize, weight: .semibold,
                            color: StrandPalette.activityExerciseText)
                .frame(width: iconCircle, height: iconCircle)
                .background(Circle().fill(StrandPalette.fitnessCard))
            VStack(alignment: .leading, spacing: 0) {
                Text(WorkoutSource.localizedSport(row.sport))
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(dts.isAccessibilitySize ? nil : 1)
                Text(headline)
                    .font(StrandFont.pro(28, weight: .semibold))
                    .foregroundStyle(StrandPalette.activityExerciseText)
                    .lineLimit(dts.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.7)
            }
            if !dts.isAccessibilitySize { Spacer(minLength: 8) }
            Text(dateLabel)
                .font(StrandFont.pro(13))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(maxHeight: dts.isAccessibilitySize ? nil : CGFloat.infinity, alignment: .bottom)
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
