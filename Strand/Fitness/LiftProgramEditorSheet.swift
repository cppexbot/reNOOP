import SwiftUI
import StrandDesign
import WhoopStore

// Build or edit a program: a name and an ordered list of exercise lines carrying the TARGETS —
// working sets, reps, weight, rest and the user's own technique note.
//
// Lines are edited as local drafts and written in one go on Save, through
// `replaceLiftProgramItems`, which swaps the whole list transactionally. Editing a program never
// rewrites history: a session snapshots the program's NAME when it runs, so renaming "Upper A" or
// deleting it entirely leaves every past session reading exactly as it did.

struct LiftProgramEditorSheet: View {
    /// The program being edited, or nil to create a new one.
    let program: LiftProgramRow?
    /// Called after a successful save or delete, so the caller can reload.
    let onSaved: () async -> Void

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var note: String = ""
    /// The exercise lines, in display order. `ord` is assigned from the array index on save, so
    /// reordering is just moving an element.
    @State private var items: [LiftProgramItemRow] = []
    @State private var loaded = false
    @State private var saving = false

    /// The line being added or edited (nil = that sheet is closed).
    @State private var editingItem: ItemEditTarget?
    @State private var confirmingDelete = false

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    #if os(iOS)
    /// Rows drag to reorder only in edit mode; the section header's Reorder button turns it on.
    @State private var editMode: EditMode = .inactive
    #endif

    @FocusState private var focused: Field?
    private enum Field: Hashable { case name, note }

    private var isNew: Bool { program == nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Upper A"))
                        .focused($focused, equals: .name)
                    TextField("Note (optional)", text: $note, prompt: Text("Anything you want to remember"))
                        // Capped at what the hub can actually show (two caption lines). A field that
                        // silently discards the end is worse than one that stops.
                        .onChange(of: note) { new in
                            if new.count > WhoopStore.maxProgramNoteLength {
                                note = String(new.prefix(WhoopStore.maxProgramNoteLength))
                            }
                        }
                        .focused($focused, equals: .note)
                }

                Section {
                    ForEach(items, id: \.id) { item in
                        itemRow(item)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        editingItem = ItemEditTarget(id: "new", item: nil)
                    } label: {
                        Label {
                            Text("Add Exercise").foregroundStyle(StrandPalette.activityExerciseText)
                        } icon: {
                            Image(systemName: "plus").foregroundStyle(StrandPalette.activityExerciseText)
                        }
                    }
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        #if os(iOS)
                        if items.count > 1 {
                            Button(editMode.isEditing ? "Done" : "Reorder") {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            }
                            .font(StrandFont.pro(15))
                            .textCase(nil)
                            .tint(StrandPalette.activityExerciseText)
                        }
                        #endif
                    }
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete Program", systemImage: "trash")
                                .foregroundStyle(StrandPalette.statusCritical)
                        }
                    }
                }
            }
            #if os(iOS)
            .environment(\.editMode, $editMode)
            #endif
            .navigationTitle(isNew ? Text("New Program") : Text("Edit Program"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { WorkoutSheetCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    WorkoutSheetConfirmButton { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .liftKeyboardDone($focused)
            .confirmationDialog("Delete this program?",
                                isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await deleteProgram() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Sessions you already logged from it are kept.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
        .task { await loadIfNeeded() }
        .sheet(item: $editingItem) { target in
            LiftProgramItemSheet(item: target.item) { saved in
                apply(saved, replacing: target.item)
            }
        }
    }

    // MARK: - Exercise lines

    private func itemRow(_ item: LiftProgramItemRow) -> some View {
        Button {
            editingItem = ItemEditTarget(id: item.id, item: item)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(targetSummary(item))
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.activityExerciseText)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(StrandFont.pro(13))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    /// "4 × 8 · 60 kg · 2:00 rest" — only the parts that were actually filled in.
    private func targetSummary(_ item: LiftProgramItemRow) -> String {
        var parts: [String] = []
        if let sets = item.targetSets {
            if let reps = item.targetRepsLow {
                parts.append("\(sets) × \(reps)")
            } else {
                parts.append(String(localized: "\(sets) sets"))
            }
        }
        if let kg = item.targetWeightKg {
            parts.append(LiftFormat.weight(kg, system: unitSystem))
        }
        if let rpe = item.targetRpe {
            parts.append(String(localized: "max RPE \(LiftFormat.trim(rpe))"))
        }
        if let rest = item.restSec {
            parts.append(String(localized: "\(LiftFormat.duration(rest)) rest"))
        }
        return parts.isEmpty ? String(localized: "No targets set") : parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    /// Insert a new line, or replace an edited one in place so its position is kept.
    private func apply(_ saved: LiftProgramItemRow, replacing old: LiftProgramItemRow?) {
        guard let old, let index = items.firstIndex(where: { $0.id == old.id }) else {
            items.append(saved)
            return
        }
        items[index] = saved
    }

    // MARK: - Load / save

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        guard let program else { return }
        name = program.name
        note = program.note ?? ""
        guard let store = await repo.storeHandle() else { return }
        items = (try? await store.liftProgramItems(programId: program.id)) ?? []
    }

    private func save() async {
        guard canSave, let store = await repo.storeHandle() else { return }
        saving = true
        defer { saving = false }

        let now = Int(Date().timeIntervalSince1970)
        let id = program?.id ?? UUID().uuidString
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let row = LiftProgramRow(
            id: id,
            deviceId: repo.deviceId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            createdAt: program?.createdAt ?? now,
            updatedAt: now,
            archived: program?.archived ?? false
        )
        _ = try? await store.upsertLiftPrograms([row])

        // `ord` is the array index: reordering the list is all it takes to reorder the program.
        let ordered = items.enumerated().map { index, item in
            LiftProgramItemRow(
                id: item.id,
                deviceId: repo.deviceId,
                programId: id,
                ord: index,
                exercise: item.exercise,
                targetSets: item.targetSets,
                targetRepsLow: item.targetRepsLow,
                targetRepsHigh: item.targetRepsHigh,
                targetRpe: item.targetRpe,
                targetWeightKg: item.targetWeightKg,
                restSec: item.restSec,
                note: item.note
            )
        }
        _ = try? await store.replaceLiftProgramItems(programId: id, items: ordered)

        await onSaved()
        dismiss()
    }

    private func deleteProgram() async {
        guard let program, let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftProgram(id: program.id)
        await onSaved()
        dismiss()
    }
}

/// What the line editor is editing — a wrapper so "new line" has an identity to present on.
private struct ItemEditTarget: Identifiable {
    let id: String
    let item: LiftProgramItemRow?
}
