package com.noop.ui.sleep

import com.noop.analytics.RestScorer
import com.noop.data.DailyMetric
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset

/** Pins the Sleep tab's pure logic: the score card, the vitals verdict and the highlights. */
class SleepLogicTest {

    private fun row(
        day: String,
        total: Double? = 420.0,
        eff: Double? = 0.9,
        deep: Double? = 80.0,
        rem: Double? = 100.0,
        light: Double? = 240.0,
        rhr: Int? = 55,
        resp: Double? = 14.5,
        spo2: Double? = 97.0,
        dev: Double? = 0.1,
    ) = DailyMetric(
        deviceId = "my-whoop", day = day, totalSleepMin = total, efficiency = eff, deepMin = deep, remMin = rem,
        lightMin = light, restingHr = rhr, respRateBpm = resp, spo2Pct = spo2, skinTempDevC = dev,
    )

    // MARK: Score

    @Test fun wordBands() {
        assertEquals(SleepScoreWord.POOR, SleepScore.word(49))
        assertEquals(SleepScoreWord.FAIR, SleepScore.word(50))
        assertEquals(SleepScoreWord.FAIR, SleepScore.word(69))
        assertEquals(SleepScoreWord.GOOD, SleepScore.word(70))
        assertEquals(SleepScoreWord.GOOD, SleepScore.word(84))
        assertEquals(SleepScoreWord.OPTIMAL, SleepScore.word(85))
    }

    @Test fun partsAreTheCompositeWeights() {
        assertEquals(listOf(50, 20, 20, 10), SleepScorePart.entries.map { it.maxPoints })
    }

    @Test fun componentsRebuildTheComposite() {
        val d = row("2026-09-30", total = 390.0, eff = 0.86, deep = 40.0, rem = 70.0, light = 280.0)
        val c = SleepScore.components(d)!!
        val weighted = SleepScorePart.entries.sumOf { it.maxPoints * c.getValue(it) }
        assertEquals(RestScorer.restFromDaily(d)!!, weighted, 0.01)
    }

    @Test fun pointsAddUpToTheRing() {
        for (total in listOf(390.0, 300.0, 480.0, 200.0)) {
            val s = SleepScore.make(row("2026-09-30", total = total, eff = 0.83, deep = 50.0), null)!!
            assertEquals(s.value, s.parts.sumOf { it.points!! })
        }
    }

    @Test fun apportionLargestRemainder() {
        assertEquals(listOf(42, 16, 9, 17), SleepScore.apportion(listOf(41.6, 15.7, 9.2, 16.5), 84))
        assertEquals(listOf(1, 1, 0), SleepScore.apportion(listOf(0.6, 0.6, 0.6), 2))
        assertEquals(84, SleepScore.apportion(listOf(42.9, 16.9, 9.9, 16.9), 84).sum())
    }

    @Test fun sentenceNamesTheBiggestLoss() {
        fun score(vararg f: Double) = SleepScore(70, false, SleepScorePart.entries.mapIndexed { i, p -> SleepScorePartScore(p, f[i], 0) })
        // Duration loses 15 of 50; the others little.
        assertEquals(SleepScoreSentence.DURATION, score(0.7, 0.95, 0.95, 0.9).sentence)
        // Interruptions lose 8 of 20, more than duration's 5.
        assertEquals(SleepScoreSentence.INTERRUPTIONS, score(0.9, 0.6, 0.95, 1.0).sentence)
        assertEquals(SleepScoreSentence.RESTORATIVE, score(0.95, 1.0, 0.4, 1.0).sentence)
        assertEquals(SleepScoreSentence.REGULARITY, score(1.0, 1.0, 1.0, 0.0).sentence)
        // Under 10 points lost in all: a sound night.
        assertEquals(SleepScoreSentence.SOUND, score(0.95, 0.9, 0.95, 0.9).sentence)
    }

    @Test fun importedScoreHasNoPointsAndNoRegularity() {
        val s = SleepScore.make(row("2026-09-30"), importedPct = 93.4)!!
        assertTrue(s.imported)
        assertEquals(93, s.value)
        assertEquals(SleepScoreSentence.IMPORTED, s.sentence)
        assertEquals(listOf(SleepScorePart.DURATION, SleepScorePart.INTERRUPTIONS, SleepScorePart.RESTORATIVE), s.parts.map { it.part })
        assertTrue(s.parts.all { it.points == null })
    }

    @Test fun noRowNoScore() {
        assertNull(SleepScore.make(null, null))
        assertNull(SleepScore.make(row("2026-09-30", total = null), null))
    }

    // MARK: Vitals

    private fun history(n: Int, rhr: Int = 55) = (1..n).map { i -> row("2026-09-%02d".format(i), rhr = rhr + (i % 3) - 1) }

    @Test fun vitalsLearnForSevenNights() {
        val rows = history(4) + row("2026-09-30")
        val v = SleepVitals.make(rows, "2026-09-30")
        assertEquals(3, v.nightsRemaining)
        assertEquals(4, v.nightsRecorded)
        assertTrue(v.readings.isEmpty())
    }

    @Test fun vitalsTypicalAndOutliers() {
        val typical = SleepVitals.make(history(10) + row("2026-09-30"), "2026-09-30")
        assertEquals(0, typical.nightsRemaining)
        assertEquals(0, typical.outliers)
        assertEquals(SleepVitals.Metric.entries.size, typical.readings.size)
        val high = SleepVitals.make(history(10) + row("2026-09-30", rhr = 70, spo2 = 90.0), "2026-09-30")
        assertEquals(2, high.outliers)
        val hr = high.readings.first { it.metric == SleepVitals.Metric.HEART_RATE }
        assertTrue(hr.position > 1)
    }

    @Test fun vitalsRangeNeverNarrowerThanResolution() {
        val (lo, hi) = SleepVitals.typicalRange(List(10) { 55.0 }, minHalfWidth = 2.0)!!
        assertEquals(53.0, lo, 1e-9)
        assertEquals(57.0, hi, 1e-9)
    }

    // MARK: Highlights and ranges

    private val utc = ZoneOffset.UTC

    private fun entry(day: String, onsetHour: Double, asleep: Double = 420.0): SleepNightEntry {
        val d = LocalDate.parse(day)
        val onset = d.atStartOfDay(utc).toEpochSecond() + ((onsetHour - 24) * 3600).toLong()
        return SleepNightEntry(d, onset, onset + 8 * 3600, asleep)
    }

    @Test fun bedtimeHighlightRoundsToFiveAndNeedsThreeNights() {
        assertNull(SleepHighlight.bedtime(listOf(entry("2026-09-28", 23.0), entry("2026-09-29", 23.0), entry("2026-09-30", 23.5)), utc))
        val h = SleepHighlight.bedtime(
            listOf(entry("2026-09-26", 23.0), entry("2026-09-27", 23.0), entry("2026-09-28", 23.0), entry("2026-09-29", 23.0), entry("2026-09-30", 23.6)),
            utc,
        )!!
        assertEquals(35, h.diffMin)
        assertEquals(5, h.nights.size)
    }

    @Test fun durationHighlightComparesTwoWeeks() {
        val today = LocalDate.parse("2026-09-30")
        val entries = (0 until 14).map { i -> entry(today.minusDays(i.toLong()).toString(), 23.0, if (i < 7) 450.0 else 420.0) }.sortedBy { it.day }
        val h = SleepHighlight.duration(entries, today)!!
        assertEquals(30, h.diffMin)
        assertEquals(450.0, h.averageMin, 1e-9)
    }

    @Test fun weekWindowHasSevenSlotsAndSixMonthsTwentySix() {
        val today = LocalDate.parse("2026-09-30")
        val entries = listOf(entry("2026-09-29", 23.0), entry("2026-09-30", 22.5))
        val w = SleepHistory.window(SleepRange.WEEK, entries, today, utc)
        assertEquals(7, w.slotStarts.size)
        assertEquals(listOf(5, 6), w.bars.map { it.slot })
        assertEquals(5 * 60.0, w.bars.first().onsetMin, 1e-9) // 23:00 is five hours into the night clock
        assertEquals(26, SleepHistory.window(SleepRange.SIX_MONTHS, entries, today, utc).slotStarts.size)
    }

    @Test fun overlayDomainWidensAFlatLine() {
        val (lo, hi) = overlayDomain(listOf(60.0, 60.5))!!
        assertTrue(hi - lo >= 12.0)
    }
}
