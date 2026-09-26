import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import WhoopProtocol

// MARK: - Steps estimate calibration

/// Small shared formatters for the steps-estimate calibration UI — kept apart from the sheet so the
/// Profile-card summary row and the sheet agree on the confidence wording. Mirrors the Android
/// `StepsCalibrationFormat` object.
enum StepsCalibrationFormat {
    /// A 0–1 confidence as Low / Medium / High — the honest read-out the sheet and the summary row share.
    /// Thirds: < 0.34 Low, < 0.67 Medium, else High. A manual coefficient is confidence 1.0 → "High".
    static func confidenceLabel(_ confidence: Double) -> String {
        switch confidence {
        case ..<0.34: return String(localized: "Low")
        case ..<0.67: return String(localized: "Medium")
        default:      return String(localized: "High")
        }
    }
}

/// One recent day's estimated-vs-phone steps comparison row, for the sheet's accuracy table.
private struct StepsComparisonRow: Identifiable {
    let day: String          // yyyy-MM-dd
    let estimated: Int
    let actual: Int
    var id: String { day }
    /// Signed error of the estimate against the phone count, as a percentage (estimate − actual) / actual.
    var errorPct: Double { actual > 0 ? Double(estimated - actual) / Double(actual) * 100 : 0 }
}

/// WHOOP 4.0 steps-ESTIMATE calibration — honest explainer + current fit + a recent estimated-vs-phone
/// table + a manual coefficient override with a live preview. Presented as a sheet from Settings →
/// Profile → "Steps estimate". Reads the SAME data the engine fits against (the computed `steps_est`
/// series and the phone's `steps`), never recomputing the headline. Mirrors Android `StepsCalibrationScreen`.
// Internal (not file-private) so the Today Steps tile can present the SAME calibration sheet directly
// when it's showing an ESTIMATE for a WHOOP 4.0 user — one shared entry point, no duplicated screen (H6).
struct StepsCalibrationSheet: View {
    let repo: Repository
    let onClose: () -> Void
    @EnvironmentObject var profile: ProfileStore

    /// Recent days that have BOTH an estimate and a real phone step count, newest first — the accuracy table.
    @State private var comparison: [StepsComparisonRow] = []
    /// A representative recent motion volume (median of recent days' motion), used so the manual-coefficient
    /// preview reflects a TYPICAL day. nil until loaded / no recent estimated day with a known motion.
    @State private var sampleMotion: Double?

    /// The draft manual coefficient the slider edits, committed to ProfileStore on release. 0 = auto-fit.
    @State private var draftManual: Double = 0
    @State private var didLoad = false

    /// The strap has banked no motion, and we have looked.
    ///
    /// Named once because two places depend on it and they must stay exactly complementary: the
    /// no-motion banner appears, and the calibration countdown does NOT. Written as two separate
    /// expressions they drifted immediately — the guard's first draft tested `sampleMotion == nil`
    /// alone, which is also true during the load, so the countdown vanished in a window where the
    /// banner had not appeared yet and the card explained nothing at all.
    private var strapHasNoMotion: Bool { didLoad && sampleMotion == nil }

    /// #107: the sheet's guidance depends on the strap family. A WHOOP 4.0 streams motion automatically, so
    /// "let it sync" is right; a 5/MG only streams motion once the experimental deep-data unlock is on, so
    /// the 4.0 advice is futile there and the empty state must say so instead.
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue
    @AppStorage(PuffinExperiment.deepDataKey) private var deepDataEnabled = false
    private var is5MG: Bool { selectedWhoopModelRaw == WhoopModel.whoop5mg.rawValue }

    /// The coefficient the slider's max anchors to — generous headroom over whatever the auto-fit found so
    /// a manual nudge in either direction is reachable. Floor keeps the slider usable before any fit.
    private var sliderMax: Double {
        max(profile.stepsCalibrationCoefficient, profile.stepsManualCoefficient, 50) * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(StrandPalette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    explainerCard
                    if strapHasNoMotion { noMotionNote }
                    currentFitCard
                    comparisonCard
                    manualAdjustCard
                }
                .padding(20)
            }
            #if os(iOS)
            // #697/#horizontal-swipe parity, see ScreenScaffold.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            #endif
            Divider().overlay(StrandPalette.hairline)
            footerBar
        }
        #if os(macOS)
        .frame(width: 560, height: 680)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .noopSheetPresentation(largeFirst: true)
        #endif
        .background(StrandPalette.surfaceBase)
        .task { await loadIfNeeded() }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STEPS ESTIMATE").font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Calibrate your steps").font(StrandFont.rounded(26, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(is5MG ? "WHOOP 5.0 / MG · motion → steps" : "WHOOP 4.0 · motion → steps").font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(20)
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Text("Done").frame(minWidth: 120)
            }
            .buttonStyle(NoopButtonStyle(.primary))
            .keyboardShortcut(.defaultAction)
        }
        .padding(NoopMetrics.space4)
    }

    // MARK: Cards

    /// The honest "it's an estimate, not a step counter" framing — reused verbatim from the engine doc.
    private var explainerCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("How this works", systemImage: "figure.walk.motion")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(is5MG
                     ? String(localized: "NOOP estimates your steps from your WHOOP's stored motion, calibrated to your phone's step count. It's an estimate, not a hardware step counter; normal WHOOP 5/MG history sync supplies the motion data.")
                     : String(localized: "NOOP estimates your steps from your WHOOP's motion, calibrated to your phone's step count. It's an estimate, not a step counter. A WHOOP 4.0 doesn't transmit steps."))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("On the days your phone also counted steps, NOOP learns how much your motion maps to steps, then applies that to the strap-only days. The more matching days it has, the more it trusts the estimate.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Shown when the strap has banked NO motion yet (sampleMotion is nil) — the real reason a fresh
    /// WHOOP 4.0 shows zero steps (#37 bringiton321). Steps are built from the strap's synced motion
    /// history, so without a backfill there is nothing to estimate from — calibration can't help yet.
    ///
    /// #107: family-aware. A 4.0 streams motion automatically → "let it sync" is right. A 5/MG only streams
    /// motion once the experimental deep-data unlock is ON — so on a 5/MG the honest advice is "turn that on
    /// and reconnect", not "wait for a sync" (which never comes). Imports don't supply strap motion either.
    private var noMotionNote: some View {
        NoopCard(tint: StrandPalette.metricAmber) {
            VStack(alignment: .leading, spacing: 10) {
                Label("No motion synced yet", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(noMotionLead)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(noMotionAction)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The "why it's empty" line — a 5/MG needs the deep-data unlock before it streams motion at all.
    private var noMotionLead: String {
        if is5MG {
            return String(localized: "We're not seeing motion from your WHOOP 5.0 / MG yet. Keep NOOP connected and let strap history finish syncing; the experimental R22 flags are not required. Account or Apple Health imports do not contain the raw strap motion this estimate needs.")
        }
        return String(localized: "We're not seeing any motion from your strap yet. Steps are estimated from your WHOOP's banked motion history, so your strap needs to sync that history before NOOP has anything to count.")
    }

    /// The "what to do" line — 5/MG points at the deep-data toggle (unless it's already on, then just sync).
    private var noMotionAction: String {
        if is5MG && !deepDataEnabled {
            return String(localized: "Open NOOP near the strap and let WHOOP 5/MG history finish syncing. The step estimate and calibration fill in once enough stored motion has arrived; the legacy R22 experiment is not required.")
        }
        if is5MG {
            return String(localized: "Deep data is on — open NOOP near your strap and let it sync its motion history (a full first-run sync can take a while). Once a day or two of motion lands, your step estimate and the calibration below fill in.")
        }
        return String(localized: "Open NOOP near your strap and let it catch up (a full history sync can take a while on first run). Once a day or two of motion lands, your step estimate and the calibration below will start to fill in.")
    }

    /// The current calibration read-out: coefficient, sample days, and a Low/Medium/High confidence —
    /// or, if nothing's fit yet and no manual value is set, an honest "what we still need" prompt.
    private var currentFitCard: some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current calibration").strandOverline()
                if profile.stepsCalibrationCoefficient > 0 || profile.stepsManualCoefficient > 0 {
                    let coeff = profile.stepsManualCoefficient > 0
                        ? profile.stepsManualCoefficient : profile.stepsCalibrationCoefficient
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", coeff))
                            .font(StrandFont.number(30))
                            .foregroundStyle(StrandPalette.accent)
                        Text("steps per motion unit")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if profile.stepsManualCoefficient > 0 {
                        statLine(String(localized: "Source"), String(localized: "Manual (you set this by hand)"))
                    } else {
                        statLine(String(localized: "Fitted from"),
                                 profile.stepsCalibrationSampleDays == 1
                                     ? String(localized: "1 day your phone also counted")
                                     : String(localized: "\(profile.stepsCalibrationSampleDays) days your phone also counted"))
                        statLine(String(localized: "Confidence"), "\(StepsCalibrationFormat.confidenceLabel(profile.stepsCalibrationConfidence)) · \(Int((profile.stepsCalibrationConfidence * 100).rounded()))%")
                    }
                } else {
                    Text("Not calibrated yet")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.textPrimary)
                    // Only ask for phone-step days when phone-step days are what is actually missing.
                    //
                    // A step estimate is `motion * coefficient` (`StepsEstimateEngine.estimate`) and a
                    // calibration point is the ratio `steps / motion`, so BOTH halves are required. With no
                    // banked strap motion neither the estimate nor the fit can move however many days the
                    // phone counts. The countdown below then names the half the user already has and hides
                    // the half they do not — a field report asked whether entering Apple Health steps by
                    // hand would start the calibration, which is exactly the conclusion it invites.
                    //
                    // The no-motion banner at the top of this sheet already explains the real blocker, so
                    // the honest move is to stop competing with it rather than to add more copy.
                    if !strapHasNoMotion {
                    // #589: a concrete countdown instead of a vague "a few days". Headline comes straight
                    // from the engine's needsMoreDays state so the wording matches the Today steps tile.
                    // #693: drive `have` off `profile.stepsCalibrationSampleDays` — the value the engine
                    // persists for the not-yet-calibrated case (IntelligenceEngine.swift sets it to the
                    // usable-day `have`, the SAME source the Today tile reads). `usableMatchedDays` can't be
                    // used here: `loadIfNeeded` early-returns before computing it when coeff == 0 (no fit
                    // yet), so it would always read 0 and the card was stuck on "Need 3 more days".
                    Text(StepsEstimateEngine.CalibrationStatus
                        .needsMoreDays(have: profile.stepsCalibrationSampleDays,
                                       need: StepsEstimateEngine.minCalibrationDays)
                        .headline)
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.accent)
                    Text("These are the days where your phone also counted steps, so NOOP can learn how your motion maps to steps. Or set the coefficient manually below.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The accuracy table: recent days that have BOTH an estimate and a phone count, side by side, so the
    /// user can SEE how close the estimate runs. Empty until enough both-have days exist.
    private var comparisonCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Estimated vs your phone").strandOverline()
                if comparison.isEmpty {
                    Text("No days yet where both NOOP and your phone counted steps. Once your phone logs a few days alongside the strap, they'll appear here so you can see how close the estimate is.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Column header.
                    HStack {
                        Text("Day").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Est.").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 64, alignment: .trailing)
                        Text("Phone").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 64, alignment: .trailing)
                        Text("Δ").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    ForEach(comparison) { row in
                        HStack {
                            Text(Self.shortDay(row.day))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Self.grouped(row.estimated))
                                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                                .frame(width: 64, alignment: .trailing)
                            Text(Self.grouped(row.actual))
                                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                                .frame(width: 64, alignment: .trailing)
                            Text(String(format: "%+.0f%%", row.errorPct))
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(abs(row.errorPct) <= 15
                                                 ? StrandPalette.metricCyan : StrandPalette.statusWarning)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(Self.shortDay(row.day)): estimated \(row.estimated) steps, phone \(row.actual) steps, \(Int(row.errorPct.rounded())) percent difference")
                    }
                    Text("These days are excluded from the estimate (your phone's real count is shown instead). They're here only so you can judge the estimate's accuracy.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Manual override: a slider bound to a draft, committed on release, with a live preview of what a
    /// typical recent day would estimate at the chosen coefficient. 0 returns to auto-fit.
    private var manualAdjustCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Adjust manually").strandOverline()
                Text("Override the automatic fit with your own steps-per-motion value. Useful if your phone has no step history to learn from, or the estimate runs consistently high or low. Set it back to auto by dragging to the far left.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(draftManual > 0 ? String(format: "%.1f", draftManual) : String(localized: "Auto"))
                        .font(StrandFont.number(24))
                        .foregroundStyle(draftManual > 0 ? StrandPalette.accent : StrandPalette.textSecondary)
                    Text(draftManual > 0 ? "steps / motion unit" : "fit from your phone")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                }

                Slider(value: $draftManual, in: 0...sliderMax, step: 0.5) {
                    Text("Manual steps coefficient")
                } minimumValueLabel: {
                    Text("Auto").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                } maximumValueLabel: {
                    Text("High").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                } onEditingChanged: { editing in
                    // Commit on release — snap a tiny drag back to 0 (auto) so "auto" is reachable.
                    if !editing { profile.stepsManualCoefficient = draftManual < 0.5 ? 0 : draftManual }
                }
                .tint(StrandPalette.accent)
                .accessibilityValue(draftManual > 0
                                    ? "\(String(format: "%.1f", draftManual)) steps per motion unit"
                                    : "Automatic")

                // Live preview: a typical recent day re-estimated at the draft coefficient.
                if let motion = sampleMotion {
                    let effective = draftManual > 0 ? draftManual : profile.stepsCalibrationCoefficient
                    if effective > 0 {
                        let preview = Int((motion * effective).rounded())
                        statLine(String(localized: "A typical recent day"),
                                 draftManual > 0
                                     ? String(localized: "≈ \(Self.grouped(preview)) steps at this setting")
                                     : String(localized: "≈ \(Self.grouped(preview)) steps (auto)"))
                    }
                }
                if draftManual > 0 {
                    Text("Takes effect on the next analytics pass (after the next sync).")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    /// A small "label … value" line shared by the fit + preview cards.
    private func statLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Spacer(minLength: 12)
            Text(value).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Data

    /// Build the comparison table + a typical-day motion, once. The engine stores `steps_est` ONLY for
    /// strap-only days (a phone-covered day uses the phone's real count), so an estimate and a phone count
    /// never co-exist in storage. To still SHOW "how close the estimate is", we reconstruct what the
    /// estimate WOULD have been on recent phone-covered days: read each day's motion volume the same way
    /// the engine does (gravity over [localMidnight, +24h)) and run the public `StepsEstimateEngine` with
    /// the live calibration. This reuses the engine, never invents a number, and needs no extra storage.
    private func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        draftManual = profile.stepsManualCoefficient

        // Effective calibration in force right now: a manual override wins, else the persisted auto-fit.
        let coeff = profile.stepsManualCoefficient > 0
            ? profile.stepsManualCoefficient : profile.stepsCalibrationCoefficient

        // Phone reference steps from Apple Health daily rows (steps > 0 only), newest first.
        let appleRows = await repo.appleDailyRows()
        let phoneDays = appleRows
            .compactMap { row -> (day: String, steps: Int)? in
                guard let s = row.steps, s > 0 else { return nil }
                return (row.day, s)
            }
            .sorted { $0.day > $1.day }

        // Reconstruct the estimate for the most recent phone-covered days, motion-by-motion.
        guard coeff > 0 else { return }
        let cal = StepsEstimateEngine.Calibration(coefficient: coeff,
                                                  sampleDays: profile.stepsCalibrationSampleDays,
                                                  confidence: profile.stepsCalibrationConfidence,
                                                  manual: profile.stepsManualCoefficient > 0)
        let dayParser = DateFormatter(); dayParser.locale = Locale(identifier: "en_US_POSIX"); dayParser.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        var rows: [StepsComparisonRow] = []
        var motions: [Double] = []
        for entry in phoneDays.prefix(10) {           // scan a few extra to fill 7 after motion gaps
            guard let dayDate = dayParser.date(from: entry.day) else { continue }
            let mid = Int(calendar.startOfDay(for: dayDate).timeIntervalSince1970)
            // #1643: the UNION, not `repo.deviceId` alone — a re-added strap leaves motion under both the
            // active id and the canonical one, and reading either by itself makes this screen disagree
            // with the estimator it is supposed to be reconstructing.
            let grav = await repo.gravitySamplesUnion(from: mid, to: mid + 86_400 - 1)
            let motion = StepsEstimateEngine.dayMotionIntensity(grav)
            guard motion > 0, let est = StepsEstimateEngine.estimate(motion: motion, calibration: cal) else { continue }
            motions.append(motion)
            rows.append(StepsComparisonRow(day: entry.day, estimated: est, actual: entry.steps))
            if rows.count >= 7 { break }
        }
        comparison = rows
        // #693: the "Need N more days…" countdown is now driven by `profile.stepsCalibrationSampleDays`
        // (the engine-persisted usable-day count, read directly in the card) — NOT a local match count
        // computed here. This scan reaches here ONLY when coeff > 0 (already calibrated), so a local count
        // would never reflect the not-yet-calibrated state the countdown describes. The rows still feed the
        // accuracy table (`comparison`) above.

        // Typical recent day's motion for the live preview = median of the motions we just measured.
        if !motions.isEmpty {
            let s = motions.sorted()
            sampleMotion = s[s.count / 2]
        }
    }

    // MARK: Formatting

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    /// "yyyy-MM-dd" → "EEE d MMM" for the table's day column.
    private static func shortDay(_ key: String) -> String {
        let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: key) else { return key }
        let outF = DateFormatter(); outF.dateFormat = "EEE d MMM"
        return outF.string(from: d)
    }
}

