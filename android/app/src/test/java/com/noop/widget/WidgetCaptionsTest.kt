package com.noop.widget

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins what the widgets print and speak. The rule under all of it is honest-blank: a value NOOP does not
 * have is a dash and a ring with no arc, never a zero.
 */
class WidgetCaptionsTest {

    @Test
    fun aScoreIsTheBareNumberAndAnUnscoredOneIsADash() {
        assertEquals("68", WidgetCaptions.score(68))
        assertEquals("0", WidgetCaptions.score(0))
        assertEquals("—", WidgetCaptions.score(null))
    }

    @Test
    fun anUnscoredRingDrawsNoArc() {
        assertEquals(0, WidgetCaptions.ringProgress(null))
        assertEquals(68, WidgetCaptions.ringProgress(68))
    }

    @Test
    fun aRingNeverDrawsPastItsCircle() {
        assertEquals(100, WidgetCaptions.ringProgress(140))
        assertEquals(0, WidgetCaptions.ringProgress(-5))
    }

    @Test
    fun theHeartRateIsTheNumberOrADash() {
        assertEquals("62", WidgetCaptions.heartRate(62))
        assertEquals("—", WidgetCaptions.heartRate(null))
    }

    @Test
    fun aRingIsSpokenAsItsCaptionAndItsValue() {
        assertEquals("Заряд, 68%", WidgetCaptions.spoken("Заряд", "68%", "Нет данных"))
    }

    @Test
    fun aMissingValueIsSpokenAsNoDataNotAsADash() {
        // TalkBack reads a dash as nothing, or as "dash": the words say what the dash means.
        assertEquals("Charge, No data", WidgetCaptions.spoken("Charge", null, "No data"))
    }

    @Test
    fun aBriefExcerptIsItsFirstLinesThatSaySomething() {
        val brief = "Charge is 68%.\n\n  Sleep was short.  \n\nKeep today easy.\nDrink water.\nFifth line."
        assertEquals(
            "Charge is 68%.\nSleep was short.\nKeep today easy.\nDrink water.",
            WidgetCaptions.briefExcerpt(brief),
        )
    }

    @Test
    fun aShortBriefIsShownWhole() {
        assertEquals("One line.", WidgetCaptions.briefExcerpt("One line."))
        assertEquals("", WidgetCaptions.briefExcerpt("  \n\n "))
    }
}
