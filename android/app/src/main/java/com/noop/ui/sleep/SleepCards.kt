package com.noop.ui.sleep

import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bed
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.noop.R
import com.noop.ui.m3.CardTitleRow
import com.noop.ui.m3.HealthCard
import com.noop.ui.m3.Health
import java.util.Locale
import kotlin.math.max

// MARK: - The cards of the Sleep tab (twin of iOS SleepScoreCards / SleepPageCards)

@Composable
internal fun scorePartColor(part: SleepScorePart): Color = when (part) {
    SleepScorePart.DURATION -> Health.colors.scoreDuration
    SleepScorePart.INTERRUPTIONS -> Health.colors.scoreInterruptions
    SleepScorePart.RESTORATIVE -> Health.colors.scoreDeepRem
    SleepScorePart.REGULARITY -> Health.colors.scoreRegularity
}

@Composable
internal fun scorePartName(part: SleepScorePart): String = stringResource(
    when (part) {
        SleepScorePart.DURATION -> R.string.sleep_score_duration
        SleepScorePart.INTERRUPTIONS -> R.string.sleep_score_interruptions
        SleepScorePart.RESTORATIVE -> R.string.sleep_score_deep_rem
        SleepScorePart.REGULARITY -> R.string.sleep_score_regularity
    },
)

@Composable
internal fun scoreWord(word: SleepScoreWord): String = stringResource(
    when (word) {
        SleepScoreWord.POOR -> R.string.sleep_score_poor
        SleepScoreWord.FAIR -> R.string.sleep_score_fair
        SleepScoreWord.GOOD -> R.string.sleep_score_good
        SleepScoreWord.OPTIMAL -> R.string.sleep_score_optimal
    },
)

@Composable
internal fun scoreSentence(score: SleepScore): String = when (score.sentence) {
    SleepScoreSentence.IMPORTED -> stringResource(R.string.sleep_score_sentence_imported, score.value)
    SleepScoreSentence.SOUND -> stringResource(R.string.sleep_score_sentence_sound, score.value)
    SleepScoreSentence.DURATION -> stringResource(R.string.sleep_score_sentence_duration, score.value)
    SleepScoreSentence.INTERRUPTIONS -> stringResource(R.string.sleep_score_sentence_interruptions, score.value)
    SleepScoreSentence.RESTORATIVE -> stringResource(R.string.sleep_score_sentence_restorative, score.value)
    SleepScoreSentence.REGULARITY -> stringResource(R.string.sleep_score_sentence_regularity, score.value)
}

// MARK: Score card

/** Health's Sleep Score card: the ring and its word, each part's points, then one sentence. */
@Composable
internal fun SleepScoreCard(score: SleepScore, onClick: () -> Unit) {
    HealthCard(onClick = onClick, verticalSpacing = 12.dp) {
        CardTitleRow(icon = null, title = stringResource(R.string.sleep_score_title), tint = Health.colors.sleep)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            SleepScoreRing(score, Modifier.size(112.dp))
            Text(
                scoreWord(score.word),
                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            SleepScorePart.legendOrder.forEach { part ->
                val earned = score.parts.firstOrNull { it.part == part } ?: return@forEach
                LegendRow(earned)
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        Text(scoreSentence(score), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface)
    }
}

/** "● Duration: 42 of 50": the name semibold, the points plain. An imported score's parts carry no points. */
@Composable
private fun LegendRow(part: SleepScorePartScore) {
    val name = scorePartName(part.part)
    val points = part.points?.let { stringResource(R.string.sleep_score_points, it, part.part.maxPoints) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(12.dp).clip(CircleShape).background(scorePartColor(part.part)))
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(if (points != null) "$name:" else name) }
                if (points != null) append(" $points")
            },
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

/**
 * The score ring: one arc per part, clockwise from 12 o'clock (Interruptions, Duration, Deep & REM,
 * Regularity), each as long as the points it is worth, with small gaps; a pale track of the part's hue,
 * the earned share filled. The number sits in the middle.
 */
@Composable
internal fun SleepScoreRing(score: SleepScore, modifier: Modifier = Modifier) {
    val parts = SleepScorePart.ringOrder.mapNotNull { p -> score.parts.firstOrNull { it.part == p } }
    val colors = parts.associate { it.part to scorePartColor(it.part) }
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.matchParentSize()) {
            val stroke = 11.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(size.width - stroke, size.height - stroke)
            val radius = arcSize.width / 2
            val total = parts.sumOf { it.part.maxPoints }.coerceAtLeast(1)
            // Gap of 3 dp between arcs plus the round caps' overhang at both ends.
            val gapDeg = Math.toDegrees(((3.dp.toPx() + stroke) / radius).toDouble()).toFloat()
            var angle = -90f
            for (p in parts) {
                val sweep = 360f * p.part.maxPoints / total
                val usable = max(0.5f, sweep - gapDeg)
                val start = angle + gapDeg / 2
                val color = colors.getValue(p.part)
                drawArc(color.copy(alpha = 0.25f), start, usable, false, Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
                val earned = (usable * p.fraction.toFloat()).coerceIn(0f, usable)
                if (earned > 0.1f) {
                    drawArc(color, start, earned, false, Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
                }
                angle += sweep
            }
        }
        Text(
            "${score.value}",
            style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"),
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

// MARK: Tiles

/** One of the two tiles under the score card: a title with its chevron, then the tile's picture. */
@Composable
private fun SleepPageTile(
    title: String,
    tint: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    HealthCard(modifier = modifier.fillMaxHeight(), onClick = onClick, verticalSpacing = 10.dp) {
        CardTitleRow(icon = null, title = title, tint = tint)
        Spacer(Modifier.weight(1f, fill = false))
        content()
    }
}

/** Health's Sleep tile: the night's stages across the tile and the time asleep under them in the Sleep hue. */
@Composable
internal fun SleepDurationTile(night: SleepNightDetail, onClick: () -> Unit, modifier: Modifier = Modifier) {
    SleepPageTile(stringResource(R.string.nav_sleep), Health.colors.sleep, onClick, modifier) {
        SleepStagesChart(
            spans = night.spans, onsetTs = night.onsetTs, stages = night.stages, compact = true,
            modifier = Modifier.fillMaxWidth().height(92.dp),
        )
        TileDuration(night.asleepMin)
    }
}

/** "7 hr 42 min" in the Sleep hue, the figures bold and the units a size down. */
@Composable
internal fun TileDuration(minutes: Double, color: Color = Health.colors.sleep) {
    val (h, m) = durationParts(minutes)
    val big = SpanStyle(fontWeight = FontWeight.Bold, fontSize = MaterialTheme.typography.titleLarge.fontSize)
    val small = SpanStyle(fontWeight = FontWeight.SemiBold, fontSize = MaterialTheme.typography.titleSmall.fontSize)
    val hr = stringResource(R.string.metric_unit_hr)
    val min = stringResource(R.string.metric_unit_min)
    Text(
        buildAnnotatedString {
            if (h > 0) {
                withStyle(big) { append("$h") }
                withStyle(small) { append(" $hr ") }
            }
            if (m > 0 || h == 0) {
                withStyle(big) { append("$m") }
                withStyle(small) { append(" $min") }
            }
        },
        color = color,
        maxLines = 1,
    )
}

/**
 * Health's Vitals tile. While the ranges are being learned: a capsule per night still needed (the nights on
 * record filled) and how many are left. Once they exist: the typical band between grey high and low zones,
 * a ring per vital where the night fell, and "Typical" or the count of outliers.
 */
@Composable
internal fun SleepVitalsTile(vitals: SleepVitals, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val tint = Health.colors.vitalsTypical
    SleepPageTile(stringResource(R.string.sleep_vitals_title), tint, onClick, modifier) {
        if (vitals.nightsRemaining > 0) {
            Row(
                Modifier.fillMaxWidth().height(64.dp).clearAndSetSemantics {},
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                repeat(SleepVitals.NIGHTS_NEEDED) { i ->
                    val shape = RoundedCornerShape(50)
                    Box(
                        Modifier.width(13.dp).fillMaxHeight().clip(shape)
                            .background(if (i < vitals.nightsRecorded) tint.copy(alpha = 0.45f) else Color.Transparent)
                            .border(2.dp, MaterialTheme.colorScheme.outlineVariant, shape),
                    )
                }
            }
            val n = vitals.nightsRemaining
            val words = pluralStringResource(R.plurals.sleep_sessions_until_results, n, n).replace("$n", "").trim()
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("$n", style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Light))
                Text(words, style = MaterialTheme.typography.labelLarge, maxLines = 3)
            }
        } else {
            SleepVitalsBand(vitals.readings, Modifier.fillMaxWidth().height(88.dp))
            VitalsVerdict(vitals.outliers, MaterialTheme.typography.titleLarge)
        }
    }
}

/** "Typical" in the Vitals hue, or "2 outliers" in the outlier hue. */
@Composable
internal fun VitalsVerdict(outliers: Int, style: androidx.compose.ui.text.TextStyle) {
    if (outliers == 0) {
        Text(stringResource(R.string.sleep_vitals_typical), style = style.copy(fontWeight = FontWeight.SemiBold), color = Health.colors.vitalsTypical)
    } else {
        Text(
            pluralStringResource(R.plurals.sleep_vitals_outliers, outliers, outliers),
            style = style.copy(fontWeight = FontWeight.SemiBold),
            color = Health.colors.vitalsOutlier,
        )
    }
}

/** The tile's picture: grey high zone, the typical band, grey low zone, and a ring per vital in its slot. */
@Composable
internal fun SleepVitalsBand(readings: List<SleepVitals.Reading>, modifier: Modifier = Modifier) {
    val zoneColor = MaterialTheme.colorScheme.surfaceContainerHighest
    val band = Health.colors.vitalsTypical.copy(alpha = 0.3f)
    val typical = Health.colors.vitalsTypical
    val outlier = Health.colors.vitalsOutlier
    val fill = MaterialTheme.colorScheme.surfaceContainerLow
    Canvas(modifier.clearAndSetSemantics {}) {
        val zone = 6.dp.toPx()
        val gap = 6.dp.toPx()
        val ring = 11.dp.toPx()
        val top = ring / 2
        val bottom = size.height - ring / 2
        val bandTop = top + zone / 2 + gap
        val bandH = bottom - top - zone - 2 * gap
        for (y in listOf(top, bottom)) {
            drawRoundRect(zoneColor, Offset(0f, y - zone / 2), Size(size.width, zone), CornerRadius(zone / 2, zone / 2))
        }
        drawRoundRect(band, Offset(0f, bandTop), Size(size.width, bandH), CornerRadius(6.dp.toPx(), 6.dp.toPx()))
        val slots = SleepVitals.Metric.entries.size
        for (r in readings) {
            val x = size.width * (r.metric.ordinal + 0.5f) / slots
            val p = r.position
            val y = when {
                p > 1 -> top
                p < 0 -> bottom
                else -> (bandTop + bandH - ring / 2 - 2f - p.toFloat() * (bandH - ring - 4f))
            }
            drawCircle(fill, ring / 2, Offset(x, y))
            drawCircle(if (r.isOutlier) outlier else typical, ring / 2 - 1.25.dp.toPx(), Offset(x, y), style = Stroke(2.5.dp.toPx()))
        }
    }
}

// MARK: Highlights

/** A Sleep highlight: the category, the sentence, two figures side by side, the nights behind them. */
@Composable
internal fun SleepHighlightCard(h: SleepHighlight, locale: Locale, is24h: Boolean) {
    val sentence = when (h) {
        is SleepHighlight.Bedtime -> when {
            kotlin.math.abs(h.diffMin) < 15 -> stringResource(R.string.sleep_hl_bedtime_usual)
            h.diffMin > 0 -> stringResource(R.string.sleep_hl_bedtime_later, h.diffMin)
            else -> stringResource(R.string.sleep_hl_bedtime_earlier, -h.diffMin)
        }
        is SleepHighlight.Duration -> {
            val avg = sleepDuration(h.averageMin)
            when {
                kotlin.math.abs(h.diffMin) < 10 -> stringResource(R.string.sleep_hl_duration_same, avg)
                h.diffMin > 0 -> stringResource(R.string.sleep_hl_duration_more, avg, sleepDuration(h.diffMin.toDouble()))
                else -> stringResource(R.string.sleep_hl_duration_less, avg, sleepDuration(-h.diffMin.toDouble()))
            }
        }
    }
    val sleepHue = Health.colors.sleep
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    HealthCard(verticalSpacing = 10.dp) {
        CardTitleRow(icon = Icons.Filled.Bed, title = stringResource(R.string.nav_sleep), tint = sleepHue, chevron = false)
        Text(sentence, style = MaterialTheme.typography.bodyLarge)
        Row(Modifier.fillMaxWidth()) {
            when (h) {
                is SleepHighlight.Bedtime -> {
                    Figure(stringResource(R.string.sleep_hl_avg_bedtime), nightClock(h.usualMin, is24h, locale), muted, Modifier.weight(1f))
                    Figure(stringResource(R.string.sleep_hl_last_bedtime), nightClock(h.lastMin, is24h, locale), sleepHue, Modifier.weight(1f), end = true)
                }
                is SleepHighlight.Duration -> {
                    Figure(stringResource(R.string.sleep_hl_avg_asleep), sleepDuration(h.averageMin), sleepHue, Modifier.weight(1f))
                    Figure(stringResource(R.string.sleep_hl_week_before), sleepDuration(h.priorAverageMin), muted, Modifier.weight(1f), end = true)
                }
            }
        }
        val (values, average) = when (h) {
            is SleepHighlight.Bedtime -> h.nights to h.usualMin
            is SleepHighlight.Duration -> h.nights to h.averageMin
        }
        HighlightBars(values, average, sleepHue, Modifier.fillMaxWidth().height(44.dp))
    }
}

@Composable
private fun Figure(title: String, value: String, tint: Color, modifier: Modifier, end: Boolean = false) {
    Column(modifier, horizontalAlignment = if (end) Alignment.End else Alignment.Start) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
        Text(value, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), color = tint)
    }
}

/** The nights as bars on their own scale, the newest in the Sleep hue, the average as a line across. */
@Composable
private fun HighlightBars(values: List<Double>, average: Double, latest: Color, modifier: Modifier) {
    val grey = MaterialTheme.colorScheme.outlineVariant
    val line = MaterialTheme.colorScheme.onSurfaceVariant
    Canvas(modifier.clearAndSetSemantics {}) {
        if (values.isEmpty()) return@Canvas
        val lo = minOf(values.min(), average)
        val hi = maxOf(values.max(), average)
        val floor = lo - max(30.0, (hi - lo) * 0.6)
        fun frac(v: Double) = ((v - floor) / max(1.0, hi - floor)).toFloat()
        val gap = 6.dp.toPx()
        val w = (size.width - gap * (values.size - 1)) / values.size
        values.forEachIndexed { i, v ->
            val h = max(3.dp.toPx(), size.height * frac(v))
            drawRoundRect(
                if (i == values.lastIndex) latest else grey,
                Offset(i * (w + gap), size.height - h), Size(w, h), CornerRadius(3.dp.toPx(), 3.dp.toPx()),
            )
        }
        val y = size.height - size.height * frac(average)
        drawLine(line, Offset(0f, y), Offset(size.width, y), 3.dp.toPx(), cap = StrokeCap.Round)
    }
}

/** Health's "Sleep: Stages" highlight: the night's length in a sentence, then each stage beside its row. */
@Composable
internal fun SleepStagesHighlightCard(night: SleepNightDetail, locale: Locale, is24h: Boolean) {
    HealthCard(verticalSpacing = 10.dp) {
        CardTitleRow(icon = Icons.Filled.Bed, title = stringResource(R.string.sleep_hl_stages), tint = Health.colors.sleep, chevron = false)
        Text(stringResource(R.string.sleep_hl_stages_sentence, sleepDuration(night.asleepMin)), style = MaterialTheme.typography.bodyLarge)
        if (night.spans.isEmpty()) {
            // At least 160 dp, and as tall as its four labelled bars need at the reader's font size.
            SleepStagesChart(night.spans, night.onsetTs, night.stages, Modifier.fillMaxWidth().heightIn(min = 160.dp))
        } else {
            val summary = stagesSummary(night.stages)
            // A row is as tall as its two lines of text at the reader's font size, never under 52 dp; the
            // chart beside it is four of them.
            val rowHeight = with(LocalDensity.current) {
                val text = MaterialTheme.typography.labelLarge.lineHeight.toDp() + MaterialTheme.typography.labelMedium.lineHeight.toDp()
                maxOf(52.dp, text + 8.dp)
            }
            Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = summary }, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.height(rowHeight * 4)) {
                    SleepStageRow.entries.forEach { row ->
                        Column(Modifier.height(rowHeight), verticalArrangement = Arrangement.Center) {
                            Text(stageName(row), style = MaterialTheme.typography.labelLarge)
                            Text(sleepDuration(night.stages.minutes(row)), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                Column(Modifier.weight(1f)) {
                    Box(Modifier.fillMaxWidth().height(rowHeight * 4)) {
                        RowRules(Modifier.matchParentSize())
                        SleepStagesChart(night.spans, night.onsetTs, night.stages, Modifier.matchParentSize(), compact = true)
                    }
                    Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
                        Text(clockLabel(night.onsetTs, is24h, locale), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.weight(1f))
                        Text(clockLabel(night.wakeTs, is24h, locale), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/** Dotted rules between the four rows. */
@Composable
private fun RowRules(modifier: Modifier) {
    val c = MaterialTheme.colorScheme.outlineVariant
    Canvas(modifier) {
        for (i in 1..3) {
            val y = size.height * i / 4
            drawLine(
                c, Offset(0f, y), Offset(size.width, y), 1.dp.toPx(),
                pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 3.dp.toPx())),
            )
        }
    }
}

/** A night-clock minute (minutes after 18:00 the evening before) as a clock time. */
internal fun nightClock(minutesOfNight: Double, is24h: Boolean, locale: Locale): String {
    val m = (((minutesOfNight.toInt() + 18 * 60) % (24 * 60)) + 24 * 60) % (24 * 60)
    val t = java.time.LocalTime.of(m / 60, m % 60)
    return java.time.format.DateTimeFormatter.ofPattern(if (is24h) "HH:mm" else "h:mm a", locale).format(t)
}

/** A stage-coloured dot for the lists. */
@Composable
internal fun Dot(color: Color, size: androidx.compose.ui.unit.Dp = 10.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(color))
}
