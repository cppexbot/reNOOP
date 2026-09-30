//  SleepTimeEditor.swift
//  NOOP · Sleep — hand-correcting a night's bed/wake times and adding a missed nap.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Identifies the night being edited for `.sheet(item:)`. A night's `startTs` is its stable natural
/// key (wake-time edits never move it), so it doubles as the sheet identity.
struct WakeEdit: Identifiable {
    let detectedStartTs: Int   // immutable detected key the edit writes against
    let bedTs: Int             // current effective onset (seeds the bed picker)
    let wakeTs: Int            // current wake (seeds the wake picker)
    let stagesJSON: String?
    /// True for a hand-edited / manually-added (nap) night. Such a delete writes NO tombstone (it is
    /// never re-detected), so the editor's delete-confirm copy must NOT promise re-detection suppression
    /// for it. Mirrors the undo-banner branch (#65 banner/confirm honesty).
    let userEdited: Bool
    var id: Int { detectedStartTs }
}

/// Seeds the "Add nap" picker (#508). A nap is short, so seed a 30-minute window anchored to the night's
/// wake (a natural place to look for a missed afternoon nap), clamped to never start before the night's
/// onset. The identity is the seed start so `.sheet(item:)` presents once per request.
struct AddNapSeed: Identifiable {
    let bedTs: Int
    let wakeTs: Int
    var id: Int { bedTs }
    init(forNight night: Night) {
        // Anchor an hour after the night's wake; a 30-min default window the user adjusts.
        let anchor = night.session.endTs + 3_600
        self.bedTs = anchor
        self.wakeTs = anchor + 30 * 60
    }
}

/// A small sheet to hand-correct a night's bed (onset) and wake (end) instants. Seeds both pickers with
/// the current values, including each calendar date. Hands the chosen unix-second (bed, wake) back via
/// `onSave`. Pure presentation + a single async save — persistence lives in the repo.
struct SleepTimeEditor: View {
    let onSave: (Int, Int) async -> Void
    /// Optional destructive delete (#68). Non-nil for an existing main-sleep / nap edit (the editor then
    /// shows a "Delete this sleep" button gated behind a confirmation); nil for the "Add a nap" sheet,
    /// which has nothing to delete yet.
    let onDelete: (() async -> Void)?
    private let title: LocalizedStringKey
    private let blurb: LocalizedStringKey
    private let bedLabel: LocalizedStringKey
    private let wakeLabel: LocalizedStringKey
    private let deleteLabel: LocalizedStringKey
    /// The night's RECORDED coverage (detected onset ... current wake, unix seconds) for the #940
    /// guards: a time-only bed roll past the wake auto-decrements the date, and a corrected window
    /// fully outside this range gets an explicit confirm instead of silent acceptance. nil for the
    /// "Add a nap" sheet, whose window deliberately sits outside the night (only the future-bed
    /// guard applies there).
    private let coverage: ClosedRange<Int>?
    /// True when deleting THIS session writes a re-detection tombstone (a DETECTED night). false for a
    /// userEdited/nap row, which is never re-detected, so the delete-confirm copy drops the suppression
    /// promise for it, matching the undo banner. (#65 confirm honesty.)
    private let suppressesReDetection: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var bed: Date
    @State private var wake: Date
    @State private var saving = false
    @State private var confirmingDelete = false
    /// The bed value BEFORE the in-flight picker change, so the #940 auto-correct can tell a
    /// time-only roll (same calendar day: rescue it) from a deliberate date change (respect it).
    @State private var previousBed: Date
    /// True while the #940 "no recorded data there" confirm is up; Save proceeds only on consent.
    @State private var confirmingDisjoint = false

    /// `title`/`blurb`/`bedLabel`/`wakeLabel` default to the edit-an-existing-night wording; the
    /// "Add a nap" caller (#508) overrides them. The save logic is identical either way — adding a nap
    /// is just an edit whose "existing" window is a seed. `onDelete` (#68) is the optional destructive
    /// action; `deleteLabel` lets the nap editor say "Delete this nap".
    init(bedTs: Int, wakeTs: Int,
         title: LocalizedStringKey = "Edit sleep times",
         blurb: LocalizedStringKey = "Correct when you went to bed and woke. Stages are re-derived from your data; the edit is kept through the next strap sync.",
         bedLabel: LocalizedStringKey = "Asleep",
         wakeLabel: LocalizedStringKey = "Woke",
         deleteLabel: LocalizedStringKey = "Delete this sleep",
         coverage: ClosedRange<Int>? = nil,
         suppressesReDetection: Bool = true,
         onSave: @escaping (Int, Int) async -> Void,
         onDelete: (() async -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.title = title; self.blurb = blurb
        self.bedLabel = bedLabel; self.wakeLabel = wakeLabel
        self.deleteLabel = deleteLabel
        self.coverage = coverage
        self.suppressesReDetection = suppressesReDetection
        // A bed can never be seeded in the future (#940): the "Add a nap" anchor is wake+1h, which is
        // ahead of the clock right after a morning sync; clamp so the picker opens inside its bound.
        let seedBed = min(bedTs, Int(Date().timeIntervalSince1970))
        _bed = State(initialValue: Date(timeIntervalSince1970: TimeInterval(seedBed)))
        _previousBed = State(initialValue: Date(timeIntervalSince1970: TimeInterval(seedBed)))
        _wake = State(initialValue: Date(timeIntervalSince1970: TimeInterval(wakeTs)))
    }

    /// The current edit window after the same future/inverted/duration guards used by persistence.
    private var validatedWindow: (start: Int, end: Int)? {
        SleepEditGuard.clampedEditWindow(
            start: Int(bed.timeIntervalSince1970),
            end: Int(wake.timeIntervalSince1970),
            now: Int(Date().timeIntervalSince1970))
    }

    /// The single save funnel: both the direct Save and the #940 disjoint confirm land here.
    private func commit(start: Int, end: Int) {
        saving = true
        Task {
            await onSave(start, end)
            dismiss()
        }
    }

    /// True when the picked window no longer touches the night's recorded data (#940 guard 2). Drives
    /// the one-line footer; Save still asks for consent through the alert below.
    private var windowIsDisjoint: Bool {
        guard let coverage, let window = validatedWindow else { return false }
        return SleepEditGuard.isDisjoint(
            newStart: window.start, newEnd: window.end,
            coverageStart: coverage.lowerBound, coverageEnd: coverage.upperBound)
    }

    private func save() {
        // #940 guard 2: a corrected window that no longer touches the night's recorded coverage has no
        // data to stage from. Silently accepting it fabricated an all-awake phantom night; ask first.
        guard let window = validatedWindow else { return }
        if windowIsDisjoint {
            confirmingDisjoint = true
        } else {
            commit(start: window.start, end: window.end)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Bed is bounded to the PAST (#940): a sleep can't start in the future, and an
                    // unbounded picker let a cross-midnight time roll land the bed on the coming
                    // evening, creating a future-dated night the tab couldn't render.
                    DatePicker(bedLabel, selection: $bed, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                    // The wake date and time are both editable so corrections preserve the exact
                    // endpoint selected by the user (#970).
                    DatePicker(wakeLabel, selection: $wake, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    if windowIsDisjoint {
                        Label("No recorded data in this window", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(StrandPalette.settingsOrange)
                    } else {
                        Text(blurb)
                    }
                }
                .tint(StrandPalette.settingsBlue)

                // Destructive delete for an existing night/nap (#68). Confirmation-gated so a tap can't
                // clear a night by accident; nil for the "Add a nap" sheet (nothing to delete).
                if onDelete != nil {
                    Section {
                        Button(deleteLabel, role: .destructive) { confirmingDelete = true }
                            .foregroundStyle(StrandPalette.settingsRed)
                            .disabled(saving)
                    }
                }
            }
            .settingsForm()
            .navigationTitle(Text(title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView().controlSize(.small)
                    } else {
                        SheetConfirmButton(tint: StrandPalette.settingsBlue) { save() }
                            .disabled(validatedWindow == nil)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #endif
        // #940 guard 1: a time-only roll that lands the bed in the future, or at/after the night's
        // wake, almost always means the PREVIOUS evening (23:00 "yesterday", not tonight). Snap the
        // date back a day so the picker visibly shows the night the user meant. Pure rule + tests:
        // SleepEditGuard.autoCorrectedBed (Android twin in com.noop.analytics).
        .onChangeCompat(of: bed) { newBed in
            let corrected = SleepEditGuard.autoCorrectedBed(
                previousBed: previousBed, candidateBed: newBed,
                originalWake: coverage.map { Date(timeIntervalSince1970: TimeInterval($0.upperBound)) },
                now: Date())
            previousBed = corrected
            if corrected != newBed { bed = corrected }
        }
        // #940 guard 2's consent step. On-brand role-tagged .alert, same shape as the delete confirm.
        .alert("Move this sleep?", isPresented: $confirmingDisjoint) {
            Button("Cancel", role: .cancel) { }
            Button("Move anyway") {
                guard let window = SleepEditGuard.clampedEditWindow(
                    start: Int(bed.timeIntervalSince1970),
                    end: Int(wake.timeIntervalSince1970),
                    now: Int(Date().timeIntervalSince1970)) else { return }
                commit(start: window.start, end: window.end)
            }
        } message: {
            Text("This moves the night to a time with no recorded data. Stages can't be derived there, so it may show as empty until data covers it.")
        }
        // On-brand destructive confirm — the same role-tagged .alert DevicesView uses for "Remove this
        // device?", not a bare default. (#68 — Android parity: "Delete this sleep session?")
        .alert("Delete this sleep session?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                saving = true
                Task {
                    await onDelete?()
                    dismiss()
                }
            }
        } message: {
            // A detected night is tombstoned so it won't re-detect; a userEdited/nap row writes no
            // tombstone, so its copy drops that (false) promise. Mirrors the undo banner. (#65)
            Text(suppressesReDetection
                 ? "Removes this recorded sleep and recomputes the day without it. reNOOP won't re-detect sleep in this window. You can undo for a few seconds after."
                 : "Removes this sleep and recomputes the day without it. You can undo for a few seconds after.")
        }
    }
}
