package com.noop.ui.sleep

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.Bed
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.ui.AppViewModel
import com.noop.ui.TemperatureUnit
import com.noop.ui.UnitFormatter
import com.noop.ui.UnitPrefs
import com.noop.ui.m3.ChevronRight
import com.noop.ui.m3.Health
import com.noop.ui.m3.HealthCard
import com.noop.ui.m3.ListGroup
import com.noop.ui.m3.ListRow
import com.noop.ui.m3.M3Dimens
import com.noop.ui.m3.PushedTopBar
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.roundToInt

// MARK: - Vitals (twin of iOS SleepVitalsView)
//
// The verdict and the night's date over a chart of every vital against its typical range (a column each,
// High / Typical / Low zones, a ring where the night fell), then each vital's reading beside its range,
// opening that metric's page.

internal fun vitalIcon(metric: SleepVitals.Metric): ImageVector = when (metric) {
    SleepVitals.Metric.HEART_RATE -> Icons.Filled.Favorite
    SleepVitals.Metric.RESPIRATORY -> Icons.Filled.Air
    SleepVitals.Metric.TEMPERATURE -> Icons.Filled.Thermostat
    SleepVitals.Metric.OXYGEN -> Icons.Filled.WaterDrop
    SleepVitals.Metric.SLEEP_DURATION -> Icons.Filled.Bed
}

@Composable
internal fun vitalTitle(metric: SleepVitals.Metric): String = stringResource(
    when (metric) {
        SleepVitals.Metric.HEART_RATE -> R.string.sleep_vitals_rhr
        SleepVitals.Metric.RESPIRATORY -> R.string.sleep_vitals_resp
        SleepVitals.Metric.TEMPERATURE -> R.string.sleep_vitals_skin_temp
        SleepVitals.Metric.OXYGEN -> R.string.sleep_vitals_spo2
        SleepVitals.Metric.SLEEP_DURATION -> R.string.sleep_vitals_sleep_duration
    },
)

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun SleepVitalsScreen(vm: AppViewModel, day: String, onBack: () -> Unit, onOpenMetric: (String) -> Unit) {
    val context = LocalContext.current
    val locale = context.resources.configuration.locales[0]
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val vitals = remember(days, day) { SleepVitals.make(days, day) }
    val tempUnit = remember { UnitPrefs.temperature(context) }
    val date = runCatching { LocalDate.parse(day) }.getOrNull()
    androidx.compose.foundation.layout.Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        PushedTopBar(stringResource(R.string.sleep_vitals_title), onBack)
        LazyColumn(
            contentPadding = PaddingValues(start = M3Dimens.screenPadding, end = M3Dimens.screenPadding, top = 8.dp, bottom = M3Dimens.bottomBarClearance),
            verticalArrangement = Arrangement.spacedBy(M3Dimens.itemGap),
        ) {
            item {
                Column(Modifier.padding(horizontal = 4.dp)) {
                    if (vitals.nightsRemaining == 0) VitalsVerdict(vitals.outliers, MaterialTheme.typography.headlineMedium)
                    if (date != null) {
                        Text(
                            DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(date),
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            if (vitals.nightsRemaining > 0) {
                item {
                    HealthCard {
                        Text(
                            pluralStringResource(R.plurals.sleep_sessions_until_results, vitals.nightsRemaining, vitals.nightsRemaining),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 80.dp).padding(top = 28.dp),
                        )
                    }
                }
            } else {
                item { HealthCard { SleepVitalsChart(vitals.readings, Modifier.fillMaxWidth().height(220.dp)) } }
                item {
                    ListGroup {
                        vitals.readings.forEach { r ->
                            item { shape ->
                                val tint = if (r.isOutlier) Health.colors.vitalsOutlier else Health.colors.vitalsTypical
                                ListRow(
                                    shape = shape,
                                    title = vitalTitle(r.metric),
                                    subtitle = run {
                                        // A signed range ("−0.4 – +0.4 °C") or one whose ends are several words
                                        // ("5 h 52 min – 8 h 22 min") needs space round the dash to stay readable.
                                        val low = bareVital(r.low, r.metric, tempUnit, locale)
                                        val high = formatVital(r.high, r.metric, tempUnit, locale)
                                        val spaced = r.low < 0 || low.contains(' ')
                                        stringResource(
                                            R.string.sleep_vitals_typical_range,
                                            if (spaced) "$low " else low,
                                            if (spaced) " $high" else high,
                                        )
                                    },
                                    leading = { Icon(vitalIcon(r.metric), null, tint = tint) },
                                    trailing = {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text(
                                                formatVital(r.value, r.metric, tempUnit, locale),
                                                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                                                color = if (r.isOutlier) Health.colors.vitalsOutlier else MaterialTheme.colorScheme.onSurface,
                                            )
                                            ChevronRight()
                                        }
                                    },
                                    onClick = { onOpenMetric(r.metric.catalogKey) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Health's Vitals chart: a column per vital, High / Typical / Low zones, a ring where the night fell. */
@Composable
private fun SleepVitalsChart(readings: List<SleepVitals.Reading>, modifier: Modifier) {
    val rule = MaterialTheme.colorScheme.outlineVariant
    val band = Health.colors.vitalsTypical.copy(alpha = 0.18f)
    val typical = Health.colors.vitalsTypical
    val outlier = Health.colors.vitalsOutlier
    val fill = MaterialTheme.colorScheme.surfaceContainerLow
    val inside = stringResource(R.string.sleep_vitals_within)
    val outside = stringResource(R.string.sleep_vitals_outside)
    val spoken = readings.map { "${vitalTitle(it.metric)} ${if (it.isOutlier) outside else inside}" }.joinToString(", ")
    Column(modifier.clearAndSetSemantics { contentDescription = spoken }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Canvas(Modifier.weight(1f).fillMaxHeight()) {
                val columns = SleepVitals.Metric.entries.size
                val zone = size.height / 3
                val hair = 1.dp.toPx()
                drawRect(band, Offset(0f, zone), androidx.compose.ui.geometry.Size(size.width, zone))
                for (i in 0..3) {
                    val y = (i * zone).coerceIn(hair / 2, size.height - hair / 2)
                    drawLine(rule, Offset(0f, y), Offset(size.width, y), hair)
                }
                for (i in 0..columns) {
                    val x = (size.width * i / columns).coerceIn(hair / 2, size.width - hair / 2)
                    drawLine(rule, Offset(x, 0f), Offset(x, size.height), hair)
                }
                val ring = 12.dp.toPx()
                for (r in readings) {
                    val x = size.width * (r.metric.ordinal + 0.5f) / columns
                    val p = r.position.coerceIn(-0.5, 1.5)
                    val y = (2 * zone - p * zone).toFloat()
                    drawCircle(fill, ring / 2, Offset(x, y))
                    drawCircle(if (r.isOutlier) outlier else typical, ring / 2 - 1.25.dp.toPx(), Offset(x, y), style = Stroke(2.5.dp.toPx()))
                }
            }
            Column(Modifier.fillMaxHeight()) {
                listOf(R.string.sleep_vitals_zone_high, R.string.sleep_vitals_zone_typical, R.string.sleep_vitals_zone_low).forEach {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
                        Text(stringResource(it), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(end = 52.dp)) {
            SleepVitals.Metric.entries.forEach { m ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(vitalIcon(m), null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

/** A range's low end: the number alone, the high end carries the unit ("50–62 BPM"). */
@Composable
private fun bareVital(v: Double, metric: SleepVitals.Metric, unit: TemperatureUnit, locale: Locale): String = when (metric) {
    SleepVitals.Metric.HEART_RATE, SleepVitals.Metric.OXYGEN -> "${v.roundToInt()}"
    SleepVitals.Metric.RESPIRATORY -> String.format(locale, "%.1f", v)
    SleepVitals.Metric.TEMPERATURE -> formatVital(v, metric, unit, locale).substringBefore(" ")
    SleepVitals.Metric.SLEEP_DURATION -> sleepDuration(v)
}

@Composable
internal fun formatVital(v: Double, metric: SleepVitals.Metric, unit: TemperatureUnit, locale: Locale): String = when (metric) {
    SleepVitals.Metric.HEART_RATE -> stringResource(R.string.sleep_bpm_value, v.roundToInt())
    SleepVitals.Metric.RESPIRATORY -> stringResource(R.string.sleep_br_min_value, String.format(locale, "%.1f", v))
    // A deviation is a small signed number; an absolute reading is a body temperature.
    SleepVitals.Metric.TEMPERATURE -> if (kotlin.math.abs(v) < 10) signedDelta(v, unit)
        else UnitFormatter.temperatureFromCelsius(v, unit)
    SleepVitals.Metric.OXYGEN -> "${v.roundToInt()} %"
    SleepVitals.Metric.SLEEP_DURATION -> sleepDuration(v)
}

/** A skin-temperature deviation with its sign ("+0.2 °C", "−0.3 °C", "0.0 °C"), never "-0.0". */
internal fun signedDelta(v: Double, unit: TemperatureUnit): String {
    val text = UnitFormatter.temperatureDeltaFromCelsius(kotlin.math.abs(v), unit)
    val shown = text.substringBefore(" ").replace(',', '.').toDoubleOrNull() ?: 0.0
    return when {
        shown == 0.0 -> text
        v > 0 -> "+$text"
        else -> "−$text"
    }
}
