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

/// WHOOP steps-ESTIMATE calibration: the current fit, a recent estimated-vs-phone table and a manual
/// coefficient override with a live preview. Presented as a sheet from Settings →
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
    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .subheadline) private var countColumn: CGFloat = 64
    @ScaledMetric(relativeTo: .subheadline) private var deltaColumn: CGFloat = 52
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
        NavigationStack {
            Form {
                if strapHasNoMotion { noMotionSection }
                currentFitSection
                comparisonSection
                manualSection
            }
            .settingsForm()
            .navigationTitle(Text("Steps estimate"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton(action: onClose)
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 640)
        #else
        .noopSheetPresentation(largeFirst: true)
        #endif
        .task { await loadIfNeeded() }
    }

    // MARK: Sections

    /// Shown when the strap has banked NO motion yet (sampleMotion is nil) — the real reason a fresh
    /// WHOOP 4.0 shows zero steps (#37). Steps are built from the strap's synced motion history, so
    /// without a backfill there is nothing to estimate from and calibration can't help yet.
    private var noMotionSection: some View {
        Section {
            NoticeCard(title: Text("No motion synced yet"),
                       message: Text(noMotionAction),
                       systemImage: "antenna.radiowaves.left.and.right.slash",
                       tone: .warning)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    /// #107: family-aware "what to do". A 4.0 streams motion automatically; a 5/MG syncs it with its
    /// normal history, and imports never carry strap motion.
    private var noMotionAction: String {
        if is5MG && !deepDataEnabled {
            return String(localized: "Keep reNOOP near the strap until its history finishes syncing. Imports don't include strap motion.")
        }
        if is5MG {
            return String(localized: "Deep data is on. Keep reNOOP near the strap until its motion history syncs.")
        }
        return String(localized: "Keep reNOOP near your strap until its motion history syncs.")
    }

    /// The current calibration: coefficient, sample days and confidence, or what is still missing.
    private var currentFitSection: some View {
        let isCalibrated = profile.stepsCalibrationCoefficient > 0 || profile.stepsManualCoefficient > 0
        return Section {
            if isCalibrated {
                let coeff = profile.stepsManualCoefficient > 0
                    ? profile.stepsManualCoefficient : profile.stepsCalibrationCoefficient
                LabeledContent("Steps / motion", value: String(format: "%.1f", coeff))
                if profile.stepsManualCoefficient > 0 {
                    LabeledContent("Source", value: String(localized: "Manual"))
                } else {
                    LabeledContent("Fitted from",
                                   value: profile.stepsCalibrationSampleDays == 1
                                       ? String(localized: "1 day your phone also counted")
                                       : String(localized: "\(profile.stepsCalibrationSampleDays) days your phone also counted"))
                    LabeledContent("Confidence",
                                   value: "\(StepsCalibrationFormat.confidenceLabel(profile.stepsCalibrationConfidence)) · \(Int((profile.stepsCalibrationConfidence * 100).rounded()))%")
                }
            } else {
                Text("Not calibrated yet")
                    .foregroundStyle(StrandPalette.textPrimary)
            }
        } header: {
            Text("Current calibration")
        } footer: {
            // Only ask for phone-step days when phone-step days are what is actually missing. An estimate
            // is `motion * coefficient` and a calibration point is `steps / motion`, so with no banked
            // strap motion the countdown can't move however many days the phone counts; the no-motion
            // notice above already names the real blocker.
            //
            // #589/#693: the countdown reads `profile.stepsCalibrationSampleDays`, the usable-day count the
            // engine persists for the not-yet-calibrated case (the SAME source the Today tile reads).
            if !isCalibrated && !strapHasNoMotion {
                Text(verbatim: StepsEstimateEngine.CalibrationStatus
                    .needsMoreDays(have: profile.stepsCalibrationSampleDays,
                                   need: StepsEstimateEngine.minCalibrationDays)
                    .headline)
            }
        }
    }

    /// Recent days that have BOTH an estimate and a phone count, side by side.
    private var comparisonSection: some View {
        Section {
            if comparison.isEmpty {
                Text("No matching days yet")
                    .foregroundStyle(StrandPalette.textSecondary)
            } else if dts.isAccessibilitySize {
                // Four columns no longer fit a line: each day lists its figures under it.
                ForEach(comparison) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: Self.shortDay(row.day))
                            .foregroundStyle(StrandPalette.textPrimary)
                        LabeledContent("Est.") { Text(verbatim: Self.grouped(row.estimated)) }
                        LabeledContent("Phone") { Text(verbatim: Self.grouped(row.actual)) }
                        LabeledContent {
                            Text(verbatim: String(format: "%+.0f%%", row.errorPct))
                                .foregroundStyle(abs(row.errorPct) <= 15
                                                 ? StrandPalette.settingsGreen : StrandPalette.settingsOrange)
                        } label: {
                            Text(verbatim: "Δ")
                        }
                    }
                    .font(StrandFont.pro(15).monospacedDigit())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(Self.shortDay(row.day)): estimated \(row.estimated) steps, phone \(row.actual) steps, \(Int(row.errorPct.rounded())) percent difference")
                }
            } else {
                HStack {
                    Text("Day").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Est.").frame(width: countColumn, alignment: .trailing)
                    Text("Phone").frame(width: countColumn, alignment: .trailing)
                    Text(verbatim: "Δ").frame(width: deltaColumn, alignment: .trailing)
                }
                .font(StrandFont.pro(13))
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityHidden(true)
                ForEach(comparison) { row in
                    HStack {
                        Text(verbatim: Self.shortDay(row.day))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: Self.grouped(row.estimated))
                            .foregroundStyle(StrandPalette.textSecondary)
                            .frame(width: countColumn, alignment: .trailing)
                        Text(verbatim: Self.grouped(row.actual))
                            .foregroundStyle(StrandPalette.textSecondary)
                            .frame(width: countColumn, alignment: .trailing)
                        Text(verbatim: String(format: "%+.0f%%", row.errorPct))
                            .foregroundStyle(abs(row.errorPct) <= 15
                                             ? StrandPalette.settingsGreen : StrandPalette.settingsOrange)
                            .frame(width: deltaColumn, alignment: .trailing)
                    }
                    .font(StrandFont.pro(15).monospacedDigit())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(Self.shortDay(row.day)): estimated \(row.estimated) steps, phone \(row.actual) steps, \(Int(row.errorPct.rounded())) percent difference")
                }
            }
        } header: {
            Text("Estimated vs your phone")
        }
    }

    /// Manual override: a slider bound to a draft, committed on release, with a live preview of what a
    /// typical recent day would estimate at the chosen coefficient. 0 returns to auto-fit.
    private var manualSection: some View {
        Section {
            LabeledContent("Manual steps coefficient",
                           value: draftManual > 0 ? String(format: "%.1f", draftManual) : String(localized: "Auto"))
            Slider(value: $draftManual, in: 0...sliderMax, step: 0.5) {
                Text("Manual steps coefficient")
            } minimumValueLabel: {
                Text("Auto").font(StrandFont.pro(13)).foregroundStyle(StrandPalette.textSecondary)
            } maximumValueLabel: {
                Text("High").font(StrandFont.pro(13)).foregroundStyle(StrandPalette.textSecondary)
            } onEditingChanged: { editing in
                // Commit on release — snap a tiny drag back to 0 (auto) so "auto" is reachable.
                if !editing { profile.stepsManualCoefficient = draftManual < 0.5 ? 0 : draftManual }
            }
            .labelsHidden()
            .tint(StrandPalette.settingsBlue)
            .accessibilityValue(draftManual > 0
                                ? "\(String(format: "%.1f", draftManual)) steps per motion unit"
                                : "Automatic")

            // Live preview: a typical recent day re-estimated at the draft coefficient.
            if let motion = sampleMotion {
                let effective = draftManual > 0 ? draftManual : profile.stepsCalibrationCoefficient
                if effective > 0 {
                    let preview = Int((motion * effective).rounded())
                    LabeledContent("A typical recent day",
                                   value: draftManual > 0
                                       ? String(localized: "≈ \(Self.grouped(preview)) steps at this setting")
                                       : String(localized: "≈ \(Self.grouped(preview)) steps (auto)"))
                }
            }
        } header: {
            Text("Adjust manually")
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

