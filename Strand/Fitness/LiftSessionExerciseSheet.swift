import SwiftUI
import StrandDesign
import WhoopStore

// Add an exercise to the running session (Utku, 21 Sep 2026): one done before, picked from the user's own
// exercise names in a searchable list, or a new one, typed into the search and given its muscles on the
// next page — and remembered, like a name typed into the program editor. It joins the session at the end
// as one set planned at 0 kg × 0 reps; ⊕/⊖ change its sets like any other line, and finishing asks whether
// the program keeps it. Sets, rest and max RPE are not asked here: they belong to the program editor, later.

struct LiftSessionExerciseSheet: View {
    /// Handed the exercise once it is remembered; the session adds it.
    let onAdd: (_ name: String, _ primary: LiftMuscle?, _ secondaries: [LiftMuscle]) -> Void

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var exercise = ""
    @State private var primary: LiftMuscle?
    @State private var secondaries: Set<LiftMuscle> = []
    /// The user's own exercise names, most recently used first.
    @State private var vocabulary: [LiftExerciseRow] = []
    /// Set when the vocabulary is full, so the refusal is explained rather than silent.
    @State private var vocabularyFullLimit: Int?
    @State private var adding = false
    /// Drives the pushed muscles page once a name is picked.
    @State private var confirming = false

    private var trimmedExercise: String {
        exercise.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canAdd: Bool { !trimmedExercise.isEmpty && !adding }

    var body: some View {
        NavigationStack {
            LiftExerciseList(vocabulary: vocabulary,
                             selected: trimmedExercise.isEmpty ? nil : trimmedExercise,
                             onPick: { name, known in
                                 if let known { adopt(known) } else { exercise = name }
                                 confirming = true
                             })
                .navigationTitle(Text("Add exercise"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { WorkoutSheetCloseButton { dismiss() } }
                }
                .navigationDestination(isPresented: $confirming) { musclesPage }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
        .task { await load() }
        // A name typed out in full that is already known brings its muscles with it, as picking it from
        // the list does — unless muscles were already chosen here.
        .onChange(of: exercise) { _ in
            guard primary == nil, secondaries.isEmpty,
                  let known = vocabulary.first(where: { $0.name == trimmedExercise }) else { return }
            primary = known.primaryMuscle
            secondaries = Set(known.secondaryMuscles)
        }
        .alert("You've saved the most exercises NOOP remembers",
               isPresented: Binding(get: { vocabularyFullLimit != nil },
                                    set: { if !$0 { vocabularyFullLimit = nil } })) {
            Button("OK", role: .cancel) { vocabularyFullLimit = nil }
        } message: {
            Text("Forget one you no longer use and this one will save. Your logged sessions are never affected.")
        }
    }

    /// The picked name with its muscles, and the ✓ that adds it.
    private var musclesPage: some View {
        Form {
            Section {
                LabeledContent("Exercise", value: trimmedExercise)
            } footer: {
                Text("It joins this session with one set, its weight and reps at 0 until you type what you lift. Finishing asks whether the program keeps it.")
            }
            LiftMusclePicker(primary: $primary, secondaries: $secondaries)
        }
        .navigationTitle(Text("Add exercise"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                WorkoutSheetConfirmButton { Task { await add() } }
                    .disabled(!canAdd)
                    .accessibilityLabel(Text("Add to session"))
            }
        }
    }

    /// Take a known exercise, with the muscles it is already known by.
    private func adopt(_ row: LiftExerciseRow) {
        exercise = row.name
        primary = row.primaryMuscle
        secondaries = Set(row.secondaryMuscles)
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
    }

    /// Remember the exercise — a new name is saved to the vocabulary, a known one is marked used — then
    /// hand it to the session.
    private func add() async {
        guard canAdd else { return }
        adding = true
        defer { adding = false }
        let name = trimmedExercise
        let ordered = LiftExerciseVocabulary.ordered(secondaries, excluding: primary)
        if let store = await repo.storeHandle() {
            do {
                try await LiftExerciseVocabulary.remember(name, primary: primary, secondaries: ordered,
                                                          known: vocabulary, deviceId: repo.deviceId,
                                                          in: store)
            } catch let full as WhoopStore.LiftExerciseVocabularyFull {
                vocabularyFullLimit = full.limit
                return
            } catch {
                // Still added: every set the session saves carries its own copy of the name and muscles,
                // so a name the vocabulary could not take this once costs nothing that is logged.
            }
        }
        onAdd(name, primary, ordered)
        dismiss()
    }
}
