package com.noop.ui.sleep

import com.noop.analytics.RestScorer
import com.noop.data.DailyMetric
import com.noop.ui.PersistedSegment
import com.noop.ui.Stages
import com.noop.ui.canonicalStage
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

// MARK: - The pure logic of the Sleep tab (twin of iOS Strand/SleepHealth/SleepScore, SleepVitals,
// SleepHistory and SleepMoreData). No Android types: the screens map the enums below to strings.

// MARK: Sleep Score

/** The four parts of the Rest composite, in the composite's own order. */
internal enum class SleepScorePart {
    DURATION, INTERRUPTIONS, RESTORATIVE, REGULARITY;

    /** Points this part is worth out of 100 (the composite's weights). */
    val maxPoints: Int
        get() = when (this) {
            DURATION -> (RestScorer.wDuration * 100).roundToInt()
            INTERRUPTIONS -> (RestScorer.wEfficiency * 100).roundToInt()
            RESTORATIVE -> (RestScorer.wRestorative * 100).roundToInt()
            REGULARITY -> (RestScorer.wConsistency * 100).roundToInt()
        }

    companion object {
        /** The ring, clockwise from 12 o'clock. */
        val ringOrder = listOf(INTERRUPTIONS, DURATION, RESTORATIVE, REGULARITY)
        /** The legend under the ring. */
        val legendOrder = listOf(DURATION, RESTORATIVE, REGULARITY, INTERRUPTIONS)
    }
}

/** How the night did on one part: the share earned (0…1) and, for an on-device score, its whole points. */
internal data class SleepScorePartScore(val part: SleepScorePart, val fraction: Double, val points: Int?)

/** The word under the ring. */
internal enum class SleepScoreWord { POOR, FAIR, GOOD, OPTIMAL }

/** Which sentence closes the score card. */
internal enum class SleepScoreSentence { IMPORTED, SOUND, DURATION, INTERRUPTIONS, RESTORATIVE, REGULARITY }

/**
 * One night's sleep score split into its parts (iOS `SleepScore`). The score is the one every surface
 * shows: WHOOP's imported figure for the wake-day when the export carried one, else the Rest composite of
 * the day's row ([RestScorer.restFromDaily]). The parts are the composite's own sub-scores, rounded so the
 * legend's points add up to the number in the ring. An imported score has no known make-up: its parts are
 * the night's own figures without points, and regularity (a neutral constant for one night) is left out.
 */
internal data class SleepScore(val value: Int, val imported: Boolean, val parts: List<SleepScorePartScore>) {

    val word: SleepScoreWord get() = word(value)

    /** The part that cost the most points, or [SleepScoreSentence.SOUND] when the night lost fewer than 10. */
    val sentence: SleepScoreSentence
        get() {
            if (imported) return SleepScoreSentence.IMPORTED
            val lost = parts.map { it.part to it.part.maxPoints * (1 - it.fraction) }
            val worst = lost.maxByOrNull { it.second }
            if (worst == null || lost.sumOf { it.second } < 10.0) return SleepScoreSentence.SOUND
            return when (worst.first) {
                SleepScorePart.DURATION -> SleepScoreSentence.DURATION
                SleepScorePart.INTERRUPTIONS -> SleepScoreSentence.INTERRUPTIONS
                SleepScorePart.RESTORATIVE -> SleepScoreSentence.RESTORATIVE
                SleepScorePart.REGULARITY -> SleepScoreSentence.REGULARITY
            }
        }

    companion object {
        /** The composite's sub-scores for a day row, each 0…1, exactly as [RestScorer.rest] weighs them. */
        fun components(daily: DailyMetric): Map<SleepScorePart, Double>? {
            val tstMin = daily.totalSleepMin ?: return null
            val eff = daily.efficiency ?: return null
            if (tstMin <= 0.0) return null
            val asleepSec = tstMin * 60.0
            val deepSec = (daily.deepMin ?: 0.0) * 60.0
            val remSec = (daily.remMin ?: 0.0) * 60.0
            val needHours = RestScorer.defaultSleepNeedHours.coerceAtLeast(0.1)
            val duration = min(1.0, asleepSec / 3600.0 / needHours)
            val efficiency = eff.coerceIn(0.0, 1.0)
            val deepAdequacy = ((deepSec / asleepSec) / RestScorer.deepShareTarget).coerceIn(0.0, 1.0)
            val deepFactor = RestScorer.deepFloorFactor + (1.0 - RestScorer.deepFloorFactor) * deepAdequacy
            val restorative = min(1.0, (deepSec + remSec) / asleepSec / RestScorer.restorativeTargetShare) * deepFactor
            val consistency = RestScorer.NEUTRAL_CONSISTENCY.coerceIn(0.0, 1.0)
            return mapOf(
                SleepScorePart.DURATION to duration,
                SleepScorePart.INTERRUPTIONS to efficiency,
                SleepScorePart.RESTORATIVE to restorative,
                SleepScorePart.REGULARITY to consistency,
            )
        }

        /** The night's score from its day row and the imported figure for the same wake-day. */
        fun make(daily: DailyMetric?, importedPct: Double?): SleepScore? {
            val c = daily?.let { components(it) }
            if (importedPct != null) {
                val parts = c?.let { m ->
                    listOf(SleepScorePart.DURATION, SleepScorePart.INTERRUPTIONS, SleepScorePart.RESTORATIVE)
                        .map { SleepScorePartScore(it, m.getValue(it), null) }
                } ?: emptyList()
                return SleepScore(importedPct.roundToInt(), imported = true, parts = parts)
            }
            if (daily == null || c == null) return null
            val composite = RestScorer.restFromDaily(daily) ?: return null
            val total = composite.roundToInt()
            val order = listOf(
                SleepScorePart.DURATION, SleepScorePart.INTERRUPTIONS, SleepScorePart.RESTORATIVE, SleepScorePart.REGULARITY,
            )
            val points = apportion(order.map { it.maxPoints * c.getValue(it) }, total)
            return SleepScore(total, imported = false, parts = order.mapIndexed { i, p ->
                SleepScorePartScore(p, c.getValue(p), points[i])
            })
        }

        /** Whole-number shares of [raw] that sum to [total] (largest remainder). */
        fun apportion(raw: List<Double>, total: Int): List<Int> {
            val out = raw.map { floor(it).toInt() }.toMutableList()
            val short = total - out.sum()
            if (short == 0) return out
            val order = raw.indices.sortedByDescending { raw[it] - out[it] }
            if (short > 0) {
                order.take(short).forEach { out[it] += 1 }
            } else {
                order.reversed().take(-short).forEach { if (out[it] > 0) out[it] -= 1 }
            }
            return out
        }

        /** The banding the Rest word has always used. */
        fun word(value: Int): SleepScoreWord = when {
            value < 50 -> SleepScoreWord.POOR
            value < 70 -> SleepScoreWord.FAIR
            value < 85 -> SleepScoreWord.GOOD
            else -> SleepScoreWord.OPTIMAL
        }
    }
}

// MARK: Stage intervals

/** The four rows of the stages chart, top to bottom. */
internal enum class SleepStageRow { AWAKE, REM, CORE, DEEP;

    companion object {
        fun of(stage: String): SleepStageRow = when (canonicalStage(stage)) {
            "awake" -> AWAKE
            "rem" -> REM
            "deep" -> DEEP
            else -> CORE
        }
    }
}

/** One run of a stage in seconds from the night's onset. */
internal data class SleepStageSpan(val row: SleepStageRow, val startSec: Double, val endSec: Double) {
    val durationSec: Double get() = endSec - startSec
}

/** A night's timestamped segments as spans from [onsetTs], clipped to start at the onset. */
internal fun stageSpans(segments: List<PersistedSegment>?, onsetTs: Long): List<SleepStageSpan> =
    segments.orEmpty().sortedBy { it.start }.mapNotNull { s ->
        val start = max(0L, s.start - onsetTs).toDouble()
        val end = (s.end - onsetTs).toDouble()
        if (end > start) SleepStageSpan(SleepStageRow.of(s.stage), start, end) else null
    }

/** Minutes of [row] in [stages]. */
internal fun Stages.minutes(row: SleepStageRow): Double = when (row) {
    SleepStageRow.AWAKE -> awake
    SleepStageRow.REM -> rem
    SleepStageRow.CORE -> light
    SleepStageRow.DEEP -> deep
}

// MARK: Vitals

/** A night's overnight vitals against their typical ranges (iOS `SleepVitals`). */
internal data class SleepVitals(val readings: List<Reading>, val nightsRemaining: Int) {

    enum class Metric(val catalogKey: String, val minHalfWidth: Double) {
        HEART_RATE("rhr", 2.0),
        RESPIRATORY("resp_rate", 0.5),
        TEMPERATURE("skin_temp", 0.3),
        OXYGEN("spo2", 1.0),
        SLEEP_DURATION("sleep_total_min", 30.0);

        /** This metric's reading for one day's row: skin temperature as a deviation or an absolute. */
        fun value(row: DailyMetric, deviation: Boolean = false): Double? = when (this) {
            HEART_RATE -> row.restingHr?.toDouble()
            RESPIRATORY -> row.respRateBpm
            TEMPERATURE -> if (deviation) row.skinTempDevC else row.skinTempC
            OXYGEN -> row.spo2Pct
            SLEEP_DURATION -> row.totalSleepMin
        }
    }

    data class Reading(val metric: Metric, val value: Double, val low: Double, val high: Double) {
        /** 0 at the range's low edge, 1 at its high edge, outside 0…1 beyond it. */
        val position: Double get() = if (high - low > 0) (value - low) / (high - low) else 0.5
        val isOutlier: Boolean get() = value < low || value > high
    }

    val nightsRecorded: Int get() = NIGHTS_NEEDED - nightsRemaining
    val outliers: Int get() = readings.count { it.isOutlier }

    companion object {
        const val NIGHTS_NEEDED = 7
        const val WINDOW = 28

        /** The night that ended on [day] read against up to [WINDOW] nights before it. */
        fun make(rows: List<DailyMetric>, day: String): SleepVitals {
            val tonight = rows.lastOrNull { it.day == day } ?: return SleepVitals(emptyList(), NIGHTS_NEEDED)
            val prior = rows.filter { it.day < day }.sortedBy { it.day }.takeLast(WINDOW)
            val withVitals = prior.count { row ->
                Metric.entries.any { it.value(row) != null || it.value(row, deviation = true) != null }
            }
            val remaining = max(0, NIGHTS_NEEDED - withVitals)
            if (remaining != 0) return SleepVitals(emptyList(), remaining)
            val deviation = tonight.skinTempDevC != null
            val readings = Metric.entries.mapNotNull { metric ->
                val value = metric.value(tonight, deviation) ?: return@mapNotNull null
                val history = prior.mapNotNull { metric.value(it, deviation) }
                if (history.size < NIGHTS_NEEDED) return@mapNotNull null
                val (lo, hi) = typicalRange(history, metric.minHalfWidth) ?: return@mapNotNull null
                Reading(metric, value, lo, hi)
            }
            return SleepVitals(readings, 0)
        }

        /** Mean ± two standard deviations, at least [minHalfWidth] either side. */
        fun typicalRange(values: List<Double>, minHalfWidth: Double): Pair<Double, Double>? {
            if (values.isEmpty()) return null
            val mean = values.sum() / values.size
            val variance = values.sumOf { (it - mean) * (it - mean) } / values.size
            val half = max(2 * sqrt(variance), minHalfWidth)
            return (mean - half) to (mean + half)
        }
    }
}

// MARK: Nights over time

/** One decoded night: its span, stage totals and (when stored) its timestamped stages. */
internal data class SleepNightDetail(
    /** Index into navDays (0 = newest night on record). */
    val navIndex: Int,
    /** The calendar day the night ended on, and its "yyyy-MM-dd" key. */
    val day: LocalDate,
    val onsetTs: Long,
    val wakeTs: Long,
    val stages: Stages,
    /** Spans from [onsetTs]; empty when the night carries only stage totals. */
    val spans: List<SleepStageSpan>,
) {
    val dayKey: String get() = day.toString()
    val inBedMin: Double get() = stages.total
    val asleepMin: Double get() = stages.asleep
    val entry: SleepNightEntry get() = SleepNightEntry(day, onsetTs, wakeTs, asleepMin)
}

/** A night as (bedtime, wake, time asleep), with a night clock that runs through midnight. */
internal data class SleepNightEntry(val day: LocalDate, val onsetTs: Long, val wakeTs: Long, val asleepMin: Double) {
    /** Minutes after 18:00 on the evening before [day]. */
    fun onsetOfNightMin(zone: ZoneId = ZoneId.systemDefault()): Double = (onsetTs - nightOrigin(day, zone)) / 60.0
    fun wakeOfNightMin(zone: ZoneId = ZoneId.systemDefault()): Double = (wakeTs - nightOrigin(day, zone)) / 60.0

    companion object {
        fun nightOrigin(day: LocalDate, zone: ZoneId): Long = day.atStartOfDay(zone).toEpochSecond() - 6 * 3600
    }
}

internal enum class SleepRange { DAY, WEEK, MONTH, SIX_MONTHS }

/** One bar of a range chart: a night (week / month) or a week's average (6 months). */
internal data class SleepRangeBar(
    val slot: Int,
    val start: LocalDate,
    val onsetMin: Double,
    val wakeMin: Double,
    val asleepMin: Double,
)

internal data class SleepRangeWindow(val range: SleepRange, val slotStarts: List<LocalDate>, val bars: List<SleepRangeBar>) {
    val averageAsleepMin: Double? get() = if (bars.isEmpty()) null else bars.sumOf { it.asleepMin } / bars.size
}

internal object SleepHistory {
    /** The window ending on [today]: 7 nights, 30 nights, or 26 weekly averages (weeks start Monday). */
    fun window(
        range: SleepRange,
        entries: List<SleepNightEntry>,
        today: LocalDate,
        zone: ZoneId = ZoneId.systemDefault(),
    ): SleepRangeWindow {
        val byDay = entries.associateBy { it.day }
        return when (range) {
            SleepRange.DAY, SleepRange.WEEK, SleepRange.MONTH -> {
                val count = if (range == SleepRange.MONTH) 30 else 7
                val starts = (count - 1 downTo 0).map { today.minusDays(it.toLong()) }
                val bars = starts.mapIndexedNotNull { slot, day ->
                    val e = byDay[day] ?: return@mapIndexedNotNull null
                    SleepRangeBar(slot, day, e.onsetOfNightMin(zone), e.wakeOfNightMin(zone), e.asleepMin)
                }
                SleepRangeWindow(range, starts, bars)
            }
            SleepRange.SIX_MONTHS -> {
                val thisWeek = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                val starts = (25 downTo 0).map { thisWeek.minusWeeks(it.toLong()) }
                val bars = starts.mapIndexedNotNull { slot, weekStart ->
                    val weekEnd = weekStart.plusDays(7)
                    val nights = entries.filter { !it.day.isBefore(weekStart) && it.day.isBefore(weekEnd) }
                    if (nights.isEmpty()) return@mapIndexedNotNull null
                    val n = nights.size.toDouble()
                    SleepRangeBar(
                        slot, weekStart,
                        nights.sumOf { it.onsetOfNightMin(zone) } / n,
                        nights.sumOf { it.wakeOfNightMin(zone) } / n,
                        nights.sumOf { it.asleepMin } / n,
                    )
                }
                SleepRangeWindow(range, starts, bars)
            }
        }
    }

    /** The nights a range view covers, by the same slot boundaries as [window]. */
    fun nightsIn(range: SleepRange, nights: List<SleepNightDetail>, today: LocalDate): List<SleepNightDetail> {
        val first = window(range, emptyList(), today).slotStarts.firstOrNull() ?: return emptyList()
        return nights.filter { !it.day.isBefore(first) && !it.day.isAfter(today) }
    }

    /** The vertical domain of a range chart (night-clock minutes): whole hours either side, at least 2 h. */
    fun domain(window: SleepRangeWindow): Pair<Double, Double> {
        val lo = window.bars.minOfOrNull { it.onsetMin } ?: return 240.0 to 840.0
        val hi = window.bars.maxOf { it.wakeMin }
        val start = (floor(lo / 60) - 1) * 60
        val end = (ceil(hi / 60) + 1) * 60
        return start to max(start + 120, end)
    }
}

/** Averages over a set of nights (a single night averages to itself). */
internal data class SleepPeriodSummary(
    val nights: Int,
    val inBedMin: Double?,
    val asleepMin: Double?,
    val stageMin: Map<SleepStageRow, Double>,
    val bedtimeOfNightMin: Double?,
    val wakeOfNightMin: Double?,
) {
    fun share(row: SleepStageRow): Double? {
        val inBed = inBedMin ?: return null
        val m = stageMin[row] ?: return null
        return if (inBed > 0) m / inBed else null
    }

    val efficiency: Double?
        get() {
            val inBed = inBedMin ?: return null
            val asleep = asleepMin ?: return null
            return if (inBed > 0) asleep / inBed else null
        }

    companion object {
        fun of(nights: List<SleepNightDetail>, zone: ZoneId = ZoneId.systemDefault()): SleepPeriodSummary {
            if (nights.isEmpty()) return SleepPeriodSummary(0, null, null, emptyMap(), null, null)
            val n = nights.size.toDouble()
            fun mean(f: (SleepNightDetail) -> Double) = nights.sumOf(f) / n
            return SleepPeriodSummary(
                nights = nights.size,
                inBedMin = mean { it.inBedMin },
                asleepMin = mean { it.asleepMin },
                stageMin = SleepStageRow.entries.associateWith { row -> mean { it.stages.minutes(row) } },
                bedtimeOfNightMin = mean { it.entry.onsetOfNightMin(zone) },
                wakeOfNightMin = mean { it.entry.wakeOfNightMin(zone) },
            )
        }
    }
}

/** The vertical scale an overlaid vital is drawn on: its own min…max, at least 20 % of its level wide. */
internal fun overlayDomain(values: List<Double>): Pair<Double, Double>? {
    val lo = values.minOrNull() ?: return null
    val hi = values.maxOrNull() ?: return null
    val minSpread = max(abs((lo + hi) / 2) * 0.2, 1.0)
    if (hi - lo >= minSpread) return lo to hi
    val mid = (lo + hi) / 2
    return (mid - minSpread / 2) to (mid + minSpread / 2)
}

// MARK: Highlights

/** A Health-style Sleep highlight: which sentence, and the figures and nights behind it. */
internal sealed class SleepHighlight {
    /** Last night's bedtime against the mean of up to seven nights before it; [diffMin] rounded to 5. */
    data class Bedtime(val diffMin: Int, val usualMin: Double, val lastMin: Double, val nights: List<Double>) : SleepHighlight()

    /** The last seven days' average time asleep against the seven before; [diffMin] rounded to 5. */
    data class Duration(val averageMin: Double, val priorAverageMin: Double, val diffMin: Int, val nights: List<Double>) : SleepHighlight()

    companion object {
        fun make(entries: List<SleepNightEntry>, today: LocalDate, zone: ZoneId = ZoneId.systemDefault()): List<SleepHighlight> =
            listOfNotNull(bedtime(entries, zone), duration(entries, today))

        fun bedtime(entries: List<SleepNightEntry>, zone: ZoneId = ZoneId.systemDefault()): Bedtime? {
            val last = entries.lastOrNull() ?: return null
            val before = entries.dropLast(1).takeLast(7)
            if (before.size < 3) return null
            val usual = before.sumOf { it.onsetOfNightMin(zone) } / before.size
            val lastMin = last.onsetOfNightMin(zone)
            val diff = ((lastMin - usual) / 5).roundToInt() * 5
            return Bedtime(diff, usual, lastMin, before.map { it.onsetOfNightMin(zone) } + lastMin)
        }

        fun duration(entries: List<SleepNightEntry>, today: LocalDate): Duration? {
            val weekAgo = today.minusDays(7)
            val twoWeeksAgo = today.minusDays(14)
            val recent = entries.filter { it.day.isAfter(weekAgo) && !it.day.isAfter(today) }
            val prior = entries.filter { it.day.isAfter(twoWeeksAgo) && !it.day.isAfter(weekAgo) }
            if (recent.size < 3 || prior.size < 3) return null
            val avg = recent.sumOf { it.asleepMin } / recent.size
            val priorAvg = prior.sumOf { it.asleepMin } / prior.size
            val diff = ((avg - priorAvg) / 5).roundToInt() * 5
            return Duration(avg, priorAvg, diff, recent.map { it.asleepMin })
        }
    }
}

/** Hours and minutes of a duration, rounded to the minute. */
internal fun durationParts(minutes: Double): Pair<Int, Int> {
    val total = max(0, minutes.roundToInt())
    return (total / 60) to (total % 60)
}

/** The local calendar day an instant falls on. */
internal fun localDate(ts: Long, zone: ZoneId = ZoneId.systemDefault()): LocalDate =
    Instant.ofEpochSecond(ts).atZone(zone).toLocalDate()
