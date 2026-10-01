package com.noop.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.noop.R

/**
 * The common Shown / Hidden editor body (the Sleep tab's section editor uses it). Items are never deleted:
 * remove moves one from Shown to Hidden, add restores it at the end of Shown, and the arrow controls use
 * the same ordering behavior in every editor. SnapshotStateList callers recompose on these mutations.
 */
@Composable
internal fun <T> EditableVisibilityRows(
    shown: MutableList<T>,
    hidden: MutableList<T>,
    itemTitle: (T) -> String,
    modifier: Modifier = Modifier,
    // Whether the Shown list may go EMPTY. Default false — the last shown item can't be hidden, so
    // surfaces needing >=1 item can't be emptied. The hosted-cards editor (#today-hosted-cards) passes
    // true (opt-in: un-hosting the last card is valid).
    allowEmpty: Boolean = false,
    // Optional grouping key for the Hidden ("Available") list. When set (the hosted-cards editor passes the
    // card's origin, e.g. "Sleep" / "Trends"), the Available items render under one sub-header per group so
    // a user browses by origin. null (Today sections, Key Metrics, Your Cards) keeps the flat list. The
    // Shown list stays flat — it is the user's own cross-origin order. Twin of the Swift EditableLayoutList.
    hiddenGroup: ((T) -> String)? = null,
) {
    val minShown = if (allowEmpty) 0 else 1
    Column(
        modifier = modifier
            .heightIn(max = Metrics.editorListMaxHeight)
            .verticalScroll(rememberScrollState()),
    ) {
        Text(stringResource(R.string.today_customize_shown), style = NoopType.overline, color = Palette.textTertiary)
        shown.forEachIndexed { index, item ->
            val title = itemTitle(item)
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = Metrics.space6),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, style = NoopType.body, color = Palette.textPrimary, modifier = Modifier.weight(1f))
                IconButton(
                    onClick = {
                        if (index > 0) shown.add(index - 1, shown.removeAt(index))
                    },
                    enabled = index > 0,
                    modifier = Modifier.size(Metrics.iconButton),
                ) {
                    Icon(
                        Icons.Filled.KeyboardArrowUp,
                        contentDescription = stringResource(R.string.today_customize_move_up, title),
                        tint = if (index > 0) Palette.textSecondary else Palette.textTertiary,
                        modifier = Modifier.size(Metrics.iconSmall),
                    )
                }
                IconButton(
                    onClick = {
                        if (index < shown.lastIndex) shown.add(index + 1, shown.removeAt(index))
                    },
                    enabled = index < shown.lastIndex,
                    modifier = Modifier.size(Metrics.iconButton),
                ) {
                    Icon(
                        Icons.Filled.KeyboardArrowDown,
                        contentDescription = stringResource(R.string.today_customize_move_down, title),
                        tint = if (index < shown.lastIndex) Palette.textSecondary else Palette.textTertiary,
                        modifier = Modifier.size(Metrics.iconSmall),
                    )
                }
                IconButton(
                    onClick = {
                        if (shown.size > minShown) hidden.add(shown.removeAt(index))
                    },
                    enabled = shown.size > minShown,
                    modifier = Modifier.size(Metrics.iconButton),
                ) {
                    Icon(
                        Icons.Filled.Close,
                        contentDescription = stringResource(R.string.today_customize_hide, title),
                        tint = if (shown.size > minShown) Palette.textSecondary else Palette.textTertiary,
                        modifier = Modifier.size(Metrics.iconSmall),
                    )
                }
            }
            if (index < shown.lastIndex) {
                HorizontalDivider(color = Palette.hairline, thickness = Metrics.divider)
            }
        }

        Spacer(Modifier.height(Metrics.space16))
        Text(stringResource(R.string.today_customize_hidden), style = NoopType.overline, color = Palette.textTertiary)
        if (hidden.isEmpty()) {
            Text(
                stringResource(R.string.today_customize_nothing_hidden),
                style = NoopType.body,
                color = Palette.textTertiary,
                modifier = Modifier.padding(vertical = Metrics.space12),
            )
        } else if (hiddenGroup != null) {
            // Grouped Available list: one sub-header per origin ("Sleep", "Trends"). Remove by identity
            // (items are unique) so the move is index-free across the regrouped display.
            val buckets = LinkedHashMap<String, MutableList<T>>()
            hidden.forEach { item -> buckets.getOrPut(hiddenGroup(item)) { ArrayList() }.add(item) }
            buckets.keys.toList().forEachIndexed { gi, groupName ->
                Text(
                    groupName,
                    style = NoopType.overline,
                    color = Palette.textTertiary,
                    modifier = Modifier.padding(top = if (gi == 0) Metrics.space4 else Metrics.space12),
                )
                val itemsIn = buckets.getValue(groupName)
                itemsIn.forEachIndexed { ii, item ->
                    val title = itemTitle(item)
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = Metrics.space6),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(title, style = NoopType.body, color = Palette.textTertiary, modifier = Modifier.weight(1f))
                        IconButton(
                            onClick = { hidden.remove(item); shown.add(item) },
                            modifier = Modifier.size(Metrics.iconButton),
                        ) {
                            Icon(
                                Icons.Filled.Add,
                                contentDescription = stringResource(R.string.today_customize_show, title),
                                tint = Palette.accent,
                                modifier = Modifier.size(Metrics.iconSmall),
                            )
                        }
                    }
                    if (ii < itemsIn.lastIndex) {
                        HorizontalDivider(color = Palette.hairline, thickness = Metrics.divider)
                    }
                }
            }
        } else {
            hidden.forEachIndexed { index, item ->
                val title = itemTitle(item)
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = Metrics.space6),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(title, style = NoopType.body, color = Palette.textTertiary, modifier = Modifier.weight(1f))
                    IconButton(
                        onClick = { shown.add(hidden.removeAt(index)) },
                        modifier = Modifier.size(Metrics.iconButton),
                    ) {
                        Icon(
                            Icons.Filled.Add,
                            contentDescription = stringResource(R.string.today_customize_show, title),
                            tint = Palette.accent,
                            modifier = Modifier.size(Metrics.iconSmall),
                        )
                    }
                }
                if (index < hidden.lastIndex) {
                    HorizontalDivider(color = Palette.hairline, thickness = Metrics.divider)
                }
            }
        }
    }
}
