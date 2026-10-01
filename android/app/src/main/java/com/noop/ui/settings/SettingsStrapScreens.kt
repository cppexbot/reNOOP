package com.noop.ui.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.noop.R
import com.noop.ble.BackgroundHealth
import com.noop.ble.PuffinExperiment
import com.noop.ui.AppViewModel
import com.noop.ui.NoopPrefs
import com.noop.ui.m3.ListGroup
import com.noop.ui.m3.ListRow
import com.noop.ui.m3.SwitchRow
import com.noop.ui.rememberRequestAdvertise

// MARK: - The strap's own settings pages (iOS StrapSettingsSections: Sync, Heart rate broadcast)
//
// Sync: the strap link itself. Keep connected in the background (the foreground service), the two
// experimental sync-speed levers (#533), and, only on a ROM known to kill background work with the
// battery exemption not yet granted, the one-way "Allow" that asks for it (#386: no switch, because
// Android never hands the exemption back). Heart rate broadcast: the phone re-sharing the live heart rate
// as a standard BLE sensor, and the 5/MG strap's own broadcast. Same prefs and BLE calls as before.

@Composable
internal fun StrapSyncScreen(vm: AppViewModel, onBack: () -> Unit) {
    val context = LocalContext.current
    var background by remember { mutableStateOf(NoopPrefs.backgroundConnection(context)) }
    var fastHistory by remember { mutableStateOf(NoopPrefs.fastHistorySync(context)) }
    var fastLink by remember { mutableStateOf(NoopPrefs.fastLinkPhy(context)) }
    val aggressiveVendor = remember { BackgroundHealth.isAggressiveVendor() }
    // Re-read on every resume, so the prompt goes the moment the grant lands (and returns if revoked).
    var exempt by remember { mutableStateOf(BackgroundHealth.isBatteryExempt(context)) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(Unit) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { exempt = BackgroundHealth.isBatteryExempt(context) }
    }
    val oemAutostart = remember { BackgroundHealth.oemAutostartIntent(context) }

    SettingsPage(title = stringResource(R.string.settings_sync), onBack = onBack) {
        item {
            ListGroup {
                item { shape ->
                    SwitchRow(shape, stringResource(R.string.l10n_settings_screen_keep_connected_in_the_background_44499d45), background, {
                        background = it
                        vm.setBackgroundConnection(it)
                    })
                }
                if (background && aggressiveVendor && !exempt) {
                    item { shape ->
                        ListRow(
                            shape = shape,
                            title = stringResource(R.string.l10n_settings_screen_keep_noop_alive_overnight_e43b2fba),
                            subtitle = stringResource(R.string.keep_alive_needed_vendor, android.os.Build.MANUFACTURER),
                            trailing = {
                                androidx.compose.material3.Text(
                                    stringResource(R.string.l10n_settings_screen_allow_3ad0e369),
                                    color = MaterialTheme.colorScheme.primary,
                                    style = MaterialTheme.typography.labelLarge,
                                )
                            },
                            // One system dialog per tap; the app's battery page if a ROM lacks the dialog.
                            onClick = {
                                runCatching { context.startActivity(BackgroundHealth.batteryExemptionIntent(context)) }
                                    .onFailure { runCatching { context.startActivity(BackgroundHealth.appBatterySettingsIntent(context)) } }
                            },
                        )
                    }
                    if (oemAutostart != null) {
                        item { shape ->
                            // The vendor's auto-start screen, a separate tap by choice (never chained).
                            ListRow(
                                shape = shape,
                                title = stringResource(R.string.l10n_settings_screen_some_phones_also_need_auto_start_79b7147b),
                                titleColor = MaterialTheme.colorScheme.primary,
                                onClick = { runCatching { context.startActivity(oemAutostart) } },
                            )
                        }
                    }
                }
            }
        }
        item {
            ListGroup {
                item { shape ->
                    SwitchRow(shape, stringResource(R.string.fast_history_sync), fastHistory, {
                        fastHistory = it
                        vm.setFastHistorySync(it)
                    })
                }
                item { shape ->
                    SwitchRow(shape, stringResource(R.string.fast_link_phy), fastLink, {
                        fastLink = it
                        vm.setFastLinkPhy(it)
                    })
                }
            }
        }
    }
}

@Composable
internal fun HeartRateBroadcastScreen(vm: AppViewModel, onBack: () -> Unit) {
    val context = LocalContext.current
    val live by vm.live.collectAsStateWithLifecycle()
    val phoneOn by vm.hrBroadcast.collectAsStateWithLifecycle()
    val advertising by vm.hrBroadcastAdvertising.collectAsStateWithLifecycle()
    val subscribers by vm.hrBroadcastSubscribers.collectAsStateWithLifecycle()
    val statusNote by vm.hrBroadcastStatus.collectAsStateWithLifecycle()
    val puffin = remember { PuffinExperiment.from(context) }
    var strapOn by remember { mutableStateOf(puffin.broadcastHr) }
    DisposableEffect(Unit) {
        val prefs = context.getSharedPreferences(PuffinExperiment.PREFS, Context.MODE_PRIVATE)
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == null || key == PuffinExperiment.KEY_BROADCAST_HR) strapOn = puffin.broadcastHr
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    // Turning on asks for BLUETOOTH_ADVERTISE first (Android 12+); the view model starts once granted.
    val requestAdvertise = rememberRequestAdvertise(onGranted = { vm.setHrBroadcast(true) })

    SettingsPage(title = stringResource(R.string.settings_hr_broadcast), onBack = onBack) {
        item {
            val status = when {
                !phoneOn -> null
                !advertising -> stringResource(R.string.settings_broadcast_starting)
                subscribers > 0 -> stringResource(R.string.settings_broadcast_readers, subscribers)
                live.heartRate != null -> stringResource(R.string.settings_broadcast_waiting, live.heartRate ?: 0)
                else -> stringResource(R.string.settings_broadcast_no_hr)
            }
            ListGroup(footer = statusNote ?: if (phoneOn) stringResource(R.string.settings_broadcast_battery_note) else null) {
                item { shape ->
                    SwitchRow(
                        shape = shape,
                        title = stringResource(R.string.l10n_data_sources_screen_broadcast_hr_from_this_phone_10e5605c),
                        subtitle = status,
                        checked = phoneOn,
                        onCheckedChange = { on -> if (on) requestAdvertise() else vm.setHrBroadcast(false) },
                    )
                }
            }
        }
        item {
            ListGroup {
                item { shape ->
                    SwitchRow(shape, stringResource(R.string.raw_diag_broadcast_hr), strapOn, { enabled ->
                        strapOn = enabled
                        puffin.broadcastHr = enabled
                        vm.ble.setBroadcastHr(enabled)
                    })
                }
            }
        }
    }
}
