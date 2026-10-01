package com.noop.ui

import com.noop.analytics.AutoWorkoutDetector
import com.noop.data.WorkoutRow

// MARK: - Auto-detected workouts: the pure source-union helpers
//
// The "looks like a workout" card that offered to save a detected bout lived on the old Today and went with
// it, as iOS's AutoWorkoutCard did (Denis 63984147). What stays is the pure half its tests pin: the saved-row
// union the detector excludes, the labelled spans its shadow comparison reads, and the policies it compares.

/**
 * Compose the same saved-workout source set the Workouts screen/Swift `workoutRows()` expose, then apply
 * the shared cross-source duplicate collapse once. The WHOOP arguments are already natural-key-deduped by
 * [com.noop.data.WhoopRepository.workoutsUnion] / `detectedWorkoutsUnion`; this final pass collapses a
 * physical activity mirrored by another provider without hiding distinct sessions.
 */
internal fun mergeAutoDetectSavedRows(
    whoopRows: List<WorkoutRow>,
    computedRows: List<WorkoutRow>,
    appleRows: List<WorkoutRow>,
    healthConnectRows: List<WorkoutRow>,
    liftingRows: List<WorkoutRow>,
    activityFileRows: List<WorkoutRow>,
): List<WorkoutRow> = WorkoutEditing.dedupCrossSource(
    whoopRows + computedRows + appleRows + healthConnectRows + liftingRows + activityFileRows,
)

/** Shadow ground truth is the already-deduped saved set, excluding legacy detector output. */
internal fun autoDetectLabelledSpans(savedRows: List<WorkoutRow>): List<Pair<Long, Long>> =
    savedRows
        .filter { WorkoutEditing.classify(it.source) != WorkoutSource.DETECTED }
        .map { it.startTs to it.endTs }

/** Compare the published baseline with every proposed shadow alternative in stable order. */
internal fun autoDetectShadowPolicies(): List<Double> =
    (AutoWorkoutDetector.shadowSustainedMinutes + AutoWorkoutDetector.minSustainedMin)
        .distinct()
        .sorted()
