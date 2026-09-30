package com.noop.ui

import com.noop.ui.metric.MetricCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #1995: the Charge, Effort and Rest hero rings open their own metric page, so the ring and the metric
 * card below it can never lead to different screens.
 *
 * The rings still pass the legacy keys ("recovery", "strain", "rest"); the metric page maps them through
 * [MetricCatalog.keyForLegacy] to catalogue keys. Rest is the one that bites: its legacy key is "rest"
 * while its series is "sleep_performance", so the mapping, not the constant, is what has to hold.
 */
class HeroRingMetricKeyTest {

    private fun opens(legacy: String): String = MetricCatalog.keyForLegacy(legacy)

    @Test fun chargeOpensTheChargePage() {
        assertEquals("recovery", HERO_CHARGE_METRIC_KEY)
        assertEquals("recovery", opens(HERO_CHARGE_METRIC_KEY))
    }

    @Test fun effortRingOpensTheEffortPage() {
        assertEquals("strain", HERO_EFFORT_METRIC_KEY)
        assertEquals("strain", opens(HERO_EFFORT_METRIC_KEY))
    }

    @Test fun restRingOpensTheRestPage() {
        assertEquals("rest", HERO_REST_METRIC_KEY)
        assertEquals("sleep_performance", opens(HERO_REST_METRIC_KEY))
    }

    @Test fun everyRingKeyHasACatalogueEntry() {
        for (key in listOf(HERO_CHARGE_METRIC_KEY, HERO_EFFORT_METRIC_KEY, HERO_REST_METRIC_KEY)) {
            assertTrue(key, MetricCatalog.byKey(opens(key)).isNotEmpty())
        }
    }
}
