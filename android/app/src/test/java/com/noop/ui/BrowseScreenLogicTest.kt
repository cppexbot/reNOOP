package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/** The pure half of Browse: which rows exist, how a query matches, and the order results come in. */
class BrowseScreenLogicTest {

    private val en = Locale.ENGLISH
    private val ru = Locale.forLanguageTag("ru")

    private val englishTitles = mapOf(
        BrowseDestination.AllMetrics to "All Metrics",
        BrowseDestination.Coach to "Coach",
        BrowseDestination.Journal to "Journal",
        BrowseDestination.LabResults to "Lab Results",
        BrowseDestination.Trends to "Trends",
        BrowseDestination.WhatMovesYou to "What Moves You",
        BrowseDestination.Devices to "Devices",
        BrowseDestination.HeartRate to "Heart Rate",
        BrowseDestination.Mindfulness to "Mindfulness",
    )

    private val russianTitles = mapOf(
        BrowseDestination.AllMetrics to "Все показатели",
        BrowseDestination.Coach to "ИИ-тренер",
        BrowseDestination.Journal to "Журнал",
        BrowseDestination.LabResults to "Результаты анализов",
        BrowseDestination.Trends to "Тренды",
        BrowseDestination.WhatMovesYou to "Что вами движет",
        BrowseDestination.Devices to "Устройства",
        BrowseDestination.HeartRate to "Пульс",
        BrowseDestination.Mindfulness to "Осознанность",
    )

    private val catalogue = listOf(
        BrowseMetricEntry("recovery", "Charge", "Charge"),
        BrowseMetricEntry("hrv", "HRV", "Charge"),
        BrowseMetricEntry("rhr", "Resting HR", "Charge"),
        BrowseMetricEntry("resp_rate", "Respiratory Rate", "Charge"),
        BrowseMetricEntry("avg_hr", "Average Heart Rate", "Heart"),
        BrowseMetricEntry("max_hr", "Max Heart Rate", "Heart"),
    )

    @Test
    fun categoriesAndToolsMatchIos() {
        assertEquals(
            setOf(
                BrowseDestination.AllMetrics, BrowseDestination.Coach, BrowseDestination.Journal,
                BrowseDestination.LabResults, BrowseDestination.Trends, BrowseDestination.WhatMovesYou,
            ),
            browseRows(BrowseGroup.Categories, coachEnabled = true).toSet(),
        )
        assertEquals(
            setOf(BrowseDestination.Devices, BrowseDestination.HeartRate, BrowseDestination.Mindfulness),
            browseRows(BrowseGroup.Tools, coachEnabled = true).toSet(),
        )
    }

    @Test
    fun coachRowFollowsTheMasterSwitchAndNothingElseDoes() {
        val on = browseRows(BrowseGroup.Categories, coachEnabled = true)
        val off = browseRows(BrowseGroup.Categories, coachEnabled = false)
        assertTrue(BrowseDestination.Coach in on)
        assertEquals(on - BrowseDestination.Coach, off)
        assertEquals(
            browseRows(BrowseGroup.Tools, coachEnabled = true),
            browseRows(BrowseGroup.Tools, coachEnabled = false),
        )
    }

    @Test
    fun coachIsNotFoundBySearchWhileOff() {
        val result = browseSearch("coach", en, coachEnabled = false, titleOf = { englishTitles.getValue(it) }, catalogue = catalogue)
        assertTrue(result.screens.isEmpty())
        assertTrue(result.isEmpty)
    }

    @Test
    fun rowsSortByLocalizedTitle() {
        val sortedEn = sortedByTitle(browseRows(BrowseGroup.Tools, true), en) { englishTitles.getValue(it) }
        assertEquals(listOf(BrowseDestination.Devices, BrowseDestination.HeartRate, BrowseDestination.Mindfulness), sortedEn)
        val sortedRu = sortedByTitle(browseRows(BrowseGroup.Tools, true), ru) { russianTitles.getValue(it) }
        // Осознанность, Пульс, Устройства.
        assertEquals(listOf(BrowseDestination.Mindfulness, BrowseDestination.HeartRate, BrowseDestination.Devices), sortedRu)
        val categoriesRu = sortedByTitle(browseRows(BrowseGroup.Categories, true), ru) { russianTitles.getValue(it) }
        // Все показатели, Журнал, ИИ-тренер, Результаты анализов, Тренды, Что вами движет (Ж before И).
        assertEquals(
            listOf(
                BrowseDestination.AllMetrics, BrowseDestination.Journal, BrowseDestination.Coach,
                BrowseDestination.LabResults, BrowseDestination.Trends, BrowseDestination.WhatMovesYou,
            ),
            categoriesRu,
        )
    }

    @Test
    fun matchingIgnoresCaseDiacriticsAndSurroundingSpace() {
        assertTrue(browseMatches("Heart Rate", "  heart ", en))
        assertTrue(browseMatches("Frequência cardíaca", "cardiaca", Locale.forLanguageTag("pt-PT")))
        assertTrue(browseMatches("Écran", "ecran", Locale.FRENCH))
        assertTrue(browseMatches("Ёжик", "еж", ru))
        assertTrue(browseMatches("Осознанность", "ОСОЗ", ru))
        assertFalse(browseMatches("Heart Rate", "   ", en))
        assertFalse(browseMatches("Heart Rate", "pulse", en))
    }

    @Test
    fun searchListsScreensFirstThenMetricsEachAlphabetical() {
        val result = browseSearch("rate", en, coachEnabled = true, titleOf = { englishTitles.getValue(it) }, catalogue = catalogue)
        assertEquals(listOf(BrowseDestination.HeartRate), result.screens)
        assertEquals(listOf("avg_hr", "max_hr", "resp_rate"), result.metrics.map { it.key })
    }

    @Test
    fun searchKeepsOneRowPerMetricKey() {
        val doubled = catalogue + BrowseMetricEntry("hrv", "HRV", "Charge")
        val result = browseSearch("hrv", en, coachEnabled = true, titleOf = { englishTitles.getValue(it) }, catalogue = doubled)
        assertEquals(listOf("hrv"), result.metrics.map { it.key })
    }
}
