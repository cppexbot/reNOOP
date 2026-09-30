package com.noop.ui

import java.time.LocalDate

/** Trailing 30 calendar days, inclusive of the selected day; unrecorded days are not zero steps. */
internal fun rollingStepsAverage(readings: List<VitalReading>, through: LocalDate): Pair<Double?, Int> {
    val start = through.minusDays(29)
    val observed = readings.filter {
        val day = runCatching { LocalDate.parse(it.day) }.getOrNull()
        day != null && !day.isBefore(start) && !day.isAfter(through) && it.value.isFinite() && it.value >= 0
    }.distinctBy { it.day }
    return (observed.takeIf { it.isNotEmpty() }?.map { it.value }?.average()) to observed.size
}

/** #377: merge the three step stores into one per-day series with the SAME precedence as the Today
 *  Steps tile — a REAL on-device count ([real], WHOOP 5/MG @57 → DailyMetric.steps) wins, else an
 *  [imported] Health Connect / Apple Health count, else the motion-model [est] (`steps_est`). The three
 *  are disjoint stores so the `?:` chain never double-counts. Ascending by day. Pure for testability. */
internal fun mergeStepsReadings(
    real: Map<String, VitalReading>,
    imported: Map<String, VitalReading>,
    est: Map<String, VitalReading>,
): List<VitalReading> =
    (real.keys + imported.keys + est.keys).toSortedSet()
        .mapNotNull { day ->
            listOf(real[day], imported[day], est[day])
                .firstOrNull { it != null && it.value.isFinite() && it.value >= 0.0 }
        }

/**
 * Every day's steps as the Today Steps tile resolves them (#377), for the 30-day average card: the
 * on-device count, else an imported Apple Health / Health Connect total, else the motion estimate.
 */
internal suspend fun mergedStepsReadings(vm: AppViewModel): List<VitalReading> {
    suspend fun resolved(key: String) = vm.repo.resolvedSeries(key, "my-whoop", "0000-00-00", "9999-99-99", strapDeviceId = vm.activeStrapId)
    val real = resolved("steps").points.asSequence()
        .filter { it.value.isFinite() && it.value >= 0.0 }
        .associateBy({ it.day }, { VitalReading(it.day, it.value, it.source) })
    val imported = LinkedHashMap<String, VitalReading>()
    for (r in vm.repo.appleDaily("apple-health", "0000-01-01", "9999-12-31") +
        vm.repo.appleDaily("health-connect", "0000-01-01", "9999-12-31")) {
        val s = r.steps
        if (s != null && s >= 0) imported.putIfAbsent(r.day, VitalReading(r.day, s.toDouble(), r.deviceId))
    }
    val est = resolved("steps_est").points.asSequence()
        .filter { it.value.isFinite() && it.value >= 0.0 }
        .associateBy({ it.day }, { VitalReading(it.day, it.value, it.source) })
    return mergeStepsReadings(real, imported, est)
}
