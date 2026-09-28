import SwiftUI
import Combine
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
//   cyan    the rest that follows it
//   grey    numbers nobody typed
//
// The session itself lives in `LiftSessionController`, ABOVE this view. The top bar's minimize
// button drops this screen to the bottom bar; the clock, the strap gesture and the buzzes all
// keep running, because a workout outlives the screen you happen to be looking at.

struct LiftSessionView: View {
    // Only what the sheet draws from. The live heart rate and the running clocks are their own small views
    // (`LiftLiveReadouts.swift`): watched from here, every beat, log line and tick redrew the whole sheet.
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What Undo will take back, named (see `LiftUndoLedger`).
    @ObservedObject private var undoLedger = LiftUndoLedger.shared
    /// The one "Keep screen on" setting every recording screen honours (Settings → Workouts): the rest
    /// timer is a clock to watch, so the screen stays up for it as it does for a workout.
    @AppStorage(LiveWorkoutView.keepScreenOnKey) private var keepScreenOn = false

    /// Called once the session has been written, so the hub can reload.
    let onFinished: () async -> Void

    @State private var showingFinish = false
    @State private var confirmingDiscard = false
    @State private var sessionRpe: Double?
    @State private var saving = false
    /// Set when writing the session failed; the finish sheet stays open to try again.
    @State private var saveFailed = false
    /// The id the session is written under, kept across a retry so a second attempt replaces the first
    /// rather than filing the session twice.
    @State private var savingSessionId: String?
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

    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .body) private var panelGlyphSize: CGFloat = 18


    private var engine: LiftSessionEngine? { session.engine }


    var body: some View {
        Group {
            if let engine {
                // The control panel never scrolls away: at the rack the clock and the one action have to be
                // where your thumb already is.
                VStack(spacing: 0) {
                    // Minimising leaves the session running as the bar above the tab bar. Undo sits on the
                    // same row, so it is there on both pages.
                    RecordingTopBar(onMinimize: { dismiss() }) {
                        if engine.canUndo { undoButton }
                    }
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
                EmptyStateView(title: Text("No Session"), systemImage: "dumbbell") {
                    Button("Close") { dismiss() }
                        .tint(StrandPalette.activityExerciseText)
                }
            }
        }
        #if !os(iOS)
        .frame(width: 560, height: 800)
        #endif
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // Re-read whenever the session's exercises change, so an exercise added mid-session that was
        // done before shows last time's numbers in grey, like every other line.
        .task(id: engine?.plan.map(\.exercise)) { await loadLastTime() }
        .sheet(isPresented: $showingFinish) { finishSheet }
        .onAppear {
            undoLedger.attach(session)
            undoLedger.undoManager = undoManager
            if keepScreenOn { ScreenIdle.keepAwake(true) }
        }
        .onDisappear {
            undoLedger.undoManager = nil
            // Always release, even if the toggle was flipped off mid-session.
            ScreenIdle.keepAwake(false)
        }
    }

    /// Undo, saying what it takes back: "Undo Delete Set".
    private var undoButton: some View {
        let title = undoLedger.names.last.flatMap { $0.isEmpty ? nil : String(localized: "Undo \($0)") }
            ?? String(localized: "Undo")
        return Button { undoLedger.undo(session: session) } label: {
            Label(title, systemImage: "arrow.uturn.backward")
                .font(StrandFont.pro(15, weight: .semibold))
                .lineLimit(1)
        }
        .undoButtonStyle()
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
                if reduceMotion {
                    proxy.scrollTo(slot.exerciseIndex, anchor: .top)
                } else {
                    withAnimation { proxy.scrollTo(slot.exerciseIndex, anchor: .top) }
                }
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
    /// running clock (the rest counting down in cyan), the set's weight and reps, the heart rate, and
    /// what comes next.
    private func nowPage(_ engine: LiftSessionEngine) -> some View {
        let slot: LiftSlot? = {
            if case .resting = engine.stage { return engine.upcomingSlot }
            return engine.currentSlot ?? engine.nextPendingSlot
        }()
        let item = slot.flatMap { engine.planItem(for: $0) }
        return RecordingFigures {
            VStack(alignment: .leading, spacing: 0) {
                RecordingHeading(caption: stageCaption(engine), tint: stageTint(engine),
                                 title: item?.exercise ?? session.programName ?? String(localized: "Session"))
                    .padding(.top, 8)
                Spacer(minLength: 8)
                stageFigure(engine)
                Spacer(minLength: 8)
                if let slot {
                    let v = session.values(of: slot)
                    LiveFigure(value: v.weightKg.map { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: unitSystem)) } ?? "—",
                               unit: v.weightKg == nil ? "" : weightSymbol, label: "")
                    Spacer(minLength: 8)
                    LiveFigure(value: v.reps.map(String.init) ?? "—", label: String(localized: "REPS"))
                    Spacer(minLength: 8)
                }
                LiftHeartRateFigure()
                Spacer(minLength: 8)
                Text(LiftSessionController.nextLine(engine))
                    .font(StrandFont.pro(17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(dts.isAccessibilitySize ? nil : 1)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
        }
    }

    /// The stage's own clock as a large figure: this set counting up, or the rest counting down.
    private func stageFigure(_ engine: LiftSessionEngine) -> some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)) { ctx in
            let now = Int(ctx.date.timeIntervalSince1970)
            switch engine.stage {
            case .resting:
                LiveFigure(value: ActiveWorkoutClock.clock(engine.restRemaining(now: now) ?? 0),
                           label: String(localized: "Remaining"), tint: StrandPalette.activityStandText)
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
        case .resting: return StrandPalette.activityStandText
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
                Text(note).lineLimit(dts.isAccessibilitySize ? nil : 3)
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

        let layout = dts.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return Button { editingSet = SetEditTarget(slot: slot) } label: {
            layout {
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
                    .font(StrandFont.pro(22))
                    .accessibilityHidden(true)
                    Text(warmup ? String(localized: "Warm-up") : String(localized: "Set \(slot.setIndex)"))
                        .foregroundStyle(warmup ? StrandPalette.fitnessTime : StrandPalette.textPrimary)
                }
                if !dts.isAccessibilitySize { Spacer() }
                Text(numbers(slot))
                    .monospacedDigit()
                    .foregroundStyle(typed || recorded ? StrandPalette.textPrimary : StrandPalette.textTertiary)
            }
            .font(StrandFont.pro(17))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(recorded ? "Done" : isWorking ? "In progress" : ""))
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
                .font(.system(size: panelGlyphSize, weight: .semibold))
                .foregroundStyle(StrandPalette.activityExerciseText)),
            clock: {
                TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)) { ctx in
                    let s = Int(ctx.date.timeIntervalSince1970) - engine.startTs
                    RecordingClockText(text: ActiveWorkoutClock.clock(s))
                        .accessibilityLabel(Text("Session"))
                        .accessibilityValue(Text(Duration.seconds(max(0, s)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))))
                        .accessibilityAddTraits(.updatesFrequently)
                }
            },
            trailing: { LiftHeartRate() },
            leading: {
                RecordingButton(symbol: "xmark", destructive: true, label: "Finish") { confirmingEnd = true }
                    .confirmationDialog("Finish Session", isPresented: $confirmingEnd, titleVisibility: .hidden) {
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
                RecordingButton(symbol: page == 0 ? "list.bullet" : "dumbbell",
                                label: page == 0 ? "Sets" : "Current Set") {
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
                    LiftRPEPicker(title: "Session RPE", rpe: $sessionRpe)
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
                        Label("Discard Session", systemImage: "trash")
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
            .navigationTitle(Text("Finish Session"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton { showingFinish = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton { Task { await save() } }
                        .disabled(saving || !answered)
                }
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .task { await loadSetCountChanges() }
        .alert("Couldn't Save Session", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    /// The session so far, as the Fitness app's Workout Details grid: time, sets and exercises.
    private func summaryGrid(_ engine: LiftSessionEngine) -> some View {
        let row = dts.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return VStack(spacing: 0) {
            row {
                figureCell("Workout Time", tint: StrandPalette.fitnessTime) {
                    RunningClock { $0 - engine.startTs }
                }
                figureCell("Sets", tint: StrandPalette.activityExerciseText) {
                    Text(verbatim: "\(engine.completedWorkingSets)/\(engine.plannedWorkingSets)")
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 12)
            Divider()
            row {
                figureCell("Exercises", tint: StrandPalette.activityStandText) {
                    Text(verbatim: "\(engine.plan.count)")
                }
                if !dts.isAccessibilitySize { Spacer().frame(maxWidth: .infinity) }
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
                .foregroundStyle(StrandPalette.text(for: tint))
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
        guard !saving else { return }
        guard let store = await repo.storeHandle() else { saveFailed = true; return }
        saving = true
        defer { saving = false }

        session.finish()
        guard let engine = session.engine else { return }
        // The session ended when it was finished, not when a retry after a failed write went through.
        let endTs = engine.isFinished ? engine.stageStartedAt : Int(Date().timeIntervalSince1970)
        let sessionId = savingSessionId ?? UUID().uuidString
        savingSessionId = sessionId
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
            sessionRpe: sessionRpe,
            note: session.programName)

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
        // A failed write keeps the sheet open, as it was, to try again — closing it as if it had saved
        // would lose the session without a word.
        do {
            _ = try await store.upsertLiftSessions([row])
            _ = try await store.upsertLiftSets(rows)
        } catch {
            saveFailed = true
            return
        }
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
        savingSessionId = nil
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

// MARK: - Undo, named

/// Names what the gym session's Undo will take back ("Undo Delete Set"), and registers each step with the
/// screen's undo manager, so shaking the phone undoes it as the button does.
///
/// The engine keeps ONE unnamed stack of snapshots and pushes onto it from the session screen, the
/// minimised bar and the strap alike, so the names cannot come from whoever called. They are read off each
/// change the engine publishes instead, by the same rules that decide whether it pushed: a set started or
/// done, a rest ended, a set or an exercise added, a set removed, the session finished. Typing a set's
/// numbers pushes nothing and names nothing; an undo pops one name. It observes the controller for the
/// life of the app, because the strap moves the session on while this screen is put away.
///
/// A change it cannot name still counts, as a blank name, so a name never describes a step below the one
/// that will actually be undone; the button then says only "Undo".
@MainActor
final class LiftUndoLedger: ObservableObject {
    static let shared = LiftUndoLedger()

    /// One per undoable step, the latest last. Empty strings are steps without a name.
    @Published private(set) var names: [String] = []
    /// The screen's undo manager while the session screen is up; shake-to-undo only applies there.
    weak var undoManager: UndoManager? {
        didSet { if undoManager !== oldValue { oldValue?.removeAllActions(withTarget: self) } }
    }

    private var observation: AnyCancellable?
    private var last: LiftSessionEngine?
    private var undoing = false

    /// Starts observing `session`. Idempotent: the controller lives at the app root, and so does this.
    func attach(_ session: LiftSessionController) {
        guard observation == nil else { return }
        last = session.engine
        // `@Published` delivers every assignment in order, so no two steps merge into one change.
        observation = session.$engine.sink { [weak self, weak session] engine in
            guard let self, let session else { return }
            self.observe(engine, session: session)
        }
    }

    /// Undo the latest step, through the undo manager when its top entry is this step so the two stay one
    /// stack; otherwise directly, dropping the shake entries that would now be out of step.
    func undo(session: LiftSessionController) {
        if let manager = undoManager, manager.canUndo, let top = names.last, !top.isEmpty,
           manager.undoActionName == top {
            manager.undo()
        } else {
            undoManager?.removeAllActions(withTarget: self)
            perform(session)
        }
    }

    private func perform(_ session: LiftSessionController) {
        guard session.engine?.canUndo == true else { names.removeAll(); return }
        if !names.isEmpty { names.removeLast() }
        undoing = true
        session.undo()
        undoing = false
    }

    private func observe(_ engine: LiftSessionEngine?, session: LiftSessionController) {
        defer { last = engine }
        guard let engine, let previous = last, previous.startTs == engine.startTs else {
            // A new session, or none: nothing of the old one can be undone.
            names.removeAll()
            undoManager?.removeAllActions(withTarget: self)
            return
        }
        if undoing { return }
        guard engine.canUndo else { names.removeAll(); return }
        guard let name = Self.step(from: previous, to: engine) else { return }
        names.append(name)
        guard let manager = undoManager, !name.isEmpty else { return }
        manager.registerUndo(withTarget: self) { ledger in
            MainActor.assumeIsolated { ledger.perform(session) }
        }
        manager.setActionName(name)
    }

    /// The name of the step between two published states; nil when nothing was pushed (a set's numbers
    /// typed), "" for a step it cannot name.
    static func step(from old: LiftSessionEngine, to new: LiftSessionEngine) -> String? {
        if new.plan.count > old.plan.count { return String(localized: "Add Exercise") }
        if new.plan.count == old.plan.count {
            for (before, after) in zip(old.plan, new.plan) where before.targetSets != after.targetSets {
                return after.targetSets > before.targetSets
                    ? String(localized: "Add Set") : String(localized: "Delete Set")
            }
        }
        // Everything else that pushes moves the stage or its start; only typed numbers leave both alone.
        guard new.stage != old.stage || new.stageStartedAt != old.stageStartedAt
                || new.sets.count != old.sets.count || new.plan != old.plan else { return nil }
        switch (old.stage, new.stage) {
        case (.finished, _): return ""
        case (_, .finished): return String(localized: "Finish Session")
        case (.working, .resting): return String(localized: "Set Done")
        case (.resting, .resting): return String(localized: "All Sets Done")
        case (_, .working): return String(localized: "Start Set")
        default: return ""
        }
    }
}

private extension View {
    /// Undo on the dark recording screen: a Liquid Glass capsule on iOS 26, a bordered one before it.
    @ViewBuilder
    func undoButtonStyle() -> some View {
        let styled = self.tint(.white)
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            styled.buttonStyle(.glass)
        } else {
            styled.buttonStyle(.bordered)
        }
        #else
        styled.buttonStyle(.bordered)
        #endif
    }
}
