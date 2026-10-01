package com.noop.ui

import com.noop.data.DailyMetric
import com.noop.data.WorkoutRow

// MARK: - Activity Cost inputs (#439)
//
// Kept from the retired Insights screen (iOS 8f840a3c split Insights into Journal and What Moves You and
// dropped the Activity Cost section); the Workouts detail still reads one sport's cost through it.

/**
 * Shape the [ActivityCostEngine] inputs from the loaded sessions + cached daily metrics, then rank.
 * [workouts] → [sport: Set<localDayKey>] (displaySport collapses detected/"Activity" into one bucket
 * and de-camelCases WHOOP names; manual/imported labels pass through), keyed by the LOCAL calendar
 * day the session STARTED via the SAME AnalyticsEngine.dayString path [DailyMetric.day] uses, so the
 * engine's D+1 next-morning alignment is honest. [days] → [localDayKey: Charge] off DailyMetric.recovery.
 */
internal fun computeActivityCosts(
    workouts: List<WorkoutRow>,
    days: List<DailyMetric>,
): List<com.noop.analytics.ActivityCost> {
    // Single "now" offset for every session, the SAME tz-offset basis IntelligenceEngine.kt uses to
    // key DailyMetric.day (getOffset(now)/1000 applied across the run), via the SAME
    // AnalyticsEngine.dayString(ts, offsetSec) path, so the engine's D+1 next-morning lookups align
    // byte-for-byte with the recovery keys (and match the Swift TimeZone.current.secondsFromGMT path).
    val offsetSec = java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 1_000L
    val activityDaysBySport = HashMap<String, MutableSet<String>>()
    for (w in workouts) {
        val sport = WorkoutEditing.displaySport(w.sport)
        if (sport.isEmpty()) continue
        val day = com.noop.analytics.AnalyticsEngine.dayString(w.startTs, offsetSec)
        activityDaysBySport.getOrPut(sport) { mutableSetOf() }.add(day)
    }
    val recoveryByDay = HashMap<String, Double>()
    for (d in days) {
        d.recovery?.let { recoveryByDay[d.day] = it }
    }
    return com.noop.analytics.ActivityCostEngine.evaluate(
        activityDaysBySport = activityDaysBySport.mapValues { it.value.toSet() },
        recoveryByDay = recoveryByDay,
    )
}
