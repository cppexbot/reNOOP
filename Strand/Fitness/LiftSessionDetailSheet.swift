import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// One finished session, read back in full: every set as performed, the session figures, and how
// each exercise compares with the last time you did it.
//
// This is the screen the whole feature exists to produce. A log book that cannot show you what you
// lifted last week is a diary.
//
// EVERY FIGURE IS ARITHMETIC THE USER CAN REDO BY HAND from the sets listed on the same screen —
// that is the design constraint, and it is why there is no single composite "workout score". The
// maths lives in `LiftMetrics` (pure, unit-tested); this file only lays it out.
//
// Effort is shown BESIDE the lifting figures and is never computed from them: it is whatever NOOP
// measured from heart rate over the session's window, filled in by the engine's own rescore pass.

struct LiftSessionDetailSheet: View {
    let session: LiftSessionRow
    /// Called after the session is edited or deleted, so the hub can reload its list.
    var onChanged: () async -> Void = {}

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var sets: [LiftSetRow] = []
    /// The `workout` row this session is pinned to, for the HR-measured figures.
    @State private var workout: WorkoutRow?
    /// Previous performance per exercise, for the "vs last time" comparison.
    @State private var previousVolume: [String: Double] = [:]
    @State private var loaded = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var editing = false
    /// Session RPE as stored now. The edit sheet can correct it, and the session load must follow.
    @State private var sessionRpe: Double?

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private var durationSec: Int {
        guard let end = session.endTs else { return 0 }
        return max(0, end - session.startTs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if !loaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else {
                        figuresSection
                        exercisesSection
                        if !performed.isEmpty {
                            muscleSection
                            rpeSection
                        }
                        deleteSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(StrandPalette.summaryCanvas.ignoresSafeArea())
            .navigationTitle(Text(start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { WorkoutSheetCloseButton { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = true } label: { Image(systemName: "pencil") }
                        .tint(StrandPalette.textPrimary)
                        .disabled(!loaded)
                        .accessibilityLabel(Text("Edit sets"))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 700)
        #endif
        .task { await load() }
        .sheet(isPresented: $editing) {
            LiftSessionEditSheet(session: storedSession, sets: sets) {
                await load()
                await onChanged()
            }
        }
    }

    private var start: Date { Date(timeIntervalSince1970: TimeInterval(session.startTs)) }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            WorkoutTypeIcon(workoutType: session.sport, size: 42, weight: .semibold,
                            color: StrandPalette.activityExerciseText)
                .frame(width: 88, height: 88)
                .background(Circle().fill(StrandPalette.fitnessCard))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.programName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Session"))
                    .font(StrandFont.pro(20))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(timeRange)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var timeRange: String {
        let f = AppClock.hourMinuteFormatter()
        guard let endTs = session.endTs, endTs > session.startTs else { return f.string(from: start) }
        return "\(f.string(from: start))–\(f.string(from: Date(timeIntervalSince1970: TimeInterval(endTs))))"
    }

    /// The session as stored now, with any corrected RPE.
    private var storedSession: LiftSessionRow {
        var row = session
        row.sessionRpe = sessionRpe
        return row
    }

    /// Remove a session that should not have been recorded — a mis-tap, or a test.
    ///
    /// Deletes the paired `workout` row TOO. A lift session writes one so the training lands in
    /// Workouts and Today like any other, and the analytics engine fills its strain from the heart
    /// rate measured over that window. Leaving it behind would keep the day's Effort inflated by a
    /// session the user just said did not happen — which is worse than not being able to delete at
    /// all, because it would look like the delete worked.
    private var deleteSection: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Text("Delete Session")
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.statusCritical)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(deleting)
        .confirmationDialog("Delete this session?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteSession() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(performed.count) recorded sets will be removed, and so will the workout this session created. This cannot be undone.")
        }
    }

    private func deleteSession() async {
        guard !deleting, let store = await repo.storeHandle() else { return }
        deleting = true
        defer { deleting = false }

        _ = try? await store.deleteLiftSession(id: session.id)   // cascades to its sets
        if let workout { await repo.deleteWorkout(workout) }

        await onChanged()
        dismiss()
    }

    // MARK: - The session figures

    private struct Figure {
        let label: LocalizedStringKey
        let value: String
        let unit: String
        let color: Color
        var caption: String?
    }

    private var figures: [Figure] {
        var out: [Figure] = []
        out.append(Figure(label: "Workout Time", value: WorkoutDetailView.clock(Double(durationSec)), unit: "",
                          color: StrandPalette.fitnessTime))
        // Weight x reps, summed. Exact, but only meaningful against the SAME program run again: 100 kg
        // of leg press is not 100 kg of squat, so the total across different exercises compares
        // nothing. The per-exercise figure below, with its delta against last time, is the form that
        // answers "am I progressing" — this one is the tally.
        let (volume, volumeUnit) = WorkoutDetailView.split(
            LiftFormat.weight(LiftMetrics.volumeLoadKg(performed), system: unitSystem))
        out.append(Figure(label: "Volume", value: volume, unit: volumeUnit,
                          color: StrandPalette.activityExerciseText))
        out.append(Figure(label: "Working sets", value: "\(workingSetCount)", unit: "",
                          color: StrandPalette.activityStandText))
        out.append(Figure(label: "Session load", value: sessionLoadText, unit: "",
                          color: StrandPalette.activityMoveText, caption: sessionLoadCaption))
        out.append(Figure(label: "Effort", value: workout?.strain.map { LiftFormat.trim($0) } ?? "—", unit: "",
                          color: StrandPalette.fitnessEffort,
                          caption: String(localized: "measured from heart rate")))
        return out
    }

    private var figuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Workout Details")
            let rows = stride(from: 0, to: figures.count, by: 2).map { Array(figures[$0..<min($0 + 2, figures.count)]) }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, pair in
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(pair.enumerated()), id: \.offset) { figureCell($0.element) }
                        if pair.count == 1 { Spacer().frame(maxWidth: .infinity) }
                    }
                    .padding(.vertical, 12)
                    if index < rows.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private func figureCell(_ f: Figure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(f.label)
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.textPrimary)
            (Text(f.value).font(StrandFont.pro(28, weight: .semibold))
             + Text(f.unit.isEmpty ? "" : f.unit.uppercased()).font(StrandFont.pro(20, weight: .semibold)))
                .foregroundStyle(f.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption = f.caption {
                Text(caption)
                    .font(StrandFont.pro(13))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(StrandFont.pro(22, weight: .bold))
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, 4)
    }

    /// The sets that were performed. A set at zero reps was discarded or skipped: it stays in the store
    /// so Edit sets can fill it in, and out of everything this screen shows.
    private var performed: [LiftSetRow] { sets.filter { LiftMetrics.isPerformed(reps: $0.reps) } }

    private var workingSetCount: Int { performed.filter { !$0.isWarmup }.count }

    private var sessionLoadText: String {
        guard let load = LiftMetrics.sessionLoad(sessionRpe: sessionRpe,
                                                 durationSec: durationSec) else { return "—" }
        return String(Int(load.rounded()))
    }

    /// The caption must show the SAME minutes the load was computed from.
    ///
    /// Showing whole minutes while computing from exact seconds silently breaks the one promise this
    /// screen makes: that every figure is arithmetic you can redo by hand. A 2:40 session captioned
    /// "× 2 min" invites the reader to check 8 × 2 = 16 against a displayed 21 and conclude the app
    /// is making numbers up.
    private var sessionLoadCaption: String {
        guard let rpe = sessionRpe else {
            return String(localized: "not rated")
        }
        let minutes = Double(durationSec) / 60.0
        return String(localized: "RPE \(LiftFormat.trim(rpe)) × \(LiftFormat.trim(minutes)) min")
    }

    // MARK: - Per exercise, with every set

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Exercises")
            if performed.isEmpty {
                Text("No sets were performed. Discarded sets stay under Edit sets as zeros you can fill in.")
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            ForEach(LiftMetrics.perExercise(performed), id: \.exercise) { summary in
                exerciseCard(summary)
            }
        }
    }

    private func exerciseCard(_ summary: LiftMetrics.ExerciseSummary) -> some View {
        let rows = performed.filter { $0.exercise == summary.exercise }.sorted { $0.ord < $1.ord }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.exercise)
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let first = rows.first {
                    Text(LiftMuscleSummary.line(primary: first.primaryMuscle,
                                                secondaries: first.secondaryMuscles))
                        .font(StrandFont.pro(13))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(rows, id: \.id) { row in setLine(row) }
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Best set")
                        .font(StrandFont.pro(15))
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text(bestSetText(summary))
                        .font(StrandFont.pro(20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(StrandPalette.activityExerciseText)
                    if let e1rm = summary.bestEstimatedOneRepMaxKg {
                        // "Estimated" is in the label, not a footnote: it is a formula off one set, not
                        // a measured maximum, and the word has to travel with it.
                        Text(String(localized: "≈ \(LiftFormat.weight(e1rm, system: unitSystem)) estimated 1RM"))
                            .font(StrandFont.pro(13))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Volume")
                        .font(StrandFont.pro(15))
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text(LiftFormat.weight(summary.volumeKg, system: unitSystem))
                        .font(StrandFont.pro(20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let delta = volumeDeltaText(summary) {
                        Text(delta)
                            .font(StrandFont.pro(13))
                            .foregroundStyle(deltaColor(summary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func setLine(_ row: LiftSetRow) -> some View {
        HStack(spacing: 12) {
            Text(row.isWarmup ? String(localized: "W") : "\(row.setIndex)")
                .font(StrandFont.pro(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(row.isWarmup ? StrandPalette.textSecondary : StrandPalette.activityExerciseText)
                .frame(width: 26, height: 26)
                .background(Circle().fill(row.isWarmup ? StrandPalette.textPrimary.opacity(0.08)
                                                       : StrandPalette.fitnessCard))

            Text(setValueText(row))
                .font(StrandFont.pro(17).monospacedDigit())
                .foregroundStyle(row.isWarmup ? StrandPalette.textSecondary : StrandPalette.textPrimary)

            Spacer(minLength: 0)

            if let rpe = row.rpe {
                Text(String(localized: "RPE \(LiftFormat.trim(rpe))"))
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            if let rest = row.restSec {
                Text(LiftFormat.duration(rest))
                    .font(StrandFont.pro(15).monospacedDigit())
                    .foregroundStyle(StrandPalette.fitnessTime)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func setValueText(_ row: LiftSetRow) -> String {
        let reps = row.reps.map(String.init) ?? "—"
        guard let kg = row.weightKg else {
            // Bodyweight work: reps alone, with no fabricated tonnage behind it.
            return String(localized: "\(reps) reps")
        }
        return "\(LiftFormat.weight(kg, system: unitSystem)) × \(reps)"
    }

    private func bestSetText(_ summary: LiftMetrics.ExerciseSummary) -> String {
        guard let reps = summary.bestReps else { return "—" }
        guard let kg = summary.bestWeightKg else { return String(localized: "\(reps) reps") }
        return "\(LiftFormat.weight(kg, system: unitSystem)) × \(reps)"
    }

    /// How this exercise's volume compares with the last session that included it. The single most
    /// useful line in the screen: progression is a comparison, not a number.
    private func volumeDeltaText(_ summary: LiftMetrics.ExerciseSummary) -> String? {
        guard let now = summary.volumeKg, let before = previousVolume[summary.exercise], before > 0
        else { return nil }
        let delta = now - before
        guard abs(delta) >= 0.5 else { return String(localized: "same as last time") }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(LiftFormat.weight(abs(delta), system: unitSystem)) vs last time"
    }

    private func deltaColor(_ summary: LiftMetrics.ExerciseSummary) -> Color {
        guard let now = summary.volumeKg, let before = previousVolume[summary.exercise], before > 0
        else { return StrandPalette.textTertiary }
        if now > before { return StrandPalette.statusPositive }
        if now < before { return StrandPalette.textSecondary }
        return StrandPalette.textTertiary
    }

    // MARK: - Sets per muscle

    /// Counted from the muscles the user assigned each exercise: direct sets once, indirect ones as a half.
    /// Hidden when none of the exercises has a muscle yet.
    @ViewBuilder private var muscleSection: some View {
        let counts = LiftMetrics.muscleCounts(performed)
        let ordered = LiftMuscle.ordered.filter { (counts.fractional[$0] ?? 0) > 0 }
        if !ordered.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Sets per Muscle")
                VStack(spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.element) { index, muscle in
                        HStack(spacing: 12) {
                            Text(muscle.displayName)
                                .font(StrandFont.pro(17))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer(minLength: 0)
                            Text(componentText(counts, muscle))
                                .font(StrandFont.pro(13))
                                .foregroundStyle(StrandPalette.textSecondary)
                            Text(LiftFormat.trim(counts.fractional[muscle] ?? 0))
                                .font(StrandFont.pro(17, weight: .semibold).monospacedDigit())
                                .foregroundStyle(StrandPalette.textPrimary)
                                .frame(minWidth: 28, alignment: .trailing)
                        }
                        .padding(.vertical, 11)
                        .accessibilityElement(children: .combine)
                        if index < ordered.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
    }

    /// "4 direct · 2 indirect" — so the total above is inspectable rather than asserted.
    private func componentText(_ counts: LiftMetrics.MuscleCounts, _ muscle: LiftMuscle) -> String {
        let d = counts.direct[muscle] ?? 0
        let i = counts.indirect[muscle] ?? 0
        if d > 0 && i > 0 { return String(localized: "\(d) direct · \(i) indirect") }
        if d > 0 { return String(localized: "\(d) direct") }
        return String(localized: "\(i) indirect")
    }

    // MARK: - RPE profile

    private var rpeSection: some View {
        let p = LiftMetrics.rpeProfile(performed)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("How hard it felt")
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mean RPE")
                            .font(StrandFont.pro(17))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(p.mean.map { LiftFormat.trim($0) } ?? "—")
                            .font(StrandFont.pro(28, weight: .semibold))
                            .foregroundStyle(StrandPalette.fitnessEffort)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Sets at RPE \(LiftFormat.trim(p.threshold)) or above"))
                            .font(StrandFont.pro(17))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("\(p.setsAtOrAboveThreshold)")
                            .font(StrandFont.pro(28, weight: .semibold))
                            .foregroundStyle(StrandPalette.fitnessEffort)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                .padding(.vertical, 12)
                if p.unratedSets > 0 {
                    Divider()
                    Text(String(localized: "\(p.unratedSets) working sets weren't rated, so the mean is drawn from \(p.ratedSets)."))
                        .font(StrandFont.pro(13))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .background(StrandPalette.summaryCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    // MARK: - Load

    private func load() async {
        guard let store = await repo.storeHandle() else { sessionRpe = session.sessionRpe; loaded = true; return }
        sets = (try? await store.liftSets(sessionId: session.id)) ?? []
        // Re-read rather than trusting the row this sheet was opened with: the edit sheet can change it.
        let stored = try? await store.liftSessions(deviceId: session.deviceId,
                                                   fromTs: session.startTs, toTs: session.startTs)
        if let row = stored?.first(where: { $0.id == session.id }) {
            sessionRpe = row.sessionRpe
        } else {
            sessionRpe = session.sessionRpe
        }

        // The workout row this session is pinned to, by that table's own natural key.
        let rows = (try? await store.workouts(deviceId: repo.deviceId,
                                              from: session.startTs - 1,
                                              to: session.startTs + 1, limit: 10)) ?? []
        workout = rows.first { $0.startTs == session.startTs && $0.sport == session.sport }

        // Previous volume per exercise, for the "vs last time" line.
        var previous: [String: Double] = [:]
        for name in Set(performed.map(\.exercise)) {
            let before = (try? await store.lastLiftSets(deviceId: repo.deviceId,
                                                        exercise: name,
                                                        before: session.startTs)) ?? []
            if let v = LiftMetrics.volumeLoadKg(before) { previous[name] = v }
        }
        previousVolume = previous
        loaded = true
    }
}
