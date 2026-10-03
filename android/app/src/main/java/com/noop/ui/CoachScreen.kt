package com.noop.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.HapticFeedbackConstants
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.findRootCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.noop.R
import com.noop.ai.AiProvider
import com.noop.ai.ChatMsg
import com.noop.ui.m3.EmptyState
import com.noop.ui.m3.Health
import java.time.format.DateTimeFormatter

/**
 * AI Coach, drawn as a Google Messages conversation (port of Denis's iOS 26 Messages-style Coach): a top
 * app bar with the Coach's gradient avatar, "AI Coach" and "{provider} · AI can make mistakes", and the
 * settings action; reply bubbles on the left in surfaceContainerHigh (Markdown), question bubbles on the
 * right in primary, grouped corners, day stamps, the "Today's Brief" label, "Stopped" under a cut-off
 * reply, the typing bubble, and "Not Delivered" with Try Again / Update Key; a long-press menu (Copy,
 * Share, Save to Journal, Try Again); suggestion chips above a pill field with the mic, and a send button
 * that turns into Stop while a reply is being written.
 *
 * Strictly opt-in and bring-your-own-key. Nothing is sent until a provider is connected and the wearer
 * asks: a typed question, a chip, or the "Today's Brief" chip. Opening the chat sends nothing (CR-10).
 * Not connected, the screen is an empty state whose "Set Up" opens the Coach settings page.
 */
@Composable
fun CoachScreen(
    vm: CoachViewModel = viewModel(),
    onBack: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
) {
    val context = LocalContext.current
    val keyVersion by vm.keyVersion.collectAsStateWithLifecycle()
    val provider by vm.provider.collectAsStateWithLifecycle()
    val customConnected by vm.customConnected.collectAsStateWithLifecycle()
    // Re-evaluate the gate whenever the stored key, provider, or custom-connect state changes.
    val configured = remember(keyVersion, provider, customConnected) { vm.isConfigured(context) }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        CoachTopBar(provider = provider, onBack = onBack, onOpenSettings = onOpenSettings)
        if (configured) {
            CoachConversation(vm = vm, onOpenSettings = onOpenSettings, modifier = Modifier.weight(1f))
        } else {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                EmptyState(
                    icon = Icons.Filled.AutoAwesome,
                    title = stringResource(R.string.coach_empty_title),
                    message = stringResource(R.string.coach_empty_message),
                    action = stringResource(R.string.coach_set_up),
                    onAction = onOpenSettings,
                )
            }
        }
    }
}

// MARK: - Top app bar

/** The provider as the screen names it: the brand, or "Custom Server" for the wearer's own. */
@Composable
internal fun coachProviderLabel(p: AiProvider): String =
    if (p == AiProvider.CUSTOM) stringResource(R.string.coach_custom_server) else p.displayName

/** The Coach's gradient avatar with its sparkle (Messages' contact picture). */
@Composable
internal fun CoachAvatar(size: androidx.compose.ui.unit.Dp = 40.dp) {
    val brush = Brush.linearGradient(listOf(Health.colors.rest, Health.colors.stageRem))
    Box(
        modifier = Modifier.size(size).clip(CircleShape).background(brush),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Filled.AutoAwesome,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.inverseOnSurface,
            modifier = Modifier.size(size * 0.55f),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CoachTopBar(provider: AiProvider, onBack: () -> Unit, onOpenSettings: () -> Unit) {
    val who = if (provider == AiProvider.CUSTOM) stringResource(R.string.coach_your_server) else provider.displayName
    TopAppBar(
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back))
            }
        },
        title = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CoachAvatar()
                Column(Modifier.semantics(mergeDescendants = true) { heading() }) {
                    Text(
                        stringResource(R.string.coach_title),
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        stringResource(R.string.coach_subtitle, who),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        },
        actions = {
            IconButton(onClick = onOpenSettings) {
                Icon(Icons.Filled.Tune, contentDescription = stringResource(R.string.coach_settings))
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        // The app Scaffold already pads its content below the status bar.
        windowInsets = WindowInsets(0, 0, 0, 0),
    )
}

// MARK: - Conversation

/** One line of the transcript as drawn, oldest first (the list renders it reversed, anchored low). */
private sealed interface TranscriptRow {
    val key: String

    data class Stamp(override val key: String, val ms: Long) : TranscriptRow
    data class BriefLabel(override val key: String) : TranscriptRow
    data class Bubble(
        override val key: String,
        val msg: ChatMsg,
        val followsSameSide: Boolean,
        val first: Boolean,
        val failed: Boolean,
        val isLast: Boolean,
    ) : TranscriptRow
    data class Stopped(override val key: String) : TranscriptRow
    data object Typing : TranscriptRow { override val key = "typing" }
    data class ErrorLine(val text: String) : TranscriptRow { override val key = "error" }
}

private fun transcriptRows(
    shown: List<ChatMsg>,
    times: Map<String, Long>,
    sending: Boolean,
    error: String?,
    allMessages: List<ChatMsg>,
): List<TranscriptRow> {
    val ids = shown.map { it.id }
    val failedIdx = CoachConversationRules.failedQuestionIndex(shown, sending, error)
    val rows = mutableListOf<TranscriptRow>()
    shown.forEachIndexed { i, m ->
        CoachConversationRules.stampBefore(i, ids, times)?.let { rows += TranscriptRow.Stamp("stamp-${m.id}", it) }
        if (m.role == "assistant" && m.isBrief) rows += TranscriptRow.BriefLabel("brief-${m.id}")
        val prev = shown.getOrNull(i - 1)
        rows += TranscriptRow.Bubble(
            key = m.id,
            msg = m,
            followsSameSide = prev != null && prev.role == m.role && !prev.isInterrupted,
            first = i == 0,
            failed = failedIdx == i,
            isLast = i == shown.lastIndex,
        )
        if (m.role == "assistant" && m.isInterrupted) rows += TranscriptRow.Stopped("stopped-${m.id}")
    }
    if (CoachConversationRules.showsTyping(allMessages, sending)) rows += TranscriptRow.Typing
    if (!error.isNullOrEmpty() && failedIdx == null && !sending) rows += TranscriptRow.ErrorLine(error)
    return rows
}

@Composable
private fun CoachConversation(vm: CoachViewModel, onOpenSettings: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val view = LocalView.current
    val messages by vm.messages.collectAsStateWithLifecycle()
    val times by vm.messageTimes.collectAsStateWithLifecycle()
    val sending by vm.sending.collectAsStateWithLifecycle()
    val error by vm.error.collectAsStateWithLifecycle()
    val keyRejected by vm.keyRejected.collectAsStateWithLifecycle()
    val consent by vm.consent.collectAsStateWithLifecycle()
    val contextual by vm.suggestions.collectAsStateWithLifecycle()
    // K15: the composer draft is persisted to SharedPreferences so it survives an app relaunch.
    // Restored on first composition, saved on every change. Keyed identically to the iOS twin.
    val draftPrefs = remember { context.getSharedPreferences("noop_coach_draft", android.content.Context.MODE_PRIVATE) }
    var draft by remember { mutableStateOf(draftPrefs.getString("draft", "") ?: "") }
    fun setDraft(value: String) {
        draft = value
        draftPrefs.edit().putString("draft", value).apply()
        if (error != null && !sending) vm.clearError()
    }
    var showFailure by remember { mutableStateOf(false) }

    // K2 + K5 ordering matters and both gate on an EMPTY transcript, so this is ONE coroutine,
    // sequential: restore whatever the prior launch persisted FIRST, retire it if it belongs to an
    // earlier day, THEN surface a brief the scheduled notification already generated (if any) — so K5
    // never overwrites K2's restore, and never appends a duplicate brief onto a transcript K2 just
    // repopulated. Nothing here reaches the provider: the interactive brief is only ever asked for by
    // its chip (CR-10).
    LaunchedEffect(Unit) {
        vm.loadPersistedMessagesIfNeeded()
        // The load runs once per PROCESS, so on a process kept alive overnight it returns without
        // re-checking the day and leaves yesterday's chat in memory, which K5 then refuses to replace.
        // Retiring here is what lets today's brief reach the screen at all (#2087).
        vm.retireStaleConversationIfNeeded()
        vm.consumeScheduledBriefIfAny(context)
    }
    // The contextual chips are re-derived when the chat empties, so a fresh sync updates them.
    LaunchedEffect(messages.isEmpty()) { if (messages.isEmpty()) vm.refreshSuggestions() }

    // K14 / CO-6: one haptic per outcome, and TalkBack reads what came (the start of the reply, or why it
    // failed). Nothing for a stop, which the wearer has just done themselves.
    var wasSending by remember { mutableStateOf(false) }
    val replyReceived = stringResource(R.string.coach_reply_received)
    LaunchedEffect(sending) {
        if (wasSending && !sending && messages.isNotEmpty()) {
            val failed = !error.isNullOrEmpty()
            val feedback = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                    if (failed) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.CONFIRM
                else -> HapticFeedbackConstants.KEYBOARD_TAP
            }
            view.performHapticFeedback(feedback)
            val last = messages.last()
            val announcement = when {
                failed -> error
                last.role == "assistant" && !last.isInterrupted ->
                    last.text.replace(Regex("[*_`#|]"), "").trim().take(200).ifEmpty { replyReceived }
                else -> null
            }
            @Suppress("DEPRECATION")
            if (announcement != null) view.announceForAccessibility(announcement)
        }
        wasSending = sending
    }

    val shown = remember(messages) { CoachConversationRules.shown(messages) }
    val rows = remember(shown, times, sending, error, messages) { transcriptRows(shown, times, sending, error, messages) }
    val reversed = remember(rows) { rows.asReversed() }
    val listState = rememberLazyListState()
    // A new message (or the typing bubble) scrolls the conversation to its end, as Messages does.
    LaunchedEffect(shown.size, sending) { if (rows.isNotEmpty()) listState.animateScrollToItem(0) }

    val canRetry = remember(messages, sending, consent) { vm.canRetryLastReply(context) }

    // The composer sits on the keyboard: the part of the IME height not already covered by the
    // navigation bar under this screen is added below it. While the conversation shows, the window is
    // told not to pan for the keyboard (which would push the app bar off screen); edge to edge it does
    // not resize either, so this padding is the only thing that moves.
    DisposableEffect(view) {
        val window = (view.context.findActivity())?.window
        val previous = window?.attributes?.softInputMode
        window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        onDispose { if (window != null && previous != null) window.setSoftInputMode(previous) }
    }
    val density = LocalDensity.current
    var bottomGapPx by remember { mutableIntStateOf(0) }
    val imeBottom = WindowInsets.ime.getBottom(density)
    val lift = with(density) { (imeBottom - bottomGapPx).coerceAtLeast(0).toDp() }

    Column(
        modifier
            .fillMaxWidth()
            .onGloballyPositioned { c ->
                val root = c.findRootCoordinates()
                bottomGapPx = (root.size.height - c.boundsInRoot().bottom).toInt().coerceAtLeast(0)
            }
            .padding(bottom = lift),
    ) {
        LazyColumn(
            state = listState,
            reverseLayout = true,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 16.dp),
        ) {
            items(reversed, key = { it.key }) { row ->
                when (row) {
                    is TranscriptRow.Stamp -> StampLine(row.ms)
                    is TranscriptRow.BriefLabel -> MetaLine(stringResource(R.string.coach_todays_brief), top = 8.dp)
                    is TranscriptRow.Bubble -> BubbleRow(
                        row = row,
                        canRetry = row.isLast && canRetry,
                        keyRejected = keyRejected,
                        onRetryReply = { vm.retryLastReply(context) },
                        onShowFailure = { showFailure = true },
                        onUpdateKey = onOpenSettings,
                        onSaveToJournal = { vm.saveAdviceToJournal(it) },
                    )
                    is TranscriptRow.Stopped -> MetaLine(stringResource(R.string.coach_stopped), top = 2.dp)
                    TranscriptRow.Typing -> TypingBubble()
                    is TranscriptRow.ErrorLine -> ErrorLine(row.text, keyRejected, onUpdateKey = onOpenSettings)
                }
            }
        }

        val hasDraft = draft.isNotBlank()
        if (!hasDraft && !sending) {
            val chips = CoachConversationRules.suggestions(
                messages = messages,
                configured = true,
                consent = consent,
                contextual = contextual,
                followUps = vm.followUpSuggestions,
            )
            SuggestionRow(chips = chips, onChoose = { chip ->
                when (chip) {
                    CoachSuggestion.Brief -> vm.startBrief(context)
                    is CoachSuggestion.Prompt -> {
                        val text = coachPromptText(context, chip.english)
                        vm.send(context, text)
                    }
                }
            })
        }

        Composer(
            draft = draft,
            onDraftChange = ::setDraft,
            sending = sending,
            onSend = {
                val text = draft
                if (text.isNotBlank() && !sending) {
                    vm.send(context, text)
                    setDraft("")
                }
            },
            onStop = { vm.stop() },
        )
    }

    if (showFailure) {
        val message = error.orEmpty()
        AlertDialog(
            onDismissRequest = { showFailure = false },
            text = { Text(message) },
            confirmButton = {
                Row {
                    if (keyRejected) {
                        TextButton(onClick = { showFailure = false; onOpenSettings() }) {
                            Text(stringResource(R.string.coach_update_key))
                        }
                    }
                    TextButton(onClick = { showFailure = false; vm.retryFailedQuestion(context) }) {
                        Text(stringResource(R.string.coach_try_again))
                    }
                }
            },
            dismissButton = {
                TextButton(onClick = { showFailure = false }) { Text(stringResource(R.string.coach_cancel)) }
            },
        )
    }
}

// MARK: - Transcript pieces

@Composable
private fun StampLine(ms: Long) {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val now = remember { System.currentTimeMillis() }
    val date = coachLocalDate(ms)
    val word = when (CoachConversationRules.dayWord(ms, now)) {
        CoachDayWord.TODAY -> stringResource(R.string.coach_stamp_today)
        CoachDayWord.YESTERDAY -> stringResource(R.string.coach_stamp_yesterday)
        CoachDayWord.WEEKDAY -> date.format(DateTimeFormatter.ofPattern("EEEE", locale))
            .replaceFirstChar { it.titlecase(locale) }
        CoachDayWord.DATE -> date.format(DateTimeFormatter.ofPattern("EEE d MMM", locale))
    }
    val pattern = if (ClockPrefs.uses24Hour(context)) "HH:mm" else "h:mm a"
    val time = java.time.Instant.ofEpochMilli(ms).atZone(java.time.ZoneId.systemDefault())
        .format(DateTimeFormatter.ofPattern(pattern, locale))
    Text(
        "$word · $time",
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 4.dp),
    )
}

/** A line in the transcript's small grey type on the reply side (the brief's name, "Stopped"). */
@Composable
private fun MetaLine(text: String, top: androidx.compose.ui.unit.Dp) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.fillMaxWidth().padding(start = 12.dp, top = top, bottom = 2.dp),
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BubbleRow(
    row: TranscriptRow.Bubble,
    canRetry: Boolean,
    keyRejected: Boolean,
    onRetryReply: () -> Unit,
    onShowFailure: () -> Unit,
    onUpdateKey: () -> Unit,
    onSaveToJournal: (String) -> Unit,
) {
    val msg = row.msg
    val outgoing = msg.role == "user"
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    var menu by remember { mutableStateOf(false) }
    val maxWidth = (LocalConfiguration.current.screenWidthDp * 0.78f).dp
    val corners = CoachConversationRules.bubbleCorners(outgoing, row.followsSameSide)
    val shape = RoundedCornerShape(corners[0].dp, corners[1].dp, corners[2].dp, corners[3].dp)
    val said = stringResource(if (outgoing) R.string.coach_you_said else R.string.coach_coach_said, msg.text)
    // Messages' spacing: a run from one side sits close, a new speaker starts a little further down.
    val top = when {
        row.first -> 0.dp
        row.followsSameSide -> 2.dp
        else -> 10.dp
    }

    Column(Modifier.fillMaxWidth().padding(top = top)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = if (outgoing) Arrangement.End else Arrangement.Start,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (row.failed) {
                IconButton(onClick = onShowFailure) {
                    Icon(
                        Icons.Filled.ErrorOutline,
                        contentDescription = stringResource(R.string.coach_not_delivered),
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            }
            Box {
                Surface(
                    shape = shape,
                    color = if (outgoing) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHigh,
                    contentColor = if (outgoing) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier
                        .widthIn(max = maxWidth)
                        .clip(shape)
                        .combinedClickable(onClick = {}, onLongClick = { menu = true })
                        .clearAndSetSemantics { contentDescription = said },
                ) {
                    Box(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                        if (outgoing) {
                            // Questions stay verbatim, so a typed `*` or `#` never turns into formatting.
                            Text(msg.text, style = MaterialTheme.typography.bodyLarge)
                        } else {
                            CoachMarkdown(msg.text, color = MaterialTheme.colorScheme.onSurface)
                        }
                    }
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.coach_copy_action)) },
                        leadingIcon = { Icon(Icons.Filled.ContentCopy, null) },
                        onClick = { clipboard.setText(AnnotatedString(msg.text)); menu = false },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.coach_share_action)) },
                        leadingIcon = { Icon(Icons.Filled.Share, null) },
                        onClick = {
                            menu = false
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, msg.text)
                            }
                            context.startActivity(Intent.createChooser(send, null))
                        },
                    )
                    if (!outgoing) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.coach_save_to_journal)) },
                            leadingIcon = { Icon(Icons.AutoMirrored.Filled.MenuBook, null) },
                            onClick = { onSaveToJournal(msg.text); menu = false },
                        )
                        if (canRetry) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.coach_try_again)) },
                                leadingIcon = { Icon(Icons.Filled.Refresh, null) },
                                onClick = { menu = false; onRetryReply() },
                            )
                        }
                    }
                }
            }
        }
        if (row.failed) {
            Text(
                stringResource(R.string.coach_not_delivered),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth().padding(end = 12.dp, top = 4.dp),
            )
            if (keyRejected) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onUpdateKey) { Text(stringResource(R.string.coach_update_key)) }
                }
            }
        }
    }
}

/** The three-dot typing bubble, breathing while a reply is on its way; posed still (stepped dots) under
 *  Remove animations or battery saver (#909). */
@Composable
private fun TypingBubble() {
    val label = stringResource(R.string.coach_thinking)
    val still = rememberPoseStill()
    Row(Modifier.fillMaxWidth().padding(top = 10.dp)) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(20.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .padding(horizontal = 18.dp, vertical = 14.dp)
                .clearAndSetSemantics { contentDescription = label },
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            val transition = if (still) null else rememberInfiniteTransition(label = "typing")
            repeat(3) { i ->
                val alpha = transition?.animateFloat(
                    initialValue = 0.3f,
                    targetValue = 1f,
                    animationSpec = infiniteRepeatable(tween(600, delayMillis = i * 180), RepeatMode.Reverse),
                    label = "typingDot",
                )?.value ?: (1f - i * 0.35f)
                Box(
                    Modifier
                        .size(8.dp)
                        .alpha(alpha)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.onSurfaceVariant),
                )
            }
        }
    }
}

/** A failure with no question of its own to mark (the brief, or a reply cut off mid-way). */
@Composable
private fun ErrorLine(text: String, keyRejected: Boolean, onUpdateKey: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        if (keyRejected) TextButton(onClick = onUpdateKey) { Text(stringResource(R.string.coach_update_key)) }
    }
}

// MARK: - Composer

/** The engine's English prompts, as the screen shows and sends them in the app's language. */
private val PROMPT_RES: Map<String, Int> = mapOf(
    "How's my recovery trending this week?" to R.string.coach_prompt_recovery_week,
    "What should today's training look like?" to R.string.coach_prompt_training_today,
    "Analyse my sleep" to R.string.coach_prompt_analyse_sleep,
    "Why am I run down?" to R.string.coach_prompt_run_down,
    "Active recovery only today — what should I do?" to R.string.coach_prompt_active_recovery,
    "Quality over volume today — plan my session" to R.string.coach_prompt_quality_volume,
    "Green light — how hard can I push today?" to R.string.coach_prompt_green_light,
    "Why is my HRV trending down?" to R.string.coach_prompt_hrv_down,
    "I slept poorly — how do I recover today?" to R.string.coach_prompt_slept_poorly,
    "Have I done enough today, or push more?" to R.string.coach_prompt_done_enough,
    "Tell me more about that" to R.string.coach_prompt_tell_more,
    "What should I do next?" to R.string.coach_prompt_next,
    "How does today compare to this week?" to R.string.coach_prompt_compare_week,
    "Give me a specific action plan" to R.string.coach_prompt_action_plan,
)

internal fun coachPromptText(context: android.content.Context, english: String): String =
    PROMPT_RES[english]?.let { context.getString(it) } ?: english

@Composable
private fun SuggestionRow(chips: List<CoachSuggestion>, onChoose: (CoachSuggestion) -> Unit) {
    if (chips.isEmpty()) return
    val context = LocalContext.current
    LazyRow(
        contentPadding = PaddingValues(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
    ) {
        itemsIndexed(chips) { i, chip ->
            val label = when (chip) {
                CoachSuggestion.Brief -> stringResource(R.string.coach_todays_brief)
                is CoachSuggestion.Prompt -> coachPromptText(context, chip.english)
            }
            val a11y = stringResource(R.string.coach_suggested_prompt, label)
            SuggestionChip(
                onClick = { onChoose(chip) },
                label = { Text(label, maxLines = 1) },
                icon = if (i == 0) {
                    { Icon(Icons.Filled.AutoAwesome, null, tint = Health.colors.rest, modifier = Modifier.size(SuggestionChipDefaults.IconSize)) }
                } else null,
                modifier = Modifier.semantics { contentDescription = a11y },
            )
        }
    }
}

/**
 * The entry row: a pill field with the mic inside it, and the send button beside it, which turns into
 * Stop while a reply is being written. Dictation APPENDS to what was typed (CR-12) and stays stoppable
 * for the whole recording; the microphone permission is asked on the first tap, and once refused the
 * mic opens the app's settings instead.
 */
@Composable
private fun Composer(
    draft: String,
    onDraftChange: (String) -> Unit,
    sending: Boolean,
    onSend: () -> Unit,
    onStop: () -> Unit,
) {
    val context = LocalContext.current
    var recording by remember { mutableStateOf(false) }
    var voiceStatus by remember { mutableStateOf<String?>(null) }
    var micRefused by remember { mutableStateOf(false) }
    // The draft as it was when dictation started; the live transcript is appended to it, never over it.
    var dictationBase by remember { mutableStateOf("") }
    val currentOnDraftChange by rememberUpdatedState(onDraftChange)

    val voiceInput = remember {
        CoachVoiceInput(
            context = context,
            onPartial = { partial -> currentOnDraftChange(CoachConversationRules.dictationDraft(dictationBase, partial)) },
            onFinal = { final ->
                // The transcript is already in the draft; the final text only settles it.
                if (final.isNotBlank()) currentOnDraftChange(CoachConversationRules.dictationDraft(dictationBase, final))
                recording = false
            },
            onError = { msg -> voiceStatus = msg; recording = false },
        )
    }
    DisposableEffect(voiceInput) { onDispose { voiceInput.destroy() } }

    fun startDictation() {
        dictationBase = draft.trim()
        voiceStatus = null
        voiceInput.start()
        recording = true
    }

    val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) startDictation() else micRefused = true
    }

    val voiceAvailable = remember { voiceInput.isAvailable() }
    val placeholder = stringResource(if (recording) R.string.coach_listening else R.string.coach_ask)
    val questionLabel = stringResource(R.string.coach_question)

    Column(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 12.dp)) {
        voiceStatus?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 20.dp, bottom = 6.dp),
            )
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 52.dp)
                    .clip(RoundedCornerShape(26.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                    .padding(start = 20.dp, end = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface)
                BasicTextField(
                    value = draft,
                    onValueChange = onDraftChange,
                    textStyle = textStyle,
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    maxLines = 6,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                        imeAction = ImeAction.Default,
                    ),
                    modifier = Modifier
                        .weight(1f)
                        .padding(vertical = 14.dp)
                        .semantics { contentDescription = questionLabel },
                    decorationBox = { inner ->
                        Box {
                            if (draft.isEmpty()) {
                                Text(placeholder, style = textStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            inner()
                        }
                    },
                )
                if (voiceAvailable) {
                    IconButton(
                        onClick = {
                            when {
                                recording -> voiceInput.stop()
                                voiceInput.isPermissionGranted() -> startDictation()
                                micRefused -> context.startActivity(
                                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                        .setData(Uri.fromParts("package", context.packageName, null)),
                                )
                                else -> permLauncher.launch(voiceInput.requiredPermission)
                            }
                        },
                        enabled = !sending,
                    ) {
                        Icon(
                            if (recording) Icons.Filled.StopCircle else Icons.Filled.Mic,
                            contentDescription = stringResource(
                                if (recording) R.string.coach_stop_voice_input else R.string.coach_voice_input,
                            ),
                            tint = if (recording) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            FilledIconButton(
                onClick = if (sending) onStop else onSend,
                enabled = sending || (draft.isNotBlank() && !recording),
                shape = RoundedCornerShape(18.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
                modifier = Modifier.size(52.dp),
            ) {
                if (sending) {
                    Icon(Icons.Filled.Stop, contentDescription = stringResource(R.string.coach_stop))
                } else {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = stringResource(R.string.coach_send))
                }
            }
        }
    }
}

/** The Activity behind a Compose context (which may be wrapped, e.g. for the app language). */
private tailrec fun android.content.Context.findActivity(): android.app.Activity? = when (this) {
    is android.app.Activity -> this
    is android.content.ContextWrapper -> baseContext.findActivity()
    else -> null
}
