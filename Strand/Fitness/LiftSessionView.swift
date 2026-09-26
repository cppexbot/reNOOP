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
    /// The discard offered from the control panel, separate from the finish sheet's own so the two
    /// dialogs never contend for one flag while that sheet is up.
    @State private var confirmingPanelDiscard = false
    @State private var sessionRpeText = ""
    @State private var saving = false
    /// The two questions finishing can ask. Nil until answered: saving waits for an answer rather than
    /// deciding for the user.
    @State private var unfinishedChoice: UnfinishedChoice?
    @State private var programChoice: ProgramChoice?
    /// Program lines whose set count this session changed, read when the finish sheet opens.
    @State private var setCountChanges: [LiftSessionController.SetCountChange] = []
    @State private var addingExercise = false
    /// The exercise the card shows when the user picked one; nil follows the session.
    @State private var shownExercise: Int?
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
        case weight(LiftSlot), reps(LiftSlot), rpe(LiftSlot), sessionRpe
    }

    /// What the user has TYPED into a field, held until they leave it.
    ///
    /// Without this a numeric field cannot accept a decimal at all. Each binding read its text back
    /// out of the engine, so every keystroke round-tripped through `LiftFormat` and was replaced by
    /// the canonical rendering of the parsed value. Typing "45." parsed to 45, re-rendered as "45",
    /// and the point vanished as it was typed — then the next keystroke made "455". A user entering
    /// 45.5 kg silently got 455 kg, which is the shape of bug this feature has to stop having.
    ///
    /// So while a field is focused it shows exactly what was typed; the parsed value still goes to
    /// the engine and to disk on every keystroke, so nothing about durability changes. The draft is
    /// dropped when focus leaves and the row goes back to the canonical formatting.
    @State private var draft: [FocusTarget: String] = [:]

    private var engine: LiftSessionEngine? { session.engine }

    private static let cardAnchor = "exerciseCard"

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
        // Release a field's draft once the user leaves it, so the row returns to the canonical
        // formatting ("45.50" typed becomes "45.5"). The single-argument form on purpose: the
        // two-argument `onChange` is macOS 14+ and this file also builds for macOS 13.
        .onChange(of: focused) { now in
            draft = draft.filter { $0.key == now }
        }
        .sheet(isPresented: $showingFinish) { finishSheet }
    }

    // MARK: - The page

    private func sheet(_ engine: LiftSessionEngine) -> some View {
        let shown = shownIndex(engine)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(engine)
                    if engine.plan.indices.contains(shown) {
                        exerciseCard(engine, index: shown, item: engine.plan[shown])
                            .id(Self.cardAnchor)
                    }
                    otherExercises(engine, shown: shown) { index in
                        withAnimation {
                            shownExercise = index
                            proxy.scrollTo(Self.cardAnchor, anchor: .top)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .onChange(of: engine.currentSlot) { slot in
                // Follow the session to the exercise it moved to, but only when it moves on its own —
                // switching to read another exercise must not be yanked away from.
                guard let slot else { return }
                withAnimation {
                    shownExercise = slot.exerciseIndex
                    proxy.scrollTo(Self.cardAnchor, anchor: .top)
                }
            }
            .sheet(isPresented: $addingExercise) {
                LiftSessionExerciseSheet { name, primary, secondaries in
                    guard session.addExercise(name, primaryMuscle: primary,
                                              secondaryMuscles: secondaries) else { return }
                    // Bring the new one into view: it is the last line.
                    shownExercise = (session.engine?.plan.count ?? 1) - 1
                }
            }
        }
    }

    /// The exercise the card shows: the one picked below, else the one being worked or rested from,
    /// else the next one the plan suggests.
    private func shownIndex(_ engine: LiftSessionEngine) -> Int {
        let index = shownExercise ?? engine.currentSlot?.exerciseIndex
            ?? engine.nextPendingSlot?.exerciseIndex ?? 0
        return min(max(0, index), max(0, engine.plan.count - 1))
    }

    private func header(_ engine: LiftSessionEngine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.programName ?? String(localized: "Session"))
                .font(StrandFont.pro(34, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(2)
            Text(String(localized: "\(engine.completedWorkingSets) of \(engine.plannedWorkingSets) sets done"))
                .font(StrandFont.pro(15))
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func exerciseCard(_ engine: LiftSessionEngine, index: Int, item: LiftPlanItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise)
                    .font(StrandFont.pro(22, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(LiftMuscleSummary.line(primary: item.primaryMuscle,
                                            secondaries: item.secondaryMuscles))
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            if let note = item.note, !note.isEmpty {
                Label {
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                        // Belt and braces with the entry cap: the sets are what this screen is for,
                        // and a note must never be able to push them off it.
                        .lineLimit(4)
                } icon: {
                    Image(systemName: "note.text")
                }
                .font(StrandFont.pro(15))
                .foregroundStyle(StrandPalette.textSecondary)
            }

            VStack(spacing: 6) {
                columnHeadings
                ForEach(engine.slots(forExercise: index), id: \.self) { slot in
                    setRow(engine, slot: slot)
                }
            }

            setCountRow(engine, index: index, item: item)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// Add one more set, or drop the last planned one — at the END of the exercise, because that is
    /// where the question comes up: you have done what was written down and have one more in you, or
    /// you have not. Until this existed the sheet drew exactly `1...targetSets` and the extra set was
    /// performed and then lost.
    ///
    /// The geometry mirrors a set row: the minus sits in the tick column, under the checks it undoes.
    ///
    /// **Both buttons change this session only.** Whether the program keeps the new count is asked
    /// when the session is finished: a program is a plan for next time, and one extra set on a good
    /// day is not always a new plan.
    private func setCountRow(_ engine: LiftSessionEngine, index: Int, item: LiftPlanItem) -> some View {
        let canAdd = item.targetSets < LiftSessionEngine.maxSetsPerExercise
        let canRemove = engine.canRemoveSet(fromExercise: index)

        return HStack(spacing: Self.columnSpacing) {
            Button {
                session.addSet(toExercise: index)
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(canAdd ? StrandPalette.activityExerciseText : StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Self.fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .accessibilityLabel(String(localized: "Add a set to \(item.exercise)"))

            Button {
                session.removeSet(fromExercise: index)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 17, weight: .semibold))
                    // Dimmed rather than gone: the pair reads as one control, and a minus that
                    // disappears once the last set is done looks like a feature that broke.
                    .foregroundStyle(canRemove ? StrandPalette.textPrimary
                                               : StrandPalette.textTertiary.opacity(0.5))
                    .frame(width: Self.tickColumnWidth, height: 44)
                    .background(Circle().fill(Self.fieldFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canRemove)
            .accessibilityLabel(String(localized: "Remove the last set from \(item.exercise)"))
        }
    }

    /// Width of the set-number column, shared by the heading and every row so the number sits
    /// directly under its label. Also read by `LiftSessionEditSheet`, which lays its rows out the same.
    ///
    /// The headings are `lineLimit(1)` with a scale floor: this row is six short labels across a phone
    /// width in ten languages, and a wrapped heading breaks the column alignment for every row beneath it.
    static let setColumnWidth: CGFloat = 34

    /// Width of the trailing tick column — a full 44 pt tap target. Mirrored by a clear spacer in the
    /// heading row so the labels sit over the things they name.
    private static let tickColumnWidth: CGFloat = 44
    private static let weightColumnWidth: CGFloat = 64
    private static let repsColumnWidth: CGFloat = 52
    private static let rpeColumnWidth: CGFloat = 46
    private static let columnSpacing: CGFloat = 6
    /// The number fields' well. This screen is always dark, so a light wash reads as a field.
    private static let fieldFill = Color.white.opacity(0.08)

    private var columnHeadings: some View {
        HStack(spacing: Self.columnSpacing) {
            Text(verbatim: "№").frame(width: Self.setColumnWidth, alignment: .center)
            Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
            Text(weightHeading).frame(width: Self.weightColumnWidth, alignment: .center)
            Text("Reps").frame(width: Self.repsColumnWidth, alignment: .center)
            Text("RPE").frame(width: Self.rpeColumnWidth, alignment: .center)
            Color.clear.frame(width: Self.tickColumnWidth, height: 1)
        }
        .font(StrandFont.pro(13))
        .foregroundStyle(StrandPalette.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var weightHeading: LocalizedStringKey {
        unitSystem == .imperial ? "Lb" : "Kg"
    }

    // MARK: - One set row

    private func setRow(_ engine: LiftSessionEngine, slot: LiftSlot) -> some View {
        let recorded = engine.recordedSet(for: slot)
        let isWorking = engine.stage == .working(slot)

        return HStack(spacing: Self.columnSpacing) {
            // The set number IS the warm-up toggle. Warm-ups are excluded from volume and from the
            // per-muscle counts, so being unable to mark one silently inflates the single figure the
            // whole feature rests on — it has to be reachable in one tap, without leaving the row.
            Button {
                toggleWarmup(slot)
            } label: {
                Text(isWarmup(slot) ? String(localized: "W") : "\(slot.setIndex)")
                    .font(StrandFont.pro(17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isWarmup(slot)
                                     ? StrandPalette.fitnessTime
                                     : (isWorking ? StrandPalette.activityExerciseText
                                                  : StrandPalette.textPrimary))
                    .frame(width: Self.setColumnWidth, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWarmup(slot)
                                ? String(localized: "Warm-up set — tap to make it a working set")
                                : String(localized: "Set \(slot.setIndex) — tap to mark it a warm-up"))

            Text(previous(engine, slot: slot))
                .font(StrandFont.pro(15))
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            numberField(field: .weight(slot), text: weightBinding(slot), ghost: ghostWeight(slot))
                .frame(width: Self.weightColumnWidth)
            numberField(field: .reps(slot), text: repsBinding(slot), ghost: ghostReps(slot))
                .frame(width: Self.repsColumnWidth)
            numberField(field: .rpe(slot), text: rpeBinding(slot), ghost: ghostRpe(engine, slot: slot))
                .frame(width: Self.rpeColumnWidth)

            // The tick both REPORTS and ACTS: green when the set is done, and tappable to start
            // this set when it is not — which is how you jump to a different set or exercise.
            Button {
                session.start(slot)
            } label: {
                Image(systemName: recorded == nil ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(recorded != nil || isWorking
                                     ? StrandPalette.activityExerciseText
                                     : StrandPalette.textTertiary)
                    .frame(width: Self.tickColumnWidth, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorded == nil
                                ? String(localized: "Start this set")
                                : String(localized: "Redo this set"))
        }
        .padding(.vertical, 2)
        .background(isWorking ? StrandPalette.activityExerciseText.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Warm-up state lives in the controller, so a mark survives the sheet being minimised and
    /// applies however the set was closed out — button, strap, or the minimised bar.
    private func isWarmup(_ slot: LiftSlot) -> Bool { session.isWarmup(slot) }

    private func toggleWarmup(_ slot: LiftSlot) {
        session.setWarmup(slot, !session.isWarmup(slot))
    }

    private func numberField(field: FocusTarget, text: Binding<String>, ghost: String) -> some View {
        TextField(ghost, text: text)
            .textFieldStyle(.plain)
            .font(StrandFont.pro(17, weight: .medium))
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .foregroundStyle(StrandPalette.textPrimary)
            .numericKeyboard()
            .focused($focused, equals: field)
            .frame(height: 40)
            .background(Self.fieldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    // MARK: - Ghost values
    //
    // The grey numbers come from ONE chain, `LiftSessionController.carry(for:)`: this exercise earlier
    // in the session (set 2 almost always mirrors set 1), then the same set last session, then the
    // program's target. The minimised bar and the Lock Screen read the same chain.
    //
    // A set keeps its grey numbers after it is done, until something is typed over them — grey means
    // "not entered". What they are worth is decided when the session is finished: every set without
    // typed numbers is completed with them, or discarded, in one choice.

    private func ghostWeight(_ slot: LiftSlot) -> String {
        session.carry(for: slot).weightKg.map { display($0) } ?? "—"
    }

    private func ghostReps(_ slot: LiftSlot) -> String {
        session.carry(for: slot).reps.map(String.init) ?? "—"
    }

    /// Grey RPE is the line's max RPE when the program sets one — and, like every other grey number, it is
    /// what the set saves if nothing is typed over it (RULES 34). A previous set's own rating is shown as a
    /// reminder when the plan sets no maximum, and that one is never saved: it belongs to another set.
    private func ghostRpe(_ engine: LiftSessionEngine, slot: LiftSlot) -> String {
        if let planned = engine.planItem(for: slot)?.targetRpe { return LiftFormat.trim(planned) }
        return engine.previousSetInSession(for: slot)?.rpe.map { LiftFormat.trim($0) } ?? "—"
    }

    private func display(_ kg: Double) -> String {
        LiftFormat.trim(LiftFormat.display(fromKilograms: kg, system: unitSystem))
    }

    // MARK: - Field bindings
    //
    // Each field reads and writes THROUGH the controller, so a keystroke lands in the engine and on
    // disk immediately.
    //
    // TYPING INTO ANY SET, AT ANY TIME. A set that has already been performed is edited in place; one
    // that has not is held in `LiftSessionController.pendingValues` and applied the moment it is
    // recorded. The two are indistinguishable from the row, which is the requirement: being mid-set
    // on one machine is no reason to refuse a correction to another row you are looking at.
    //
    // This used to be a claim rather than a behaviour — the comment here said the value was "held
    // until the set is recorded" while `write` silently dropped it — and a real session found it:
    // "when I type something during an active set to other sets it refreshes to the empty".

    /// A text binding that does not fight the user while they type: reads the draft if there is one,
    /// otherwise the canonical rendering of what is stored.
    ///
    /// A typed comma becomes a point on the way in. iOS's `.decimalPad` labels its separator key
    /// from the DEVICE's region — a German or French phone offers "," and the app cannot relabel it
    /// — so the two would otherwise disagree with the "." this screen displays everywhere else.
    /// Normalising here means the field always reads back in the notation it shows, whichever key
    /// the keyboard happened to offer.
    private func fieldBinding(_ field: FocusTarget,
                              formatted: @escaping () -> String,
                              store: @escaping (String) -> Void) -> Binding<String> {
        Binding(
            get: { draft[field] ?? formatted() },
            set: { typed in
                let text = typed.replacingOccurrences(of: ",", with: ".")
                draft[field] = text
                store(text)
            })
    }

    private func weightBinding(_ slot: LiftSlot) -> Binding<String> {
        fieldBinding(.weight(slot),
                     formatted: { session.enteredValues(for: slot).weightKg.map { display($0) } ?? "" },
                     store: { text in
                         let kg = LiftFormat.number(text).map {
                             LiftFormat.kilograms(fromDisplay: $0, system: unitSystem)
                         }
                         write(slot) { $0.weightKg = kg }
                     })
    }

    private func repsBinding(_ slot: LiftSlot) -> Binding<String> {
        fieldBinding(.reps(slot),
                     formatted: { session.enteredValues(for: slot).reps.map(String.init) ?? "" },
                     store: { text in
                         write(slot) { $0.reps = Int(text.trimmingCharacters(in: .whitespaces)) }
                     })
    }

    private func rpeBinding(_ slot: LiftSlot) -> Binding<String> {
        fieldBinding(.rpe(slot),
                     formatted: { session.enteredValues(for: slot).rpe.map { LiftFormat.trim($0) } ?? "" },
                     store: { text in write(slot) { $0.rpe = LiftFormat.number(text) } })
    }

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

    // MARK: - The other exercises

    /// Every other exercise of the session, one row each — tap to show it in the card. Then the way to
    /// add one the program does not have.
    private func otherExercises(_ engine: LiftSessionEngine, shown: Int,
                                select: @escaping (Int) -> Void) -> some View {
        let others = engine.plan.indices.filter { $0 != shown }
        return VStack(alignment: .leading, spacing: 10) {
            if !others.isEmpty {
                Text("Exercises")
                    .font(StrandFont.pro(22, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.top, 4)
                ForEach(others, id: \.self) { index in
                    exerciseRow(engine, index: index) { select(index) }
                }
            }
            addExerciseRow(engine)
        }
    }

    private func exerciseRow(_ engine: LiftSessionEngine, index: Int,
                             action: @escaping () -> Void) -> some View {
        let item = engine.plan[index]
        let slots = engine.slots(forExercise: index)
        let done = slots.filter { engine.isCompleted($0) }.count
        let allDone = !slots.isEmpty && done == slots.count
        let isCurrent = engine.currentSlot?.exerciseIndex == index
        return Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: allDone ? "checkmark" : "dumbbell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StrandPalette.activityExerciseText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(StrandPalette.fitnessCard))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.exercise)
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                    Text(String(localized: "\(done) of \(slots.count) sets"))
                        .font(StrandFont.pro(15))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? StrandPalette.activityExerciseText
                                                   : StrandPalette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Add an exercise the program does not have — at the END of the session, after everything planned,
    /// because that is where it goes: the program's lines keep their order, and the new one is tapped to
    /// start whenever the lifter gets to it (Utku, 21 Sep 2026). Finishing asks whether the program keeps
    /// it; until then it changes this session only, like ⊕/⊖.
    private func addExerciseRow(_ engine: LiftSessionEngine) -> some View {
        let canAdd = engine.plan.count < LiftSessionEngine.maxExercises
        return Button {
            addingExercise = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canAdd ? StrandPalette.activityExerciseText : StrandPalette.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(StrandPalette.fitnessCard))
                Text("Add exercise")
                    .font(StrandFont.pro(17))
                    .foregroundStyle(canAdd ? StrandPalette.activityExerciseText : StrandPalette.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
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
                    .confirmationDialog("End this session?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                        Button("Finish Session") {
                            unfinishedChoice = nil
                            programChoice = nil
                            setCountChanges = []
                            showingFinish = true
                        }
                        Button("Discard Session", role: .destructive) { confirmingPanelDiscard = true }
                        Button("Keep going", role: .cancel) { }
                    }
                    .confirmationDialog("Discard this session?",
                                        isPresented: $confirmingPanelDiscard, titleVisibility: .visible) {
                        Button("Discard", role: .destructive) { session.discard() }
                        Button("Keep going", role: .cancel) { }
                    } message: {
                        Text("\(engine.completedWorkingSets) recorded sets will be thrown away. Nothing is saved and no workout is created.")
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
                        Text("How hard was the whole session? (1–10)")
                    }
                } footer: {
                    Text("This is session RPE. Multiplied by the session's length it gives session load — the one figure that compares across completely different training.")
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
                                        isPresented: $confirmingDiscard, titleVisibility: .visible) {
                        Button("Discard", role: .destructive) {
                            session.discard()
                            showingFinish = false
                        }
                        Button("Keep going", role: .cancel) { }
                    } message: {
                        Text("\(engine?.completedWorkingSets ?? 0) recorded sets will be thrown away. Nothing is saved and no workout is created.")
                    }
                } footer: {
                    if !answered {
                        Text("Choose an option above to save.")
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
            Text("Sets not started: \(count)")
                .fixedSize(horizontal: false, vertical: true)
            Picker("Unfinished sets", selection: $unfinishedChoice) {
                Text("Complete them").tag(UnfinishedChoice?.some(.complete))
                Text("Discard them").tag(UnfinishedChoice?.some(.discard))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Unfinished sets")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Completing saves them with the grey numbers shown. Discarding keeps them out of every figure; they stay under Edit sets as zeros you can fill in later.")
                // Said before Save rather than after: `save` files nothing when no set counts.
                if unfinishedChoice == .discard,
                   !LiftSessionController.anyPerformed(session.setsToSave(completingUnfinished: false)) {
                    Text("Every set would be a zero, so discarding saves no session and no workout.")
                        .foregroundStyle(StrandPalette.statusWarning)
                }
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
            Text(programQuestion(countsChanged: !setCountChanges.isEmpty, exercisesAdded: !added.isEmpty))
                .fixedSize(horizontal: false, vertical: true)
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

    /// The program question, worded for what actually changed.
    private func programQuestion(countsChanged: Bool, exercisesAdded: Bool) -> LocalizedStringKey {
        switch (countsChanged, exercisesAdded) {
        case (true, true):  return "You added exercises and changed the number of sets. Keep these changes in the program for next time?"
        case (false, true): return "You added exercises. Add them to the program for next time?"
        default:            return "You changed the number of sets. Keep the new counts in the program for next time?"
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
