//  WorkoutSportPicker.swift
//  NOOP · choosing an activity: a searchable list of the catalogue with the recently used ones first, as
//  the Fitness app lists workout types. Used to start a live session ("Other Workout", Live) and to set the
//  type of a workout added by hand. Free text stays allowed (#519): a search with no match can be used as is.

import SwiftUI
import StrandDesign

struct WorkoutSportList: View {
    /// The activity currently chosen, check-marked in the list.
    var selected: String?
    let onPick: (_ sport: String) -> Void

    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var recent: [WorkoutCatalog.Sport] {
        RecentSportsPrefs.recent().compactMap { WorkoutCatalog.sport(named: $0) }
    }
    /// The catalogue in the reader's language order, filtered by the query in either language.
    private var all: [WorkoutCatalog.Sport] {
        let sports = WorkoutCatalog.all.filter { sport in
            trimmed.isEmpty
                || sport.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || WorkoutSource.localizedSport(sport.name)
                    .range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return sports.sorted {
            WorkoutSource.localizedSport($0.name).localizedStandardCompare(WorkoutSource.localizedSport($1.name))
                == .orderedAscending
        }
    }

    var body: some View {
        List {
            if trimmed.isEmpty, !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent) { row($0.name) }
                }
            }
            Section {
                ForEach(all) { row($0.name) }
                if !trimmed.isEmpty, WorkoutCatalog.sport(named: trimmed) == nil {
                    Button { onPick(trimmed) } label: {
                        Label {
                            Text("Use “\(trimmed)”").foregroundStyle(StrandPalette.textPrimary)
                        } icon: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(StrandPalette.activityExerciseText)
                        }
                    }
                }
            } header: {
                if trimmed.isEmpty { Text("All Workouts") }
            }
        }
        .searchable(text: $query, prompt: Text("Search workouts"))
    }

    private func row(_ name: String) -> some View {
        Button { onPick(name) } label: {
            HStack(spacing: 14) {
                WorkoutTypeIcon(workoutType: name, size: 20, weight: .semibold,
                                color: StrandPalette.activityExerciseText)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(StrandPalette.fitnessCard))
                Text(WorkoutSource.localizedSport(name))
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                if let selected, selected.caseInsensitiveCompare(name) == .orderedSame {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StrandPalette.activityExerciseText)
                }
            }
        }
        .accessibilityAddTraits(selected?.caseInsensitiveCompare(name) == .orderedSame ? .isSelected : [])
    }
}

// MARK: - Start sheet

/// The activity list presented to begin a session: pick a row and it starts. The title can be overridden for
/// other one-shot picks that reuse it.
struct StartWorkoutSheet: View {
    let onStart: (_ sport: String) -> Void
    private let title: String

    @Environment(\.dismiss) private var dismiss

    init(title: String? = nil, onStart: @escaping (_ sport: String) -> Void) {
        self.onStart = onStart
        self.title = title ?? String(localized: "Choose a workout")
    }

    var body: some View {
        NavigationStack {
            WorkoutSportList { name in
                RecentSportsPrefs.recordSelection(name)
                onStart(name)
                dismiss()
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }
}

extension View {
    /// Presents the activity list. A sheet on every platform, as the Fitness app presents its workout list.
    func workoutSelectionCover(isPresented: Binding<Bool>,
                               @ViewBuilder content: @escaping () -> StartWorkoutSheet) -> some View {
        sheet(isPresented: isPresented, content: content)
    }
}
