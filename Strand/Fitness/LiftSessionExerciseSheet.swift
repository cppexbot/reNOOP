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
    /// The name the user is about to forget (nil = no confirmation showing).
    @State private var forgetting: LiftExerciseRow?

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
                             },
                             onForget: { forgetting = $0 })
                .navigationTitle(Text("Add Exercise"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
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
        // Not an alert that only informs: it leads back to the list, where a name is forgotten with a swipe.
        .alert("Exercise List Is Full",
               isPresented: Binding(get: { vocabularyFullLimit != nil },
                                    set: { if !$0 { vocabularyFullLimit = nil } })) {
            Button("Manage Exercises") {
                vocabularyFullLimit = nil
                confirming = false
            }
            Button("Cancel", role: .cancel) { vocabularyFullLimit = nil }
        } message: {
            Text("Forget one you no longer use and this one will save. Your logged sessions are never affected.")
        }
        .confirmationDialog(
            forgetting.map { Text(String(localized: "Forget \($0.name)?")) } ?? Text(""),
            isPresented: Binding(get: { forgetting != nil },
                                 set: { if !$0 { forgetting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forget", role: .destructive) { Task { await forget() } }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: {
            Text("It stops being offered here. Sessions you already logged with it are kept exactly as they are.")
        }
    }

    /// Forget a name. Logged sets keep their own copy of the name and muscles, so no session changes.
    private func forget() async {
        guard let row = forgetting, let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftExercise(id: row.id)
        vocabulary.removeAll { $0.id == row.id }
        forgetting = nil
    }

    /// The picked name with its muscles, and the ✓ that adds it.
    private var musclesPage: some View {
        Form {
            Section {
                LabeledContent("Exercise", value: trimmedExercise)
            }
            LiftMusclePicker(primary: $primary, secondaries: $secondaries)
        }
        .navigationTitle(Text("Add Exercise"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                SheetConfirmButton { Task { await add() } }
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
