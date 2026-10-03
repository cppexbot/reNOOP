package com.noop.ui.sleep

import com.noop.ui.m3.labelStride
import com.noop.ui.metric.MetricDateLabels
import com.noop.ui.m3.labelBand
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.analytics.SkinTempDisplay
import com.noop.analytics.SleepDebtLedger
import com.noop.data.HrBucket
import com.noop.ui.AppViewModel
import com.noop.ui.ClockPrefs
import com.noop.ui.TemperatureUnit
import com.noop.ui.UnitFormatter
import com.noop.ui.UnitPrefs
import com.noop.ui.m3.Health
import com.noop.ui.m3.HealthCard
import com.noop.ui.m3.ListGroup
import com.noop.ui.m3.ListRow
import com.noop.ui.m3.M3Dimens
import com.noop.ui.m3.PeriodSegmented
import com.noop.ui.m3.PushedTopBar
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// MARK: - More Sleep Data (twin of iOS SleepMoreDataView)
//
// "D | W | M | 6M" over the time in bed and asleep, the chart (D: the night's stages, swipe for another
// night; W / M / 6M: each night's or week's bedtime→wake as a floating bar, time running down), then
// "Stages | Amounts | Comparisons": the stage minutes (tap one to pick it out on the chart), the amounts with
// the sleep-debt card, and the overnight vitals (tap one to draw it over the chart).

private enum class MoreTab { STAGES, AMOUNTS, COMPARISONS }

/** A vital compared against the night(s). */
private enum class Comparison { HEART_RATE, RESPIRATORY, HRV, OXYGEN, SKIN_TEMP }

private class ComparisonRow(val metric: Comparison, val value: String, val plottable: Boolean)

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun SleepMoreDataScreen(vm: AppViewModel, startOffset: Int, onBack: () -> Unit) {
    val context = LocalContext.current
    val locale = context.resources.configuration.locales[0]
    val is24h = remember { ClockPrefs.uses24Hour(context) }
    val tempUnit = remember { UnitPrefs.temperature(context) }
    val skinPrefer = remember { UnitPrefs.skinTempPreferred(context) }
    val days by vm.recentDays.collectAsStateWithLifecycle()
    var data by remember { mutableStateOf<SleepNights?>(null) }
    LaunchedEffect(days, SleepNightsLoader.revision) { data = SleepNightsLoader.load(vm, days) }
    val nights = data ?: SleepNights.EMPTY

    var range by rememberSaveable { mutableStateOf(SleepRange.DAY) }
    var tab by rememberSaveable { mutableStateOf(MoreTab.STAGES) }
    var offset by rememberSaveable { mutableStateOf(startOffset) }
    var selectedStage by remember { mutableStateOf<SleepStageRow?>(null) }
    var pickedComparison by remember { mutableStateOf<Comparison?>(null) }
    var comparisonPicked by remember { mutableStateOf(false) }
    LaunchedEffect(range) { selectedStage = null; comparisonPicked = false; pickedComparison = null }

    val today = LocalDate.now()
    val lastIndex = (nights.navDays.size - 1).coerceAtLeast(0)
    val dayNight = nights.details.getOrNull(offset)
    val rangeNights = remember(nights, range) { SleepHistory.nightsIn(range, nights.nights, today) }
    val shown = if (range == SleepRange.DAY) listOfNotNull(dayNight) else rangeNights
    val summary = remember(shown) { SleepPeriodSummary.of(shown) }
    val window = remember(nights, range) { SleepHistory.window(range, nights.entries, today) }

    // Heart rate inside the shown nights, in buckets sized to the view.
    var buckets by remember { mutableStateOf<List<HrBucket>>(emptyList()) }
    LaunchedEffect(range, offset, nights) {
        val first = shown.firstOrNull()
        val last = shown.lastOrNull()
        buckets = if (first == null || last == null) emptyList() else runCatching {
            val size = when (range) { SleepRange.DAY -> 180L; SleepRange.SIX_MONTHS -> 1200L; else -> 600L }
            vm.repo.hrBucketsUnion(vm.activeStrapId, first.onsetTs, last.wakeTs, size)
        }.getOrDefault(emptyList())
    }
    val rows = remember(nights.days) { nights.days.associateBy { it.day } }

    fun heartPoints(n: SleepNightDetail): List<Pair<Double, Double>> =
        buckets.filter { it.bucket in n.onsetTs..n.wakeTs && it.avgBpm > 0 }.map { (it.bucket - n.onsetTs).toDouble() to it.avgBpm }

    fun nightly(metric: Comparison, n: SleepNightDetail): Double? {
        val row = rows[n.dayKey] ?: return null
        return when (metric) {
            Comparison.HEART_RATE -> heartPoints(n).takeIf { it.isNotEmpty() }?.let { p -> p.sumOf { it.second } / p.size }
            Comparison.RESPIRATORY -> row.respRateBpm
            Comparison.HRV -> row.avgHrv
            Comparison.OXYGEN -> row.spo2Pct
            Comparison.SKIN_TEMP -> SkinTempDisplay.leadReading(row.skinTempC, row.skinTempDevC, skinPrefer)?.value
        }
    }

    fun valuesByDay(metric: Comparison): Map<LocalDate, Double> {
        val out = rangeNights.mapNotNull { n -> nightly(metric, n)?.let { n.day to it } }.toMap()
        if (metric != Comparison.SKIN_TEMP) return out
        val kind = SkinTempDisplay.dominantKind(out.toSortedMap().values.toList()) ?: return emptyMap()
        return out.filterValues { SkinTempDisplay.kind(it) == kind }
    }

    val comparisons: List<ComparisonRow> = Comparison.entries.mapNotNull { metric ->
        if (range == SleepRange.DAY) {
            val n = dayNight ?: return@mapNotNull null
            if (metric == Comparison.HEART_RATE) {
                val pts = heartPoints(n)
                val lo = pts.minOfOrNull { it.second } ?: return@mapNotNull null
                val hi = pts.maxOf { it.second }
                return@mapNotNull ComparisonRow(metric, bpmRange(lo, hi), pts.size >= 2)
            }
            val v = nightly(metric, n) ?: return@mapNotNull null
            ComparisonRow(metric, formatComparison(metric, v, tempUnit, locale), plottable = false)
        } else {
            val values = valuesByDay(metric).values
            if (values.isEmpty()) return@mapNotNull null
            if (metric == Comparison.HEART_RATE) return@mapNotNull ComparisonRow(metric, bpmRange(values.min(), values.max()), true)
            ComparisonRow(metric, formatComparison(metric, values.average(), tempUnit, locale), true)
        }
    }
    val selectedComparison: Comparison? = if (tab != MoreTab.COMPARISONS) null else {
        val plottable = comparisons.filter { it.plottable }.map { it.metric }
        if (comparisonPicked) pickedComparison?.takeIf { it in plottable } else plottable.firstOrNull()
    }
    val overlayColor = selectedComparison?.let { comparisonColor(it) } ?: Health.colors.heart

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        PushedTopBar(stringResource(R.string.nav_sleep), onBack)
        LazyColumn(
            contentPadding = PaddingValues(start = M3Dimens.screenPadding, end = M3Dimens.screenPadding, bottom = M3Dimens.bottomBarClearance),
            verticalArrangement = Arrangement.spacedBy(M3Dimens.itemGap),
        ) {
            item {
                PeriodSegmented(
                    options = listOf(
                        stringResource(R.string.sleep_range_d), stringResource(R.string.sleep_range_w),
                        stringResource(R.string.sleep_range_m), stringResource(R.string.sleep_range_6m),
                    ),
                    selectedIndex = range.ordinal,
                    onSelect = { range = SleepRange.entries[it] },
                    contentDescriptions = listOf(
                        stringResource(R.string.sleep_range_day), stringResource(R.string.sleep_range_week),
                        stringResource(R.string.sleep_range_month), stringResource(R.string.sleep_range_six_months),
                    ),
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            item {
                val average = range != SleepRange.DAY
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                        HeaderFigure(stringResource(if (average) R.string.sleep_more_avg_in_bed else R.string.sleep_more_in_bed), summary.inBedMin)
                        HeaderFigure(stringResource(if (average) R.string.sleep_more_avg_asleep else R.string.sleep_more_asleep), summary.asleepMin)
                    }
                    Text(
                        periodLabel(range, dayNight, window, locale),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item {
                Box(Modifier.fillMaxWidth().height(283.dp)) {
                    if (range == SleepRange.DAY) {
                        if (dayNight != null) {
                            val swipe = Modifier.pointerInput(lastIndex) {
                                var dx = 0f
                                detectHorizontalDragGestures(onDragStart = { dx = 0f }, onDragEnd = {
                                    if (abs(dx) > 50.dp.toPx()) offset = (offset + if (dx > 0) 1 else -1).coerceIn(0, lastIndex)
                                }) { _, a -> dx += a }
                            }
                            SleepStagesChart(
                                spans = dayNight.spans, onsetTs = dayNight.onsetTs, stages = dayNight.stages,
                                modifier = swipe.fillMaxSize(),
                                highlight = if (tab == MoreTab.STAGES) selectedStage else null,
                                overlay = if (selectedComparison == Comparison.HEART_RATE) heartPoints(dayNight) else emptyList(),
                                overlayColor = overlayColor,
                            )
                        } else {
                            Text(
                                stringResource(R.string.sleep_no_data),
                                modifier = Modifier.align(Alignment.Center),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        val stagesBySlot = if (range == SleepRange.SIX_MONTHS) emptyMap() else {
                            val byDay = nights.nights.associate { it.day to it.spans }
                            window.slotStarts.mapIndexedNotNull { slot, d -> byDay[d]?.let { slot to it } }.toMap()
                        }
                        val overlay = selectedComparison?.let { slotValues(window, valuesByDay(it)) }.orEmpty()
                        SleepRangeChart(
                            window = window,
                            stagesBySlot = stagesBySlot,
                            highlight = if (tab == MoreTab.STAGES && range != SleepRange.SIX_MONTHS) selectedStage else null,
                            overlay = overlay,
                            overlayColor = overlayColor,
                            is24h = is24h,
                            locale = locale,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
            }
            item {
                PeriodSegmented(
                    options = listOf(
                        stringResource(R.string.sleep_more_stages), stringResource(R.string.sleep_more_amounts),
                        stringResource(R.string.sleep_more_comparisons),
                    ),
                    selectedIndex = tab.ordinal,
                    onSelect = { tab = MoreTab.entries[it] },
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            item {
                when (tab) {
                    MoreTab.STAGES -> if (summary.nights == 0) EmptyRow() else ListGroup {
                        SleepStageRow.entries.forEach { row ->
                            item { shape ->
                                val selected = selectedStage == row
                                val name = stageName(row)
                                val typical = typicalMinutes(nights, row)
                                ListRow(
                                    shape = shape,
                                    title = if (range == SleepRange.DAY) name else stringResource(R.string.sleep_more_average, name),
                                    subtitle = if (range == SleepRange.DAY && typical != null) stringResource(R.string.sleep_more_usually, sleepDuration(typical)) else null,
                                    leading = { Dot(stageColor(row)) },
                                    trailing = {
                                        ValueTrail(
                                            detail = summary.sharePercent(row)?.let { percent(it / 100.0, locale) },
                                            value = summary.stageMin[row]?.let { sleepDuration(it) } ?: "–",
                                            selected = selected,
                                        )
                                    },
                                    enabled = range != SleepRange.SIX_MONTHS,
                                    onClick = { selectedStage = if (selected) null else row },
                                )
                            }
                        }
                    }
                    MoreTab.AMOUNTS -> if (summary.nights == 0) EmptyRow() else Column(verticalArrangement = Arrangement.spacedBy(M3Dimens.itemGap)) {
                        AmountRows(range != SleepRange.DAY, summary, sleepNeed(nights, shown), is24h, locale)
                        nights.model?.sleepDebtLedger?.takeIf { it.nights.isNotEmpty() }?.let { SleepDebtCard(it, locale) }
                    }
                    MoreTab.COMPARISONS -> if (comparisons.isEmpty()) EmptyRow() else ListGroup {
                        comparisons.forEach { row ->
                            item { shape ->
                                val selected = selectedComparison == row.metric
                                ListRow(
                                    shape = shape,
                                    title = comparisonName(row.metric),
                                    leading = { Dot(comparisonColor(row.metric)) },
                                    trailing = { ValueTrail(null, row.value, selected) },
                                    enabled = row.plottable,
                                    onClick = if (row.plottable) {
                                        { comparisonPicked = true; pickedComparison = if (selected) null else row.metric }
                                    } else null,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HeaderFigure(title: String, minutes: Double?) {
    Column {
        Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (minutes == null || minutes <= 0) {
            Text("–", style = MaterialTheme.typography.displaySmall)
        } else {
            val (h, m) = durationParts(minutes)
            val big = SpanStyle(fontWeight = FontWeight.SemiBold, fontSize = MaterialTheme.typography.headlineLarge.fontSize)
            val small = SpanStyle(color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = MaterialTheme.typography.titleMedium.fontSize)
            val hr = stringResource(R.string.metric_unit_hr)
            val min = stringResource(R.string.metric_unit_min)
            Text(buildAnnotatedString {
                if (h > 0) { withStyle(big) { append("$h") }; withStyle(small) { append(" $hr ") } }
                withStyle(big) { append("$m") }; withStyle(small) { append(" $min") }
            }, maxLines = 1)
        }
    }
}

@Composable
private fun ValueTrail(detail: String?, value: String, selected: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (detail != null) Text(detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"))
        if (selected) Icon(Icons.Filled.Check, null, tint = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun EmptyRow() {
    ListGroup { item { shape -> ListRow(shape = shape, title = stringResource(R.string.sleep_no_data)) } }
}

@Composable
private fun AmountRows(average: Boolean, s: SleepPeriodSummary, need: Double?, is24h: Boolean, locale: Locale) {
    val inBed = s.inBedMin?.let { sleepDuration(it) } ?: "–"
    val asleep = s.asleepMin?.let { sleepDuration(it) } ?: "–"
    val needText = need?.let { sleepDuration(it) }
    val efficiency = s.efficiency?.let { percent(it, locale) }
    val bed = s.bedtimeOfNightMin
    val wake = s.wakeOfNightMin
    ListGroup {
        fun row(title: Int, value: String) = item { shape ->
            ListRow(shape = shape, title = stringResource(title), trailing = { ValueTrail(null, value, false) })
        }
        row(if (average) R.string.sleep_more_avg_time_in_bed else R.string.sleep_more_time_in_bed, inBed)
        row(if (average) R.string.sleep_more_avg_time_asleep else R.string.sleep_more_time_asleep, asleep)
        if (needText != null) row(R.string.sleep_more_need, needText)
        if (efficiency != null) row(if (average) R.string.sleep_more_avg_efficiency else R.string.sleep_more_efficiency, efficiency)
        if (bed != null && wake != null) {
            row(if (average) R.string.sleep_more_avg_bedtime else R.string.sleep_more_bedtime, nightClock(bed, is24h, locale))
            row(if (average) R.string.sleep_more_avg_wake else R.string.sleep_more_wake, nightClock(wake, is24h, locale))
        }
    }
}

/** The ledger's last 14 nights as diverging bars around need, with the balance at the top. */
@Composable
private fun SleepDebtCard(ledger: SleepDebtLedger, locale: Locale) {
    val nights = ledger.nights.takeLast(14)
    val peak = max(60.0, nights.maxOfOrNull { abs(it.deltaMin) } ?: 60.0)
    val surplus = Health.colors.stageCore
    val deficit = MaterialTheme.colorScheme.onSurfaceVariant
    val axis = MaterialTheme.colorScheme.outlineVariant
    val measurer = rememberTextMeasurer()
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant)
    HealthCard(verticalSpacing = 10.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.sleep_more_debt), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Text(
                if (ledger.isDebt) sleepDuration(ledger.magnitudeMin) else stringResource(R.string.sleep_more_no_debt),
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
            )
        }
        val labels = nights.map { n -> runCatching { LocalDate.parse(n.day).dayOfMonth.toString() }.getOrDefault("") }
        // CR-3: each night's surplus or shortfall in words, so the bars are not silent.
        val spoken = nights.map { n ->
            val sign = if (n.deltaMin >= 0) "+" else "\u2212"
            "${MetricDateLabels.shortDate(n.day, locale)}: $sign${sleepDuration(abs(n.deltaMin))}"
        }.joinToString(", ")
        Canvas(Modifier.fillMaxWidth().height(80.dp).clearAndSetSemantics { contentDescription = spoken }) {
            val labelH = labelBand(measurer, labelStyle, floor = 14.dp, gap = 2.dp)
            val h = size.height - labelH
            val half = h / 2
            val slot = size.width / max(1, nights.size)
            // When the day numbers would touch (large text) every other one is drawn, counted back from
            // the latest night so that one always shows.
            val dayTexts = labels.map { measurer.measure(it, labelStyle) }
            val stride = labelStride(dayTexts.maxOfOrNull { it.size.width.toFloat() } ?: 0f, slot, 2.dp.toPx())
            drawLine(axis, Offset(0f, half), Offset(size.width, half), 1.dp.toPx())
            nights.forEachIndexed { i, n ->
                val bh = max(2.dp.toPx(), (half * min(1.0, abs(n.deltaMin) / peak)).toFloat())
                val w = min(slot * 0.6f, 10.dp.toPx())
                val x = i * slot + (slot - w) / 2
                val y = if (n.deltaMin >= 0) half - bh else half
                drawRoundRect(if (n.deltaMin >= 0) surplus else deficit, Offset(x, y), Size(w, bh), CornerRadius(2.dp.toPx(), 2.dp.toPx()))
                if ((nights.lastIndex - i) % stride == 0) {
                    val t = dayTexts[i]
                    drawText(t, topLeft = Offset(i * slot + (slot - t.size.width) / 2, h + 2.dp.toPx()))
                }
            }
        }
    }
}

/** Week / month / 6-month chart: each slot's bedtime→wake as a floating bar, time running down. */
@Composable
private fun SleepRangeChart(
    window: SleepRangeWindow,
    stagesBySlot: Map<Int, List<SleepStageSpan>>,
    highlight: SleepStageRow?,
    overlay: List<Pair<Int, Double>>,
    overlayColor: Color,
    is24h: Boolean,
    locale: Locale,
    modifier: Modifier,
) {
    val colors = SleepStageRow.entries.associateWith { stageColor(it) }
    val plain = Health.colors.stageCore
    val grid = MaterialTheme.colorScheme.outlineVariant
    val measurer = rememberTextMeasurer()
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant)
    val (lo, hi) = SleepHistory.domain(window)
    val avg = window.averageAsleepMin
    // CR-3: a period with no nights says so, rather than reading out as an empty element.
    val spoken = avg?.let { stringResource(R.string.sleep_more_average, sleepDuration(it)) } ?: stringResource(R.string.sleep_no_data)
    val slotLabels = window.slotStarts.mapIndexed { slot, start -> slotLabel(window, slot, start, locale) }
    Canvas(modifier.clearAndSetSemantics { contentDescription = spoken }) {
        val hourLabels = generateSequence(lo) { it + 120 }.takeWhile { it <= hi }.toList()
        val hourTexts = hourLabels.map { measurer.measure(nightClock(it, is24h, locale), labelStyle) }
        val axisW = (hourTexts.maxOfOrNull { it.size.width } ?: 0) + 6.dp.toPx()
        val slotH = labelBand(measurer, labelStyle, floor = 18.dp)
        val w = size.width - axisW
        val h = size.height - slotH
        fun y(m: Double) = ((m - lo) / (hi - lo) * h).toFloat()
        val n = max(1, window.slotStarts.size)
        fun cx(slot: Int) = (slot + 0.5f) * w / n
        // An hour whose label would sit on the one above it is ruled but not labelled (large text).
        var hourEdge = Float.NEGATIVE_INFINITY
        hourLabels.forEachIndexed { i, m ->
            val yy = y(m)
            drawLine(grid, Offset(0f, yy), Offset(w, yy), 1.dp.toPx())
            val t = hourTexts[i]
            val top = (yy - t.size.height / 2).coerceIn(0f, (h - t.size.height).coerceAtLeast(0f))
            if (top >= hourEdge) {
                drawText(t, topLeft = Offset(w + 6.dp.toPx(), top))
                hourEdge = top + t.size.height
            }
        }
        val barW = max(3.dp.toPx(), min(22.dp.toPx(), w / n * 0.55f))
        val dim = if (overlay.isEmpty()) 1f else 0.35f
        for (bar in window.bars) {
            val x = cx(bar.slot) - barW / 2
            val top = y(bar.onsetMin)
            val bottom = y(bar.wakeMin)
            val rectH = max(barW, bottom - top)
            val spans = stagesBySlot[bar.slot]
            val radius = if (stagesBySlot.isEmpty()) barW / 2 else min(3.dp.toPx(), barW / 2)
            if (spans.isNullOrEmpty()) {
                drawRoundRect(plain.copy(alpha = if (highlight == null) dim else 0.18f), Offset(x, top), Size(barW, rectH), CornerRadius(radius, radius))
                continue
            }
            val clip = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(x, top, x + barW, top + rectH, CornerRadius(radius, radius))) }
            clipPath(clip) {
                for (s in spans) {
                    val y1 = y(bar.onsetMin + s.startSec / 60)
                    val y2 = y(bar.onsetMin + s.endSec / 60)
                    val a = highlight?.let { if (it == s.row) 1f else 0.18f } ?: dim
                    drawRect(colors.getValue(s.row).copy(alpha = a), Offset(x, y1), Size(barW, max(0.75f, y2 - y1)))
                }
            }
        }
        overlayDomain(overlay.map { it.second })?.let { (olo, ohi) ->
            val spread = max(ohi - olo, 1e-6)
            val pts = overlay.map { (slot, v) -> Offset(cx(slot), (h * (0.9 - 0.8 * (v - olo) / spread)).toFloat()) }
            pts.zipWithNext().forEach { (a, b) -> drawLine(overlayColor.copy(alpha = 0.6f), a, b, 1.5.dp.toPx()) }
            val r = if (n > 10) 2.5.dp.toPx() else 4.dp.toPx()
            pts.forEach { drawCircle(overlayColor, r, it) }
        }
        // When the slot labels would touch (large text) every other one is drawn, evenly.
        val labelled = slotLabels.mapIndexedNotNull { slot, text -> text?.let { slot to measurer.measure(it, labelStyle) } }
        val stride = labelStride(
            widest = labelled.maxOfOrNull { it.second.size.width.toFloat() } ?: 0f,
            spacing = if (labelled.size > 1) (cx(labelled.last().first) - cx(labelled.first().first)) / (labelled.size - 1) else 0f,
            gap = 4.dp.toPx(),
        )
        labelled.forEachIndexed { i, (slot, t) ->
            if (i % stride != 0) return@forEachIndexed
            val left = (cx(slot) - t.size.width / 2).coerceIn(0f, (w - t.size.width).coerceAtLeast(0f))
            drawText(t, topLeft = Offset(left, h + 3.dp.toPx()))
        }
    }
}

private fun slotLabel(window: SleepRangeWindow, slot: Int, start: LocalDate, locale: Locale): String? = when (window.range) {
    SleepRange.DAY, SleepRange.WEEK -> start.dayOfWeek.getDisplayName(TextStyle.SHORT, locale)
    SleepRange.MONTH -> if ((window.slotStarts.size - 1 - slot) % 7 == 0) start.dayOfMonth.toString() else null
    SleepRange.SIX_MONTHS -> {
        val opens = if (slot == 0) start.dayOfMonth <= 7 else start.monthValue != window.slotStarts[slot - 1].monthValue
        if (opens) start.month.getDisplayName(TextStyle.SHORT, locale) else null
    }
}

/** "20 Sep – 26 Sep 2026" for a range, the night's date for D. */
private fun periodLabel(range: SleepRange, night: SleepNightDetail?, window: SleepRangeWindow, locale: Locale): String {
    if (range == SleepRange.DAY) return night?.let { DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(it.day) } ?: " "
    val first = window.slotStarts.firstOrNull() ?: return ""
    val last = if (range == SleepRange.SIX_MONTHS) LocalDate.now() else window.slotStarts.last()
    return DateTimeFormatter.ofPattern("d MMM", locale).format(first) + " – " + DateTimeFormatter.ofPattern("d MMM yyyy", locale).format(last)
}

/** Per-slot values: a night's value (W / M) or the mean of a week's nights (6M). */
private fun slotValues(window: SleepRangeWindow, byDay: Map<LocalDate, Double>): List<Pair<Int, Double>> =
    window.slotStarts.mapIndexedNotNull { slot, start ->
        val values = if (window.range == SleepRange.SIX_MONTHS) {
            byDay.filterKeys { !it.isBefore(start) && it.isBefore(start.plusDays(7)) }.values.toList()
        } else listOfNotNull(byDay[start])
        if (values.isEmpty()) null else slot to values.average()
    }

/** The typical minutes of a stage over the whole history (Core = light). */
private fun typicalMinutes(n: SleepNights, row: SleepStageRow): Double? = when (row) {
    SleepStageRow.DEEP -> n.model?.typicalDeepMin
    SleepStageRow.REM -> n.model?.typicalRemMin
    SleepStageRow.CORE -> n.model?.typicalLightMin
    SleepStageRow.AWAKE -> null
}

/** The sleep need behind the shown nights: each night's imported need, else the personal need. */
private fun sleepNeed(n: SleepNights, shown: List<SleepNightDetail>): Double? {
    if (shown.isEmpty()) return null
    val fallback = max(450.0, n.days.mapNotNull { it.totalSleepMin }.filter { it > 0 }.takeIf { it.isNotEmpty() }?.average() ?: 450.0)
    return shown.map { n.imported.needMin[it.dayKey] ?: fallback }.average()
}

private fun percent(fraction: Double, locale: Locale): String = java.text.NumberFormat.getPercentInstance(locale).format(fraction)

@Composable
private fun bpmRange(lo: Double, hi: Double): String {
    val l = lo.roundToInt()
    val h = hi.roundToInt()
    return if (l == h) stringResource(R.string.sleep_bpm_value, l) else stringResource(R.string.sleep_bpm_range, l, h)
}

@Composable
private fun formatComparison(metric: Comparison, v: Double, unit: TemperatureUnit, locale: Locale): String = when (metric) {
    Comparison.HEART_RATE -> stringResource(R.string.sleep_bpm_value, v.roundToInt())
    Comparison.RESPIRATORY -> stringResource(R.string.sleep_br_min_value, String.format(locale, "%.1f", v))
    Comparison.HRV -> stringResource(R.string.sleep_ms_value, v.roundToInt())
    Comparison.OXYGEN -> percent(v / 100, locale)
    Comparison.SKIN_TEMP -> if (SkinTempDisplay.kind(v) == SkinTempDisplay.Kind.DEVIATION) signedDelta(v, unit)
        else UnitFormatter.temperatureFromCelsius(v, unit)
}

@Composable
private fun comparisonColor(metric: Comparison): Color = when (metric) {
    Comparison.HEART_RATE, Comparison.HRV -> Health.colors.heart
    Comparison.RESPIRATORY -> Health.colors.respiratory
    Comparison.OXYGEN -> Health.colors.oxygen
    Comparison.SKIN_TEMP -> Health.colors.temperature
}

@Composable
private fun comparisonName(metric: Comparison): String = stringResource(
    when (metric) {
        Comparison.HEART_RATE -> R.string.sleep_more_heart_rate
        Comparison.RESPIRATORY -> R.string.sleep_vitals_resp
        Comparison.HRV -> R.string.sleep_more_hrv
        Comparison.OXYGEN -> R.string.sleep_vitals_spo2
        Comparison.SKIN_TEMP -> R.string.sleep_vitals_skin_temp
    },
)
