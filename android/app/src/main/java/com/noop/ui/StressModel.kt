package com.noop.ui

import com.noop.R
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.noop.analytics.DaytimeStress
import com.noop.data.DailyMetric
import com.noop.widget.StressPoint
import com.noop.widget.StressTrace
import kotlin.math.exp
import kotlin.math.roundToInt
import kotlin.math.sqrt

// MARK: - Stress model (what the Stress screen left behind)
//
// The Stress screen folded into the Stress metric page (Denis 309e5a6c; ui/metric/MetricStressDay.kt).
// What stays here is what the legacy Today still reads: the daily stress model (a stored "stress" value,
// else the z-score proxy against a personal 30-day baseline) and the hosted stress-curve card. The
// Summary rebuild retires both.
//
//   zRHR = (todayRHR − meanRHR) / sdRHR        // positive when RHR is UP
//   zHRV = (meanHRV − todayHRV) / sdHRV        // positive when HRV is DOWN
//   raw  = zRHR + zHRV                          // combined autonomic load
//   stress = 3 / (1 + e^(−raw))                // 0 calm · 1.5 baseline · 3 high

/**
 * The stress curve as a card for the Today screen, mirroring the home-screen widget.
 *
 * READ-ONLY on purpose. The Stress tab's own timeline is the interactive one, with scrubbing, a
 * crosshair and per-hour tooltips; hosting that here would put two live charts on two screens fighting
 * over the same gestures. This is the same rule the Sleep tab's hosted "Stages" card follows, where the
 * Today host mirrors only the display.
 *
 * Geometry comes from [StressTrace], the same pure helper the widget draws through, so the card and the
 * widget cannot disagree about where an hour sits, where the line breaks or which hours are high. Only
 * the drawing differs, because Glance has to render to a Bitmap and Compose does not.
 */
@Composable
internal fun StressTodayCard(points: List<StressPoint>, modifier: Modifier = Modifier) {
    val stats = remember(points) { StressTrace.stats(points) }
    val ticks = remember(points) { StressTrace.timeTicks(points) }
    val textTertiary = Palette.textTertiary
    // #2106: the movement marks read as data, not chrome, so they take the same tone the WIDGET
    // already uses for them rather than the tertiary one the axis labels use.
    val markTone = Palette.textSecondary
    val calm = StressRamp.CALM
    val steady = StressRamp.STEADY
    val tense = StressRamp.TENSE

    NoopCard(tint = Palette.stressColor, modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                // The SAME title the Customise list offers, so what you added and what appears are
                // recognisably one thing. "Stress" alone collided with the pinned Your Cards tile,
                // which shows a number rather than this curve.
                Overline(uiString(R.string.hosted_card_stress_title), modifier = Modifier.weight(1f))
                if (stats != null) {
                    Text(
                        uiString(R.string.trends_peak) +
                            " ${StressTrace.formatLevel(stats.peak.level ?: 0.0)} · " +
                            pointTimeLabel(stats.peak.ts),
                        style = NoopType.footnote,
                        color = Palette.textSecondary,
                    )
                }
            }

            if (stats == null) {
                // Two states, two answers, which is the distinction the WIDGET already draws and this card
                // did not. Outside the 06:00-22:00 scored window nothing is coming until morning, and at
                // 1am the local day has just rolled over with no waking hour in it at all: saying
                // "Calibrating" there claims the app is working on something it will not touch for hours.
                // Inside the window it is the honest word, the day simply not having produced a scorable
                // hour yet. Both strings already exist and are translated, so this borrows rather than
                // adds. Honest blank either way, never a flat line at zero.
                val outsideScoredWindow =
                    !DaytimeStress.isWakingHourOfDay(java.time.LocalTime.now().hour)
                Text(
                    uiString(
                        if (outsideScoredWindow) {
                            R.string.l10n_stress_glance_widget_resumes_in_the_morning_a640b49f
                        } else {
                            R.string.l10n_today_screen_calibrating_37c2c9bd
                        }
                    ),
                    style = NoopType.footnote,
                    color = textTertiary,
                )
            } else {
                Row(modifier = Modifier.fillMaxWidth()) {
                    // The FIXED 0-3 scale down the left, as the screen and the widget both draw it. An
                    // axis that moved with the day would make two days impossible to compare.
                    Column(
                        // Marked decorative: read aloud, "3 2 1 0" is four bare numbers with nothing to
                        // say what they measure. The peak and average beside the chart carry the reading,
                        // and the axis is only meaningful to someone who can see what it annotates.
                        // Glance could not do this for the widget; Compose can.
                        modifier = Modifier
                            .height(Metrics.chartHeight)
                            .clearAndSetSemantics { },
                        horizontalAlignment = Alignment.End,
                        verticalArrangement = Arrangement.SpaceBetween,
                    ) {
                        StressTrace.levelTicks().forEach {
                            Text(it.toString(), style = NoopType.footnote, color = textTertiary)
                        }
                    }
                    Spacer(Modifier.width(6.dp))
                    // The chart and its hour labels share ONE column, so the labels line up with the
                    // ink they name. As siblings of the whole row they started at the card's edge
                    // instead, shifted left of the chart by the width of the level scale (#2106).
                    // The 10.dp is the gap the labels had as a direct child of the card's column,
                    // carried over so moving them only changes WHERE they start, not how they sit.
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Canvas(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(Metrics.chartHeight),
                        ) {
                            val w = size.width
                            val h = size.height
                            if (w <= 0f || h <= 0f) return@Canvas
                            val strokeW = 2.dp.toPx()
                            // Reserve the bottom strip for the movement marks, and build the geometry AT the
                            // reduced height rather than scaling it afterwards. A calm hour sits at the very
                            // bottom of a fixed domain, so without the strip its line and the marks share a
                            // row and read as one thing. (The widget carves the same band out of its bitmap;
                            // computing against `chartH` here is the same idea without the second mapping
                            // that had to be got right there.)
                            val hasMarks = points.any { it.moving }
                            val markBand = if (hasMarks) (strokeW * 2.5f).coerceAtMost(h / 6f) else 0f
                            val chartH = (h - markBand).coerceAtLeast(1f)
                            // Amber at the top through green to blue at the bottom: because the domain is
                            // fixed, vertical position IS the level, so one shader colours every run by the
                            // score it actually carries.
                            val gradient = Brush.verticalGradient(listOf(tense, steady, calm),
                                                                  startY = 0f, endY = chartH)

                            StressTrace.segments(points, w, chartH).forEach { run ->
                                if (run.isEmpty()) return@forEach
                                if (run.size == 1) {
                                    // Brushed, not a flat colour: the dot has to carry the level the same way
                                    // the line does, or a lone HIGH hour would draw the calm-day green.
                                    drawCircle(brush = gradient, radius = strokeW,
                                               center = Offset(run[0].x.coerceAtLeast(strokeW), run[0].y))
                                    return@forEach
                                }
                                val line = Path().apply {
                                    moveTo(run[0].x, run[0].y)
                                    run.drop(1).forEach { lineTo(it.x, it.y) }
                                }
                                // Closed PER RUN, so the fill cannot spread under an hour that was never
                                // scored and undo the gap the broken line exists to draw.
                                val fill = Path().apply {
                                    addPath(line)
                                    lineTo(run.last().x, chartH)
                                    lineTo(run[0].x, chartH)
                                    close()
                                }
                                drawPath(fill, brush = gradient, alpha = StrandAlpha.chartFillSoft)
                                drawPath(line, brush = gradient,
                                         style = Stroke(width = strokeW, cap = StrokeCap.Round,
                                                        join = StrokeJoin.Round))
                            }
                            // Hours in the HIGH band, dotted above the line exactly as the screen marks them.
                            StressTrace.highPoints(points, w, chartH).forEach {
                                drawCircle(color = tense, radius = strokeW,
                                           center = Offset(it.x, (it.y - strokeW * 2f).coerceAtLeast(strokeW)))
                            }
                            // The stretches the motion gate masked: exertion raises heart rate on its own, so
                            // the hour is marked rather than scored.
                            // #2106: one bar per CONTIGUOUS masked stretch, not a dot per hour, and in a
                            // colour that is not the one the axis labels use. Reported as "many gaps" by a
                            // wearer who read the old evenly spaced tertiary dots as tick marks and asked
                            // whether he needed to enable continuous HRV to fill them. A scale does not
                            // start and stop with the data, so a bar sitting under the stretch it explains
                            // cannot be read as one. The span already covers the masked hours edge to edge,
                            // so the floor below is only for a degenerate series with no width to spread
                            // across, not the ordinary lone-hour case. It is the WIDGET's floor, and wider
                            // than the dot this replaced, so even that case is no less visible than before.
                            val markY = h - markBand / 2f
                            val markH = (markBand * 0.5f).coerceAtLeast(1f)
                            val minMarkW = strokeW * 3f
                            StressTrace.movingSpans(points, w).forEach { span ->
                                val x1 = maxOf(span.endInclusive, minOf(span.start + minMarkW, w))
                                val x0 = minOf(span.start, maxOf(x1 - minMarkW, 0f))
                                drawRoundRect(
                                    color = markTone,
                                    topLeft = Offset(x0, markY - markH / 2f),
                                    size = Size(x1 - x0, markH),
                                    cornerRadius = CornerRadius(markH / 2f, markH / 2f),
                                )
                            }
                        }
                        // Evenly spread, which is only honest because the ticks now span the same series
                        // the chart does. While they named the last SCORED hour, the right-hand label sat
                        // at the right-hand edge and claimed the day ended there (#2106).
                        if (ticks.size >= 2) {
                            Row(modifier = Modifier.fillMaxWidth()) {
                                ticks.forEachIndexed { i, ts ->
                                    Text(pointTimeLabel(ts), style = NoopType.footnote, color = textTertiary)
                                    if (i < ticks.size - 1) Spacer(Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }

                Text(
                    uiString(R.string.l10n_stress_screen_avg_a178769d) +
                        " ${StressTrace.formatLevel(stats.mean)}",
                    style = NoopType.footnote,
                    color = textTertiary,
                )
            }
        }
    }
}

/**
 * A point's clock time, in the device's own short format.
 *
 * NOT [hourLabel]: that renders an hour-of-day and nothing finer, which was correct while every point
 * sat on the hour. The timeline now reads its window every half hour, so a peak at 09:30 would have
 * been labelled "9 am" and an axis tick at 06:30 "6 am" — wrong by up to half an hour, and silently,
 * since the number beside it would still be the right one. The widget formats the timestamp for the
 * same reason.
 */
private fun pointTimeLabel(ts: Long): String =
    java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT)
        .format(java.util.Date(ts * 1_000L))

// MARK: - Daytime autonomic-load line (gradient, same scale as the gauge)
//
// Interactive Canvas line over the scored waking hours. Tap or drag to scrub across hours
// and see the stress level at a specific time in a tooltip pill. The Y-axis shows the 0–3
// scale with hairline grid lines. Unscored hours break the line (honest gap, no interpolation).

/** "6 am" / "2 pm" style hour-of-day label. */
private fun hourLabel(hour: Int): String {
    val h = ((hour % 24) + 24) % 24
    val ampm = if (h < 12) "am" else "pm"
    val h12 = if (h % 12 == 0) 12 else h % 12
    return "$h12 $ampm"
}

// MARK: - 2 · Today's tiles (uniform grid)

internal enum class StressBand(val title: String, val tone: StrandTone) {
    Low("LOW", StrandTone.Positive),
    Medium("MEDIUM", StrandTone.Warning),
    High("HIGH", StrandTone.Critical);

    companion object {
        fun forScore(score: Double): StressBand = when {
            score < 1.0 -> Low
            score < 2.0 -> Medium
            else -> High
        }
    }
}

// MARK: - Stress ramp (the WHOOP Stress sweep: blue → green → amber)
//
// The Stress screen's one ramp, matching the iOS StressRamp exactly. WHOOP has NO gold:
// calm reads as the link blue, a balanced day as positive green, and a high-stress day as
// warning amber. The PipBar tint, the day autonomic-load line, the Calm/Moderate/High totals
// bar and the trend all sample this SAME ramp, so the colour language is identical across the
// screen. Never the gold or red→green recovery ramp.

private object StressRamp {
    val CALM = Palette.accent           // calm WHOOP blue — low
    val STEADY = Palette.statusPositive // balanced WHOOP green — baseline
    val TENSE = Palette.statusWarning   // high WHOOP amber — high

    /** The 3-stop ramp, evenly spaced (blue → green → amber). */
    val stops: List<Pair<Float, Color>> = listOf(
        0.00f to CALM,
        0.50f to STEADY,
        1.00f to TENSE,
    )

    /** Sample the ramp at a 0–3 stress score. */
    fun color(score: Double): Color = Palette.sample(stops, (score / 3.0).toFloat())
}

// MARK: - Trend range (the W/M/3M/6M/1Y/ALL window, mirroring ExploreRange)

internal enum class StressRange(val label: String, val days: Int?) {
    Week("W", 7),
    Month("M", 30),
    Quarter("3M", 90),
    Half("6M", 180),
    Year("1Y", 365),
    All("ALL", null),
}

// MARK: - Stress model (transparent: stored value OR z-score derivation)

// #753: `internal` (was file-private) so Today's pinned Stress card can build the SAME model the detail
// screen shows and read `model.score`, instead of taking the stress series' last banked row. The pinned card
// and the detail page then derive today's score identically (stored row preferred, else live RHR/HRV
// baseline) and refresh on the same data, so the pinned card never lags the detail page (e.g. a stale "2").
// The constructor stays private; only the companion `build` factory is exposed.
internal class StressModel private constructor(
    val score: Double,            // 0–3 (today)
    val band: StressBand,
    val explanation: String,
    val rhrToday: Int?,
    val hrvToday: Double?,
    val rhrDelta: Double?,        // today − baseline mean (bpm)
    val hrvDelta: Double?,        // today − baseline mean (ms)
    val fullTrend: List<TrendPoint>, // entire daily proxy history, oldest → newest
    val calmTimeValue: String,
    val calmTimeCaption: String,
    val usingStored: Boolean,     // true when today's value came from the stored series
) {
    data class TrendPoint(val day: String, val value: Double)

    /** The full daily proxy trend, sliced to the selected trailing window (count-based,
     *  matching the day budget). Falls back to ALL when the trailing slice has < 2 points.
     *
     *  #1600: returns the POINTS, not bare values. The chart needs the day beside each value to name
     *  it on the scrub read-out, and deriving the labels from a second call that re-applied this
     *  windowing — including the `size >= 2` fallback — would risk the two lists disagreeing. Charts
     *  drop mismatched selection labels SILENTLY, so that divergence would present as the read-out
     *  simply not working. One list, mapped twice at the call site, cannot desynchronise. */
    fun windowedTrend(range: StressRange): List<TrendPoint> {
        val days = range.days ?: return fullTrend
        val slice = fullTrend.takeLast(days)
        return if (slice.size >= 2) slice else fullTrend
    }

    companion object {
        /** Build from oldest→newest daily metrics plus any stored "stress" series.
         *  Returns null only when there is no usable signal at all. */
        fun build(days: List<DailyMetric>, stored: Map<String, Double>): StressModel? {
            // Carry (#543): today's own row is often vitals-less until the overnight is analyzed —
            // especially right after an app update relaunches and re-runs the pass — so score the NEWEST
            // day that actually carries usable signal (RHR/HRV, or a stored/imported stress value) instead
            // of calibrating, the same last-night carry every other Today vital uses. The predicate mirrors
            // the storedToday||derived gate below, so an imported stress-only latest day is still honored
            // (not skipped). Falls back to the last row when no day has any signal (cold start).
            val idx = days.indexOfLast {
                it.restingHr != null || it.avgHrv != null || stored.containsKey(it.day)
            }.let { if (it >= 0) it else days.size - 1 }
            if (idx < 0) return null   // no days at all
            val today = days[idx]

            // Baseline window: up to 30 days ending the day BEFORE the scored day, so it's measured
            // against its own recent past rather than itself.
            val baseline = if (idx > 0) days.subList(0, idx).takeLast(30) else emptyList()

            val rhrBase = baseline.mapNotNull { it.restingHr?.toDouble() }
            val hrvBase = baseline.mapNotNull { it.avgHrv }

            val meanRHR = mean(rhrBase)
            val sdRHR = std(rhrBase, meanRHR)
            val meanHRV = mean(hrvBase)
            val sdHRV = std(hrvBase, meanHRV)

            val rhrT = today.restingHr?.toDouble()
            val hrvT = today.avgHrv

            val derivedAvailable = (rhrT != null && meanRHR != null) || (hrvT != null && meanHRV != null)
            val storedToday = stored[today.day]
            if (storedToday == null && !derivedAvailable) return null

            val derivedToday: Double? = if (derivedAvailable) {
                squash(rawScore(rhrT, meanRHR, sdRHR, hrvT, meanHRV, sdHRV))
            } else {
                null
            }

            val s = storedToday ?: derivedToday ?: 1.5
            val usingStored = storedToday != null
            val band = StressBand.forScore(s)
            val rhrDelta = if (rhrT != null && meanRHR != null) rhrT - meanRHR else null
            val hrvDelta = if (hrvT != null && meanHRV != null) hrvT - meanHRV else null
            val explanation = explanation(band, rhrDelta, hrvDelta)

            // Full daily proxy history: stored value if present for the day, else the
            // z-score derivation against the SAME baseline so the line is comparable.
            val pts = ArrayList<TrendPoint>()
            for (d in days) {
                val v = stored[d.day]
                if (v != null) {
                    pts.add(TrendPoint(d.day, v.coerceIn(0.0, 3.0)))
                    continue
                }
                val dRHR = d.restingHr?.toDouble()
                val dHRV = d.avgHrv
                if ((dRHR == null || meanRHR == null) && (dHRV == null || meanHRV == null)) continue
                pts.add(TrendPoint(d.day, squash(rawScore(dRHR, meanRHR, sdRHR, dHRV, meanHRV, sdHRV))))
            }

            // "Calm time": share of the last 30 charted days that sat in the LOW band.
            val recent = pts.takeLast(30)
            val calmValue: String
            val calmCaption: String
            if (recent.isEmpty()) {
                calmValue = "—"
                calmCaption = "needs history"
            } else {
                val calm = recent.count { it.value < 1.0 }
                val pct = (calm.toDouble() / recent.size * 100).roundToInt()
                calmValue = "$pct%"
                calmCaption = "low-stress days · ${recent.size}d"
            }

            return StressModel(
                score = s,
                band = band,
                explanation = explanation,
                rhrToday = today.restingHr,
                hrvToday = hrvT,
                rhrDelta = rhrDelta,
                hrvDelta = hrvDelta,
                fullTrend = pts,
                calmTimeValue = calmValue,
                calmTimeCaption = calmCaption,
                usingStored = usingStored,
            )
        }

        // MARK: Stress math (pure helpers, ported from StressMath)

        private fun mean(xs: List<Double>): Double? =
            if (xs.isEmpty()) null else xs.sum() / xs.size

        /** Population standard deviation; 0 when there's no spread. */
        private fun std(xs: List<Double>, m: Double?): Double {
            if (m == null || xs.size <= 1) return 0.0
            val v = xs.sumOf { (it - m) * (it - m) } / xs.size
            return sqrt(v)
        }

        /** Combined autonomic z-score. RHR-up and HRV-down both push it positive. */
        private fun rawScore(
            rhrToday: Double?, meanRHR: Double?, sdRHR: Double,
            hrvToday: Double?, meanHRV: Double?, sdHRV: Double,
        ): Double {
            var sum = 0.0
            if (rhrToday != null && meanRHR != null && sdRHR > 0.0001) {
                sum += (rhrToday - meanRHR) / sdRHR        // up = stress
            }
            if (hrvToday != null && meanHRV != null && sdHRV > 0.0001) {
                sum += (meanHRV - hrvToday) / sdHRV        // down = stress
            }
            return sum
        }

        /** Logistic squash of the raw z-sum onto 0–3 (baseline 0 → 1.5). */
        private fun squash(raw: Double): Double =
            (3.0 / (1.0 + exp(-raw))).coerceIn(0.0, 3.0)

        private fun explanation(band: StressBand, rhrDelta: Double?, hrvDelta: Double?): String {
            val rhrUp = (rhrDelta ?: 0.0) > 1.0
            val hrvDn = (hrvDelta ?: 0.0) < -1.0
            val hrvUp = (hrvDelta ?: 0.0) > 1.0
            val rhrDn = (rhrDelta ?: 0.0) < -1.0
            return when (band) {
                StressBand.High -> when {
                    rhrUp && hrvDn -> "Resting HR is elevated and HRV is below your baseline, both classic signs of high activation. Prioritise rest, hydration and an easy day."
                    hrvDn -> "HRV has dropped well below your baseline, pointing to elevated stress or fatigue. Ease off and give your body time to recover."
                    rhrUp -> "Resting heart rate is running high versus your norm. Your body is under load today. Keep effort light."
                    else -> "Your autonomic markers are skewed toward stress today. Treat it as a recovery-focused day."
                }
                StressBand.Medium -> when {
                    rhrUp || hrvDn -> "Slightly off baseline (${if (rhrUp) "resting HR is a touch high" else "HRV is a little low"}), so you're moderately activated. Nothing alarming; just don't overreach."
                    else -> "You're sitting around your typical autonomic baseline: moderate stress, a normal, balanced day."
                }
                StressBand.Low -> when {
                    rhrDn && hrvUp -> "Resting heart rate is low and HRV is up. Your nervous system looks well-recovered and calm. A great day to push if you want to."
                    hrvUp -> "HRV is above baseline, a sign of a relaxed, well-recovered nervous system. Stress is low."
                    else -> "Resting heart rate and HRV are sitting at or below baseline: low physiological stress. You're in a calm, recovered state."
                }
            }
        }
    }
}
