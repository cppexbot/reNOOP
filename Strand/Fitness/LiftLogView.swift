import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// The Lift Log: build a program once, then run it in the gym by tapping through it.
//
// This screen is the front door — it lists the saved programs and (from a later phase) the sessions
// run from them. It is styled like the Workouts tab (Exercise green), because a finished session
// lands in the `workout` table beside every other workout.
//
// EFFORT IS NEVER MODIFIED HERE (load-bearing). NOOP's Effort is computed from heart rate alone
// (Karvonen %HRR → Edwards TRIMP, `StrainScorer`), and there is no validated public path from typed
// sets/reps/weight to a cardiovascular-strain equivalent — WHOOP's own muscular load runs
// velocity-based algorithms over strap accelerometer/gyroscope data under an unpublished model.
// So the lifting figures are shown BESIDE Effort and never folded into it, matching the choice the
// imported-lifting path already made (`strain: nil, // never a fabricated cardiovascular strain`).

struct LiftLogView: View {
    @EnvironmentObject var repo: Repository

    /// Saved programs, most-recently-touched first. Loaded off the store on appear/refresh.
    @State private var programs: [LiftProgramRow] = []
    @State private var loaded = false

    /// The program being created or edited (nil = the editor is closed).
    @State private var editing: ProgramEditTarget?
    @State private var importing = false
    /// The live session, owned at the app root so it survives this screen going away.
    @EnvironmentObject private var session: LiftSessionController
    /// Recent finished sessions, newest first.
    @State private var history: [LiftSessionRow] = []
    /// This week's fractional sets per muscle.
    @State private var weekCounts: [LiftMuscle: Double] = [:]
    /// The session whose detail sheet is open.
    @State private var viewing: SessionDetailTarget?
    /// Exercise lines per program id, for the card subtitle.
    @State private var exerciseCounts: [String: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                programsSection
                    .padding(.top, 4)
                weekSection
                historySection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle(Text("Lift Log"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = ProgramEditTarget(id: "new", program: nil) } label: { Image(systemName: "plus") }
                    .tint(StrandPalette.textPrimary)
                    .accessibilityLabel(Text("New Program"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Filling a dozen exercise lines by hand on a phone is the most tedious thing in the
                    // feature; a spreadsheet on a computer does it in a couple of minutes.
                    Button { importing = true } label: {
                        Label("Import a program", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .tint(StrandPalette.textPrimary)
                .accessibilityLabel(Text("More"))
            }
        }
        .refreshable { await load() }
        // Also on a saved session: the session sheet lives above this screen and cannot tell it
        // directly, and a save does not always bump `refreshSeq`.
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)") { await load() }
        .sheet(item: $editing) { target in
            LiftProgramEditorSheet(program: target.program) {
                await load()
            }
        }
        .sheet(isPresented: $importing) {
            LiftProgramImportSheet { await load() }
        }
        .sheet(item: $viewing) { target in
            LiftSessionDetailSheet(session: target.session) { await load() }
        }
    }

    // MARK: - Programs

    @ViewBuilder private var programsSection: some View {
        if loaded {
            sectionTitle("Programs")
            if programs.isEmpty {
                newProgramCard
            } else {
                ForEach(programs, id: \.id) { program in
                    programCard(program)
                }
            }
        }
    }

    /// The empty state: one card that opens the editor.
    private var newProgramCard: some View {
        Button {
            editing = ProgramEditTarget(id: "new", program: nil)
        } label: {
            goalCard(title: String(localized: "New Program"), subtitle: nil,
                     tint: StrandPalette.activityExerciseText, symbol: "plus")
        }
        .buttonStyle(.plain)
    }

    /// One program as a card on Fitness's workout-type page: tapping the card edits it, the play circle
    /// starts it. Each program takes the next goal hue, as Fitness colours its goal cards.
    private func programCard(_ program: LiftProgramRow) -> some View {
        let count = exerciseCounts[program.id] ?? 0
        let tint = StrandPalette.fitnessGoal(programs.firstIndex(where: { $0.id == program.id }) ?? 0)
        let empty = count == 0 && !session.isActive
        return Button {
            editing = ProgramEditTarget(id: program.id, program: program)
        } label: {
            goalCard(title: program.name, subtitle: String(localized: "\(count) exercises"), tint: tint, symbol: nil)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Edit program"))
        .overlay(alignment: .trailing) {
            Button { Task { await start(program) } } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(StrandPalette.fitnessOnAccent)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(tint))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18)
            // An empty program has nothing to run; `start` would return without a word.
            .disabled(empty)
            .opacity(empty ? 0.4 : 1)
            .accessibilityLabel(Text("Start this program"))
        }
    }

    /// The compact goal card: glyph, title, a line in the card's hue, and room for the trailing circle.
    private func goalCard(title: String, subtitle: String?, tint: Color, symbol: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(StrandFont.pro(20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(StrandFont.pro(17))
                        .foregroundStyle(tint)
                }
            }
            Spacer(minLength: 64)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(StrandPalette.fitnessOnAccent)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(tint))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Start a session

    /// Flatten a program into the plan the session runs. The plan is SNAPSHOT at start: editing or
    /// deleting the program mid-session cannot change what is being tapped through.
    private func start(_ program: LiftProgramRow) async {
        guard let store = await repo.storeHandle() else { return }
        let items = (try? await store.liftProgramItems(programId: program.id)) ?? []
        guard !items.isEmpty else { return }
        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []

        let plan = items.map { item -> LiftPlanItem in
            // The classification comes from the exercise vocabulary, which is the one place that owns
            // it — the program line deliberately stores no muscle of its own to drift from.
            let known = vocabulary.first { $0.name == item.exercise }
            return LiftPlanItem(exercise: item.exercise,
                                primaryMuscle: known?.primaryMuscle,
                                secondaryMuscles: known?.secondaryMuscles ?? [],
                                targetSets: item.targetSets,
                                restSec: item.restSec,
                                targetRepsLow: item.targetRepsLow,
                                targetRepsHigh: item.targetRepsHigh,
                                targetRpe: item.targetRpe,
                                targetWeightKg: item.targetWeightKg,
                                note: item.note,
                                // Carried so a set added or dropped mid-session can be written back
                                // onto the line it came from, and be there next time.
                                programItemId: item.id)
        }
        // Refuse to start a second session over a running one: two live sessions would both claim
        // the strap gesture and both write the in-flight snapshot.
        guard !session.isActive else {
            session.isPresented = true
            return
        }
        session.start(plan: plan, programId: program.id, programName: program.name)
    }

    // MARK: - This week, per muscle

    /// Hidden until a session has counted a muscle.
    @ViewBuilder private var weekSection: some View {
        let ordered = LiftMuscle.ordered.filter { (weekCounts[$0] ?? 0) > 0 }
        if !ordered.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Sets per Muscle")
                Spacer()
                Text("Last 7 days")
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(.top, 20)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.element) { index, muscle in
                    muscleBar(muscle, sets: weekCounts[muscle] ?? 0)
                        .padding(.vertical, 11)
                    if index < ordered.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            // The band is named and sourced, never phrased as a target NOOP sets for anyone: this is
            // not a medical device and does not prescribe.
            Text("Direct sets count once, indirect ones half. The tick marks \(LiftFormat.trim(LiftMetrics.ReferenceDose.hypertrophyMinimumSetsPerWeek)) sets a week, a research reference rather than a target.")
                .font(StrandFont.pro(13))
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    /// The span the weekly bar is drawn across.
    ///
    /// A DRAWING choice, not a dose. The evidence puts a floor at about 4 sets a week and identifies
    /// NO ceiling for hypertrophy — gains continue above it with strongly diminishing returns — so
    /// any bar maximum is arbitrary and must never be read as a target. 20 is chosen only because it
    /// comfortably contains the range people actually train in, which puts the floor tick early on
    /// the bar and makes a normal week read as progress rather than as "finished".
    ///
    /// The NUMBER beside the bar is the truth. The bar is context for it, and a count past 20 fills
    /// the bar while the number keeps counting.
    private static let weeklySetsBarSpan = 20.0

    /// One muscle's week: the count, and where it sits relative to the evidence.
    ///
    /// This used to scale the bar 0...4 and turn it FULL and GREEN at four sets — so the screen said
    /// "done" at the exact point the research says growth merely becomes *detectable*. It was telling
    /// the user to stop at the starting line, and it contradicted the caption printed directly below
    /// it. Now four sets is a TICK a fifth of the way along, and nothing on the bar ever reads as
    /// complete, because nothing about the dose is.
    private func muscleBar(_ muscle: LiftMuscle, sets: Double) -> some View {
        let floor = LiftMetrics.ReferenceDose.hypertrophyMinimumSetsPerWeek
        let atOrAboveFloor = sets >= floor
        let fill = min(1.0, sets / Self.weeklySetsBarSpan)
        let tick = min(1.0, floor / Self.weeklySetsBarSpan)

        return HStack(spacing: 12) {
            Text(muscle.displayName)
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 118, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.textPrimary.opacity(0.08))
                    Capsule()
                        // Muted below the floor — below it growth is not reliably detectable, which is
                        // worth showing — and the ordinary blue above it. Never a "done" colour.
                        .fill(StrandPalette.fitnessEffort.opacity(atOrAboveFloor ? 1.0 : 0.45))
                        .frame(width: max(6, geo.size.width * fill))
                    // The floor, marked where it actually falls.
                    Capsule()
                        .fill(StrandPalette.textPrimary.opacity(0.45))
                        .frame(width: 2)
                        .offset(x: max(0, geo.size.width * tick - 1))
                        .accessibilityHidden(true)
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 20)
            // Deliberately NOT a success colour. There is no success point to signal, and a green
            // number is exactly what made four sets read as an achievement.
            Text(LiftFormat.trim(sets))
                .font(StrandFont.pro(17, weight: .semibold).monospacedDigit())
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(atOrAboveFloor
                            ? String(localized: "\(muscle.displayName): \(LiftFormat.trim(sets)) sets, at or above the weekly floor of \(LiftFormat.trim(floor))")
                            : String(localized: "\(muscle.displayName): \(LiftFormat.trim(sets)) sets, below the weekly floor of \(LiftFormat.trim(floor))"))
    }

    // MARK: - History

    @ViewBuilder private var historySection: some View {
        if !history.isEmpty {
            sectionTitle("Recent Sessions")
                .padding(.top, 20)
            ForEach(history, id: \.id) { session in
                Button {
                    viewing = SessionDetailTarget(id: session.id, session: session)
                } label: {
                    LiftSessionHistoryRow(session: session)
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

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(StrandFont.pro(22, weight: .bold))
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, 4)
    }

    // MARK: - Load

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        let loadedPrograms = (try? await store.liftPrograms(deviceId: repo.deviceId)) ?? []
        var counts: [String: Int] = [:]
        for program in loadedPrograms {
            counts[program.id] = ((try? await store.liftProgramItems(programId: program.id)) ?? []).count
        }
        exerciseCounts = counts
        programs = loadedPrograms

        let now = Int(Date().timeIntervalSince1970)
        history = ((try? await store.liftSessions(deviceId: repo.deviceId,
                                                  fromTs: now - 180 * 86_400,
                                                  toTs: now)) ?? [])
            .filter { $0.endTs != nil }                 // an abandoned session is not history
            .sorted { $0.startTs > $1.startTs }
        weekCounts = (try? await store.liftSetCounts(deviceId: repo.deviceId,
                                                      fromTs: now - 7 * 86_400,
                                                      toTs: now).fractional) ?? [:]
        loaded = true
    }
}

/// One finished session as the Fitness app lists a workout: the activity in a circle, the program's name,
/// the session length as the headline figure, and the day.
private struct LiftSessionHistoryRow: View {
    let session: LiftSessionRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            WorkoutTypeIcon(workoutType: session.sport, size: 22, weight: .semibold,
                            color: StrandPalette.activityExerciseText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(StrandPalette.fitnessCard))
            VStack(alignment: .leading, spacing: 0) {
                Text(session.programName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Session"))
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(headline)
                    .font(StrandFont.pro(28, weight: .semibold))
                    .foregroundStyle(StrandPalette.activityExerciseText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Text(dateLabel)
                .font(StrandFont.pro(13))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        let seconds = max(0, (session.endTs ?? session.startTs) - session.startTs)
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// "Today" / "Yesterday" for the last two days, else the short date, as Fitness labels sessions.
    private var dateLabel: String {
        let d = Date(timeIntervalSince1970: TimeInterval(session.startTs))
        let cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "Today") }
        if cal.isDateInYesterday(d) { return String(localized: "Yesterday") }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The session whose detail is being read back. A wrapper rather than a retroactive `Identifiable`
/// on `LiftSessionRow`, keeping the store's row types free of app-layer conformances.
private struct SessionDetailTarget: Identifiable {
    let id: String
    let session: LiftSessionRow
}


/// Identifies what the editor sheet is editing. A wrapper rather than a retroactive `Identifiable`
/// on `LiftProgramRow`, so the store's row types stay free of app-layer conformances — and so
/// "new program" has an identity of its own to present on.
private struct ProgramEditTarget: Identifiable {
    let id: String
    let program: LiftProgramRow?
}
