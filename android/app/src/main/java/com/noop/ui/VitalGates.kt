package com.noop.ui

import com.noop.R
import androidx.annotation.StringRes

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
