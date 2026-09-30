package com.noop.ui

import androidx.compose.ui.graphics.Color

/**
 * The source badge (label + tint) for a merged [com.noop.data.DailyMetric], from the WINNING row's
 * [deviceId]. The numbers are always NOOP's on-device scores, but when an import covers the day it wins the
 * dashboard merge (mergeDaily), so the badge says so. A computed row's id ends in "-noop"; imports keep
 * their source id ("my-whoop" export, "apple-health" / "health-connect"). Brand wording matches the rest of
 * the app (macOS DaySource: "On-device"/"Whoop"/"Apple Health"); imports use the accent tint, computed rows
 * the charge tint. (Sleep overhaul §2.6; moved here from the removed Intelligence screen.)
 */
internal fun daySourceBadge(deviceId: String): Pair<String, Color> = when {
    deviceId.endsWith("-noop") -> "On-device" to Palette.chargeColor
    deviceId == com.noop.data.WhoopRepository.APPLE_HEALTH_SOURCE ||
        deviceId == com.noop.data.WhoopRepository.HEALTH_CONNECT_SOURCE -> "Apple Health" to Palette.accent
    // An Oura night is persisted under the ring's "oura-<uuid>" id (the ring PROVIDES its own SleepNet
    // hypnogram, banked as the merge-winning session) — name it "Oura", not the generic "Whoop" the
    // else-branch would give a non-"-noop" id. Resolved off the canonical brand table, not an "oura" literal.
    com.noop.data.DeviceBrandCatalog.isOura(deviceId) -> "Oura" to Palette.restColor
    else -> "Whoop" to Palette.accent
}
