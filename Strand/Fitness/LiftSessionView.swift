import SwiftUI
import StrandDesign
import WhoopStore

// The running gym session, laid out as the iOS 26 Fitness app records a workout: always dark, the exercise
// being worked as one card of set rows, the rest as large rounded numerals, and a glass panel at the bottom
// holding the session clock in Exercise green and the controls.
//
// WHY NOT A WIZARD. The first version showed one set at a time and walked the plan in order. In a real gym
// that fails twice over: you cannot see what is coming, and you cannot move on when a machine is occupied.
// So every set of the shown exercise is a row, any pending row can be started, every other exercise is one
// tap away below the card, and finished rows stay on screen with what you lifted.
//
// COLOUR CARRIES STATE, so you can find your place at a glance from arm's length:
//   green   the set you are working now, and a done set's tick
//   yellow  the rest that follows it
//   grey    numbers nobody typed
//
// The session itself lives in `LiftSessionController`, ABOVE this view. Swiping this sheet away
// minimises it to the bottom bar; the clock, the strap gesture and the buzzes all keep running,
// because a workout outlives the screen you happen to be looking at.

struct LiftSessionView: View {
    // Only what the sheet draws from. The live heart rate and the running clocks are their own small views
    // (`LiftLiveReadouts.swift`): watched from here, every beat, log line and tick redrew the whole sheet.
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss

    /// Called once the session has been written, so the hub can reload.
    let onFinished: () async -> Void

    @State private var showingFinish = false
    @State private var confirmingDiscard = false
    @State private var sessionRpeText = ""
    @State private var saving = false
    /// The two questions finishing can ask. Nil until answered: saving waits for an answer rather than
    /// deciding for the user.
    @State private var unfinishedChoice: UnfinishedChoice?
    @State private var programChoice: ProgramChoice?
    /// Program lines whose set count this session changed, read when the finish sheet opens.
    @State private var setCountChanges: [LiftSessionController.SetCountChange] = []
    @State private var addingExercise = false
    @State private var editingSet: SetEditTarget?
    /// 0 = the set in progress in large figures, 1 = every set in a table — the two pages swiped between.
    @State private var page = 0
    @State private var confirmingEnd = false
    /// What was lifted for each exercise LAST session, by set number — the "Previous" column. The same
    /// read `loadLastTime` hands the controller for the grey numbers.
    @State private var lastTime: [String: [Int: LiftSetCarry]] = [:]

    private enum UnfinishedChoice: Hashable { case complete, discard }
    private enum ProgramChoice: Hashable { case update, keep }

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @FocusState private var focused: FocusTarget?
    private enum FocusTarget: Hashable {
        case sessionRpe
    }


    private var engine: LiftSessionEngine? { session.engine }


    var body: some View {
        Group {
            if let engine {
                // The control panel never scrolls away: at the rack the clock and the one action have to be
                // where your thumb already is.
                VStack(spacing: 0) {
                    TabView(selection: $page) {
                        nowPage(engine).tag(0)
                        sheet(engine).tag(1)
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    #endif
                    RecordingPageDots(count: 2, selection: page)
                        .padding(.vertical, 12)
                    controlPanel(engine)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                    Text("No session running")
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 560, height: 800)
        #endif
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .liftKeyboardDone($focused)
        .dismissesKeyboardOnTap($focused)
        // Re-read whenever the session's exercises change, so an exercise added mid-session that was
        // done before shows last time's numbers in grey, like every other line.
        .task(id: engine?.plan.map(\.exercise)) { await loadLastTime() }
        .sheet(isPresented: $showingFinish) { finishSheet }
    }

    // MARK: - The page

    /// Every exercise of the session as a plain grouped list: one row per set with its numbers, a checkmark
    /// once done, and "Add Set" at the end of each exercise. A tap opens the set in a small sheet.
    private func sheet(_ engine: LiftSessionEngine) -> some View {
        ScrollViewReader { proxy in
            List {
                Text(session.programName ?? String(localized: "Session"))
                    .font(StrandFont.pro(34, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 4, bottom: 0, trailing: 4))
                ForEach(engine.plan.indices, id: \.self) { index in
                    exerciseSection(engine, index: index, item: engine.plan[index])
                        .id(index)
                }
                Section {
                    Button { addingExercise = true } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .foregroundStyle(StrandPalette.activityExerciseText)
                    }
                    .disabled(engine.plan.count >= LiftSessionEngine.maxExercises)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .onChange(of: engine.currentSlot) { slot in
                guard let slot else { return }
                withAnimation { proxy.scrollTo(slot.exerciseIndex, anchor: .top) }
            }
            .sheet(isPresented: $addingExercise) {
                LiftSessionExerciseSheet { name, primary, secondaries in
                    _ = session.addExercise(name, primaryMuscle: primary, secondaryMuscles: secondaries)
                }
            }
            .sheet(item: $editingSet) { target in
                setEditor(engine, slot: target.slot)
            }
        }
    }

    // MARK: - Now

    /// The set in progress as the Fitness recording screen shows a workout: the stage and exercise, the
    /// running clock (the rest counting down in yellow), the set's weight and reps, the heart rate, and
    /// what comes next.
    private func nowPage(_ engine: LiftSessionEngine) -> some View {
        let slot: LiftSlot? = {
            if case .resting = engine.stage { return engine.upcomingSlot }
            return engine.currentSlot ?? engine.nextPendingSlot
        }()
        let item = slot.flatMap { engine.planItem(for: $0) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RecordingHeading(caption: stageCaption(engine), tint: stageTint(engine),
                                 title: item?.exercise ?? session.programName ?? String(localized: "Session"))
                if engine.canUndo {
                    RecordingButton(symbol: "arrow.uturn.backward", size: 44, label: "Undo") { session.undo() }
                }
            }
            .padding(.top, 24)
            Spacer(minLength: 8)
            stageFigure(engine)
            Spacer(minLength: 8)
            if let slot {
                let v = session.values(of: slot)
                LiveFigure(value: v.weightKg.map { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: unitSystem)) } ?? "--",
                           unit: v.weightKg == nil ? "" : weightSymbol, label: "")
                Spacer(minLength: 8)
                LiveFigure(value: v.reps.map(String.init) ?? "--", label: String(localized: "REPS"))
                Spacer(minLength: 8)
            }
            LiftHeartRateFigure()
            Spacer(minLength: 8)
            Text(LiftSessionController.nextLine(engine))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }

    /// The stage's own clock as a large figure: this set counting up, or the rest counting down.
    private func stageFigure(_ engine: LiftSessionEngine) -> some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)) { ctx in
            let now = Int(ctx.date.timeIntervalSince1970)
            switch engine.stage {
            case .resting:
                LiveFigure(value: ActiveWorkoutClock.clock(engine.restRemaining(now: now) ?? 0),
                           label: String(localized: "Remaining"), tint: StrandPalette.fitnessTime)
            case .working:
                LiveFigure(value: ActiveWorkoutClock.clock(now - engine.stageStartedAt), label: String(localized: "This set"))
            case .warmup, .finished:
                LiveFigure(value: ActiveWorkoutClock.clock(now - engine.stageStartedAt), label: String(localized: "Time"))
            }
        }
    }

    /// "кг" / "lb" in the reader's language, set after the weight like Fitness sets "КМ".
    private var weightSymbol: String {
        let f = MeasurementFormatter()
        f.unitStyle = .short
        return f.string(from: unitSystem == .imperial ? UnitMass.pounds : UnitMass.kilograms)
    }

    private func stageCaption(_ engine: LiftSessionEngine) -> String {
        switch engine.stage {
        case .warmup, .finished: return String(localized: "Warm-up")
        case .working(let slot): return String(localized: "Set \(slot.setIndex)")
        case .resting: return String(localized: "Rest period")
        }
    }

    private func stageTint(_ engine: LiftSessionEngine) -> Color {
        switch engine.stage {
        case .working: return StrandPalette.activityExerciseText
        case .resting: return StrandPalette.fitnessTime
        case .warmup, .finished: return .white.opacity(0.6)
        }
    }

    // MARK: - One exercise, with all its sets

    private func exerciseSection(_ engine: LiftSessionEngine, index: Int, item: LiftPlanItem) -> some View {
        let slots = engine.slots(forExercise: index)
        return Section {
            ForEach(slots, id: \.self) { slot in
                setRow(engine, slot: slot)
                    // Drop the last set with a swipe, as a list drops a row. This session only: whether the
                    // program keeps the new count is asked when the session is finished.
                    .swipeActions {
                        if slot == slots.last, engine.canRemoveSet(fromExercise: index) {
                            Button(role: .destructive) { session.removeSet(fromExercise: index) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
            Button { session.addSet(toExercise: index) } label: {
                Label("Add Set", systemImage: "plus")
                    .foregroundStyle(StrandPalette.activityExerciseText)
            }
            .disabled(item.targetSets >= LiftSessionEngine.maxSetsPerExercise)
        } header: {
            Text(item.exercise)
                .font(StrandFont.pro(20, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .textCase(nil)
        } footer: {
            if let note = item.note, !note.isEmpty {
                Text(note).lineLimit(3)
            }
        }
    }

    /// Width of the set-number column. Read by `LiftSessionEditSheet`, which lays its rows out the same.
    static let setColumnWidth: CGFloat = 34

    // MARK: - One set

    /// A set as a list row: done / in progress / its number, "Set 2" (or "Warm-up"), and its numbers —
    /// grey until entered, the way the whole session reads them.
    private func setRow(_ engine: LiftSessionEngine, slot: LiftSlot) -> some View {
        let recorded = engine.recordedSet(for: slot) != nil
        let isWorking = engine.stage == .working(slot)
        let warmup = isWarmup(slot)
        let entered = session.enteredValues(for: slot)
        let typed = entered.weightKg != nil || entered.reps != nil

        return Button { editingSet = SetEditTarget(slot: slot) } label: {
            HStack(spacing: 12) {
                Group {
                    if recorded {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(StrandPalette.activityExerciseText)
                    } else if isWorking {
                        Image(systemName: "record.circle").foregroundStyle(StrandPalette.activityExerciseText)
                    } else {
                        Image(systemName: "circle").foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .font(.system(size: 22))
                Text(warmup ? String(localized: "Warm-up") : String(localized: "Set \(slot.setIndex)"))
                    .foregroundStyle(warmup ? StrandPalette.fitnessTime : StrandPalette.textPrimary)
                Spacer()
                Text(numbers(slot))
                    .monospacedDigit()
                    .foregroundStyle(typed || recorded ? StrandPalette.textPrimary : StrandPalette.textTertiary)
            }
            .font(StrandFont.pro(17))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isWorking ? StrandPalette.activityExerciseText.opacity(0.16) : nil)
    }

    /// "80 kg × 10", from what was entered, else the grey chain; "—" when neither has anything.
    private func numbers(_ slot: LiftSlot) -> String {
        let v = session.values(of: slot)
        switch (v.weightKg.map { "\(display($0)) \(weightSymbol)" }, v.reps) {
        case (let w?, let r?): return "\(w) × \(r)"
        case (let w?, nil):    return w
        case (nil, let r?):    return "× \(r)"
        case (nil, nil):       return "—"
        }
    }

    /// Warm-up state lives in the controller, so a mark survives the sheet being minimised and applies
    /// however the set was closed out — button, strap, or the minimised bar.
    private func isWarmup(_ slot: LiftSlot) -> Bool { session.isWarmup(slot) }

    // MARK: - Editing a set

    private struct SetEditTarget: Identifiable {
        let slot: LiftSlot
        let id = UUID()
    }

    private func setEditor(_ engine: LiftSessionEngine, slot: LiftSlot) -> some View {
        let v = session.values(of: slot)
        let rpe = session.enteredValues(for: slot).rpe ?? engine.planItem(for: slot)?.targetRpe
        return LiftSetEditor(
            title: isWarmup(slot) ? String(localized: "Warm-up") : String(localized: "Set \(slot.setIndex)"),
            exercise: engine.planItem(for: slot)?.exercise ?? "",
            system: unitSystem,
            weightKg: v.weightKg, reps: v.reps, rpe: rpe, warmup: isWarmup(slot),
            lastTime: previous(engine, slot: slot) == "—" ? nil : previous(engine, slot: slot),
            canStart: engine.stage != .working(slot),
            isDone: engine.recordedSet(for: slot) != nil,
            onSave: { weightKg, reps, rpe, warmup in
                if warmup != session.isWarmup(slot) { session.setWarmup(slot, warmup) }
                write(slot) {
                    $0.weightKg = weightKg
                    $0.reps = reps
                    $0.rpe = rpe
                }
            },
            onStart: { session.start(slot) })
    }

    /// Last session's numbers for this set number, as "60 × 8": the Previous column.
    private func previous(_ engine: LiftSessionEngine, slot: LiftSlot) -> String {
        guard let item = engine.planItem(for: slot),
              let last = lastTime[item.exercise]?[slot.setIndex] else { return "—" }
        switch (last.weightKg.map { display($0) }, last.reps) {
        case (let w?, let r?): return "\(w) × \(r)"
        case (let w?, nil):    return w
        case (nil, let r?):    return "× \(r)"
        case (nil, nil):       return "—"
        }
    }

    private func display(_ kg: Double) -> String {
        LiftFormat.trim(LiftFormat.display(fromKilograms: kg, system: unitSystem))
    }

    // MARK: - Writing a set
    //
    // Through the controller, so a change lands in the engine and on disk at once — on a set already
    // performed (edited in place) or one still to come (held in `pendingValues`, applied when recorded).

    /// Apply one field change to a set, leaving its other fields as they were.
    ///
    /// Works whether or not the set has been performed — the controller decides where the value
    /// lands. It reads the CURRENT entered values first, so editing the reps cannot blank a weight
    /// that was typed a moment ago into the same pending row.
    private func write(_ slot: LiftSlot, _ mutate: (inout LiftRecordedSet) -> Void) {
        let entered = session.enteredValues(for: slot)
        var row = LiftRecordedSet(exerciseIndex: slot.exerciseIndex, setIndex: slot.setIndex,
                                  weightKg: entered.weightKg, reps: entered.reps, rpe: entered.rpe,
                                  isWarmup: session.isWarmup(slot), startTs: 0, endTs: 0, restSec: nil)
        mutate(&row)
        session.updateSet(slot, weightKg: row.weightKg, reps: row.reps,
                          rpe: row.rpe, isWarmup: row.isWarmup)
    }

    // MARK: - The control panel

    private func controlPanel(_ engine: LiftSessionEngine) -> some View {
        RecordingPanel(
            glyph: AnyView(Image(systemName: "dumbbell.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StrandPalette.activityExerciseText)),
            clock: {
                TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)) { ctx in
                    RecordingClockText(text: ActiveWorkoutClock.clock(Int(ctx.date.timeIntervalSince1970) - engine.startTs))
                }
                .accessibilityLabel(Text("Session"))
            },
            trailing: { LiftHeartRate() },
            leading: {
                RecordingButton(symbol: "xmark", label: "End session") { confirmingEnd = true }
                    .confirmationDialog("End this session?", isPresented: $confirmingEnd, titleVisibility: .hidden) {
                        Button("Finish Session") {
                            unfinishedChoice = nil
                            programChoice = nil
                            setCountChanges = []
                            showingFinish = true
                        }
                        Button("Discard Session", role: .destructive) { session.discard() }
                        Button("Cancel", role: .cancel) { }
                    }
            },
            center: {
                RecordingButton(symbol: actionSymbol(engine), size: 112, prominent: true,
                                label: actionLabel(engine)) { session.advance() }
                    .disabled(engine.stage == .finished)
            },
            right: {
                RecordingButton(symbol: page == 0 ? "list.bullet" : "dumbbell", label: "Sets") {
                    withAnimation { page = page == 0 ? 1 : 0 }
                }
            })
    }

    private func actionSymbol(_ engine: LiftSessionEngine) -> String {
        switch engine.stage {
        case .warmup:   return "play.fill"
        case .working:  return "checkmark"
        case .resting:  return engine.allCompleted ? "checkmark" : "forward.end.fill"
        case .finished: return "hourglass"
        }
    }

    private func actionLabel(_ engine: LiftSessionEngine) -> LocalizedStringKey {
        switch engine.stage {
        case .warmup:   return "Start first set"
        case .working:  return "Set done"
        case .resting:  return engine.allCompleted ? "All sets done" : "Start next set"
        case .finished: return "Saving…"
        }
    }

    // MARK: - Finish

    private var finishSheet: some View {
        let unfinished = session.unfinishedSlots.count
        let asksAboutProgram = !setCountChanges.isEmpty || !addedExercises.isEmpty
        let answered = (unfinished == 0 || unfinishedChoice != nil)
            && (!asksAboutProgram || programChoice != nil)
        return NavigationStack {
            Form {
                if let engine {
                    Section {
                        summaryGrid(engine)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }

                Section {
                    LabeledContent {
                        TextField("7", text: $sessionRpeText)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .numericKeyboard()
                            .focused($focused, equals: .sessionRpe)
                            .frame(maxWidth: 80)
                    } label: {
                        Text("Session RPE (1–10)")
                    }
                }

                if unfinished > 0 { unfinishedSection(count: unfinished) }
                if asksAboutProgram { programSection }

                // One way to save — the ✓ above. Session RPE is optional, so an empty field is simply no
                // rating; a separate "Skip" saved exactly the same way and read as a second choice.
                //
                // A way OUT that records nothing. Until this existed, the only route off this screen
                // saved. A session started by a mis-tap, or to try something out, had to be saved and
                // then lived in the history and in that day's Effort for good.
                Section {
                    Button(role: .destructive) {
                        confirmingDiscard = true
                    } label: {
                        Label("Discard session", systemImage: "trash")
                            .foregroundStyle(StrandPalette.statusCritical)
                    }
                    .disabled(saving)
                    .confirmationDialog("Discard this session?",
                                        isPresented: $confirmingDiscard, titleVisibility: .hidden) {
                        Button("Discard Session", role: .destructive) {
                            session.discard()
                            showingFinish = false
                        }
                        Button("Cancel", role: .cancel) { }
                    }
                }
            }
            .navigationTitle(Text("Finish session"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    WorkoutSheetCloseButton { showingFinish = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    WorkoutSheetConfirmButton { Task { await save() } }
                        .disabled(saving || !answered)
                }
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .liftKeyboardDone($focused)
        .task { await loadSetCountChanges() }
    }

    /// The session so far, as the Fitness app's Workout Details grid: time, sets and exercises.
    private func summaryGrid(_ engine: LiftSessionEngine) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                figureCell("Workout Time", tint: StrandPalette.fitnessTime) {
                    LiftRunningClock { $0 - engine.startTs }
                }
                figureCell("Sets", tint: StrandPalette.activityExerciseText) {
                    Text(verbatim: "\(engine.completedWorkingSets)/\(engine.plannedWorkingSets)")
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 12)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                figureCell("Exercises", tint: StrandPalette.activityStandText) {
                    Text(verbatim: "\(engine.plan.count)")
                }
                Spacer().frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
        }
    }

    private func figureCell<Value: View>(_ label: LocalizedStringKey, tint: Color,
                                         @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.textPrimary)
            value()
                .font(StrandFont.pro(28, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Sets never started. One choice covers all of them, because what matters at the end of a session
    /// is simply whether they happened: complete them with the numbers the sheet showed, or discard them
    /// to zeros that every figure leaves out and Edit sets can still fill in. A set that was done is never
    /// asked about — it is complete (`LiftSessionController.setsToSave`).
    private func unfinishedSection(count: Int) -> some View {
        Section {
            Picker("Unfinished sets", selection: $unfinishedChoice) {
                Text("Complete them").tag(UnfinishedChoice?.some(.complete))
                Text("Discard them").tag(UnfinishedChoice?.some(.discard))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Sets not started: \(count)")
        } footer: {
            // Said before Save rather than after: `save` files nothing when no set counts.
            if unfinishedChoice == .discard,
               !LiftSessionController.anyPerformed(session.setsToSave(completingUnfinished: false)) {
                Text("Nothing will be saved.")
                    .foregroundStyle(StrandPalette.statusWarning)
            }
        }
    }

    /// Exercises added during the session, which the program does not have yet.
    private var addedExercises: [LiftPlanItem] {
        session.engine?.plan.filter(\.addedInSession) ?? []
    }

    /// Set counts changed with ⊕/⊖, and exercises added, during the session. The program keeps them only
    /// if asked to — one answer for all of them, listed so the lifter sees what "update" would write.
    private var programSection: some View {
        let added = addedExercises
        return Section {
            ForEach(setCountChanges, id: \.itemId) { change in
                Text("\(change.exercise): \(change.from) → \(change.to) sets")
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            ForEach(Array(added.enumerated()), id: \.offset) { _, line in
                Text("New: \(line.exercise) · sets: \(line.targetSets)")
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Picker("Program", selection: $programChoice) {
                Text("Update program").tag(ProgramChoice?.some(.update))
                Text("Keep as it was").tag(ProgramChoice?.some(.keep))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Program")
        }
    }

    // MARK: - Loading and saving

    /// What was lifted for each of this session's exercises LAST time, by set number — the middle
    /// layer of the grey numbers, handed to the controller that owns the chain, and the Previous column.
    private func loadLastTime() async {
        guard let engine, let store = await repo.storeHandle() else { return }
        var out: [String: [Int: LiftSetCarry]] = [:]
        // One query per DISTINCT exercise, not per plan line. A program that programs the same
        // movement twice — or an imported one with many lines — would otherwise re-ask the store the
        // same question, and this runs when the sheet opens.
        for exercise in NSOrderedSet(array: engine.plan.map(\.exercise)).compactMap({ $0 as? String }) {
            let rows = (try? await store.lastLiftSets(deviceId: repo.deviceId,
                                                      exercise: exercise,
                                                      before: engine.startTs)) ?? []
            var bySet: [Int: LiftSetCarry] = [:]
            for r in rows where !r.isWarmup {
                bySet[r.setIndex] = LiftSetCarry(weightKg: r.weightKg, reps: r.reps)
            }
            out[exercise] = bySet
        }
        lastTime = out
        session.setLastSession(out)
    }

    private func save() async {
        guard !saving, let store = await repo.storeHandle() else { return }
        saving = true
        defer { saving = false }

        session.finish()
        guard let engine = session.engine else { return }
        let endTs = Int(Date().timeIntervalSince1970)
        let sessionId = UUID().uuidString
        // After `finish`, which closes out the running rest: that set's measured rest belongs to it.
        let finished = session.setsToSave(completingUnfinished: unfinishedChoice == .complete)

        // Nothing to file, so file nothing. With no set done, "Discard them" turns every set into a zero.
        // Filing that anyway wrote a session with nothing in it AND a manual workout, and the engine fills
        // that workout's strain from the heart rate the strap measured — so an hour that recorded nothing
        // still read back as a workout. The finish sheet says so before Save. The program's set counts
        // are a separate thing the user chose explicitly, so those still apply.
        guard LiftSessionController.anyPerformed(finished) else {
            await writeProgram(store: store, plan: engine.plan, sets: finished)
            await finishAndDismiss()
            return
        }

        let row = LiftSessionRow(
            id: sessionId, deviceId: repo.deviceId,
            startTs: engine.startTs, endTs: endTs, sport: LiftSessionView.sport,
            programId: session.programId,
            // Snapshot the name: renaming or deleting the program never rewrites this session.
            programName: session.programName,
            sessionRpe: LiftFormat.number(sessionRpeText),
            note: session.programName)
        _ = try? await store.upsertLiftSessions([row])

        // `ord` is COMPLETION order, which with out-of-order work is not the plan's order — and it
        // is the order that actually happened, which is what a session should read back as. Sets
        // completed at finish without being started come last.
        let rows = finished.enumerated().map { ord, s -> LiftSetRow in
            let item = engine.planItem(for: s.slot)
            return LiftSetRow(
                id: UUID().uuidString, deviceId: repo.deviceId, sessionId: sessionId,
                ord: ord, exercise: item?.exercise ?? "",
                // Snapshot the classification AS IT WAS, so reclassifying later never rewrites what
                // past weeks were counted as.
                primaryMuscle: item?.primaryMuscle,
                secondaryMuscles: item?.secondaryMuscles ?? [],
                setIndex: s.slot.setIndex, weightKg: s.weightKg, reps: s.reps, rpe: s.rpe,
                isWarmup: s.isWarmup, startTs: s.startTs, endTs: s.endTs,
                restSec: s.restSec, note: nil)
        }
        _ = try? await store.upsertLiftSets(rows)
        await writeProgram(store: store, plan: engine.plan, sets: finished)

        // Through the SAME path a manual workout takes, so it inherits overlap dedup, the engine's
        // HR-derived strain fill and delete/merge. `strain` stays nil deliberately: the engine fills
        // it from the heart rate the strap MEASURED, never from typed sets and reps.
        let workout = WorkoutRow(
            startTs: engine.startTs, endTs: endTs, sport: LiftSessionView.sport,
            source: "manual", durationS: Double(max(0, endTs - engine.startTs)),
            energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
            distanceM: nil, zonesJSON: nil, notes: session.programName, steps: nil)
        await repo.saveManualWorkout(workout)

        await finishAndDismiss()
    }

    /// Close the session down and leave the sheet. Shared by the normal save and the nothing-to-file
    /// path above, so the two cannot drift about what ending a session means.
    private func finishAndDismiss() async {
        session.finishedSaving()
        await repo.refresh()
        await onFinished()
        showingFinish = false
        dismiss()
    }

    /// The program lines whose set count this session changed, for the finish sheet to ask about.
    private func loadSetCountChanges() async {
        guard let programId = session.programId, let plan = session.engine?.plan,
              let store = await repo.storeHandle(),
              let rows = try? await store.liftProgramItems(programId: programId) else { return }
        setCountChanges = LiftSessionController.setCountChanges(plan: plan, program: rows)
    }

    /// Carry this session onto its program (`LiftSessionController.programAfterSession`): each line's
    /// heaviest done set becomes its weight and reps (always, Utku 21 Sep 2026); changed set counts and
    /// exercises added during the session reach it only when the user chose to keep them.
    ///
    /// Re-reads the lines, so a program edited elsewhere while the session ran keeps every other change
    /// and a line deleted since is not resurrected. The store call replaces the lines wholesale, so
    /// nothing is written when no line differs.
    private func writeProgram(store: WhoopStore, plan: [LiftPlanItem],
                              sets: [LiftSessionController.FinishedSet]) async {
        guard let programId = session.programId,
              let rows = try? await store.liftProgramItems(programId: programId) else { return }
        let edited = LiftSessionController.programAfterSession(
            sets, plan: plan, program: rows, keepingChanges: programChoice == .update,
            programId: programId, deviceId: repo.deviceId)
        guard edited != rows else { return }
        _ = try? await store.replaceLiftProgramItems(programId: programId, items: edited)
    }

    /// The sport every logged session is filed under — the same token the Hevy/Liftosaur importer
    /// uses, so a typed session and an imported one land in one bucket with one icon.
    static let sport = "Strength Training"
}
