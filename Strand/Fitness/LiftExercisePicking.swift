import SwiftUI
import StrandDesign
import WhoopStore

// What the two exercise pickers share: the program line editor (`LiftProgramItemSheet`) and the running
// session's Add exercise sheet (`LiftSessionExerciseSheet`). The user's own exercise names offered back,
// a name remembered with its muscles, and the muscle classification itself — one copy of each, so the two
// pickers cannot drift about what a name is or which muscles it works.

/// The user's own exercise names (`liftExercise`), as the pickers read and write them.
enum LiftExerciseVocabulary {

    /// Names matching what has been typed so far, minus an exact match (no point suggesting the thing
    /// already in the box), most recently used first as the store orders them. Capped — this is a hint,
    /// not a browser.
    static func suggestions(_ vocabulary: [LiftExerciseRow], matching typed: String,
                            limit: Int = 6) -> [LiftExerciseRow] {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Array(vocabulary.prefix(limit)) }
        return Array(vocabulary
            .filter { $0.name.lowercased().contains(query) && $0.name.lowercased() != query }
            .prefix(limit))
    }

    /// Remember `name` with its muscles, so it is offered back next time. `upsertLiftExercises` is keyed
    /// on (deviceId, name), so a known name is updated — its muscles, and when it was last used — never
    /// duplicated. Throws `WhoopStore.LiftExerciseVocabularyFull` for a NEW name once the vocabulary is
    /// full, which the caller explains rather than dropping the name silently.
    static func remember(_ name: String, primary: LiftMuscle?, secondaries: [LiftMuscle],
                         known vocabulary: [LiftExerciseRow], deviceId: String,
                         in store: WhoopStore) async throws {
        let now = Int(Date().timeIntervalSince1970)
        let existing = vocabulary.first { $0.name == name }
        _ = try await store.upsertLiftExercises([LiftExerciseRow(
            id: existing?.id ?? UUID().uuidString,
            deviceId: deviceId,
            name: name,
            primaryMuscle: primary,
            secondaryMuscles: secondaries,
            createdAt: existing?.createdAt ?? now,
            lastUsedTs: now)])
    }

    /// Secondaries in the vocabulary's canonical order rather than `Set` iteration order, so the stored
    /// list is stable between saves instead of reshuffling on every edit.
    static func ordered(_ secondaries: Set<LiftMuscle>, excluding primary: LiftMuscle?) -> [LiftMuscle] {
        LiftMuscle.ordered.filter { secondaries.contains($0) && $0 != primary }
    }
}

/// One remembered exercise as a picker lists it: its name, and the muscles it is known by.
struct LiftExerciseSuggestionLabel: View {
    let row: LiftExerciseRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.textPrimary)
            Text(LiftMuscleSummary.line(primary: row.primaryMuscle, secondaries: row.secondaryMuscles))
                .font(StrandFont.pro(13))
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Exercise list

/// Choosing an exercise: the user's own names as a searchable list, most recently used first, as the
/// Fitness app lists workout types. NOOP ships no catalogue, so a search with no exact match can be used
/// as a new name; it is remembered, with its muscles, when the caller saves.
struct LiftExerciseList: View {
    let vocabulary: [LiftExerciseRow]
    /// The exercise currently chosen, check-marked in the list.
    var selected: String?
    /// Handed the name, and the remembered entry when it is one, so its muscles can come with it.
    let onPick: (_ name: String, _ known: LiftExerciseRow?) -> Void
    /// Forget a remembered name. nil hides the swipe action.
    var onForget: ((LiftExerciseRow) -> Void)?

    @State private var query = ""
    @ScaledMetric(relativeTo: .subheadline) private var glyphSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var glyphCircle: CGFloat = 32

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [LiftExerciseRow] {
        guard !trimmed.isEmpty else { return vocabulary }
        return vocabulary.filter {
            $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
    private var exactMatch: Bool {
        vocabulary.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        List {
            if !trimmed.isEmpty, !exactMatch {
                Section {
                    Button { onPick(trimmed, nil) } label: {
                        Label {
                            Text("Use “\(trimmed)”").foregroundStyle(StrandPalette.textPrimary)
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(StrandPalette.activityExerciseText)
                        }
                    }
                }
            }
            Section {
                ForEach(matches, id: \.id) { row in
                    Button { onPick(row.name, row) } label: { exerciseRow(row) }
                        .swipeActions {
                            if let onForget {
                                // A typo becomes a permanent picker entry otherwise. Forgetting a name is
                                // safe by construction: every logged set SNAPSHOTS its exercise name and
                                // classification, so history is untouched.
                                Button(role: .destructive) { onForget(row) } label: {
                                    Label("Forget", systemImage: "trash")
                                }
                            }
                        }
                }
            } header: {
                if trimmed.isEmpty, !vocabulary.isEmpty { Text("Used before") }
            }
        }
        .searchable(text: $query, prompt: Text("Search exercises"))
    }

    private func exerciseRow(_ row: LiftExerciseRow) -> some View {
        let isSelected = selected.map { $0 == row.name } ?? false
        return HStack(spacing: 14) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(StrandPalette.activityExerciseText)
                .frame(width: glyphCircle, height: glyphCircle)
                .background(Circle().fill(StrandPalette.fitnessCard))
                .accessibilityHidden(true)
            LiftExerciseSuggestionLabel(row: row)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(StrandFont.pro(15, weight: .semibold))
                    .foregroundStyle(StrandPalette.activityExerciseText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Muscles

/// The muscle classification: the primary muscle (a direct set) and the muscles an exercise also works
/// (half a set each). Asked once per exercise and remembered with its name; leaving it unset is allowed —
/// an unclassified exercise still counts toward volume and session load, it simply claims no muscle it
/// was never assigned. Form content: two sections, for a `Form` or `List`.
struct LiftMusclePicker: View {
    @Binding var primary: LiftMuscle?
    @Binding var secondaries: Set<LiftMuscle>

    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .subheadline) private var chipMinWidth: CGFloat = 100

    var body: some View {
        Section {
            LabeledContent("Primary") {
                Menu {
                    Button("Not classified") { primary = nil }
                    ForEach(LiftMuscle.Region.allCases, id: \.self) { region in
                        Section(region.displayName) {
                            ForEach(LiftMuscle.inRegion(region), id: \.self) { muscle in
                                Button(muscle.displayName) { select(primary: muscle) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(primary?.displayName ?? String(localized: "Not classified"))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(StrandFont.pro(12, weight: .semibold))
                    }
                    .foregroundStyle(StrandPalette.textSecondary)
                }
                #if os(macOS)
                .fixedSize()
                #endif
                .accessibilityLabel("Primary muscle")
            }
        } header: {
            Text("Muscles")
        }

        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: chipMinWidth), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(LiftMuscle.allCases, id: \.self) { muscle in
                    if muscle != primary {
                        secondaryChip(muscle)
                    }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Also works (counted as half a set)")
        }
    }

    private func secondaryChip(_ muscle: LiftMuscle) -> some View {
        let on = secondaries.contains(muscle)
        return Button {
            if on { secondaries.remove(muscle) } else { secondaries.insert(muscle) }
        } label: {
            Text(muscle.displayName)
                .font(StrandFont.pro(15, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? StrandPalette.fitnessOnAccent : StrandPalette.textPrimary)
                .lineLimit(dts.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(on ? StrandPalette.activityExerciseText
                                              : StrandPalette.textPrimary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// Setting a primary that is also ticked as a secondary drops it from the secondaries: one
    /// muscle can never be credited twice for the same set.
    private func select(primary muscle: LiftMuscle) {
        primary = muscle
        secondaries.remove(muscle)
    }
}

// MARK: - Keyboard

extension View {
    /// A Done button over the software keyboard that resigns `focus` — the decimal pad has no return key.
    /// No-op on macOS.
    func liftKeyboardDone<Value: Hashable>(_ focus: FocusState<Value?>.Binding) -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus.wrappedValue = nil }
                    .tint(StrandPalette.activityExerciseText)
            }
        }
        #else
        self
        #endif
    }
}
