package com.noop.ui.sleep

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshContainer
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.analytics.SleepEditGuard
import com.noop.analytics.SleepGroupEdit
import com.noop.analytics.SleepMark
import com.noop.analytics.SleepMarkType
import com.noop.data.SleepSession
import com.noop.ui.AppViewModel
import com.noop.ui.ClockPrefs
import com.noop.ui.OnScrollToTop
import com.noop.ui.SleepFreshnessStatus
import com.noop.ui.SleepNightRequest
import com.noop.ui.m3.HealthCard
import com.noop.ui.m3.LargeTitle
import com.noop.ui.m3.ListGroup
import com.noop.ui.m3.ListRow
import com.noop.ui.m3.ChevronRight
import com.noop.ui.m3.M3Dimens
import com.noop.ui.m3.NoticeCard
import com.noop.ui.m3.SectionHeader
import com.noop.ui.resolveSleepFreshness
import com.noop.ui.todayPullToSyncEnabled
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

// MARK: - Sleep tab (twin of iOS SleepHealthView, set in Material 3)
//
// The tab root laid out like Health's Sleep Score page: the score card (ring, word, the parts' points, a
// sentence; opens the Rest metric page), the Sleep tile (opens More Sleep Data) beside the Vitals tile
// (opens Vitals), Highlights, and Options (the sleep schedule). The overflow menu edits the night, adds or
// edits a nap and logs sleep marks. Android shows a visible ‹ night › picker over the cards (swiping them
// still changes the night), with the night's date on a chip that opens a date picker.

/** Where the Sleep tab's taps go; the shell resolves each to a route on the Sleep tab. */
internal class SleepActions(
    val openMetric: (String) -> Unit,
    /** More Sleep Data on the night at this offset (0 = newest). */
    val openMoreData: (Int) -> Unit,
    /** The Vitals page for the night that ended on this "yyyy-MM-dd" day. */
    val openVitals: (String) -> Unit,
    val openHighlights: (Int) -> Unit,
    val openSchedule: () -> Unit,
)

/** The undo offered after a delete (or a time edit that retired fragments of a bridged night). */
private class SleepUndo(val sessions: List<SleepSession>, val message: String)

/** The live-state fields the freshness note reads, so the 1 Hz heart-rate tick does not redraw the page. */
private data class FreshnessLive(
    val backfilling: Boolean,
    val chunks: Int,
    val analyzing: Boolean,
    val lastSyncAt: Long?,
    val syncFailed: Boolean,
    val connected: Boolean,
    val bonded: Boolean,
    val historyReady: Boolean,
)

/** An editor on screen: the request, and the session(s) a save or delete acts on. */
private class OpenEditor(
    val request: SleepEditorRequest,
    val adding: Boolean,
    val anchor: SleepSession?,
    val group: List<SleepSession>,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SleepTabScreen(vm: AppViewModel, actions: SleepActions) {
    val context = LocalContext.current
    val locale = context.resources.configuration.locales[0]
    val is24h = remember { ClockPrefs.uses24Hour(context) }
    val scope = rememberCoroutineScope()
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val live by vm.live.collectAsStateWithLifecycle()
    val fresh by remember {
        derivedStateOf {
            val s = live
            FreshnessLive(
                s.backfilling, s.syncChunksThisSession, s.analyzingHistory, s.lastSyncAt, s.lastSyncError != null,
                s.connected, s.bonded, s.historyReady,
            )
        }
    }

    var data by remember { mutableStateOf<SleepNights?>(null) }
    val revision = SleepNightsLoader.revision
    LaunchedEffect(days, revision) { data = SleepNightsLoader.load(vm, days) }
    val nights = data ?: SleepNights.EMPTY
    var nightOffset by rememberSaveable { mutableStateOf(0) }
    val lastIndex = (nights.navDays.size - 1).coerceAtLeast(0)
    if (nightOffset > lastIndex) nightOffset = lastIndex

    // The Summary's Sleep card and Rest ring ask for a particular night: show it once the nights are here.
    val requested = SleepNightRequest.wakeDay
    LaunchedEffect(requested, nights) {
        val key = requested ?: return@LaunchedEffect
        if (nights.navDays.isEmpty()) return@LaunchedEffect
        val i = nights.index(key)
        if (i >= 0) nightOffset = i
        SleepNightRequest.wakeDay = null
    }

    val night = nights.details.getOrNull(nightOffset)
    val wakeDay = night?.dayKey
    val score = remember(night, nights) {
        night?.let { n ->
            val key = nights.heroNight(nightOffset)?.dayKey ?: n.dayKey
            SleepScore.make(nights.dailyRow(key), nights.imported.performance[key])
        }
    }
    val vitals = remember(wakeDay, nights) { wakeDay?.let { SleepVitals.make(nights.days, it) } }
    val highlights = remember(nights) { SleepHighlight.make(nights.entries, LocalDate.now()) }

    var undo by remember { mutableStateOf<SleepUndo?>(null) }
    var editor by remember { mutableStateOf<OpenEditor?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    var pickDate by remember { mutableStateOf(false) }

    val freshness = remember(nights, fresh) {
        val zone = ZoneId.systemDefault()
        val now = Instant.now().atZone(zone)
        val latestWake = nights.sleeps.maxOfOrNull { it.endTs }
        val current = latestWake?.let { Instant.ofEpochSecond(it).atZone(zone).toLocalDate() == now.toLocalDate() } ?: false
        val dayStart = now.toLocalDate().atStartOfDay(zone).toEpochSecond()
        resolveSleepFreshness(
            hasCurrentNight = current,
            morningReady = now.hour >= 6,
            syncing = fresh.backfilling,
            calculating = fresh.analyzing,
            syncedSinceDayStart = (fresh.lastSyncAt ?: 0L) >= dayStart,
            syncFailed = fresh.syncFailed,
        )
    }

    fun reload() = SleepNightsLoader.invalidate()

    fun openNightEditor() {
        val hero = nights.heroNight(nightOffset) ?: return
        val s = hero.session
        val group = hero.heroGroup.ifEmpty { listOf(s) }
        val window = SleepGroupEdit.groupWindow(group)
        editor = OpenEditor(
            SleepEditorRequest(
                nap = false,
                coverage = window ?: (minOf(s.startTs, s.effectiveStartTs) to s.endTs),
                bedTs = window?.first ?: s.effectiveStartTs,
                wakeTs = window?.second ?: s.endTs,
                deletable = true,
                suppressesReDetection = !s.userEdited,
            ),
            adding = false, anchor = s, group = group,
        )
    }

    fun openNapEditor(nap: SleepSession) {
        editor = OpenEditor(
            SleepEditorRequest(
                nap = true, coverage = minOf(nap.startTs, nap.effectiveStartTs) to nap.endTs,
                bedTs = nap.effectiveStartTs, wakeTs = nap.endTs, deletable = true, suppressesReDetection = false,
            ),
            adding = false, anchor = nap, group = listOf(nap),
        )
    }

    fun openAddNap() {
        val hero = nights.heroNight(nightOffset) ?: return
        val anchor = (hero.heroWakeTs ?: hero.session.endTs) + 3_600
        editor = OpenEditor(
            SleepEditorRequest(nap = true, coverage = null, bedTs = anchor, wakeTs = anchor + 30 * 60, deletable = false, suppressesReDetection = false),
            adding = true, anchor = null, group = emptyList(),
        )
    }

    fun logMark(type: SleepMarkType) {
        val mark = SleepMark.now(type)
        vm.ble.externalLog(mark.logLine())
        scope.launch { runCatching { vm.repo.upsertMetricSeries(listOf(mark.metricPoint("my-whoop"))) } }
        Toast.makeText(context, mark.confirmation(), Toast.LENGTH_SHORT).show()
    }

    val deletedMessage = stringResource(R.string.sleep_deleted)
    fun deletedWindowMessage(s: SleepSession): String = context.getString(
        R.string.sleep_deleted_window, clockLabel(s.effectiveStartTs, is24h, locale), clockLabel(s.endTs, is24h, locale),
    )

    val pull = rememberPullToRefreshState()
    LaunchedEffect(pull.isRefreshing) {
        if (!pull.isRefreshing) return@LaunchedEffect
        if (todayPullToSyncEnabled(fresh.connected, fresh.bonded, fresh.backfilling, fresh.historyReady)) vm.syncNow()
        reload()
        pull.endRefresh()
    }
    val listState = rememberLazyListState()
    OnScrollToTop { listState.animateScrollToItem(0) }

    val heroNight = remember(nights, nightOffset) { nights.heroNight(nightOffset) }
    val naps = heroNight?.napBlocks.orEmpty()

    Box(
        Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface).nestedScroll(pull.nestedScrollConnection),
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = M3Dimens.bottomBarClearance),
            verticalArrangement = Arrangement.spacedBy(M3Dimens.itemGap),
        ) {
            item(key = "title") {
                LargeTitle(stringResource(R.string.nav_sleep)) {
                    Box {
                        IconButton(onClick = { menuOpen = true }) {
                            Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.sleep_menu_more))
                        }
                        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                            if (heroNight != null) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.sleep_menu_edit_times)) },
                                    leadingIcon = { Icon(Icons.Filled.Edit, null) },
                                    onClick = { menuOpen = false; openNightEditor() },
                                )
                                if (naps.isNotEmpty()) {
                                    HorizontalDivider()
                                    Text(
                                        stringResource(R.string.sleep_menu_naps),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                    )
                                    naps.forEach { nap ->
                                        DropdownMenuItem(
                                            text = { Text("${clockLabel(nap.effectiveStartTs, is24h, locale)} – ${clockLabel(nap.endTs, is24h, locale)}") },
                                            leadingIcon = { Icon(Icons.Filled.Hotel, null) },
                                            onClick = { menuOpen = false; openNapEditor(nap) },
                                        )
                                    }
                                }
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.sleep_menu_add_nap)) },
                                    leadingIcon = { Icon(if (naps.isEmpty()) Icons.Filled.Hotel else Icons.Filled.Add, null) },
                                    onClick = { menuOpen = false; openAddNap() },
                                )
                                HorizontalDivider()
                            }
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.sleep_menu_log_sleep)) },
                                leadingIcon = { Icon(Icons.Filled.Bedtime, null) },
                                onClick = { menuOpen = false; logMark(SleepMarkType.BEDTIME) },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.sleep_menu_log_wake)) },
                                leadingIcon = { Icon(Icons.Filled.WbSunny, null) },
                                onClick = { menuOpen = false; logMark(SleepMarkType.WAKE) },
                            )
                        }
                    }
                }
            }
            if (nights.navDays.isNotEmpty()) {
                item(key = "picker") {
                    NightPickerRow(
                        title = night?.let { nightTitle(it.day, locale) }
                            ?: heroNight?.let { nightTitle(com.noop.ui.sleep.localDate(it.heroWakeTs ?: it.session.endTs), locale) }
                            ?: "—",
                        canGoOlder = nightOffset < lastIndex,
                        canGoNewer = nightOffset > 0,
                        onOlder = { nightOffset = (nightOffset + 1).coerceAtMost(lastIndex) },
                        onNewer = { nightOffset = (nightOffset - 1).coerceAtLeast(0) },
                        onPick = { pickDate = true },
                    )
                }
            }
            undo?.let { u ->
                item(key = "undo") {
                    NoticeCard(
                        icon = Icons.Filled.Delete,
                        title = u.message,
                        modifier = Modifier.padding(horizontal = M3Dimens.screenPadding),
                        action = stringResource(R.string.sleep_undo),
                        onAction = {
                            undo = null
                            scope.launch {
                                vm.undoDeleteSleepSessions(u.sessions)
                                reload()
                            }
                        },
                        trailing = {
                            IconButton(onClick = { undo = null }) {
                                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.summary_cancel))
                            }
                        },
                    )
                }
            }
            freshness?.let { status ->
                item(key = "freshness") { Box(Modifier.padding(horizontal = M3Dimens.screenPadding)) { FreshnessNotice(status, fresh.chunks) } }
            }
            item(key = "night") {
                val swipe = Modifier.pointerInput(lastIndex) {
                    var dx = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { dx = 0f },
                        onDragEnd = {
                            if (abs(dx) > 50.dp.toPx()) {
                                nightOffset = (nightOffset + if (dx > 0) 1 else -1).coerceIn(0, lastIndex)
                            }
                        },
                    ) { _, amount -> dx += amount }
                }
                Column(
                    swipe.padding(horizontal = M3Dimens.screenPadding),
                    verticalArrangement = Arrangement.spacedBy(M3Dimens.itemGap),
                ) {
                    if (night != null) {
                        score?.let { SleepScoreCard(it) { actions.openMetric("sleep_performance") } }
                        Row(
                            Modifier.fillMaxWidth().height(IntrinsicSize.Max),
                            horizontalArrangement = Arrangement.spacedBy(M3Dimens.itemGap),
                        ) {
                            SleepDurationTile(night, onClick = { actions.openMoreData(nightOffset) }, modifier = Modifier.weight(1f))
                            SleepVitalsTile(
                                vitals ?: SleepVitals(emptyList(), SleepVitals.NIGHTS_NEEDED),
                                onClick = { actions.openVitals(night.dayKey) },
                                modifier = Modifier.weight(1f),
                            )
                        }
                    } else if (data != null) {
                        HealthCard {
                            Text(
                                stringResource(R.string.sleep_no_data),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp).padding(top = 48.dp),
                            )
                        }
                    }
                }
            }
            item(key = "hl-header") {
                SectionHeader(
                    stringResource(R.string.sleep_highlights),
                    modifier = Modifier.padding(horizontal = M3Dimens.screenPadding),
                    action = stringResource(R.string.sleep_show_all),
                    onAction = { actions.openHighlights(nightOffset) },
                )
            }
            highlights.forEach { h ->
                item(key = "hl-${h::class.simpleName}") {
                    Box(Modifier.padding(horizontal = M3Dimens.screenPadding)) { SleepHighlightCard(h, locale, is24h) }
                }
            }
            night?.let { n ->
                item(key = "hl-stages") {
                    Box(Modifier.padding(horizontal = M3Dimens.screenPadding)) { SleepStagesHighlightCard(n, locale, is24h) }
                }
            }
            item(key = "options-header") {
                SectionHeader(stringResource(R.string.sleep_options), modifier = Modifier.padding(horizontal = M3Dimens.screenPadding))
            }
            item(key = "options") {
                ListGroup(Modifier.padding(horizontal = M3Dimens.screenPadding)) {
                    item { shape ->
                        ListRow(
                            shape = shape,
                            title = stringResource(R.string.sleep_schedule_title),
                            leading = { Icon(Icons.Filled.Schedule, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
                            trailing = { ChevronRight() },
                            onClick = actions.openSchedule,
                        )
                    }
                }
            }
        }
        if (pull.progress > 0f || pull.isRefreshing) {
            PullToRefreshContainer(state = pull, modifier = Modifier.align(Alignment.TopCenter))
        }
    }

    if (pickDate) {
        val available = remember(nights) { nights.details.mapNotNull { it?.day }.toSet() }
        DayPicker(
            selected = night?.day ?: LocalDate.now(),
            earliest = available.minOrNull(),
            latest = maxOf(LocalDate.now(), available.maxOrNull() ?: LocalDate.now()),
            allowed = { it in available },
            onPick = { day ->
                pickDate = false
                val i = nights.index(day.toString())
                if (i >= 0) nightOffset = i
            },
            onDismiss = { pickDate = false },
        )
    }

    editor?.let { open ->
        SleepTimeEditorSheet(
            request = open.request,
            adding = open.adding,
            onDismiss = { editor = null },
            onSave = { start, end ->
                editor = null
                val now = System.currentTimeMillis() / 1000L
                val safe = SleepEditGuard.clampedEditWindow(start, end, now)
                if (safe == null) {
                    Toast.makeText(context, context.getString(R.string.sleep_edit_refused), Toast.LENGTH_SHORT).show()
                } else if (open.adding) {
                    scope.launch {
                        vm.addManualNap(safe.first, safe.second)
                        reload()
                    }
                } else {
                    // #1492: one plan for the whole bridged night, so retired fragments can be undone.
                    val plan = SleepGroupEdit.plan(open.group, safe.first, safe.second)
                    if (plan.dropped.isNotEmpty()) undo = SleepUndo(plan.dropped, context.getString(R.string.sleep_edit_retired))
                    scope.launch {
                        vm.updateSleepGroupTimes(open.group, safe.first, safe.second)
                        reload()
                    }
                }
            },
            onDelete = {
                editor = null
                val s = open.anchor ?: return@SleepTimeEditorSheet
                // A hand-edited or added sleep writes no tombstone, so only a detected one promises no re-detection.
                undo = SleepUndo(listOf(s), if (s.userEdited) deletedMessage else deletedWindowMessage(s))
                scope.launch {
                    vm.deleteSleepSession(s)
                    reload()
                }
            },
        )
    }
}

/** "Night of Wed, 30 Sep": the night named by the day it ended on. */
@Composable
private fun nightTitle(day: LocalDate, locale: Locale): String =
    stringResource(R.string.sleep_night_of, DateTimeFormatter.ofPattern("EEE, d MMM", locale).format(day))

/** ‹ [📅 Night of …] ›: the visible night picker (Android's addition to Health's swipe). */
@Composable
private fun NightPickerRow(
    title: String,
    canGoOlder: Boolean,
    canGoNewer: Boolean,
    onOlder: () -> Unit,
    onNewer: () -> Unit,
    onPick: () -> Unit,
) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(
            onClick = onOlder,
            enabled = canGoOlder,
            colors = IconButtonDefaults.iconButtonColors(contentColor = MaterialTheme.colorScheme.primary),
        ) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = stringResource(R.string.sleep_previous_night))
        }
        Spacer(Modifier.weight(1f))
        FilledTonalButton(onClick = onPick, contentPadding = ButtonDefaults.ButtonWithIconContentPadding) {
            Icon(Icons.Filled.CalendarToday, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(title, style = MaterialTheme.typography.labelLarge)
        }
        Spacer(Modifier.weight(1f))
        IconButton(
            onClick = onNewer,
            enabled = canGoNewer,
            colors = IconButtonDefaults.iconButtonColors(contentColor = MaterialTheme.colorScheme.primary),
        ) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = stringResource(R.string.sleep_next_night))
        }
    }
}

/** The freshness note, one state at a time (iOS SleepFreshnessNote's copy). */
@Composable
private fun FreshnessNotice(status: SleepFreshnessStatus, chunks: Int) {
    when (status) {
        SleepFreshnessStatus.SYNCING -> NoticeCard(
            icon = Icons.Filled.Sync,
            title = stringResource(R.string.sleep_fresh_syncing),
            message = if (chunks > 0) stringResource(R.string.sleep_fresh_chunks, chunks) else null,
        )
        SleepFreshnessStatus.CALCULATING -> NoticeCard(icon = Icons.Filled.Sync, title = stringResource(R.string.sleep_fresh_calculating))
        SleepFreshnessStatus.SYNC_FAILED -> NoticeCard(
            icon = Icons.Filled.ErrorOutline,
            title = stringResource(R.string.sleep_fresh_failed_title),
            message = stringResource(R.string.sleep_fresh_failed_body),
            error = true,
        )
        SleepFreshnessStatus.AWAITING_SYNC -> NoticeCard(
            icon = Icons.Filled.Sync,
            title = stringResource(R.string.sleep_fresh_waiting_title),
            message = stringResource(R.string.sleep_fresh_waiting_body),
        )
        SleepFreshnessStatus.NOT_DETECTED -> NoticeCard(
            icon = Icons.Filled.Bedtime,
            title = stringResource(R.string.sleep_fresh_none_title),
            message = stringResource(R.string.sleep_fresh_none_body),
        )
    }
}

/** The Sleep Highlights page: every highlight card, then the night's stages. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun SleepHighlightsScreen(vm: AppViewModel, offset: Int, onBack: () -> Unit) {
    val context = LocalContext.current
    val locale = context.resources.configuration.locales[0]
    val is24h = remember { ClockPrefs.uses24Hour(context) }
    val days by vm.recentDays.collectAsStateWithLifecycle()
    var data by remember { mutableStateOf<SleepNights?>(null) }
    LaunchedEffect(days, SleepNightsLoader.revision) { data = SleepNightsLoader.load(vm, days) }
    val nights = data ?: SleepNights.EMPTY
    val highlights = remember(nights) { SleepHighlight.make(nights.entries, LocalDate.now()) }
    val night = nights.details.getOrNull(offset)
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        com.noop.ui.m3.PushedTopBar(stringResource(R.string.sleep_highlights_title), onBack)
        LazyColumn(
            contentPadding = PaddingValues(start = M3Dimens.screenPadding, end = M3Dimens.screenPadding, top = 8.dp, bottom = M3Dimens.bottomBarClearance),
            verticalArrangement = Arrangement.spacedBy(M3Dimens.itemGap),
        ) {
            highlights.forEach { h -> item { SleepHighlightCard(h, locale, is24h) } }
            night?.let { n -> item { SleepStagesHighlightCard(n, locale, is24h) } }
        }
    }
}
