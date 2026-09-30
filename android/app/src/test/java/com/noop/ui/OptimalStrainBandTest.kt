package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the display-only recovery->optimal-strain band (task #43), byte-identical to the Swift
 * StrainTargetNotifier.optimalStrainRange: green >= 67 -> 14-18, yellow 34-66 -> 10-14, red < 34 -> 4-10.
 * Today's Effort ring target arc and the strain-target nudge read it; these values ARE the contract.
 */
class OptimalStrainBandTest {

    @Test fun greenDaySuggests14to18() {
        assertEquals(OptimalStrainRange(14, 18), optimalStrainRange(90.0))
        assertEquals(OptimalStrainRange(14, 18), optimalStrainRange(67.0)) // green's lower edge is inclusive
    }

    @Test fun yellowDaySuggests10to14() {
        assertEquals(OptimalStrainRange(10, 14), optimalStrainRange(66.9))
        assertEquals(OptimalStrainRange(10, 14), optimalStrainRange(50.0))
        assertEquals(OptimalStrainRange(10, 14), optimalStrainRange(34.0)) // yellow's lower edge is inclusive
    }

    @Test fun redDaySuggests4to10() {
        assertEquals(OptimalStrainRange(4, 10), optimalStrainRange(33.9))
        assertEquals(OptimalStrainRange(4, 10), optimalStrainRange(0.0))
    }

    @Test fun noRecoveryIsNoBand() {
        assertNull(optimalStrainRange(null))
        assertNull(optimalFractionRange(null))
    }

    @Test fun fractionRangeIsTheBandOverTwentyOne() {
        val green = optimalFractionRange(80.0)!!
        assertEquals(14.0f / 21.0f, green.start, 1e-6f)
        assertEquals(18.0f / 21.0f, green.endInclusive, 1e-6f)
        val yellow = optimalFractionRange(50.0)!!
        assertEquals(10.0f / 21.0f, yellow.start, 1e-6f)
        assertEquals(14.0f / 21.0f, yellow.endInclusive, 1e-6f)
        val red = optimalFractionRange(20.0)!!
        assertEquals(4.0f / 21.0f, red.start, 1e-6f)
        assertEquals(10.0f / 21.0f, red.endInclusive, 1e-6f)
    }

    @Test fun fractionRangeNeverLeavesTheAxis() {
        for (r in listOf(null, -50.0, 0.0, 33.9, 34.0, 66.9, 67.0, 100.0, 1000.0)) {
            val range = optimalFractionRange(r) ?: continue
            assertTrue("start out of range for recovery=$r", range.start in 0f..1f)
            assertTrue("end out of range for recovery=$r", range.endInclusive in 0f..1f)
            assertTrue("start > end for recovery=$r", range.start <= range.endInclusive)
        }
    }
}
