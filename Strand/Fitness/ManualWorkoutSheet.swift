import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Manual workout sheet
//
// Add a workout you tracked elsewhere, or edit one you already logged, in the iOS 26 add-data form: ✕ and ✓
// in the toolbar over an inset list of type, start, end, distance, calories and average HR — validated by WorkoutSource.buildManualRow (the same
// honest-row rules the engine uses). On save the caller persists it under the strap source via
// Repository.saveManualWorkout. Captured-but-unexposed fields (maxHr / strain / zones) on an edited
// row are carried over by WorkoutSource.preservingCaptured so editing a live-tracked session's
// sport/duration never silently wipes its real strain.
//
// `editing` is non-nil when editing an existing row (its values pre-fill the form and it is passed
// as `replacing:` so a changed natural key deletes the old row). nil = a fresh add.

struct ManualWorkoutSheet: View {
    /// The row being edited, or nil for a new manual workout.
    let editing: WorkoutRow?
    /// Called with the validated row (and the original, when editing) once the user taps Save.
    let onSave: (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var sport: String
    @State private var start: Date
    /// #2034: the span is `start` + `end`. Duration is DERIVED (`durationBinding`), never a second stored
    /// copy, so the two cannot drift; the row has always been stored as `startTs`/`endTs` anyway, and
    /// routing the save through whole minutes was what silently reshaped an edited session's end.
    @State private var end: Date
    @State private var avgHrText: String
    @State private var kcalText: String
    /// Distance as ENTERED, in the user's unit (km or mi) — converted to stored metres on save (#1195).
    @State private var distanceText: String

    /// Exercise-distance choice. Unset follows the original combined setting for existing installs.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private var distanceUnitSystem: UnitSystem {
        UnitPrefs.resolveDistance(
            system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
            override: distanceSystemRaw)
    }
    /// "км" / "mi" in the reader's language.
    private var distanceUnit: String {
        let f = MeasurementFormatter()
        f.unitStyle = .short
        return f.string(from: distanceUnitSystem == .imperial ? UnitLength.miles : UnitLength.kilometers)
    }

    /// Focus for the numeric (Avg HR / Calories / Distance) fields so the keyboard Done button can resign
    /// them — the decimal pad has no return key. iOS-only effect; the enum keeps both platforms compiling.
    private enum NumberField: Hashable { case avgHr, calories, distance }
    @FocusState private var focusedField: NumberField?

    /// Whether the Sport text field is being edited — drives whether the catalogue suggestions show
    /// beneath it. The list also stays hidden once the typed text exactly matches a catalogue sport
    /// (a settled choice), so the form isn't permanently half-covered.
    /// Drives the pushed activity list; a pick sets the sport and pops back.
    @State private var pickingSport = false

    /// Measured natural height of the floating suggestion panel's content, so the overlay can size
    /// itself (capped at 168) instead of being squeezed to the text field's height. See `suggestionList`.

    init(editing: WorkoutRow? = nil,
         onSave: @escaping (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void) {
        self.editing = editing
        self.onSave = onSave
        // Pre-fill from the edited row (display "detected" as "Activity" so a re-label starts clean).
        let e = editing
        // Seeds the LOCALE-STABLE editable form, not the localized display: the field's content is
        // persisted verbatim on save, and a translated word would split cross-source dedup per language.
        _sport = State(initialValue: e.map { WorkoutSource.editableSport($0.sport) } ?? "")
        // A fresh add opens on a VALID 45 minute session ending now, keeping the long-standing 45 minute
        // default length. It used to start at `Date()` with a 45 minute duration, so the implied end was
        // always 45 minutes in the future and `buildManualRow` rejected it: the sheet opened with Save
        // already disabled. That was invisible while the only complaint was the catch-all "Check the
        // values and try again."; now that an end in the future says so by name, it would greet every
        // fresh add with a red line. Anchoring to the end is also the truer default for the retroactive
        // entry this sheet is for.
        let defaultEnd = Date()
        _start = State(initialValue: e.map { Date(timeIntervalSince1970: TimeInterval($0.startTs)) }
                       ?? defaultEnd.addingTimeInterval(-45 * 60))
        _end = State(initialValue: e.map { Date(timeIntervalSince1970: TimeInterval($0.endTs)) }
                     ?? defaultEnd)
        _avgHrText = State(initialValue: e?.avgHr.map(String.init) ?? "")
        _kcalText = State(initialValue: e?.energyKcal.map { String(Int($0.rounded())) } ?? "")
        // Pre-fill the distance in the user's unit so an untouched edit round-trips the stored metres
        // (buildManualRow then re-stores exactly what's shown). @AppStorage isn't usable pre-init, so read
        // the same key directly.
        let bodySystem = UnitSystem(
            rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let sys = UnitPrefs.resolveDistance(
            system: bodySystem,
            override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
        _distanceText = State(initialValue: e?.distanceM.map { Self.distanceEntryString($0, system: sys) } ?? "")
    }

    /// The stored metres shown as a clean editable number in `system`'s unit (km/mi) — trailing zeros and a
    /// dangling decimal trimmed so the field reads "5.2", not "5.20". Two decimals (~10 m) is plenty for a
    /// hand-entered distance; the field's purpose is manual entry, not preserving GPS's metre precision.
    private static func distanceEntryString(_ meters: Double, system: UnitSystem) -> String {
        let km = meters / 1000.0
        let value = system == .imperial ? km * UnitFormatter.milesPerKilometer : km
        var s = String(format: "%.2f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { pickingSport = true } label: {
                        LabeledContent("Workout Type") {
                            HStack(spacing: 6) {
                                Text(sport.isEmpty ? String(localized: "Choose") : WorkoutSource.localizedSport(sport))
                                Image(systemName: "chevron.right")
                                    .font(StrandFont.pro(13, weight: .semibold))
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                    }
                    .foregroundStyle(StrandPalette.textPrimary)
                }
                Section {
                    DatePicker("Starts", selection: startBinding, in: ...Date())
                    DatePicker("Ends", selection: $end, in: ...Date())
                    LabeledContent("Duration", value: durationLabel)
                }
                Section {
                    numberRow("Distance", text: $distanceText, unit: distanceUnit, field: .distance, decimal: true)
                    numberRow("Active Calories", text: $kcalText, unit: String(localized: "kcal"), field: .calories)
                    numberRow("Avg. Heart Rate", text: $avgHrText, unit: String(localized: "bpm"), field: .avgHr)
                } footer: {
                    if !sport.isEmpty, let note = validationNote {
                        noteRow(note)
                    } else if avgHrEditedNote {
                        Text("Effort and heart-rate zones stay as captured; only the average you typed changes.")
                    }
                }
            }
            .navigationDestination(isPresented: $pickingSport) {
                WorkoutSportList(selected: sport.isEmpty ? nil : sport) { picked in
                    sport = picked
                    pickingSport = false
                }
                .navigationTitle(Text("Workout Type"))
            }
            .navigationTitle(editing == nil ? Text("Add Workout") : Text("Edit Workout"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton { save() }
                        .disabled(builtRow == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// One figure typed in by hand: the label, a trailing number field and its unit.
    private func numberRow(_ label: LocalizedStringKey, text: Binding<String>, unit: String,
                           field: NumberField, decimal: Bool = false) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("", text: text, prompt: Text("Optional"))
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: field)
                    #if os(iOS)
                    .keyboardType(decimal ? .decimalPad : .numberPad)
                    #endif
                Text(unit).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func noteRow(_ text: String) -> some View {
        Text(text)
            .font(StrandFont.footnote)
            .foregroundStyle(StrandPalette.statusWarning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }

    // MARK: - Validation / build


    /// Moving the START keeps the workout's LENGTH and carries the end with it, which is what correcting
    /// "this began an hour earlier" means. Computed from the old start before it is reassigned.
    ///
    /// Clamped so the carried end cannot land in the future: dragging the start forward would otherwise
    /// push the end past now and invalidate the sheet on a move that looks entirely reasonable. Clamping
    /// the START keeps the length the user set, where clamping the end would silently shorten the session.
    private var startBinding: Binding<Date> {
        Binding(get: { start },
                set: { picked in
                    let span = end.timeIntervalSince(start)
                    let newStart = min(picked, Date().addingTimeInterval(-span))
                    end = WorkoutSource.endAfterStartMove(oldStart: start, oldEnd: end, newStart: newStart)
                    start = newStart
                })
    }

    /// Duration is a VIEW of the span, not a stored copy. Reading clamps into the Stepper's own range so
    /// an end that is currently before the start cannot hand it an out-of-range value; the honest verdict
    /// on that state comes from `validationNote`, not from this label. Writing moves the end.
    private var durationBinding: Binding<Int> {
        Binding(get: { min(24 * 60, max(1, WorkoutSource.spanDurationMin(start: start, end: end))) },
                set: { end = WorkoutSource.endForDuration(start: start, durationMin: $0) })
    }

    private var durationLabel: String {
        Duration.seconds(durationBinding.wrappedValue * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private var avgHr: Int? { Int(avgHrText.trimmingCharacters(in: .whitespaces)) }
    // Typed on the locale's decimal pad: "5,2" parses as well as "5.2" (CR-11).
    private var kcal: Double? { LiftFormat.number(kcalText) }

    /// Parsed distance in stored METRES — nil for blank (no distance), or when the typed value can't be a
    /// non-negative number. The user enters km/mi; convert to metres for the row. (#1195)
    private var distanceMeters: Double? {
        let t = distanceText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let v = LiftFormat.number(t), v >= 0 else { return nil }
        let km = distanceUnitSystem == .imperial ? v / UnitFormatter.milesPerKilometer : v
        return km * 1000.0
    }

    /// The validated row, or nil when the inputs can't make an honest one (drives the disabled Save +
    /// the inline note). Built through the same WorkoutSource.buildManualRow the engine trusts.
    private var builtRow: WorkoutRow? {
        // A typed-but-unparseable number is invalid (e.g. "abc" in Avg HR) — guard before building.
        if !avgHrText.trimmingCharacters(in: .whitespaces).isEmpty && avgHr == nil { return nil }
        if !kcalText.trimmingCharacters(in: .whitespaces).isEmpty && kcal == nil { return nil }
        if !distanceText.trimmingCharacters(in: .whitespaces).isEmpty && distanceMeters == nil { return nil }
        guard let base = WorkoutSource.buildManualRowFromSpan(start: start, end: end,
                                                              sport: sport, avgHr: avgHr, energyKcal: kcal,
                                                              distanceM: distanceMeters)
        else { return nil }
        // Carry over captured-but-unexposed fields when editing an existing strap session.
        return WorkoutSource.preservingCaptured(base, from: editing)
    }

    /// #18: true when this edit changes the Avg HR on a row that carries CAPTURED strain/zones from a
    /// recorded session. preservingCaptured keeps the old strain/zonesJSON verbatim, so a typed Avg HR is
    /// saved while the HR graph, zones and Effort stay from the recording. That mismatch is silent, so we
    /// surface a one-line note. We do NOT re-score from a single number (that would fabricate a strain),
    /// this is purely an honest disclosure. nil for a fresh add, or when nothing captured would go stale.
    private var avgHrEditedNote: Bool {
        guard let editing, let built = builtRow else { return false }
        let captured = editing.strain != nil || editing.zonesJSON != nil
        return captured && built.avgHr != editing.avgHr
    }

    private var validationNote: String? {
        guard builtRow == nil else { return nil }
        if sport.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Enter a sport.") }
        if start > Date() { return String(localized: "Start can't be in the future.") }
        // The failure this feature introduces, so it gets its own line rather than the catch-all below.
        if end <= start { return String(localized: "End must be after the start.") }
        if end > Date() { return String(localized: "End can't be in the future.") }
        // Its own line rather than the catch-all below: "Check the values and try again." gives a wearer
        // no way to know a 30-second entry is the thing being refused. Matches the live-session floor, so
        // the same session is treated the same whether it was tracked or typed in.
        if Int(end.timeIntervalSince1970) - Int(start.timeIntervalSince1970) < WorkoutSource.minManualSpanSeconds {
            return String(localized: "A workout must be at least 1 minute.")
        }
        if !avgHrText.trimmingCharacters(in: .whitespaces).isEmpty, avgHr == nil || !(25...250).contains(avgHr ?? -1) {
            return String(localized: "Average HR must be 25-250 bpm.")
        }
        if !kcalText.trimmingCharacters(in: .whitespaces).isEmpty, kcal == nil || (kcal ?? -1) < 0 || (kcal ?? 0) > 20_000 {
            return String(localized: "Calories must be 0-20,000.")
        }
        if !distanceText.trimmingCharacters(in: .whitespaces).isEmpty,
           distanceMeters == nil || (distanceMeters ?? -1) < 0 || (distanceMeters ?? 0) > 1_000_000 {
            return distanceUnitSystem == .imperial
                ? String(localized: "Distance must be 0–621 mi.")
                : String(localized: "Distance must be 0–1,000 km.")
        }
        return String(localized: "Check the values and try again.")
    }

    private func save() {
        guard let row = builtRow else { return }
        // #297: a confirmed save is a real selection — fold the (validated) sport into the recents.
        RecentSportsPrefs.recordSelection(row.sport)
        onSave(row, editing)
        dismiss()
    }
}

#if DEBUG
#Preview("Add") {
    ManualWorkoutSheet { _, _ in }
        .preferredColorScheme(.dark)
}

#Preview("Edit") {
    ManualWorkoutSheet(editing: WorkoutRow(
        startTs: Int(Date().timeIntervalSince1970) - 3600, endTs: Int(Date().timeIntervalSince1970),
        sport: "Running", source: "manual", durationS: 3600, energyKcal: 540,
        avgHr: 148, maxHr: 172, strain: 12.4, distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)) { _, _ in }
        .preferredColorScheme(.dark)
}
#endif
