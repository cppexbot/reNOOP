package com.noop.ui

import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.noop.R
import com.noop.push.SelfHostedPushScreen

// MARK: - Navigation model
//
// Twin of the iOS RootTabView: a Material 3 NavigationBar with the four tabs of [MainTab] (Summary, Sleep,
// Workouts, Browse) over ONE NavHost. Each tab keeps its own back stack: selecting a tab pops the whole
// visible stack with its state saved and restores the selected tab's saved stack, so a tab comes back
// exactly as it was left. Re-selecting the active tab pops it to its root, or scrolls a root that is
// already showing back to the top. Screens outside the three main tabs are Browse rows and push inside
// Browse; Settings pushes on the Summary from its avatar. A request from elsewhere (a Today card opening
// Coach, a quick action, an Updates inbox link) selects the tab the screen lives in and pushes it there,
// as a tap on its row would.

/** A NavHost destination, by the stable route string it is registered under. */
internal enum class Destination(val route: String) {
    // The four tab roots.
    Today("today"),
    Sleep("sleep"),
    Workouts("workouts"),
    Browse("browse"),

    // Browse rows.
    Explore("explore?metric={metric}"),
    Coach("coach"),
    Insights("insights"),
    LabBook("lab_book"),
    Trends("trends"),
    InsightsHub("insights_hub"),
    Devices("devices"),
    Live("live"),
    Breathe("breathe"),

    // Pushed from a screen.
    // Coach settings (#2243), reached only from the strip on the Coach page; it shares Coach's view model.
    CoachSettings("coach_settings"),
    Intervals("intervals"),
    Stress("stress"),
    Hydration("hydration"),
    VitalSignsDetail("vital_detail/{key}"),
    AppleHealth("apple_health"),
    Automations("automations"),
    // "Alarms" is the one alarm surface (#766); the route id stays "smart_alarm".
    SmartAlarm("smart_alarm"),
    NoopLimitations("noop_limitations"),
    DataSources("data_sources"),
    BackupSync("backup_sync"),
    Notifications("notifications"),
    PowerSaving("power_saving"),
    Settings("settings"),
    // Experimental: reachable only through Settings > Advanced.
    SelfHostedPush("self_hosted_push"),
    // Shared by the Settings row and a blank WHOOP 4.0 Steps tile (#1515).
    StepsCalibration("steps_calibration"),
    TestCentre("test_centre"),
    GroundTruthCollector("ground_truth_collector"),
}

/** The Explore route, opened on one metric's key or (null) on the catalogue's first metric. */
internal fun exploreRoute(metricKey: String?): String =
    if (metricKey == null) "explore" else "explore?metric=${android.net.Uri.encode(metricKey)}"

/**
 * App shell: a [Scaffold] whose bottom bar is the Material 3 [NavigationBar] of [MainTab], over one
 * [NavHost]. Every screen draws its own title; there is no global toolbar. A single [AppViewModel] is
 * created here and shared with every screen, so the BLE connection and cached metrics stay app-wide.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot(viewModel: AppViewModel = viewModel()) {
    val nav = rememberNavController()
    val backStackEntry by nav.currentBackStackEntryAsState()
    val currentTab = remember(backStackEntry) { nav.currentTab() }
    val atTabRoot = backStackEntry?.destination?.route == currentTab.route
    // One re-tap counter per tab, read by that tab's root through [LocalScrollToTopSignal].
    val scrollTop = remember { mutableStateListOf(*Array(MainTab.entries.size) { 0 }) }

    val context = LocalContext.current
    // The Updates inbox (opened from the quick-actions sheet). A process singleton, so the Today cards and
    // the import path post to the same inbox this sheet renders.
    val updateStore = remember { UpdateStore.from(context) }
    var showQuickActions by remember { mutableStateOf(false) }
    var showUpdatesInbox by remember { mutableStateOf(false) }
    // #984: the changelog a What's New inbox row opens. Held here so it outlives the inbox sheet.
    var showWhatsNewFromInbox by remember { mutableStateOf(false) }
    // The running workout's full-screen recording, presented over whichever tab is showing (iOS presents it
    // from the root the same way). Guarded on an active workout so it never opens empty.
    var showActiveWorkout by remember { mutableStateOf(false) }
    val activeWorkout by viewModel.activeWorkout.collectAsStateWithLifecycle()

    /** Selects [tab] as a tap on it would: re-selecting pops to the root, then scrolls the root to the top. */
    fun onTabTapped(tab: MainTab) {
        when {
            tab != currentTab -> nav.selectTab(tab)
            !atTabRoot -> nav.popBackStack(tab.route, inclusive = false)
            else -> scrollTop[tab.ordinal] = scrollTop[tab.ordinal] + 1
        }
    }

    // Android Back on a tab root other than the Summary returns to the Summary, as Google's tabbed apps do;
    // Back on the Summary's root leaves the app. Pushed screens pop through the NavHost as usual.
    BackHandler(enabled = atTabRoot && currentTab != MainTab.Summary) {
        nav.selectTab(MainTab.Summary)
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.surface,
        bottomBar = {
            // Shown on tab roots and on pushed screens alike, as iOS keeps its tab bar. No recording is a
            // route to hide it for: the live workout is a full-screen dialog drawn over it, and the interval
            // and breathing sessions run inside their own screens.
            NavigationBar {
                MainTab.entries.forEach { tab ->
                    val selected = tab == currentTab
                    NavigationBarItem(
                        selected = selected,
                        onClick = { onTabTapped(tab) },
                        icon = {
                            Icon(if (selected) tab.selectedIcon else tab.unselectedIcon, contentDescription = null)
                        },
                        label = { Text(stringResource(tab.labelRes), maxLines = 1) },
                    )
                }
            }
        },
    ) { inner ->
        NavHost(
            navController = nav,
            startDestination = Destination.Today.route,
            modifier = Modifier.padding(inner),
            // Destinations crossfade (~240 ms) on the calm decelerating easing, forward and back alike.
            enterTransition = { fadeIn(navFadeSpec) },
            exitTransition = { fadeOut(navFadeSpec) },
            popEnterTransition = { fadeIn(navFadeSpec) },
            popExitTransition = { fadeOut(navFadeSpec) },
        ) {
            // --- Tab roots ---
            tabRoot(MainTab.Summary, scrollTop) {
                TodayScreen(
                    viewModel = viewModel,
                    // The "+" in the Today header opens the quick-actions sheet this shell presents.
                    onQuickActions = { showQuickActions = true },
                    updateStore = updateStore,
                    onOpenUpdates = { showUpdatesInbox = true },
                    // The profile avatar pushes Settings on the Summary (iOS: Summary avatar -> Settings).
                    onOpenSettings = { nav.push(Destination.Settings.route) },
                    onOpenHydration = { nav.push(Destination.Hydration.route) },
                    onOpenStress = { nav.push(Destination.Stress.route) },
                    // The Health screen is gone (iOS parity); its stale route lands on All Metrics.
                    onOpenHealth = { nav.push(exploreRoute(null)) },
                    // Every metric card opens its own detail trend (vital_detail/<key>).
                    onOpenMetric = { key -> nav.push("vital_detail/$key") },
                    onOpenStepsCalibration = { nav.push(Destination.StepsCalibration.route) },
                    onOpenSleep = { nav.showTabRoot(MainTab.Sleep) },
                    onOpenCoach = { nav.openCoach() },
                    // The "workout in progress" card: the Workouts tab, with the recording over it.
                    onOpenActiveWorkout = {
                        nav.showTabRoot(MainTab.Workouts)
                        showActiveWorkout = true
                    },
                    onOpenDevices = { nav.openInTab(MainTab.Browse, Destination.Devices.route) },
                    onOpenJournal = { nav.openInTab(MainTab.Browse, Destination.Insights.route) },
                )
            }
            tabRoot(MainTab.Sleep, scrollTop) {
                SleepScreen(
                    vm = viewModel,
                    onOpenJournal = { nav.openInTab(MainTab.Browse, Destination.Insights.route) },
                )
            }
            tabRoot(MainTab.Workouts, scrollTop) {
                WorkoutsScreen(viewModel, onOpenIntervals = { nav.push(Destination.Intervals.route) })
            }
            tabRoot(MainTab.Browse, scrollTop) {
                BrowseScreen(onOpen = { route -> nav.push(route) })
            }

            // --- Browse rows ---
            composable(
                Destination.Explore.route,
                arguments = listOf(navArgument("metric") { type = NavType.StringType; nullable = true }),
            ) { entry ->
                TrendsExploreScreen(viewModel, initialMetricKey = entry.arguments?.getString("metric"))
            }
            composable(Destination.Coach.route) {
                // A normal push, so Back returns to the conversation (#2243).
                CoachScreen(onOpenSettings = { nav.push(Destination.CoachSettings.route) })
            }
            composable(Destination.CoachSettings.route) {
                // The SAME CoachViewModel the conversation is using, not a fresh one: `viewModel()` resolves
                // against the NavBackStackEntry, and CoachViewModel keeps consent in memory, so a revoke made
                // against a second instance would leave the conversation sending on the old one. Coach is
                // always below this entry: it is reachable only from the strip on that screen.
                val coachEntry = remember(it) { nav.getBackStackEntry(Destination.Coach.route) }
                CoachSettingsScreen(vm = viewModel(coachEntry))
            }
            composable(Destination.Insights.route) {
                InsightsScreen(viewModel, onOpenInsightsHub = { nav.openInTab(MainTab.Browse, Destination.InsightsHub.route) })
            }
            composable(Destination.LabBook.route) { LabBookScreen(viewModel) }
            composable(Destination.Trends.route) { TrendsScreen(viewModel) }
            composable(Destination.InsightsHub.route) { InsightsHubScreen(viewModel) }
            composable(Destination.Devices.route) {
                DevicesScreen(viewModel, onUseFileImport = { nav.push(Destination.DataSources.route) })
            }
            composable(Destination.Live.route) {
                LiveScreen(viewModel = viewModel, onManageDevices = { nav.openInTab(MainTab.Browse, Destination.Devices.route) })
            }
            composable(Destination.Breathe.route) { BreatheScreen(viewModel) }

            // --- Pushed from a screen ---
            composable(Destination.Intervals.route) { IntervalsScreen(viewModel) }
            composable(Destination.Stress.route) {
                StressScreen(vm = viewModel, onBreathe = { nav.openInTab(MainTab.Browse, Destination.Breathe.route) })
            }
            composable(Destination.Hydration.route) { HydrationScreen(viewModel) }
            composable(Destination.VitalSignsDetail.route) { entry ->
                VitalDetailScreen(vm = viewModel, key = entry.arguments?.getString("key").orEmpty())
            }
            composable(Destination.AppleHealth.route) { AppleHealthScreen(viewModel) }
            composable(Destination.Automations.route) { AutomationsScreen(viewModel) }
            composable(Destination.SmartAlarm.route) { SmartAlarmScreen(viewModel) }
            composable(Destination.DataSources.route) { DataSourcesScreen(viewModel) }
            composable(Destination.NoopLimitations.route) { NoopLimitationsScreen() }
            composable(Destination.BackupSync.route) { BackupSyncScreen() }
            composable(Destination.Notifications.route) { NotificationsSettingsScreen(viewModel) }
            composable(Destination.PowerSaving.route) { PowerSavingScreen(viewModel) }
            composable(Destination.Settings.route) {
                SettingsScreen(
                    viewModel,
                    onOpenTestCentre = { nav.push(Destination.TestCentre.route) },
                    onOpenBackupSync = { nav.push(Destination.BackupSync.route) },
                    onOpenSelfHostedPush = { nav.push(Destination.SelfHostedPush.route) },
                    onOpenStepsCalibration = { nav.push(Destination.StepsCalibration.route) },
                    onOpenScreen = { nav.push(it.route) },
                )
            }
            composable(Destination.StepsCalibration.route) {
                val profile = remember(context) { ProfileStore.from(context) }
                var revision by remember { mutableStateOf(0) }
                // ProfileStore wraps SharedPreferences rather than snapshot state. Reading this counter
                // makes manual coefficient changes repaint the canonical screen immediately.
                @Suppress("UNUSED_VARIABLE") val tick = revision
                StepsCalibrationScreen(
                    vm = viewModel,
                    profile = profile,
                    onProfileChanged = { revision++ },
                    onClose = { nav.popBackStack() },
                )
            }
            composable(Destination.SelfHostedPush.route) { SelfHostedPushScreen() }
            composable(Destination.TestCentre.route) {
                TestCentreScreen(viewModel, onOpenGroundTruthCollector = {
                    nav.push(Destination.GroundTruthCollector.route)
                })
            }
            composable(Destination.GroundTruthCollector.route) { GroundTruthCollectorScreen(viewModel) }
        }
    }

    // The quick-actions sheet, opened by the "+" in the Today header. Each row opens the screen where it
    // now lives: Heart Rate, Journal and Mindfulness in Browse, a workout on the Workouts tab.
    if (showQuickActions) {
        ModalBottomSheet(onDismissRequest = { showQuickActions = false }) {
            Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 24.dp)) {
                Text(
                    stringResource(R.string.l10n_today_screen_quick_actions_e47e8042),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, top = 4.dp, bottom = 6.dp),
                )
                // The Updates inbox, one tap away with its unread count.
                NavigationDrawerItem(
                    selected = false,
                    onClick = {
                        showQuickActions = false
                        showUpdatesInbox = true
                    },
                    icon = { Icon(Icons.Filled.Notifications, contentDescription = null) },
                    label = { Text(stringResource(R.string.l10n_app_root_updates_c76d1807)) },
                    badge = {
                        val unread = updateStore.unreadCount
                        if (unread > 0) {
                            Text(
                                if (unread > 99) "99+" else unread.toString(),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                    modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding),
                )
                quickActions.forEach { action ->
                    NavigationDrawerItem(
                        selected = false,
                        onClick = {
                            showQuickActions = false
                            when (action.target) {
                                QuickActionTarget.LiveHeartRate -> nav.openInTab(MainTab.Browse, Destination.Live.route)
                                QuickActionTarget.StartWorkout -> nav.showTabRoot(MainTab.Workouts)
                                QuickActionTarget.LogJournal -> nav.openInTab(MainTab.Browse, Destination.Insights.route)
                                QuickActionTarget.Breathe -> nav.openInTab(MainTab.Browse, Destination.Breathe.route)
                            }
                        },
                        icon = { Icon(action.icon, contentDescription = null) },
                        label = { Text(stringResource(action.titleRes)) },
                        modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding),
                    )
                }
            }
        }
    }

    // The Updates inbox. Presented here so its deep links can navigate the tabs: "trends" pushes Trends on
    // the Summary, as the iOS router does.
    if (showUpdatesInbox) {
        ModalBottomSheet(
            onDismissRequest = { showUpdatesInbox = false },
            // Full height, over the legacy canvas colour its NoopCards are drawn to stand out on.
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = Palette.surfaceBase,
            contentColor = Palette.textPrimary,
        ) {
            UpdatesInboxScreen(
                store = updateStore,
                onClose = { showUpdatesInbox = false },
                onDeepLink = { key ->
                    // #984: What's New is a full-screen sheet (the one Settings > About opens), not a route.
                    when (key) {
                        UpdateStore.WHATS_NEW_DEEP_LINK -> showWhatsNewFromInbox = true
                        "trends" -> nav.openInTab(MainTab.Summary, Destination.Trends.route)
                        else -> Unit
                    }
                },
                onRestore = { cardId ->
                    // Flip the shared dismissed flag back off so the card reappears, and signal a mounted
                    // Today to re-read it immediately (SharedPreferences isn't reactive).
                    TodayCardDismissal.setDismissed(context, cardId, false)
                    updateStore.restoreRequest = cardId
                },
            )
        }
    }

    // #984: the changelog a What's New inbox row opens, the same full-screen dialog Settings > About uses.
    if (showWhatsNewFromInbox) {
        Dialog(
            onDismissRequest = { showWhatsNewFromInbox = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Surface(modifier = Modifier.fillMaxSize(), color = Palette.surfaceBase) {
                WhatsNewSheet(onClose = { showWhatsNewFromInbox = false })
            }
        }
    }

    if (showActiveWorkout && activeWorkout != null) {
        Dialog(
            onDismissRequest = { showActiveWorkout = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            LiveWorkoutScreen(vm = viewModel, onClose = { showActiveWorkout = false })
        }
    }
}

/**
 * Registers [tab]'s root screen. The root reads its own tab's re-tap counter, so the value it sees never
 * changes because another tab was selected (only a re-tap of this tab moves it).
 */
private fun androidx.navigation.NavGraphBuilder.tabRoot(
    tab: MainTab,
    scrollTop: List<Int>,
    content: @Composable (NavBackStackEntry) -> Unit,
) {
    composable(tab.route) { entry ->
        CompositionLocalProvider(LocalScrollToTopSignal provides scrollTop[tab.ordinal]) {
            content(entry)
        }
    }
}

/**
 * Selects [tab]: everything above the graph is popped with its state saved (the tab being left, root
 * included), then [tab]'s saved stack is restored, or its root pushed the first time. Popping to the
 * graph rather than to the start destination treats all four tabs alike, so the Summary's pushed screens
 * survive a trip to another tab as reliably as any other tab's do.
 */
private fun NavHostController.selectTab(tab: MainTab) {
    navigate(tab.route) {
        popUpTo(graph.id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}

/** True when an entry for [route] is on the back stack. */
private fun NavHostController.hasBackStackEntry(route: String): Boolean =
    runCatching { getBackStackEntry(route) }.isSuccess

/**
 * The tab whose root is on the back stack. Exactly one is: a tab switch pops everything down to the graph
 * before the next tab's stack goes on, and no screen pushes a tab root.
 */
private fun NavHostController.currentTab(): MainTab =
    MainTab.entries.firstOrNull { hasBackStackEntry(it.route) } ?: MainTab.Summary

/** Shows [tab] at its root (a quick action, the Today Sleep card). */
private fun NavHostController.showTabRoot(tab: MainTab) {
    if (tab != currentTab()) selectTab(tab)
    popBackStack(tab.route, inclusive = false)
}

/**
 * Opens [route] inside [tab], as a tap on its row would. From another tab the target tab starts from its
 * root, so Back from the opened screen lands on that tab's root (iOS `openInBrowse`); inside the tab it
 * pushes on top, so Back returns to the screen that asked.
 */
private fun NavHostController.openInTab(tab: MainTab, route: String) {
    if (tab != currentTab()) {
        selectTab(tab)
        popBackStack(tab.route, inclusive = false)
    }
    push(route)
}

/** Pushes [route] on the current tab (never twice on top of itself). */
private fun NavHostController.push(route: String) {
    navigate(route) { launchSingleTop = true }
}

/** Opens Coach in Browse; dropped while the AI Coach switch is off (a stale brief tap still asks). */
private fun NavHostController.openCoach() {
    if (CoachEnabledStore.enabled) openInTab(MainTab.Browse, Destination.Coach.route)
}

/** Where a quick action goes; the shell resolves it to a tab and a screen. */
private enum class QuickActionTarget { LiveHeartRate, StartWorkout, LogJournal, Breathe }

/** A quick action in the Today "+" sheet: its title, icon and target. */
private data class QuickAction(@StringRes val titleRes: Int, val icon: ImageVector, val target: QuickActionTarget)

/** The quick actions, in the order the sheet lists them. */
private val quickActions: List<QuickAction> = listOf(
    QuickAction(R.string.action_live_hr, Icons.Filled.MonitorHeart, QuickActionTarget.LiveHeartRate),
    QuickAction(R.string.action_start_workout, Icons.Filled.FitnessCenter, QuickActionTarget.StartWorkout),
    QuickAction(R.string.action_log_journal, Icons.AutoMirrored.Filled.MenuBook, QuickActionTarget.LogJournal),
    QuickAction(R.string.action_breathe, Icons.Filled.Air, QuickActionTarget.Breathe),
)

// MARK: - Navigation motion
//
// The calm, decelerating cubic-bezier(0.22, 1, 0.36, 1): nothing bounces or overshoots. Destinations
// crossfade over ~240 ms, and back navigation uses the same spec.

/** The calm global easing curve (cubic-bezier 0.22, 1, 0.36, 1). */
private val NavEasing = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)

/** ~240 ms crossfade on the calm easing. */
private val navFadeSpec = tween<Float>(durationMillis = 240, easing = NavEasing)
