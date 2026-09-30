package com.noop.ui

import com.noop.R
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import android.widget.Toast
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.analytics.FitnessAgeEngine
import com.noop.analytics.FitnessAgeReadiness
import com.noop.analytics.FitnessReadinessItem
import com.noop.analytics.FitnessReadinessRole
import com.noop.analytics.FitnessReadinessStatus
import com.noop.analytics.SkinTempDisplay
import com.noop.analytics.VitalBands
import com.noop.data.DailyMetric
import com.noop.data.Vo2MaxEstimator
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow


// MARK: - Metric detail (vital_detail/<key>)
//
// Every Today metric card opens its own focused trend here: a chart over the recent days, the readings
// table and the empty state that names why a vital cannot fill. What remains of the old Health screen,
// which the iOS redesign removed (its stale routes land on All Metrics); the metric page rebuild replaces
// this later. The cycle opt-in gate and the Fitness Age bound symbol, which Today and Settings still
// read, moved here with it.

/**
 * #801: whether the cycle-awareness OPT-IN invitation should be offered for a profile with this [sex]
 * value. Cycle phase is read from the menstrual skin-temperature shift, so the invitation is NOT offered
 * for a male profile; "female"/"nonbinary" (and any unrecognised value, default-show rather than hide)
 * qualify. Pure so it's unit-tested directly; mirrors the iOS SkinTempSection.cycleOptInApplies
 * (`profile.sex.lowercased() != "male"`). ProfileStore.sex is "male" | "female" | "nonbinary".
 */
internal fun cycleOptInApplies(sex: String): Boolean = sex.lowercase(Locale.US) != "male"

/** #hide-cycle: whether the cycle-awareness OFFER is VISIBLE — eligible by sex AND not hidden by the
 *  user's "not for me" opt-out. USER-controlled, never age-based. Pure, unit-tested; twin of iOS
 *  ProfileStore.cycleAwarenessVisible(sex:hidden:). */
internal fun cycleAwarenessVisible(sex: String, hidden: Boolean): Boolean =
    cycleOptInApplies(sex) && !hidden

/**
 * The symbol a stored Fitness Age needs when it is sitting on a reporting bound (#2173).
 *
 * `FitnessAgeEngine` clamps to [minAge, maxAge], so every model output below 20 is stored as exactly
 * 20.0 and every output above 80 as exactly 80.0. A reader cannot tell those from a genuine 20 or 80,
 * and the number looks as exact as any other, which is what makes a floored reading read like a sync
 * or scoring fault rather than the edge of the scale.
 *
 * Decided from the value rather than carried out of the engine deliberately. The clamp returns the
 * bound constant itself, so equality is exact and needs no tolerance, and deciding here covers the
 * weekly rows already persisted, which no flag added today could reach. The cost is that a reading
 * that is genuinely 20.0 is also called "20 or younger", which is true of it, so nothing is claimed
 * that is not known. Saying "<20" would need the unclamped value, and that is gone by the time
 * anything is stored.
 */
internal fun fitnessAgeBoundSymbol(value: Double): String = when {
    value <= FitnessAgeEngine.minAge -> "≤"
    value >= FitnessAgeEngine.maxAge -> "≥"
    else -> ""
}

internal data class VitalDetailModel(
    val key: String,
    val title: String,
    val unit: String,
    val color: Color,
    val readings: List<VitalReading>,
    val format: (Double) -> String,
    /** #1847: why the screen is not showing what Settings asked for. Null when it is. */
    val fallbackNote: String? = null,
) {
    /** (day, value) projection the trend chart + range helpers consume — SAME order as [readings], so the
     *  chart, the header count, and the table can never drift apart. */
    val points: List<Pair<String, Double>> get() = readings.map { it.day to it.value }
}

/** Metric-detail keys that are NOT plain DailyMetric columns but series the engines/importers persist
 *  (Fitness Age + Vitality under the computed strap, Steps estimate, Apple active energy). Each Today
 *  dashboard card taps through to ITS OWN focused trend here (2026-07-03), so these load their
 *  series from the repo on demand rather than off the cached `days` columns. Mirrors iOS metricDetail. */
// #1391/#1404: vo2max_est is a COMPUTED weekly series under the "-noop" spine, like fitness_age/vitality —
// so its detail must route to buildSeriesVitalDetail (which reads metricSeriesComputedUnion), NOT the
// DailyMetric-backed buildVitalDetail. #1404 added the vo2max_est CASE to the series builder but omitted it
// here, so isSeriesBacked was false and the tap-through fell to the DailyMetric builder → empty trend.
private val SERIES_BACKED_VITAL_KEYS = setOf("fitness_age", "vitality", "steps_est", "active_kcal", "rest", "vo2max_est")

/**
 * #1617: which empty-state copy a vital with fewer than two readings should show.
 *
 * The default ("not enough history yet") is honest for any vital NOOP can actually chart from this
 * strap - keep wearing it and readings accumulate. Note the test is chartable, NOT measured: a WHOOP
 * 4.0 measures blood oxygen and still cannot fill that card. For Blood Oxygen the default can be a
 * countdown that never completes:
 *
 *  - **WHOOP 4.0.** What is missing is a second CHANNEL, not a conversion. `HIST_V24` declares
 *    `spo2RedOff = 68` / `spo2IrOff = 70` and both fields carry plausible varying values, which is why
 *    this originally read as "the maths is simply unimplemented". Three captures from two contributors
 *    on two platforms say otherwise - two of them overnight (11.2 h and 7.9 h, worn and asleep) and one
 *    spanning a full 22 h day and night: `ir` is `red` plus a constant. Across 1172 consecutive
 *    sample transitions in one 22-hour capture, both moved by the IDENTICAL amount 1171 times - the only
 *    exception being the single moment the offset itself stepped (110 -> 132) - and within each segment
 *    `corr(red, ir)` is exactly +1.000. The offset also differs between captures (100 / 110 / 132), so
 *    `k` is a property of the DATA rather than a constant our decode introduced.
 *
 *    What that does not settle - and does not need to - is WHY the two track. A second emitter locked to
 *    the first, or a strap-derived value at offset 70 computed from the one at 68, fit the evidence
 *    equally well, and nothing here can separate them. It does not matter: either way offset 70 carries
 *    no information offset 68 lacks, which is the only question a percentage depends on. Resist the urge
 *    to resolve it before concluding, since the conclusion does not turn on it.
 *
 *    Ratio-of-ratios needs two INDEPENDENT wavelengths. When `ir = red + k` the ratio is a deterministic
 *    function of `red` alone and carries no oxygenation information, so anything computed from it would
 *    restate the red channel while looking like a percentage - the exact failure #194 was withdrawn for.
 *    A scan of every u16 offset in the 104-byte record found no independent channel either: the best
 *    candidate by variety correlates +0.975 and +0.874 with `ir` (one figure per offset segment), and
 *    the genuinely uncorrelated fields
 *    have 0-65331 ranges (counters or CRC material, not optical magnitudes).
 *
 *    So waiting cannot help and importing can - and the reason is the banked record, NOT an absent
 *    sensor and NOT missing arithmetic. The strap-computed `@82` percentage that does exist is gated to
 *    `hist_version == 18`, a 5/MG layout. This bounds the record type examined, not the hardware: a live
 *    stream or another record type remains untested (#1617).
 *  - **5/MG with the estimate off.** The candidate exists but ships default-off and unverified, so the
 *    screen stays empty until the user turns it on. Naming the switch beats implying more nights.
 *  - **5/MG with it on.** Genuinely just needs nights, so the default copy is right.
 *
 * [family] must come from the REGISTRY (`DeviceFamily.forRegistryDevice`), never a live-connection
 * flag: such a flag reads false for a 4.0, for an Oura ring and for nothing-connected alike, and an
 * Oura DOES produce SpO2 (`nightlySpo2CeilingMean`'s 0x6F ceiling@100). Telling that user their
 * WHOOP 4.0 lacks the sensor would be worse than the countdown this replaces. A null family - a
 * positively non-WHOOP brand, or a row not yet loaded - therefore falls through to the neutral copy
 * rather than claiming a generation that has not been established (#1086/#171).
 *
 * Pure and Compose-free so the decision is unit-tested without a device or a strap. Android-only:
 * iOS's metric detail already points at import rather than promising accumulation.
 */
internal data class VitalEmptyState(@StringRes val titleRes: Int, @StringRes val bodyRes: Int)

internal fun spo2EmptyState(
    key: String,
    family: com.noop.protocol.DeviceFamily?,
    candidateDisplayOn: Boolean,
): VitalEmptyState {
    val default = VitalEmptyState(
        R.string.l10n_health_screen_not_enough_history_yet_0e2f93b6,
        R.string.l10n_health_screen_this_vital_needs_at_least_two_0e41b8b0,
    )
    if (key != "spo2") return default
    return when {
        family == com.noop.protocol.DeviceFamily.WHOOP4 -> VitalEmptyState(
            R.string.l10n_health_screen_no_blood_oxygen_percentage_from_a_1d3d383e,
            R.string.l10n_health_screen_your_strap_banks_the_raw_optical_b52a0f80,
        )
        family == com.noop.protocol.DeviceFamily.WHOOP5 && !candidateDisplayOn -> VitalEmptyState(
            R.string.l10n_health_screen_the_blood_oxygen_estimate_is_turned_4c403ab2,
            R.string.l10n_health_screen_your_strap_reports_a_blood_oxygen_349fe34a,
        )
        else -> default
    }
}

@Composable
fun VitalDetailScreen(vm: AppViewModel, key: String) {
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val tempUnit = UnitPrefs.temperature(context)
    // The Effort detail renders per the user's Effort display scale (0-100 vs 0-21), like the Today tile.
    val effortScale = UnitPrefs.effortScale(context)
    // #103/queue-11a follow-up: same reactive source the Key Metrics tile already collects (empty when
    // the toggle is OFF, since the engine writes nothing) — reused here so this screen's spo2 candidate
    // fallback (in buildVitalDetail) stays in sync with the tile it drills in from.
    //
    // The FLOW is swapped per metric, not the collect call. Only the Blood Oxygen detail reads this map,
    // but this composable serves every vital, and subscribing the real flow runs a database union
    // (`metricSeriesComputedUnion`) that Resting HR / HRV / Skin Temp would pay for and discard —
    // `WhileSubscribed(5_000)` means arriving more than five seconds after the tile unsubscribed re-runs
    // it, which is the normal Today → Health → tap path. Gating the CALL instead (`key == "spo2" && …`)
    // would put a composable in a conditionally-evaluated position and corrupt the slot table when the
    // key changes; swapping the flow keeps exactly one unconditional call site. It also keeps the
    // `remember` below stable for every other vital, since the map is then a constant.
    val candidateFlow: StateFlow<Map<String, Double>> = remember(key) {
        if (key == "spo2") vm.spo2CandidateByDay else MutableStateFlow(emptyMap())
    }
    val spo2CandidateByDay by candidateFlow.collectAsStateWithLifecycle()
    // Profile drives the Fitness Age readiness/countdown shown when that vital has no value yet.
    val profile = remember { ProfileStore.from(context.applicationContext) }
    val isSeriesBacked = key in SERIES_BACKED_VITAL_KEYS
    val isStepsDetail = key == "steps_est"
    // #1617: the ACTIVE strap's family, resolved brand-aware from the registry rather than from a live
    // flag. Null until the row loads, and null for a non-WHOOP device; both fall through to the neutral
    // empty-state copy, so this never claims a generation it has not established.
    //
    // Collected from activeStrapIdFlow, NOT the `activeStrapId` getter: that getter is documented as
    // source-compatibility for existing call sites, and reading it here would not re-key this on a strap
    // switch, so the copy could keep describing the previous device.
    //
    // The registry read is skipped for every other vital. Only the Blood Oxygen empty state consults the
    // family, and a DB round-trip that Resting HR / HRV / Skin Temp pay for and discard is the same waste
    // the candidateFlow above is shaped to avoid. The produceState CALL stays unconditional - gating the
    // call would put a composable in a conditionally-evaluated position and corrupt the slot table when
    // the key changes - so only the work inside it is conditional.
    val activeStrapId by vm.activeStrapIdFlow.collectAsStateWithLifecycle()
    val strapFamily by produceState<com.noop.protocol.DeviceFamily?>(null, activeStrapId, key) {
        value = if (key != "spo2" || activeStrapId == null) {
            null
        } else {
            val row = runCatching { vm.pairedDevices() }.getOrDefault(emptyList())
                .firstOrNull { it.id == activeStrapId }
            com.noop.protocol.DeviceFamily.forRegistryDevice(row?.model, row?.brand)
        }
    }

    // Series-backed metrics are loaded async from metricSeries; the plain daily vitals build synchronously
    // off the cached `days`. `seriesLoaded` guards the empty-state so a still-loading trend doesn't flash
    // "not enough history" before its rows arrive.
    var seriesDetail by remember(key) { mutableStateOf<VitalDetailModel?>(null) }
    var seriesLoaded by remember(key) { mutableStateOf(false) }
    // Manual-refresh plumbing for the Fitness Age not-ready state (readiness branch below): the refresh
    // button recomputes then bumps this tick, re-running the series read so a fresh value shows at once.
    var refreshTick by remember { mutableStateOf(0) }
    var refreshing by remember { mutableStateOf(false) }
    if (isSeriesBacked) {
        LaunchedEffect(key, refreshTick) {
            seriesDetail = buildSeriesVitalDetail(vm, key)
            seriesLoaded = true
        }
    }
    // #1846: read the preference OUTSIDE remember (a Composable call is not allowed in its calculation)
    // and make it a KEY, so flipping the setting rebuilds the model instead of serving a cached one.
    val skinTempPreferred = UnitPrefs.skinTempPreferred(LocalContext.current)
    val detail = if (isSeriesBacked) seriesDetail
    else remember(days, key, tempUnit, effortScale, spo2CandidateByDay, skinTempPreferred) {
        buildVitalDetail(days, key, tempUnit, effortScale, spo2CandidateByDay, skinTempPreferred)
    }
    var range by remember { mutableStateOf(VitalDetailRange.MONTH) }

    // The subtitle tracks how much history the metric has, so we never promise a "historical trend" the
    // view isn't showing: Fitness Age with no reading yet -> what it still needs; ANY metric with a single
    // reading -> that reading (trend to follow); two+ -> the trend. Pre-load falls through to trend.
    val loadedPoints = if (seriesLoaded) (detail?.points?.size ?: 0) else -1
    // #430 parity: the detail carries the SAME backdrop as the screen that pushed it — the day-cycle sky
    // when the setting is on (full-viewport when "Sky behind cards" is also on, so the transparent cards
    // reveal it the whole way down; the top band otherwise), the plain canvas when off. Same gates the
    // Today screen uses.
    val showDayCycleBackground = remember { NoopPrefs.showDayCycleBackground(context) }
    val skyBehindCards = remember { NoopPrefs.skyBehindCards(context) }
    ScreenScaffold(
        title = detail?.title ?: if (isStepsDetail) uiString(R.string.l10n_health_screen_steps_cdde4f20) else uiString(R.string.l10n_health_screen_vital_signs_e7d9e1b1),
        subtitle = when {
            isStepsDetail -> uiString(R.string.steps_history)
            key == "fitness_age" && loadedPoints == 0 -> "What your Fitness Age still needs."
            loadedPoints == 1 -> "Your latest reading — trend to follow."
            else -> "Historical trend from cached daily metrics."
        },
        topBackground = screenBackdropSlot(showDayCycleBackground, skyBehindCards),
        // Sky-behind-cards needs the full-viewport container too — the band container's status-bar
        // offset left the lower cards on plain canvas (tester report).
        fullBleedBackground = screenBackdropFullBleed(showDayCycleBackground, skyBehindCards),
    ) {
        if (isSeriesBacked && !seriesLoaded) {
            DataPendingNote(
                title = uiString(if (isStepsDetail) R.string.steps_loading_title else R.string.l10n_health_screen_loading_33ce4174),
                body = if (isStepsDetail) uiString(R.string.steps_loading) else "Fetching this metric's history.",
            )
            return@ScreenScaffold
        }
        if (detail == null || detail.points.isEmpty()) {
            if (isStepsDetail) {
                DataPendingNote(title = uiString(R.string.steps_empty_title), body = uiString(R.string.steps_empty_body))
                return@ScreenScaffold
            }
            // Fitness Age with NO value yet (zero points): show the readiness checklist + the "N more
            // nights of wear" countdown — what it actually needs — instead of the generic "needs two
            // readings to chart" note, which describes the trend line and left the Today card's tap-through
            // a dead end. (A single reading is handled below, generically, for every metric.)
            if (key == "fitness_age" && (detail?.points?.isEmpty() != false)) {
                val (rhrDays, readiness) = rememberFitnessReadiness(days, profile)
                FitnessReadinessCard(
                    readiness = readiness, headed = true,
                    lead = fitnessReadyLead(rhrDays, profile.age > 0, profile.sex.isNotBlank()),
                    refreshing = refreshing,
                    onRefresh = {
                        refreshing = true
                        vm.refreshFitnessAgeNow { wrote ->
                            refreshing = false
                            refreshTick++
                            Toast.makeText(
                                context,
                                if (wrote) "Fitness Age updated."
                                else "Not enough wear yet — keep your strap on overnight.",
                                Toast.LENGTH_SHORT,
                            ).show()
                        }
                    },
                )
                return@ScreenScaffold
            }
            // ANY metric with exactly ONE reading: the Today card already shows this value, so the generic
            // "Not enough history yet" note read as a contradiction on tap-through — only the TREND CHART
            // needs a second point. Show the value + when the chart fills in, never a no-data dead end.
            // Matches iOS, which renders the value hero at a single point. First hit on Fitness Age, then
            // Vitality — both weekly-ish computed scores that sit at one reading for a while.
            if (!isStepsDetail && detail != null && detail.points.size == 1) {
                val one = detail.points.last()   // size 1: the single reading (last == the latest)
                NoopCard {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Overline("Latest")
                        Text(
                            text = uiString(R.string.l10n_health_screen_detail_format_one_second_detail_unit_6fde90d3, detail.format(one.second), detail.unit).trim(),
                            style = NoopType.chartValueLarge,
                            color = detail.color,
                        )
                        Text(
                            text = uiString(R.string.l10n_health_screen_as_of_one_first_2b409612, one.first),
                            style = NoopType.footnote,
                            color = Palette.textTertiary,
                        )
                        Text(
                            text = uiString(R.string.l10n_health_screen_one_reading_so_far_your_trend_eaad57f2) +
                                " reading lands.",
                            style = NoopType.subhead,
                            color = Palette.textSecondary,
                        )
                    }
                }
                return@ScreenScaffold
            }
            // #1617: "Not enough history yet" is a countdown, and on a WHOOP 4.0 Blood Oxygen is a
            // countdown that never completes. See spo2EmptyState for why. Copy only; nothing about what
            // is stored or scored moves.
            val emptyState = spo2EmptyState(
                key = key,
                family = strapFamily,
                candidateDisplayOn = NoopPrefs.spo2CandidateDisplay(context),
            )
            DataPendingNote(
                title = uiString(emptyState.titleRes),
                body = uiString(emptyState.bodyRes),
            )
            return@ScreenScaffold
        }

        // #943 (ryanbr): gate the range chips by available history so short history can't draw six
        // byte-identical charts. A locked selection (e.g. the MONTH default during the first week)
        // coerces DOWN to the largest unlocked range so a calibrating user always has a live chart.
        val unlockedRanges = remember(detail) { unlockedVitalRanges(vitalHistorySpanDays(detail.points)) }
        val effectiveRange = coercedVitalRange(range, unlockedRanges)
        // The trend chart, the "N readings" header, AND the readings table all derive from this ONE
        // windowed list, so the count and the rows can never disagree (task #8). filteredPoints is just
        // its (day, value) projection for the existing chart/stat code.
        val filteredReadings = remember(detail, effectiveRange, isStepsDetail) {
            if (isStepsDetail) filterStepReadings(detail.readings, effectiveRange)
            else filterVitalReadings(detail.readings, effectiveRange)
        }
        val stepsSeries = remember(detail, effectiveRange, isStepsDetail) {
            if (isStepsDetail) projectStepsDetail(detail.readings, effectiveRange) else null
        }
        val filteredPoints = stepsSeries?.points ?: filteredReadings.map { it.day to it.value }
        if (filteredPoints.isEmpty() || (!isStepsDetail && filteredPoints.size < 2)) {
            DataPendingNote(
                title = uiString(R.string.l10n_health_screen_not_enough_history_in_this_range_2da72f80),
                body = if (isStepsDetail) uiString(R.string.steps_empty_range) else "Try a longer interval like 3M, 6M, 1Y, or ALL to see this vital’s trend.",
            )
            return@ScreenScaffold
        }

        val values = filteredPoints.map { it.second }
        // #1600: remembered, unlike the plain projections above it. `shortDayLabel` parses a LocalDate and
        // runs a DateTimeFormatter PER POINT, so leaving it inline would re-parse every day in the window
        // on every recomposition — and the recompositions that matter are the ones a finger dragging
        // across this chart produces. Keyed on `filteredPoints`, whose structural equality holds it stable
        // across recompositions that do not change the window.
        val dayLabels = remember(filteredPoints) { filteredPoints.map { shortDayLabel(it.first) } }
        val latest = filteredPoints.last()
        val latestLabel = stepsSeries?.selectionLabels?.lastOrNull() ?: latest.first
        val min = values.minOrNull()
        val max = values.maxOrNull()
        val avg = values.average()

        if (!isStepsDetail) SectionHeader(
            detail.title,
            overline = "Vital Signs",
            trailing = stepsSeries?.let { "${it.buckets.size} bars" } ?: "${filteredReadings.size} readings",
        )
        NoopCard {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.Top) {
                    Column(modifier = Modifier.weight(1f)) {
                        Overline(uiString(R.string.steps_latest))
                        Text(
                            text = uiString(R.string.l10n_health_screen_detail_format_latest_second_detail_unit_9664278b, detail.format(latest.second), detail.unit).trim(),
                            style = NoopType.chartValueLarge,
                            color = detail.color,
                        )
                        Text(
                            text = uiString(if (isStepsDetail) R.string.steps_as_of else R.string.l10n_health_screen_as_of_latest_first_726f20bb, latestLabel),
                            style = NoopType.footnote,
                            color = Palette.textTertiary,
                        )
                        detail.fallbackNote?.let { note ->
                            Text(
                                text = note,
                                style = NoopType.footnote,
                                color = Palette.textTertiary,
                                modifier = Modifier.padding(top = 6.dp),
                            )
                        }
                    }
                }
                SegmentedPillControl(
                    items = VitalDetailRange.entries,
                    selection = effectiveRange,
                    label = { if (isStepsDetail) context.resources.getStringArray(R.array.steps_ranges)[it.ordinal] else it.label },
                    onSelect = { range = it },
                    adaptsToAvailableWidth = true,
                    enabled = { it in unlockedRanges },
                )
                if (unlockedRanges.size < VitalDetailRange.entries.size) {
                    Text(
                        uiString(if (isStepsDetail) R.string.steps_ranges_hint else R.string.l10n_health_screen_longer_ranges_unlock_as_more_history_d7da5fee),
                        style = NoopType.footnote,
                        color = Palette.textTertiary,
                    )
                }
                // BARS or a line is the user's chart-style setting, and nothing else. #2008's follow-up
                // decided it per METRIC here, forcing bars for the daily scores because a line asserts a
                // continuity a daily score never travelled. That reasoning holds and the slot layout below
                // is unchanged, but this screen had never read the setting, so a chosen LINE drew bars and
                // a chosen BAR drew lines for every other metric. Trends applies the same preference to
                // every metric, so a detail chart reached from a Today ring now agrees with the trend chart
                // for that metric instead of contradicting it. See `vitalChartIsBars`.
                //
                // Read on recompose exactly as Trends reads it: SharedPreferences is not reactive, and
                // reaching Settings means leaving this screen, so returning re-reads it. `chartStyle` is a
                // remember key so flipping the setting rebuilds or drops the slots rather than serving the
                // previous shape.
                //
                // One slot per DAY positions bars by date and turns a missing day into an empty slot.
                // Remembered like `dayLabels` beside it: densifying rebuilds a slot per day and formats a
                // label for each, and on the ALL range that is hundreds of both. The slot count follows the
                // RANGE rather than the metric, so a sparse series costs no more than a daily one.
                val chartStyle = UnitPrefs.trendChartStyle(LocalContext.current)
                // Folded over the FULL history, not the visible window: the reference is the reader's
                // normal, which does not change because they narrowed the range to a week. Null for every
                // metric but HRV and resting HR, and null until the baseline is trusted.
                val baseline = remember(detail.readings, key) { vitalBaseline(key, detail.readings) }
                val bars = remember(filteredReadings, stepsSeries, key, chartStyle) {
                    when {
                        stepsSeries != null -> stepsSeries.points
                        vitalChartIsBars(key, chartStyle) -> densifyByDay(filteredReadings)
                        else -> null
                    }
                }
                val barValues = remember(bars) { bars?.map { it.second } }
                val barLabels = remember(bars, stepsSeries) {
                    stepsSeries?.selectionLabels ?: bars?.map { shortDayLabel(it.first) }
                }
                if (barValues != null && barLabels != null) {
                    val chart: @Composable () -> Unit = {
                        BarChart(
                            baselineValue = baseline,
                            values = barValues,
                            modifier = Modifier.height(if (isStepsDetail) 300.dp else Metrics.chartHeight),
                            color = detail.color,
                            selectionEnabled = true,
                            selectionLabels = barLabels,
                            axisStep = if (isStepsDetail) 5000.0 else null,
                            showValueLabels = isStepsDetail && (effectiveRange == VitalDetailRange.WEEK || effectiveRange == VitalDetailRange.TWO_WEEK),
                            largeSelectionReadout = isStepsDetail,
                            formatValue = { value ->
                                stepsSeries?.let {
                                    if (it.granularity == com.noop.analytics.StepsDetailGranularity.DAILY) stepsBucketValueLabel(value, it.granularity)
                                    else uiString(R.string.steps_chart_mean, java.text.NumberFormat.getIntegerInstance().format(value))
                                }
                                    ?: "${detail.format(value)} ${detail.unit}".trim()
                            },
                        )
                    }
                    if (stepsSeries != null) {
                        Box(
                            modifier = Modifier.clearAndSetSemantics {
                                contentDescription = stepsSeries.accessibilitySummary
                            },
                        ) { chart() }
                    } else {
                        chart()
                    }
                } else {
                LineChart(
                    values = values,
                    modifier = Modifier.height(Metrics.chartHeight),
                    color = detail.color,
                    fill = true,
                    selectionEnabled = true, // the Vital Signs detail chart is meant to be tappable
                    // #1600: name the DAY on the scrub readout. `lineChartSelectionLabel` prints
                    // "label · value" when given one and the bare value otherwise, so a chart that opts
                    // into selection without labels answers "96" — a number with nothing to say which day
                    // it belongs to, against a Trends chart that reads "16 Jul · 92" beside it.
                    //
                    // Derived from `filteredPoints`, the same (day, value) list `values` comes from, so the
                    // two are equal in length by construction rather than by luck — `LineChart` drops
                    // mismatched labels SILENTLY, which is a failure that looks exactly like doing nothing.
                    selectionLabels = dayLabels,
                    // Position by DATE, not by reading index: a four-day gap now occupies four days of
                    // width, which is what makes the break across it read as "nothing measured here"
                    // rather than as a chopped line. Days that do not parse fall back to index spacing.
                    timestamps = dayEpochSeconds(filteredReadings),
                    // #1662: the metric's OWN formatter AND unit — byte-for-byte what the Min/Avg/Max
                    // row below renders. Without it the scrub read-out falls back to LineChart's
                    // default, which prints a decimal for any non-integer, so a rounded metric answered
                    // "72.4" on tap with "72 ms" written directly underneath.
                    formatValue = { "${detail.format(it)} ${detail.unit}".trim() },
                    // VO2max breaks on an estimator change; every other metric breaks on a missing day,
                    // so the line stops asserting a value for days that were never measured.
                    // Only VO2max breaks, on an estimator change. Breaking on a missing DAY was tried and
                    // removed: with points positioned by date a gap already shows as a longer run between
                    // two readings, and breaking as well fragmented the line into pieces with the odd
                    // orphan dot, which reads as a rendering fault rather than as missing data.
                    segmentIds = if (key == "vo2max_est") vo2MaxTrendSegmentIds(filteredReadings) else null,
                    // Anchor the metrics whose natural range IS their interesting range, so a calm one
                    // stops being drawn as violently as a wild one.
                    yDomain = vitalChartYDomain(key),
                    baselineValue = baseline,
                    // A daily trend has few enough readings for a marker each, and they are what say where
                    // the measurements actually are once gaps stretch the line between them.
                    showsPoints = true,
                )
                }
                // #1662: the VO2max line is SPLIT on purpose wherever the estimator changes, so two
                // non-adjacent Nes runs are never joined across an incompatible Uth stretch. Nothing said
                // so, and a silent gap in a trend is indistinguishable from a rendering fault - it was
                // reported as "something weird with a broken line". Shown only when a break actually
                // exists, so it explains the chart in front of the reader rather than describing a
                // behaviour they cannot see.
                if (key == "vo2max_est" && vo2MaxTrendHasBreak(filteredReadings)) {
                    Text(
                        text = uiString(R.string.vo2max_method_change_caption),
                        style = NoopType.footnote,
                        color = Palette.textTertiary,
                    )
                }
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(Metrics.divider)
                        .background(Palette.hairline),
                )
                Row(modifier = Modifier.fillMaxWidth()) {
                    listOf(
                        uiString(R.string.steps_min) to min,
                        uiString(R.string.steps_avg) to avg,
                        uiString(R.string.steps_max) to max,
                    ).forEach { (label, metric) ->
                        Column(modifier = Modifier.weight(1f)) {
                            Overline(label, color = Palette.textTertiary)
                            Text(
                                text = metric?.let { listOf(detail.format(it), detail.unit).filter(String::isNotBlank).joinToString(" ") } ?: "—",
                                style = NoopType.bodyNumber,
                                color = Palette.textPrimary,
                            )
                        }
                    }
                }
            }
        }

        // Per-reading breakdown so the provenance behind the trend is visible — whether each reading came
        // from the WHOOP strap, a Health Connect / Apple Health import, or the on-device pipeline — not
        // just the "N readings" count. Rows derive from the SAME [filteredReadings] the header counts,
        // newest first, and reuse [provenanceDisplayLabel] for the source words (task #8).
        val strapId = vm.activeStrapId
        val readingRows = remember(filteredReadings, detail, strapId) {
            vitalReadingRows(filteredReadings, detail.unit, strapId, detail.format)
        }
        VitalReadingsTable(rows = readingRows)
    }
}

/** The readings table below a vital's chart: one row per windowed reading (newest first), each showing
 *  its day, formatted value, and source (tinted by [provenanceLabelTint], so the same source reads the
 *  same colour as the Today rings). Empty [rows] render nothing. */
@Composable
private fun VitalReadingsTable(rows: List<VitalReadingRow>) {
    if (rows.isEmpty()) return
    NoopCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Overline(uiString(R.string.steps_readings))
            // Slim column header naming the three columns — SAME weights as the data rows below so each
            // label sits over its column. Swift twin (MetricExplorerView.readingsTable) mirrors this.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    uiString(R.string.l10n_health_screen_date_eb9a4bc1),
                    style = NoopType.footnote,
                    color = Palette.textSecondary,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    uiString(R.string.l10n_health_screen_value_8dce170d),
                    style = NoopType.footnote,
                    color = Palette.textSecondary,
                )
                Text(
                    uiString(R.string.l10n_health_screen_source_6da13add),
                    style = NoopType.footnote,
                    color = Palette.textSecondary,
                    textAlign = TextAlign.End,
                    modifier = Modifier.weight(1f),
                )
            }
            rows.forEachIndexed { index, row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        row.time,
                        style = NoopType.subhead,
                        color = Palette.textSecondary,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        row.value,
                        style = NoopType.bodyNumber,
                        color = Palette.textPrimary,
                    )
                    val sourceLabel = when (val source = row.source) {
                        is DisplayText.Resource -> uiString(source.id, *source.args.toTypedArray())
                        is DisplayText.Dynamic -> source.value
                    }
                    Text(
                        sourceLabel,
                        style = NoopType.footnote,
                        color = provenanceLabelTint(row.source),
                        textAlign = TextAlign.End,
                        modifier = Modifier.weight(1f),
                    )
                }
                if (index < rows.size - 1) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(Metrics.divider)
                            .background(Palette.hairline),
                    )
                }
            }
        }
    }
}

private fun buildVitalDetail(
    days: List<DailyMetric>,
    key: String,
    tempUnit: TemperatureUnit,
    effortScale: EffortScale = EffortScale.HUNDRED,
    spo2CandidateByDay: Map<String, Double> = emptyMap(),
    // #1846: travels like tempUnit — read from prefs by the caller, never defaulted quietly here, so the
    // setting cannot look wired while doing nothing.
    skinTempPreferred: SkinTempDisplay.Kind = SkinTempDisplay.Kind.ABSOLUTE,
): VitalDetailModel? {
    return when (key) {
    // The Today Key-Metrics Recovery tile's drill-in: the Recovery (Charge) trend timeline, matching the
    // Sleep night-detail pattern. Today's DRIVERS stay on the hero ring's breakdown sheet; this is history.
    "recovery" -> VitalDetailModel(
        key = key,
        title = uiString(R.string.l10n_health_screen_recovery_ea924f72),
        unit = "%",
        color = Palette.chargeColor,
        readings = days.mapNotNull { row -> row.recovery?.let { VitalReading(row.day, it, row.deviceId) } },
        format = { it.roundToInt().toString() },
    )
    // The Today Key-Metrics Effort tile's drill-in: the day-strain trend, rendered per the user's Effort
    // display scale like the tile itself. Readings store the RAW 0-100 composite; only format() scales.
    "strain" -> VitalDetailModel(
        key = key,
        title = uiString(R.string.l10n_health_screen_effort_8c974bc6),
        unit = if (effortScale == EffortScale.HUNDRED) "%" else "",
        color = Palette.effortColor,
        readings = days.mapNotNull { row -> row.strain?.let { VitalReading(row.day, it, row.deviceId) } },
        format = { UnitFormatter.effortDisplay(it, effortScale) },
    )
    "resp" -> VitalDetailModel(
        key = key,
        title = uiString(R.string.l10n_health_screen_respiratory_rate_3fbb532f),
        unit = "rpm",
        color = Palette.metricCyan,
        readings = days.mapNotNull { row -> row.respRateBpm?.let { VitalReading(row.day, it, row.deviceId) } },
        format = { String.format(Locale.US, "%.1f", it) },
    )
    "spo2" -> {
        // #103/queue-11a follow-up: fill in the spo2 candidate fallback for any day with no calibrated
        // spo2Pct — the SAME fallback the Key Metrics tile already shows (found 2026-08-24: an
        // Oura-only or WHOOP-4.0-only install with the toggle ON saw a real number on the tile but an
        // empty/stale screen here, since this branch never got #1568's candidate wiring). Calibrated
        // days always win; this only ADDS days the calibrated column is missing, never overwrites one.
        val calibrated = days.mapNotNull { row -> row.spo2Pct?.let { row.day to VitalReading(row.day, it, row.deviceId) } }.toMap()
        val candidateOnly = spo2CandidateByDay
            .filterKeys { it !in calibrated }
            .map { (day, value) -> day to VitalReading(day, value, SPO2_CANDIDATE_ATTRIBUTION_SOURCE) }
        VitalDetailModel(
            key = key,
            title = uiString(R.string.l10n_health_screen_blood_oxygen_a8ad9ff5),
            unit = "%",
            color = Palette.metricCyan,
            readings = (calibrated.values + candidateOnly.map { it.second }).sortedBy { it.day },
            format = { String.format(Locale.US, "%.0f", it) },
        )
    }
    "rhr" -> VitalDetailModel(
        key = key,
        title = uiString(R.string.l10n_health_screen_resting_heart_rate_9700f4d8),
        unit = "bpm",
        color = Palette.metricRose,
        readings = days.mapNotNull { row -> row.restingHr?.toDouble()?.let { VitalReading(row.day, it, row.deviceId) } },
        format = { it.roundToInt().toString() },
    )
    "hrv" -> VitalDetailModel(
        key = key,
        title = uiString(R.string.l10n_health_screen_heart_rate_variability_20f0069e),
        unit = "ms",
        color = Palette.metricPurple,
        readings = days.mapNotNull { row -> row.avgHrv?.let { VitalReading(row.day, it, row.deviceId) } },
        format = { it.roundToInt().toString() },
    )
    "skin" -> {
        val fahrenheit = tempUnit == TemperatureUnit.FAHRENHEIT
        // #1850: the preference applies across the WINDOW, not just the newest row. Keying the whole
        // screen off the newest night meant a wearer with twenty stored temperatures and one recent night
        // without saw twenty-three deltas — the setting says Temperature and the app HAS temperatures.
        // `leadReading`'s rule lifted to the window: the chosen kind wins whenever any night carries it,
        // the other is still the fallback, so a choice can never empty the screen.
        //
        // An absolute may live in EITHER column (#622: a WHOOP CSV import writes absolute °C into
        // skinTempDevC), so both count here and in the series below.
        val anyAbsolute = days.any { row ->
            row.skinTempC != null || row.skinTempDevC?.let { VitalBands.isAbsoluteSkinTemp(it) } == true
        }
        val anyDeviation = days.any { row ->
            row.skinTempDevC?.let { !VitalBands.isAbsoluteSkinTemp(it) } == true
        }
        if (!anyAbsolute && !anyDeviation) return null
        val leadsAbsolute = when (skinTempPreferred) {
            SkinTempDisplay.Kind.ABSOLUTE -> anyAbsolute
            SkinTempDisplay.Kind.DEVIATION -> !anyDeviation && anyAbsolute
        }
        val kind = if (leadsAbsolute) SkinTempDisplay.Kind.ABSOLUTE else SkinTempDisplay.Kind.DEVIATION
        val unit = SkinTempDisplay.unitSymbol(kind, fahrenheit)
        val skinReadings = if (leadsAbsolute) {
            // An absolute-led series takes EVERY absolute reading, whichever column holds it. A WHOOP CSV
            // import writes absolute °C straight into skinTempDevC (`skin_temp_celsius`, #622 bimodal), so
            // reading skinTempC alone hid a wearer's imported temperatures from a temperature chart — and
            // made the shortened-series note call them "a baseline difference only", which they are not.
            // Mixing is only unsound ACROSS scales; these are the same scale.
            days.mapNotNull { row ->
                (row.skinTempC ?: row.skinTempDevC?.takeIf { VitalBands.isAbsoluteSkinTemp(it) })
                    ?.let { VitalReading(row.day, it, row.deviceId) }
            }
        } else {
            // Genuine deviations only — an imported absolute sitting in this column belongs to the other
            // scale and is excluded, exactly as before.
            days.mapNotNull { row ->
                row.skinTempDevC
                    ?.takeIf { !VitalBands.isAbsoluteSkinTemp(it) }
                    ?.let { value -> VitalReading(row.day, value, row.deviceId) }
            }
        }
        val title = if (kind == SkinTempDisplay.Kind.ABSOLUTE) {
            uiString(R.string.l10n_health_screen_skin_temperature_f59127f6)
        } else {
            uiString(R.string.skin_temp_delta_title)
        }
        VitalDetailModel(
            key = key,
            title = title,
            unit = unit,
            color = Palette.metricAmber,
            readings = skinReadings,
            format = { c -> SkinTempDisplay.numberString(c, kind, fahrenheit, decimals = 1) },
            // #1847: Settings asked for a temperature and none of these nights has one, so the screen shows
            // the deviation instead. Say so — silently falling back is why the setting reads as broken.
            // Nights scored before skinTempC shipped kept only the deviation; a scoring pass refills them.
            fallbackNote = when {
                shouldExplainSkinTempFallback(
                    skinTempPreferred, leadsAbsolute, anyAbsolute,
                ) ->
                    uiString(R.string.l10n_health_screen_no_measured_temperature_for_these_nights_showing_the_differe_69d4efae)
                // Leading with the absolute drops deviation-only nights from the series — which can now
                // include the most recent one. Say why rather than letting history look like it vanished.
                shouldExplainShortenedSkinTempSeries(
                    leadsAbsolute = leadsAbsolute,
                    shownReadings = skinReadings.size,
                    rowsWithEitherNumber = days.count { it.skinTempC != null || it.skinTempDevC != null },
                ) -> uiString(R.string.l10n_health_screen_only_nights_with_a_measured_temperature_are_shown_the_others_b6f7c45b)
                else -> null
            },
        )
    }
    else -> null
    }
}

/** Build a metric-detail trend for a [SERIES_BACKED_VITAL_KEYS] key by reading its persisted series from
 *  the repo (async): Fitness Age + Vitality off the computed strap the IntelligenceEngine writes, Steps
 *  off the resolved step series (imported ∪ estimated), Active Energy off the Apple-Health import. Colours
 *  match each card's dashboard tint. Returns null for an unknown key. */
internal suspend fun buildSeriesVitalDetail(vm: AppViewModel, key: String): VitalDetailModel? = when (key) {
    // The Today Key-Metrics Rest tile's drill-in: the Rest composite (sleep_performance) trend, read via
    // the SAME imported-wins resolvedSeries merge the tile's score/sparkline use, so the detail can never
    // disagree with the tile (#248 lineage). Each reading names its winning source for the caption.
    "rest" -> VitalDetailModel(
        key = key,
        title = uiString(R.string.l10n_health_screen_rest_b79e5f48),
        unit = "%",
        color = Palette.restColor,
        readings = vm.repo.resolvedSeries("sleep_performance", "my-whoop", "0000-00-00", "9999-99-99",
            strapDeviceId = vm.activeStrapId)
            .points.map { VitalReading(it.day, it.value, it.source) },
        format = { it.roundToInt().toString() },
    )
    "fitness_age" -> VitalDetailModel(
        key = key,
        title = uiString(R.string.l10n_health_screen_fitness_age_12383b4a),
        unit = "yrs",
        color = Palette.chargeColor,
        readings = vm.repo.metricSeriesComputedUnion(vm.activeStrapId, "fitness_age", "0000-01-01", "9999-12-31")
            .map { VitalReading(it.day, it.value, it.deviceId) },
        format = { it.roundToInt().toString() },
    )
    "vitality" -> VitalDetailModel(
        key = key,
        title = uiString(R.string.l10n_health_screen_vitality_be320b06),
        unit = "",
        color = Palette.metricPurple,
        readings = vm.repo.metricSeriesComputedUnion(vm.activeStrapId, "vitality", "0000-01-01", "9999-12-31")
            .map { VitalReading(it.day, it.value, it.deviceId) },
        format = { it.roundToInt().toString() },
    )
    // #1391: the VO₂max card (opt-in, #1393) taps through here. Like its sibling computed metrics
    // (fitness_age / vitality above), the weekly estimate is persisted under the "-noop" computed spine
    // (IntelligenceEngine writes "vo2max_est"), so its trend reads the COMPUTED union — not the raw
    // resolvedSeries the imported vitals use, which carries no vo2max_est. Without this case the tap-through
    // fell to the default and the trend chart was empty (the reported bug). Parity with iOS, which handles
    // `.vo2max` alongside `.fitnessAge` / `.vitality` and reads `exploreSeries("vo2max_est")`.
    "vo2max_est" -> {
        val points = vm.repo.metricSeriesComputedUnion(
            vm.activeStrapId, "vo2max_est", "0000-01-01", "9999-12-31",
        )
        VitalDetailModel(
            key = key,
            title = uiString(R.string.l10n_health_screen_vo2max_21214fb6),
            unit = "ml/kg",
            color = Palette.chargeColor,
            readings = points.map { point ->
                val estimator = Vo2MaxEstimator.fromProvenanceId(
                    vm.repo.scoreInputSource(point.deviceId, point.day, point.key),
                )
                VitalReading(point.day, point.value, vo2MaxAttributionSource(estimator))
            },
            // #1662: ONE decimal, matching the iOS catalog's `decimals: 1` for this key. Android rounded
            // to an integer, so a chart plotted at full precision sat under labels that could not move
            // with it: VO2max shifts well under 1 ml/kg between weekly points, so the line visibly sloped
            // while every read-out, the Min/Avg/Max row and the readings table all printed the same
            // number. #1664 made those text surfaces agree with each other; it could not make them agree
            // with the LINE, because the precision was too coarse to express what the line draws.
            format = { String.format(Locale.US, "%.1f", it) },
        )
    }
    "steps_est" -> {
        // #377: the Today Steps tile resolves a REAL step count FIRST — the WHOOP 5/MG on-device @57
        // counter (DailyMetric.steps) ?: imported Health Connect / Apple Health ?: the motion-model
        // estimate (TodayScreen: `day?.steps ?: importedStepsForDay ?: estimatedStepsForDay`). This
        // detail read the estimate ALONE, so a WHOOP 5.0 with a real count saw the estimate history —
        // clamped flat at StepsEstimateEngine.MAX_DAILY_STEPS = 60,000 when the motion fit over-shoots —
        // instead of its real steps. Resolve per day with the SAME precedence so the graph + Readings
        // match the card. iOS already routes this detail through the real "steps" metric (not the
        // estimate); this brings Android to parity. Real strap steps live in DailyMetric.steps; imported
        // steps in AppleDaily; the estimate in the "steps_est" series — three disjoint stores, so the
        // per-day `?:` chain never double-counts.
        val real = vm.repo.resolvedSeries("steps", "my-whoop", "0000-00-00", "9999-99-99",
            strapDeviceId = vm.activeStrapId)
            .points.asSequence()
            .filter { it.value.isFinite() && it.value >= 0.0 }
            .associateBy({ it.day }, { VitalReading(it.day, it.value, it.source) })
        val imported = LinkedHashMap<String, VitalReading>()
        for (r in vm.repo.appleDaily("apple-health", "0000-01-01", "9999-12-31") +
            vm.repo.appleDaily("health-connect", "0000-01-01", "9999-12-31")) {
            val s = r.steps
            if (s != null && s >= 0) imported.putIfAbsent(r.day, VitalReading(r.day, s.toDouble(), r.deviceId))
        }
        val est = vm.repo.resolvedSeries("steps_est", "my-whoop", "0000-00-00", "9999-99-99",
            strapDeviceId = vm.activeStrapId)
            .points.asSequence()
            .filter { it.value.isFinite() && it.value >= 0.0 }
            .associateBy({ it.day }, { VitalReading(it.day, it.value, it.source) })
        VitalDetailModel(
            key = key,
            title = uiString(R.string.l10n_health_screen_steps_cdde4f20),
            unit = uiString(R.string.steps_unit),
            color = Palette.metricCyan,
            readings = mergeStepsReadings(real, imported, est),
            format = { java.text.NumberFormat.getIntegerInstance().format(it.roundToInt()) },
        )
    }
    "active_kcal" -> {
        // #616: calories, like steps (#377), come from TWO disjoint stores — the on-device HR estimate
        // (DailyMetric.activeKcalEst, exposed by resolvedSeries("active_kcal")) and imported Apple/Health-
        // Connect active energy (AppleDaily.activeKcal, where Health Connect writes it — NOT an active_kcal
        // metricSeries row). Reading imports ALONE opened an empty / HealthConnect-only detail for a WHOOP
        // 5.0 user whose calories are on-device, and disagreed with the Key-Metrics tile. Resolve per day
        // IMPORTED-FIRST (the phone's activeKcal, else NOOP's on-device estimate) — matching the tile + card
        // so the chart + Readings agree, while keeping every imported day in the union.
        val real = vm.repo.resolvedSeries("active_kcal", "my-whoop", "0000-00-00", "9999-99-99",
            strapDeviceId = vm.activeStrapId)
            .points.associateBy({ it.day }, { VitalReading(it.day, it.value, it.source) })
        val imported = LinkedHashMap<String, VitalReading>()
        for (r in vm.repo.appleDaily("apple-health", "0000-01-01", "9999-12-31") +
            vm.repo.appleDaily("health-connect", "0000-01-01", "9999-12-31")) {
            val k = r.activeKcal
            if (k != null && k > 0) imported.putIfAbsent(r.day, VitalReading(r.day, k, r.deviceId))
        }
        VitalDetailModel(
            key = key,
            title = uiString(R.string.l10n_health_screen_active_energy_2d3288f9),
            unit = "kcal",
            color = Palette.metricAmber,
            readings = mergeReadings(imported, real),   // imported wins its day, else on-device estimate
            format = { it.roundToInt().toString() },
        )
    }
    else -> null
}

/** Fitness Age readiness from what a screen can see: RHR coverage over the last 7 merged daily rows
 *  (drives the "N more nights" countdown), a scored-strain day as the activity signal, and the profile
 *  basics. Read by the Today card's [VitalDetailScreen] tap-through. Returns (rhrDays, readiness) — rhrDays also
 *  feeds the not-ready lead. Approximate by design; the weekly value is the authority, this explains gaps. */
@Composable
private fun rememberFitnessReadiness(days: List<DailyMetric>, profile: ProfileStore): Pair<Int, FitnessAgeReadiness> {
    val rhrDays = remember(days) { days.takeLast(7).count { it.restingHr != null } }
    val readiness = remember(days, profile.age, profile.sex, profile.waistCm) {
        val activityDays = days.takeLast(7).count { it.strain != null }
        FitnessAgeEngine.assessReadiness(
            hasAge = profile.age > 0,
            hasSex = profile.sex.isNotBlank(),
            rhrDays = rhrDays,
            activityDays = activityDays,
            hasHeightWeight = profile.heightCm > 0 && profile.weightKg > 0,
            hasWaist = profile.waistCm > 0,
        )
    }
    return rhrDays to readiness
}

/** The not-ready card's lead: a concrete countdown of nights-of-wear still needed (from the shared
 *  [FitnessAgeEngine.nightsUntilReady]), noting the profile basics only when actually missing. Copy is kept
 *  WORD-FOR-WORD identical to the iOS `fitnessReadyLead` (HealthView) so the two platforms match. */
private fun fitnessReadyLead(rhrDays: Int, hasAge: Boolean, hasSex: Boolean): String {
    val remaining = FitnessAgeEngine.nightsUntilReady(rhrDays)
    val needsBasics = !hasAge || !hasSex
    return when {
        remaining == 0 && !needsBasics -> "A few more days and we can show your Fitness Age."
        remaining == 0 && needsBasics  -> "Add your age and sex below and we can show your Fitness Age."
        remaining == 1 && !needsBasics -> "1 more night of wear and we can show your Fitness Age."
        remaining == 1 && needsBasics  -> "1 more night of wear, plus your age and sex below, and we can show your Fitness Age."
        !needsBasics -> "$remaining more nights of wear and we can show your Fitness Age."
        else         -> "$remaining more nights of wear, plus your age and sex below, and we can show your Fitness Age."
    }
}

/** The readiness checklist card: each input as a ✓ / ⚠ / ○ glyph + its detail, grouped by role into
 *  "Drives your Fitness Age" and "Sharpens your VO₂max". When [headed] (no value yet) it leads with the
 *  [lead] countdown and floats the required-missing items to the top of their group. */
@Composable
private fun FitnessReadinessCard(
    readiness: FitnessAgeReadiness,
    headed: Boolean,
    lead: String = "",
    // When set (the headed/not-ready state), a small refresh affordance sits by the lead and forces an
    // immediate Fitness Age recompute; [refreshing] swaps it for a spinner while that runs.
    onRefresh: (() -> Unit)? = null,
    refreshing: Boolean = false,
    onOpenSettings: (() -> Unit)? = null,
) {
    val drivesAge = readiness.items
        .filter { it.role == FitnessReadinessRole.DRIVES_AGE }
        .sortedBy { if (headed) readinessSortKey(it) else 0 }
    val unlocksVo2 = readiness.items
        .filter { it.role == FitnessReadinessRole.UNLOCKS_VO2MAX }
        .sortedBy { if (headed) readinessSortKey(it) else 0 }

    NoopCard(tint = if (headed) Palette.chargeColor else null) {
        Column(verticalArrangement = Arrangement.spacedBy(Metrics.space16)) {
            if (headed) {
                Column(verticalArrangement = Arrangement.spacedBy(Metrics.space4)) {
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            lead.ifBlank { "A few more days and we can show your Fitness Age." },
                            style = NoopType.headline,
                            color = Palette.textPrimary,
                            modifier = Modifier.weight(1f),
                        )
                        // Force-recompute affordance: NOOP scores Fitness Age weekly, so this lets an
                        // impatient user apply it NOW from stored data (no strap needed). Spinner while it runs.
                        if (onRefresh != null) {
                            if (refreshing) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    strokeWidth = 2.dp,
                                    color = Palette.accent,
                                )
                            } else {
                                IconButton(onClick = onRefresh, modifier = Modifier.size(28.dp)) {
                                    Icon(
                                        Icons.Filled.Refresh,
                                        contentDescription = uiString(R.string.l10n_health_screen_refresh_fitness_age_now_85fc516f),
                                        tint = Palette.accent,
                                    )
                                }
                            }
                        }
                    }
                    Text(
                        uiString(R.string.l10n_health_screen_it_compares_your_resting_heart_rate_e83e00f5) +
                            " Wear your strap for a full week and it appears here.",
                        style = NoopType.subhead,
                        color = Palette.textSecondary,
                    )
                }
            }

            ReadinessGroup(title = uiString(R.string.l10n_health_screen_drives_your_fitness_age_9d0d1219), items = drivesAge, onOpenSettings = onOpenSettings)
            ReadinessGroup(title = uiString(R.string.l10n_health_screen_sharpens_your_vo_max_c9d52991), items = unlocksVo2, onOpenSettings = onOpenSettings)

            Text(
                uiString(R.string.l10n_health_screen_weight_height_and_waist_add_a_fd2699f5),
                style = NoopType.footnote,
                color = Palette.textTertiary,
            )
        }
    }
}

/** Sort key for the headed (no-value-yet) state: required-missing first, then partial, then the rest. */
private fun readinessSortKey(item: FitnessReadinessItem): Int = when {
    item.required && item.status == FitnessReadinessStatus.MISSING -> 0
    item.status == FitnessReadinessStatus.MISSING -> 1
    item.status == FitnessReadinessStatus.PARTIAL -> 2
    else -> 3
}

@Composable
private fun ReadinessGroup(title: String, items: List<FitnessReadinessItem>, onOpenSettings: (() -> Unit)? = null) {
    if (items.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(Metrics.space8)) {
        Overline(title)
        items.forEach { ReadinessRow(it, onOpenSettings) }
    }
}

@Composable
private fun ReadinessRow(item: FitnessReadinessItem, onOpenSettings: (() -> Unit)? = null) {
    // #2: a still-unsatisfied input that CAN be filled in Settings (age/sex/body metrics/waist) gets a
    // "Fix in Settings" tap; strap-driven inputs (resting-HR/activity coverage) don't. Mirrors iOS.
    val fixable = onOpenSettings != null && item.status != FitnessReadinessStatus.SATISFIED &&
        item.key in setOf("age", "sex", "bodyMetrics", "waist")
    val glyph = when (item.status) {
        FitnessReadinessStatus.SATISFIED -> "✓"
        FitnessReadinessStatus.PARTIAL -> "⚠"
        FitnessReadinessStatus.MISSING -> "○"
    }
    val glyphColor = when (item.status) {
        FitnessReadinessStatus.SATISFIED -> Palette.chargeColor
        FitnessReadinessStatus.PARTIAL -> Palette.statusWarning
        FitnessReadinessStatus.MISSING -> Palette.textTertiary
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = uiString(R.string.l10n_health_screen_item_label_item_detail_5985e927, item.label, item.detail) },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Metrics.space10),
    ) {
        Text(
            glyph,
            style = NoopType.captionNumber,
            color = glyphColor,
            modifier = Modifier.width(16.dp),
        )
        Text(
            item.label,
            style = NoopType.subhead,
            color = Palette.textPrimary,
            modifier = Modifier.weight(1f),
        )
        if (fixable) {
            Text(
                uiString(R.string.l10n_health_screen_fix_in_settings_d7472915),
                style = NoopType.footnote,
                color = Palette.accent,
                modifier = Modifier.clickable { onOpenSettings?.invoke() },
            )
        } else {
            Text(
                item.detail,
                style = NoopType.footnote,
                color = Palette.textTertiary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
