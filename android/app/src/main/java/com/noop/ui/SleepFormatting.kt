package com.noop.ui

import androidx.compose.ui.graphics.Color
import com.noop.analytics.SleepDebt
import com.noop.analytics.SleepDebtLedger
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

// MARK: - Formatting helpers (mirror SleepView.swift)

internal fun pct(minutes: Double, total: Double): Int =
    if (total > 0.0) (minutes / total * 100.0).roundToInt() else 0

/** "+12% vs typical" / "−0.4 rpm vs typical" — the latest-vs-mean caption every tile carries. */
internal fun vsTypical(latest: Double?, typical: Double?, suffix: String, decimals: Int = 0): String {
    if (latest == null || typical == null || typical == 0.0) return "vs typical - "
    val diff = latest - typical
    val sign = if (diff >= 0) "+" else "−"
    val mag = abs(diff)
    val num = if (decimals == 0) "${mag.roundToInt()}" else String.format(java.util.Locale.US, "%.${decimals}f", mag)
    return "$sign$num$suffix vs typical"
}

// MARK: - Sleep-debt ledger formatting (mirror SleepView.swift)

internal fun durationText(minutes: Double): String {
    val m = max(0, minutes.roundToInt())
    return if (m < 60) "${m}m" else "${m / 60}h ${m % 60}m"
}

internal fun List<Double>.sleepAverageOrNull(): Double? =
    if (isEmpty()) null else sum() / size
