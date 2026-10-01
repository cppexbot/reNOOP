package com.noop.ui

import com.noop.R
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.BatteryStd
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Vibration
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.analytics.HrZones
import com.noop.analytics.NapCandidate
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import com.noop.analytics.ClockFormat

/**
 * Automations — turn the strap's physical inputs (double-tap, wrist on/off) and live
 * biometrics into on-device actions and haptic coaching. HR-zone coaching, the smart alarm
 * and the illness watch are real + persisted (ViewModel-backed).
 */
@Composable
fun AutomationsScreen(viewModel: AppViewModel) {
    val live by viewModel.live.collectAsStateWithLifecycle()

    // Double-tap action (parity since 4.2.8) — real + persisted via the ViewModel (NoopPrefs). The
    // dispatch runs in the ViewModel on a fresh strap DOUBLE_TAP event; this card just edits the choice.
    val doubleTapAction by viewModel.doubleTapAction.collectAsStateWithLifecycle()

    // (#766) The strap firmware wake-alarm state used to be read here; it moved to SmartAlarmScreen with
    // the rest of the alarm UI.
    val ctx = LocalContext.current

    // HR-zone coaching is real + persisted (zone-based, mirrors macOS): the ViewModel owns the toggle +
    // recovery option and buzzes the strap on entering the top zone (and Zone 1 if recovery is on).
    val profile = remember { ProfileStore.from(ctx.applicationContext) }
    val zoneCoaching by viewModel.zoneCoaching.collectAsStateWithLifecycle()
    val zoneCoachRecovery by viewModel.zoneCoachRecovery.collectAsStateWithLifecycle()
    // The Zone 5 entry threshold (≥ 90% of HR-max), from the same HrZones model used everywhere.
    val zone5Bpm = remember(profile.hrMax) {
        profile.hrZoneSet.zones.firstOrNull { it.number == 5 }?.lower?.roundToInt() ?: 0
    }

    // #haptics (#1115): per-event toggles for NOOP's IN-SESSION strap buzzes. Default ON (opt-out) — these
    // are feedback to a feature you started, so a fresh install buzzes as before and a user turns off any
    // cue they find noisy. Ambient cues (inactivity / calls / notifications) keep their own opt-in sections;
    // double-tap is gated by its action picker, not here. SharedPreferences isn't reactive → read into state.
    var breathingHaptic by remember { mutableStateOf(HapticPrefs.enabled(ctx, HapticPrefs.BREATHING)) }
    var intervalsHaptic by remember { mutableStateOf(HapticPrefs.enabled(ctx, HapticPrefs.INTERVALS)) }
    var workoutHaptic by remember { mutableStateOf(HapticPrefs.enabled(ctx, HapticPrefs.WORKOUT)) }

    // PERF (#707): lazy scaffold — each settings section is an unconditional top-level child, so each
    // becomes one `item { }` in the same order. No standalone Spacers (the eager `spacedBy(20.dp)` is
    // reproduced by the LazyColumn), so spacing is byte-identical; only on-screen sections compose + get
    // accessibility-walked on scroll.
    LazyScreenScaffold(
        title = uiString(R.string.l10n_automations_screen_automations_82542d6d),
        subtitle = "Make the strap do things: tap to act, walk away to lock, train by feel.",
    ) {
        // #haptics (#1115): per-event in-session haptic toggles, default ON (opt-out) — turn off any cue you
        // find noisy; the feature keeps working, just without that wrist buzz.
        item {
        SettingsSection(
            icon = Icons.Filled.Vibration,
            title = uiString(R.string.haptics_section_title),
            blurb = "Choose which in-session cues buzz your wrist during a breathing session, timer, or workout.",
            active = breathingHaptic || intervalsHaptic || workoutHaptic,
        ) {
            ToggleRow(
                label = uiString(R.string.haptics_breathing_label),
                help = "Buzz each inhale and exhale during a breathing or resonance session.",
                checked = breathingHaptic,
                onChange = { breathingHaptic = it; HapticPrefs.setEnabled(ctx, HapticPrefs.BREATHING, it) },
            )
            RowDivider()
            ToggleRow(
                label = uiString(R.string.haptics_intervals_label),
                help = "Buzz on each interval change.",
                checked = intervalsHaptic,
                onChange = { intervalsHaptic = it; HapticPrefs.setEnabled(ctx, HapticPrefs.INTERVALS, it) },
            )
            RowDivider()
            ToggleRow(
                label = uiString(R.string.haptics_workout_label),
                help = "A buzz confirms a workout starting and saving.",
                checked = workoutHaptic,
                onChange = { workoutHaptic = it; HapticPrefs.setEnabled(ctx, HapticPrefs.WORKOUT, it) },
            )
        }
        }
        // Double-tap (parity since 4.2.8): a real, persisted action picker bound to the ViewModel, with a
        // Test action button. Mirrors AutomationsView.swift's Picker (Apple-applicable subset only; no
        // lockScreen / runShortcut on Android).
        item {
        SettingsSection(
            icon = Icons.Filled.TouchApp,
            title = uiString(R.string.l10n_automations_screen_double_tap_8d2f1646),
            blurb = "Double-tap the strap to trigger an action on this device. (The strap exposes a single double-tap gesture.)",
            active = doubleTapAction != DoubleTapAction.NONE,
        ) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(uiString(R.string.l10n_automations_screen_when_i_double_tap_a1f1e04d), style = NoopType.body, color = Palette.textPrimary)
                Spacer(Modifier.weight(1f))
                DoubleTapActionPicker(
                    selected = doubleTapAction,
                    onSelect = { viewModel.setDoubleTapAction(it) },
                )
            }
            RowDivider()
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(
                    onClick = { viewModel.testDoubleTapAction() },
                    enabled = doubleTapAction != DoubleTapAction.NONE,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Palette.accent),
                ) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(uiString(R.string.l10n_automations_screen_test_action_266df314), style = NoopType.body)
                }
                Spacer(Modifier.weight(1f))
                StatePill(
                    if (live.bonded) "Strap bonded" else "Not connected",
                    tone = if (live.bonded) StrandTone.Positive else StrandTone.Warning,
                )
            }
        }
        }

        // Haptic coaching.
        item {
        SettingsSection(
            icon = Icons.Filled.Bolt,
            title = uiString(R.string.l10n_automations_screen_haptic_coaching_e2fab286),
            blurb = "Train by feel. The strap buzzes so you don't have to watch a screen.",
            active = zoneCoaching,
        ) {
            ToggleRow(
                label = uiString(R.string.l10n_automations_screen_hr_zone_coaching_9306e6e1),
                help = "A triple-buzz when you climb into your top zone (Zone 5, ≥ $zone5Bpm bpm), a cue to ease off. Max HR comes from Settings.",
                checked = zoneCoaching,
                onChange = { viewModel.setZoneCoaching(it) },
            )
            if (zoneCoaching) {
                RowDivider()
                ToggleRow(
                    label = uiString(R.string.l10n_automations_screen_recovery_buzz_1abc9a51),
                    help = "Also buzz once when your heart rate drops back to Zone 1, a cue that you've recovered.",
                    checked = zoneCoachRecovery,
                    onChange = { viewModel.setZoneCoachRecovery(it) },
                )
            }
        }
        }

        // #766: the strap's silent wake-alarm card used to sit here, which let users conflate it with the
        // Wake Window + Wind-Down reminder over on the Alarms screen. It's moved to SmartAlarmScreen so
        // every wake/alarm control lives in one place. Automations is just inputs-to-actions now.

        // On-device short-nap detection (PR #569 reimpl) — opt-in, default OFF. Detected on the offload
        // hook; a confident nap is offered as a review card you accept (it becomes a nap session) or
        // dismiss. NEVER auto-written.
        item { NapDetectionSection(viewModel) }

        // The inactivity reminder, the illness early warning and the battery alerts moved to Settings >
        // Notifications (Reminders / Alerts), as on iOS; this page keeps the strap's inputs and cues.
    }
}

// MARK: - On-device nap detection (PR #569 reimpl under NoopApp)

/**
 * The nap-detection automation: a toggle plus the REVIEW queue. Detection runs on the offload hook
 * (WhoopBleClient.maybeDetectNaps → the pure NapDetector); a confident NAP is queued in NapStore and shown
 * here as a card the user ACCEPTS (→ a manual nap session, the #508 path) or DISMISSES. The engine never
 * auto-writes a session, and an INCONCLUSIVE window queues nothing — honest by construction.
 */
@Composable
private fun NapDetectionSection(viewModel: AppViewModel) {
    val scope = rememberCoroutineScope()
    val enabled by viewModel.napDetectionEnabled.collectAsStateWithLifecycle()
    // The queue isn't a reactive flow (it's written from the BLE layer); re-read it on each toggle/action.
    var pending by remember { mutableStateOf(viewModel.pendingNaps()) }

    SettingsSection(
        icon = Icons.Filled.Bedtime,
        title = uiString(R.string.l10n_automations_screen_nap_detection_ca2dedf5),
        blurb = "Spots a likely daytime nap from the strap's motion and heart rate on each history sync, " +
            "then asks you to confirm it. Inferred and approximate: reNOOP never adds a nap to your sleep " +
            "without your OK.",
        active = enabled,
    ) {
        ToggleRow(
            label = uiString(R.string.l10n_automations_screen_detect_short_naps_bbfd136d),
            help = "When a sync shows a quiet, settled stretch in the day, reNOOP offers it here for you to keep or skip.",
            checked = enabled,
            onChange = {
                viewModel.setNapDetectionEnabled(it)
                if (it) pending = viewModel.pendingNaps()
            },
        )
        if (enabled) {
            if (pending.isEmpty()) {
                RowDivider()
                Text(
                    uiString(R.string.l10n_automations_screen_no_naps_to_review_detected_naps_2e82e9fc),
                    style = NoopType.footnote, color = Palette.textTertiary,
                )
            } else {
                pending.forEach { nap ->
                    RowDivider()
                    NapReviewRow(
                        nap = nap,
                        onAccept = { scope.launch { pending = viewModel.acceptDetectedNap(nap) } },
                        onDismiss = { pending = viewModel.dismissDetectedNap(nap) },
                    )
                }
            }
        }
    }
}

/** One pending nap candidate: an honest "HH:mm–HH:mm · ~N min" line (+ mean HR when known) with Keep /
 *  Skip controls. Keep persists it as a nap session; Skip forgets it (and won't re-queue the window). */
@Composable
private fun NapReviewRow(nap: NapCandidate, onAccept: () -> Unit, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(napWindowLabel(nap, ctx), style = NoopType.body, color = Palette.textPrimary)
            Text(napDetailLabel(nap), style = NoopType.footnote, color = Palette.textTertiary)
        }
        Spacer(Modifier.width(8.dp))
        NapActionButton(Icons.Filled.Check, "Keep this nap", Palette.statusPositive, onAccept)
        Spacer(Modifier.width(8.dp))
        NapActionButton(Icons.Filled.Close, "Skip this nap", Palette.textTertiary, onDismiss)
    }
}

@Composable
private fun NapActionButton(icon: ImageVector, contentDescription: String, tint: androidx.compose.ui.graphics.Color, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(Palette.surfaceInset)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = contentDescription, tint = tint, modifier = Modifier.size(18.dp))
    }
}

/** "HH:mm–HH:mm · ~N min", local time. Pure-ish (reads the device clock format only). */
private fun napWindowLabel(nap: NapCandidate, ctx: android.content.Context): String {
    // #1821: the reader's chosen clock, not the raw device format.
    val fmt = java.text.SimpleDateFormat(
        ClockFormat.hourMinutePattern(ClockPrefs.uses24Hour(ctx)), java.util.Locale.getDefault(),
    )
    val start = fmt.format(java.util.Date(nap.start * 1000L))
    val end = fmt.format(java.util.Date(nap.end * 1000L))
    val mins = nap.durationS / 60
    return "$start-$end · ~$mins min"
}

private fun napDetailLabel(nap: NapCandidate): String =
    if (nap.meanHr != null) "Quiet and settled, mean HR ~${nap.meanHr} bpm." else "Quiet and settled."

// MARK: - Per-weekday wake-time overrides (PR #554 reimpl under NoopApp)

/**
 * Per-weekday wake-time OVERRIDES for the smart alarm (#554). For each day the alarm fires on, shows the
 * effective wake time (the day's override, else the default) as a [TimeChip]; picking a time sets that
 * day's override, and a "Reset" affordance clears it back to the default. Days the alarm doesn't fire on
 * aren't shown (no point overriding a day it won't ring). Empty enabledDays = every day, so all seven show.
 */
// internal (not private) so the consolidated Alarms screen (SmartAlarmScreen, #766) can reuse the
// exact same picker. The strap wake-alarm card moved there but its weekday/override UI is unchanged.
// MARK: - Section + rows (mirror the settings idiom from AutomationsView.swift)

@Composable
private fun SettingsSection(
    icon: ImageVector,
    title: String,
    blurb: String,
    active: Boolean = false,
    content: @Composable () -> Unit,
) {
    NoopCard(padding = 20.dp, tint = Palette.accent) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Overline("Automation")
                    if (active) Overline("ON", color = Palette.accent)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        icon,
                        contentDescription = null,
                        tint = if (active) Palette.accent else Palette.textSecondary,
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(title, style = NoopType.title2, color = Palette.textPrimary)
                }
            }
            Text(blurb, style = NoopType.subhead, color = Palette.textSecondary)
            content()
        }
    }
}

/** A compact dropdown that mirrors the iOS double-tap Picker: a tappable label + chevron that opens a
 *  menu of [DoubleTapAction]s. Labels come from [DoubleTapAction.label] so both clients read the same. */
@Composable
private fun DoubleTapActionPicker(
    selected: DoubleTapAction,
    onSelect: (DoubleTapAction) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .clip(CircleShape)
                .clickable { expanded = true }
                .background(Palette.surfaceInset)
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(selected.label, style = NoopType.body, color = Palette.textPrimary)
            Spacer(Modifier.width(4.dp))
            Icon(
                Icons.Filled.ArrowDropDown,
                contentDescription = uiString(R.string.l10n_automations_screen_choose_double_tap_action_6ac9a313),
                tint = Palette.textSecondary,
                modifier = Modifier.size(18.dp),
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            for (action in DoubleTapAction.entries) {
                DropdownMenuItem(
                    text = {
                        Text(
                            action.label,
                            style = NoopType.body,
                            color = if (action == selected) Palette.accent else Palette.textPrimary,
                        )
                    },
                    onClick = { onSelect(action); expanded = false },
                )
            }
        }
    }
}

@Composable
private fun ToggleRow(
    label: String,
    help: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = NoopType.body, color = Palette.textPrimary)
            Text(help, style = NoopType.footnote, color = Palette.textTertiary)
        }
        Spacer(Modifier.width(16.dp))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Palette.surfaceBase,
                checkedTrackColor = Palette.accent,
                uncheckedThumbColor = Palette.textSecondary,
                uncheckedTrackColor = Palette.surfaceInset,
                uncheckedBorderColor = Palette.hairline,
            ),
        )
    }
}

@Composable
private fun RowDivider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .padding(vertical = 4.dp)
            .background(Palette.hairline),
    )
}

/**
 * Weekday selector for the smart alarm (#539). One tappable circle per weekday, Monday-first. An empty
 * [selected] set means "every day" (all circles read as on). Mirrors the macOS AutomationsView picker.
 */
// internal (not private) so SmartAlarmScreen (the consolidated Alarms surface, #766) can reuse it.
/** Calendar.DAY_OF_WEEK numbers laid out Monday-first (Mon…Sun → 2,3,4,5,6,7,1). */
private val SMART_ALARM_WEEKDAY_ORDER = intArrayOf(2, 3, 4, 5, 6, 7, 1)

/** A day reads as "on" when the set is empty (= every day) or explicitly contains it. Pure for tests. */
internal fun smartAlarmWeekdayIsSelected(dow: Int, days: Set<Int>): Boolean =
    days.isEmpty() || days.contains(dow)

/**
 * Toggle one weekday, normalising "every day" at both ends so the empty set always means every day.
 * Pure + side-effect-free for unit tests. Pulling a day out of the implicit "every day" expands to the
 * explicit other six; selecting the seventh collapses back to the empty "every day" set. Mirrors macOS
 * `AutomationsView.toggledWeekday`.
 */
internal fun toggledSmartAlarmWeekday(dow: Int, days: Set<Int>): Set<Int> {
    val next: MutableSet<Int> = when {
        days.isEmpty() -> (1..7).toMutableSet().also { it.remove(dow) }
        days.contains(dow) -> days.toMutableSet().also { it.remove(dow) }
        else -> days.toMutableSet().also { it.add(dow) }
    }
    return if (next.size == 7) emptySet() else next
}

/** Human-readable summary of the selection. Pure for tests. Mirrors macOS `weekdaySummary`. */
internal fun smartAlarmWeekdaySummary(days: Set<Int>): String = when {
    days.isEmpty() || days.size == 7 -> "Every day"
    days == setOf(2, 3, 4, 5, 6) -> "Weekdays"
    days == setOf(1, 7) -> "Weekends"
    else -> SMART_ALARM_WEEKDAY_ORDER.filter { days.contains(it) }
        .joinToString(", ") { smartAlarmWeekdayName(it) }
}

private fun smartAlarmWeekdayInitial(dow: Int): String = when (dow) {
    1 -> "S"; 2 -> "M"; 3 -> "T"; 4 -> "W"; 5 -> "T"; 6 -> "F"; 7 -> "S"; else -> "?"
}

private fun smartAlarmWeekdayName(dow: Int): String = when (dow) {
    1 -> "Sun"; 2 -> "Mon"; 3 -> "Tue"; 4 -> "Wed"; 5 -> "Thu"; 6 -> "Fri"; 7 -> "Sat"; else -> "?"
}

