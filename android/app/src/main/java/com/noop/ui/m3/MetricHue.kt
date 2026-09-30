package com.noop.ui.m3

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.Accessibility
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

// MARK: - Metric hue (iOS MetricHealthStyle.tint + AllMetricsCatalog.category glyph)
//
// Which fixed data hue, and which category glyph, a metric is drawn with wherever it is listed on its own
// (Browse search results today; All Metrics and the metric page later). Keyed by the Android metric key
// the Explore catalogue and the metric series use. The rule is the iOS one: the three rings keep their
// ring hue, a few metrics carry their own category, and the rest follow their score family.

/** The hue family of a metric. Resolved to a colour at draw time so it follows light / dark. */
enum class MetricHue { Charge, Effort, Heart, Sleep, Oxygen, Respiratory, Temperature, Body, Mind, Nutrition, Activity }

/** The hue a metric [key] is drawn in (unknown keys fall to Body, as on iOS). */
fun metricHueFor(key: String): MetricHue = when (key) {
    "recovery" -> MetricHue.Charge
    "strain" -> MetricHue.Effort
    "hrv", "rhr", "avg_hr", "max_hr" -> MetricHue.Heart
    "sleep", "efficiency", "sleep_performance", "sleep_total_min" -> MetricHue.Sleep
    "spo2" -> MetricHue.Oxygen
    "resp", "resp_rate" -> MetricHue.Respiratory
    "skin_temp" -> MetricHue.Temperature
    "mood", "stress" -> MetricHue.Mind
    "calories_in", "protein_g", "carbs_g", "fat_g" -> MetricHue.Nutrition
    "steps", "steps_est", "active_kcal" -> MetricHue.Activity
    else -> MetricHue.Body
}

/** The fixed data colour of this hue. */
val MetricHue.color: Color
    @Composable @ReadOnlyComposable get() {
        val c = Health.colors
        return when (this) {
            MetricHue.Charge -> c.charge
            MetricHue.Effort -> c.effort
            MetricHue.Heart -> c.heart
            MetricHue.Sleep -> c.sleep
            MetricHue.Oxygen -> c.oxygen
            MetricHue.Respiratory -> c.respiratory
            MetricHue.Temperature -> c.temperature
            MetricHue.Body -> c.body
            MetricHue.Mind -> c.mind
            MetricHue.Nutrition -> c.nutrition
            MetricHue.Activity -> c.activity
        }
    }

/** The category glyph shown beside a metric of this hue. */
val MetricHue.icon: ImageVector
    get() = when (this) {
        MetricHue.Charge -> Icons.Filled.Bolt
        MetricHue.Effort -> Icons.AutoMirrored.Filled.DirectionsRun
        MetricHue.Heart -> Icons.Filled.Favorite
        MetricHue.Sleep -> Icons.Filled.Bedtime
        MetricHue.Oxygen -> Icons.Filled.WaterDrop
        MetricHue.Respiratory -> Icons.Filled.Air
        MetricHue.Temperature -> Icons.Filled.Thermostat
        MetricHue.Body -> Icons.Filled.Accessibility
        MetricHue.Mind -> Icons.Filled.Psychology
        MetricHue.Nutrition -> Icons.Filled.Restaurant
        MetricHue.Activity -> Icons.Filled.LocalFireDepartment
    }
