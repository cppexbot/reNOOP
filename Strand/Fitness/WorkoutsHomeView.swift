//  WorkoutsHomeView.swift
//  NOOP · the Workouts tab, modelled on the iOS 26 Fitness app's Workout tab: a large title, one tinted
//  card per activity with a play button, then the most recent sessions and a link to the full history.

import SwiftUI
import StrandDesign
import WhoopStore

struct WorkoutsHomeView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine

    @State private var rows: [WorkoutRow] = []
    @State private var addingManual = false

    /// Trailing days read for the start-card order and Recent, so first paint never sorts a
    /// multi-thousand-workout import (#797). The full history is read by All Workouts.
    static let recentWindowDays = 400

    /// How many sessions the Recent card lists before "Show All".
    private static let recentCount = 3

    private var quickSports: [String] {
        WorkoutQuickStart.sports(recents: RecentSportsPrefs.recent(), history: rows.map(\.sport))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ActiveWorkoutCard()
                ForEach(quickSports, id: \.self) { sport in
                    WorkoutStartCard(sport: sport)
                }
                WorkoutStartCard(sport: nil)

                if !rows.isEmpty {
                    recentSection
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("Workouts"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingManual = true } label: { Image(systemName: "plus") }
                    .tint(StrandPalette.textPrimary)
                    .accessibilityLabel(Text("Add a workout"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    NavigationLink(value: TabRoute.liftLog) {
                        Label("Lift Log", systemImage: "dumbbell")
                    }
                    NavigationLink(value: TabRoute.intervalTimer) {
                        Label("Intervals", systemImage: "timer")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .tint(StrandPalette.textPrimary)
                .accessibilityLabel(Text("More"))
            }
        }
        .refreshable { await repo.refresh() }
        .task(id: repo.refreshSeq) {
            rows = await repo.workoutRows(days: Self.recentWindowDays)
                .sorted { $0.startTs > $1.startTs }
        }
        .sheet(isPresented: $addingManual) {
            ManualWorkoutSheet { row, replacing in
                Task {
                    await repo.saveManualWorkout(row, replacing: replacing)
                    await intelligence.analyzeRecent()
                    await repo.refresh()
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(StrandFont.pro(22, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                NavigationLink(value: TabRoute.workoutHistory) {
                    Text("Show All")
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.activityExerciseText)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(Array(rows.prefix(Self.recentCount))) { row in
                    NavigationLink(value: TabRoute.workout(row)) {
                        WorkoutHistoryRow(row: row)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(StrandPalette.summaryCard,
                                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension WorkoutRow: @retroactive Identifiable, @retroactive Hashable {
    public var id: String { "\(startTs)|\(sport)|\(source)" }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Quick-start order

/// Which activities get a start card, in order: the ones started most recently, then the ones the history
/// holds most often, then Fitness's own defaults — so a fresh install still opens on a sensible list.
enum WorkoutQuickStart {
    static let defaults = ["Walking", "Running", "Strength", "Cycling"]
    static let maxCards = 5

    static func sports(recents: [String], history: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for sport in history {
            guard let known = WorkoutCatalog.sport(named: WorkoutSource.displaySport(sport)) else { continue }
            counts[known.name, default: 0] += 1
        }
        let frequent = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        var out: [String] = []
        for name in recents + frequent + defaults
        where name != WorkoutCatalog.defaultSportName
            && !out.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            out.append(name)
            if out.count == maxCards { break }
        }
        return out
    }
}

// MARK: - Cards

/// One Fitness-style start card. `sport == nil` is the closing "Other Workout" card, which opens the full
/// activity list instead of starting straight away.
private struct WorkoutStartCard: View {
    let sport: String?
    @EnvironmentObject private var model: AppModel
    @State private var showLive = false
    @State private var showPicker = false

    var body: some View {
        Button(action: start) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Group {
                        if let sport {
                            WorkoutTypeIcon(workoutType: sport, size: 34, weight: .semibold,
                                            color: StrandPalette.activityExerciseText)
                        } else {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(StrandPalette.activityExerciseText)
                        }
                    }
                    .frame(width: 44, height: 44, alignment: .topLeading)
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(StrandPalette.fitnessOnAccent)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(StrandPalette.activityExerciseText))
                }
                Text(sport.map(WorkoutSource.localizedSport) ?? String(localized: "Other Workout"))
                    .font(StrandFont.pro(22, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.fitnessCard, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(sport.map(WorkoutSource.localizedSport) ?? String(localized: "Other Workout")))
        .accessibilityHint(Text("Double tap to start"))
        .sheet(isPresented: $showLive) {
            LiveWorkoutView(onClose: { showLive = false })
                .environmentObject(model.live)
        }
        .workoutSelectionCover(isPresented: $showPicker) {
            StartWorkoutSheet { name in
                model.startWorkout(sport: name)
                showLive = true
            }
        }
    }

    private func start() {
        if model.activeWorkout != nil { showLive = true; return }
        guard let sport else { showPicker = true; return }
        RecentSportsPrefs.recordSelection(sport)
        model.startWorkout(sport: sport)
        showLive = true
    }
}

/// The session in progress, pinned above the start cards while one runs. Observes `AppModel` on its own so
/// the ~1 Hz heart-rate tick re-renders only this card.
private struct ActiveWorkoutCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLive = false

    var body: some View {
        if let active = model.activeWorkout {
            Button { showLive = true } label: {
                HStack(spacing: 14) {
                    WorkoutTypeIcon(workoutType: active.sport, size: 28, weight: .semibold,
                                    color: StrandPalette.activityExerciseText)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WorkoutSource.localizedSport(active.sport))
                            .font(StrandFont.pro(17, weight: .semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(Self.elapsed(active, now: ctx.date))
                                .font(StrandFont.pro(28, weight: .semibold).monospacedDigit())
                                .foregroundStyle(StrandPalette.activityExerciseText)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .padding(20)
                .background(StrandPalette.fitnessCard, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("View the active workout"))
            .sheet(isPresented: $showLive) {
                LiveWorkoutView(onClose: { showLive = false })
                    .environmentObject(model.live)
            }
        }
    }

    private static func elapsed(_ w: AppModel.ActiveWorkout, now: Date) -> String {
        let end = w.pausedAt ?? now
        let s = max(0, Int(end.timeIntervalSince(w.start) - w.pausedDuration))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
