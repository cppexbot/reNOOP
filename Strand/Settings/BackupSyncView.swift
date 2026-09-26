import SwiftUI
import StrandDesign

/// Settings → Backup, laid out like Settings → iCloud Backup. Folder backup (pick a folder, daily
/// auto-backup as an on-launch catch-up, back up now, restore a snapshot from that folder) plus the
/// whole-file export / import and the WHOOP-format CSV export. Snapshots are the `.noopbak` whole-DB
/// format. Point the folder at Google Drive / iCloud / Dropbox for off-device sync with no account.
struct BackupSyncView: View {
    @EnvironmentObject var model: AppModel

    @State private var auto = FolderBackup.autoEnabled
    @State private var folderLabel = FolderBackup.folderLabel()
    @State private var lastMs = FolderBackup.lastBackupMs
    @State private var keep = FolderBackup.keepCount
    @State private var busy = false

    // Result alert (backup outcome / restore outcome).
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    // Restore-from-folder flow (must-fix #1 + #2): a sheet lists the folder's snapshots; choosing one
    // arms a destructive confirmation; only confirming runs the overwrite.
    @State private var showRestoreSheet = false
    @State private var snapshots: [FolderBackup.Snapshot] = []
    @State private var pendingRestore: FolderBackup.Snapshot?
    @State private var confirmRestore = false

    // Whole-file export / import / CSV (the old Settings "Backup & restore" card), on the same page.
    @State private var showOversizeRestoreConfirm = false
    @State private var oversizeRestoreMessage = ""

    var body: some View {
        Form {
            Section {
                Button {
                    backupNow()
                } label: {
                    HStack {
                        Text(busy ? "Working…" : "Back up now")
                        if busy { Spacer(); ProgressView().controlSize(.small) }
                    }
                }
                .disabled(folderLabel == nil || busy)
            } footer: {
                Text(lastMs > 0 ? "Last backup: \(relativeTime(lastMs))" : "No backup yet.")
            }

            Section {
                Toggle("Daily auto-backup", isOn: $auto)
                    .disabled(folderLabel == nil)
                    .onChangeCompat(of: auto) { on in FolderBackup.autoEnabled = on }
                // Wired to FolderBackup.keepCount; the next backup prunes the oldest beyond this count.
                Picker("Keep last snapshots", selection: $keep) {
                    ForEach(FolderBackup.keepOptions, id: \.self) { n in Text("\(n)").tag(n) }
                }
                .settingsPicker()
                .onChangeCompat(of: keep) { n in FolderBackup.keepCount = n }
            } footer: {
                // Auto is ON but the last successful backup is stale: a moved or disconnected cloud folder
                // stops backups silently, so say so here rather than at restore time.
                if auto, folderLabel != nil, lastMs > 0,
                   BackupSync.isBackupStale(lastBackupMs: lastMs,
                                            nowMs: Int(Date().timeIntervalSince1970 * 1000.0)) {
                    Text("Auto-backup hasn't run in a few days. Check the backup folder is still available — a moved or disconnected cloud folder stops backups silently.")
                        .foregroundStyle(StrandPalette.statusWarning)
                }
            }

            Section {
                LabeledContent("Folder", value: folderLabel ?? String(localized: "Not set"))
                Button(folderLabel == nil ? "Choose folder" : "Change folder") { chooseFolder() }
                    .disabled(busy)
                #if os(iOS)
                // #52: some iOS 26 pickers never return a folder; back up inside NOOP's own Files folder.
                if !FolderBackup.useInternalFolder {
                    Button("Use NOOP's own folder (browse in Files)") { useNoopFolder() }
                        .disabled(busy)
                }
                #endif
            } footer: {
                // #644: the snapshots are a plain ZIP; a cloud-synced folder uploads the readable file.
                Text("These backups are unencrypted too. If this folder syncs to Drive, Dropbox or iCloud, the readable file goes there as well — only point it at a service you trust.")
            }

            Section {
                Button("Restore from a backup…") { openRestorePicker() }
                    .disabled(folderLabel == nil || busy)
            }

            Section {
                Button("Export…") { runExport() }
                Button("Import…") { runImport() }
                Button("Export CSV…") { runCsvExport() }
            } footer: {
                Text("This is a plain, unencrypted archive — anyone who gets the file can open it with any zip tool. Store it somewhere you trust.")
            }
            .disabled(busy)
        }
        .settingsPage("Backup")
        // Result of a backup or a restore.
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage) }
        // #1807: a restore refused only for size is recoverable, so it gets its own two-button alert.
        .alert("Backup problem", isPresented: $showOversizeRestoreConfirm) {
            Button("Restore") { runImport(allowOversize: true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(oversizeRestoreMessage)
        }
        // Pick which snapshot to restore - the folder's own snapshots, newest first (must-fix #1).
        .sheet(isPresented: $showRestoreSheet) {
            RestorePickerSheet(snapshots: snapshots) { chosen in
                showRestoreSheet = false
                pendingRestore = chosen
                if chosen != nil { confirmRestore = true }
            }
        }
        // Explicit in-app destructive confirmation BEFORE any overwrite (must-fix #2).
        .alert("Restore this backup?", isPresented: $confirmRestore, presenting: pendingRestore) { snap in
            Button("Replace all data", role: .destructive) { runRestore(snap) }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { snap in
            // A hand-named file with no resolved date (timeMs 0) confirms by NAME, not "1 Jan 1970".
            Text(snap.timeMs > 0
                ? "Replace all current data with the backup from \(absoluteTime(snap.timeMs))? This cannot be undone."
                : "Replace all current data with the backup \(snap.name)? This cannot be undone.")
        }
    }

    // MARK: - File export / import

    private func runExport() {
        busy = true
        Task {
            let result = await DataBackup.runExport(checkpoint: { await model.repo.checkpointForBackup() })
            handleBackup(result)
        }
    }

    private func runImport(allowOversize: Bool = false) {
        busy = true
        Task {
            let result = await DataBackup.runImport(allowOversize: allowOversize)
            handleBackup(result)
        }
    }

    private func runCsvExport() {
        busy = true
        Task {
            let result = await CsvExport.run(repo: model.repo)
            busy = false
            switch result {
            case .cancelled:
                return
            case .exported(let url):
                alertTitle = String(localized: "CSV exported")
                alertMessage = String(localized: "Saved to \(url.lastPathComponent). The zip re-imports into NOOP (Data Sources → WHOOP Export) on any Mac, iPhone, or Android device.")
                showAlert = true
            case .failure(let message):
                alertTitle = String(localized: "Export problem")
                alertMessage = message
                showAlert = true
            }
        }
    }

    @MainActor
    private func handleBackup(_ result: DataBackup.BackupResult) {
        busy = false
        switch result {
        case .cancelled:
            return
        case .exported(let url):
            alertTitle = String(localized: "Backup exported")
            alertMessage = String(localized: "Saved to \(url.lastPathComponent). Copy this file to your other \(Platform.deviceNoun) and use Import there to restore everything.")
            showAlert = true
        case .exportedOversize(let url, let bytes, let limit):
            // #1807: the file is written and worth keeping — say so, then what restoring it will ask.
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            let cap = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            alertTitle = String(localized: "Backup exported")
            alertMessage = String(localized: "Saved to \(url.lastPathComponent). Your database is \(size), over the \(cap) NOOP restores without asking — the backup is complete and valid, and restoring it will ask you to confirm once.")
            showAlert = true
        case .restoreTooLarge(let name, let limit):
            let cap = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            oversizeRestoreMessage = String(localized: "\(name) is larger than the \(cap) NOOP restores without asking. That limit guards against a malicious archive expanding to fill this \(Platform.deviceNoun) — a backup you exported yourself is not that. Restoring it needs the space the database will take. You'll be asked to choose the file again.")
            showOversizeRestoreConfirm = true
        case .imported:
            alertTitle = String(localized: "Backup imported")
            alertMessage = String(localized: "Your data has been restored. Quit and reopen NOOP for it to take effect.")
            showAlert = true
        case .failure(let message):
            alertTitle = String(localized: "Backup problem")
            alertMessage = message
            showAlert = true
        }
    }

    // MARK: - Actions

    private func chooseFolder() {
        #if os(macOS)
        if FolderBackup.pickFolder() != nil { folderLabel = FolderBackup.folderLabel() }
        #else
        // #1000a assumed the iOS picker was refusing to ENABLE its Select button, leaving the user with
        // only Cancel. #2356 disproved that for at least one case: a reporter's log shows the delegate
        // firing after they picked an iCloud folder and pressed Open, so the button worked and iOS
        // declined the grant instead. Both still arrive here as nil, and UIKit gives us nothing to tell
        // them apart, which is exactly why the alert below describes the outcome rather than a cause.
        // Keep it that way: the previous guess is what sent the last investigation at the wrong failure.
        // Mildly chatty on a genuine Cancel; honest and actionable whenever no folder comes back.
        // `busy` guards against a double-tap stacking a second picker presentation on top of the first.
        busy = true
        Task {
            // Clear in a `defer` so it clears on ANY exit. It matters more here than elsewhere: every
            // control on this screen is `.disabled(busy)`, so a pick that never returned wedged the whole
            // screen — including the "Use NOOP's own folder" escape hatch. DocumentPicker now guarantees
            // the continuation resumes, but the flag must not depend on that promise holding.
            defer { busy = false }
            let picked = await FolderBackup.pickFolder()
            if picked != nil {
                folderLabel = FolderBackup.folderLabel()
            } else if !FolderBackup.useInternalFolder {
                // Only nag when there's no working destination. If the internal fallback is already
                // active, a cancelled picker changed nothing — and the button the message points at is
                // hidden, so alerting here would send the user chasing a control that isn't shown.
                alertTitle = String(localized: "No folder selected")
                alertMessage = String(localized: "NOOP didn't get a folder back from the picker. If the Open button won't do anything, tap \"Use NOOP's own folder\" below to back up inside NOOP instead — you can read those backups from the Files app.")
                showAlert = true
            }
        }
        #endif
    }

    #if os(iOS)
    // #52: picker-free fallback. Back up inside NOOP's own Files-visible folder (On My iPhone → NOOP →
    // Backups). No folder picker, no security-scoped bookmark — works even where the picker won't select.
    private func useNoopFolder() {
        FolderBackup.useNoopFolder()
        folderLabel = FolderBackup.folderLabel()
        alertTitle = String(localized: "Using NOOP's folder")
        alertMessage = String(localized: "Backups will be saved inside NOOP. Open the Files app → On My iPhone → NOOP → Backups to see them, or drag that folder into iCloud Drive to read it on your Mac. To use a different folder later, tap Change folder.")
        showAlert = true
    }
    #endif

    private func backupNow() {
        busy = true
        Task {
            defer { busy = false }   // any exit, incl. cancellation — see chooseFolder
            let ok = await FolderBackup.backupNow(checkpoint: { await model.repo.checkpointForBackup() })
            await MainActor.run {
                lastMs = FolderBackup.lastBackupMs
                alertTitle = ok ? String(localized: "Backed up") : String(localized: "Backup problem")
                alertMessage = ok
                    ? String(localized: "Saved a backup to your folder.")
                    : String(localized: "Backup failed - re-pick the folder and try again.")
                showAlert = true
            }
        }
    }

    private func openRestorePicker() {
        snapshots = FolderBackup.listSnapshots()
        if snapshots.isEmpty {
            alertTitle = String(localized: "No backups found")
            alertMessage = String(localized: "There are no NOOP backups in your folder yet. Use Back up now first.")
            showAlert = true
        } else {
            showRestoreSheet = true
        }
    }

    private func runRestore(_ snap: FolderBackup.Snapshot) {
        pendingRestore = nil
        busy = true
        Task {
            defer { busy = false }   // any exit, incl. cancellation — see chooseFolder
            // The restore is synchronous file I/O; run it off the main actor so the UI stays responsive
            // for a large store, then report on the main actor.
            let result = await Task.detached(priority: .userInitiated) {
                FolderBackup.restore(snapshotNamed: snap.name)
            }.value
            await MainActor.run {
                switch result {
                case .imported:
                    alertTitle = String(localized: "Restored")
                    alertMessage = String(localized: "Fully quit and reopen NOOP to load it.")
                case .failure(let m):
                    alertTitle = String(localized: "Restore problem"); alertMessage = m
                case .restoreTooLarge(let name, let limit):
                    // #1807: recoverable, but not from here — this view restores a snapshot directly and
                    // has no confirm step to hang the override on. Point at the path that does, rather
                    // than leaving the user with a refusal and nowhere to go.
                    let cap = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
                    alertTitle = String(localized: "Backup problem")
                    alertMessage = String(localized: "\(name) is larger than the \(cap) NOOP restores without asking. You can still restore it from Settings → Backup & restore → Import, which will ask you to confirm.")
                case .cancelled, .exported, .exportedOversize:
                    alertTitle = String(localized: "Restore problem"); alertMessage = String(localized: "Couldn't restore that backup.")
                }
                showAlert = true
            }
        }
    }

    // MARK: - Formatting

    private func relativeTime(_ ms: Int) -> String {
        let f = RelativeDateTimeFormatter()
        return f.localizedString(for: Date(timeIntervalSince1970: Double(ms) / 1000.0), relativeTo: Date())
    }

    private func absoluteTime(_ ms: Int) -> String {
        let f = DateFormatter()
        // #1821: localized DATE style untouched; only the hour cycle is the reader's.
        f.locale = AppClock.formattingLocale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
    }
}

/// The snapshot chooser shown before a restore (must-fix #1: pick from the folder, newest first).
/// Reports the chosen snapshot (or nil if dismissed) back to the host, which then arms the destructive
/// confirmation.
private struct RestorePickerSheet: View {
    let snapshots: [FolderBackup.Snapshot]
    let onChoose: (FolderBackup.Snapshot?) -> Void

    var body: some View {
        NavigationStack {
            List(snapshots) { snap in
                Button { onChoose(snap) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            // A hand-named file whose date lookup failed has timeMs 0; show its name as the
                            // primary line rather than "1 Jan 1970". The filename subtitle then only repeats
                            // when we DO have a real date to head the row.
                            Text(primaryLabel(snap))
                                .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                            if snap.timeMs > 0 {
                                Text(snap.name)
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .accessibilityLabel(accessibilityLabel(snap))
            }
            .navigationTitle("Choose a backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onChoose(nil) }
                }
            }
        }
        // A macOS `.sheet` sizes to its content's ideal height, and a `List` inside a `NavigationStack`
        // reports a near-zero intrinsic height there — so without an explicit frame the sheet collapses
        // to just the title + Cancel and clips every row, leaving the user an empty "Choose a backup"
        // with backups that ARE in the folder (the caller only opens this sheet when the list is
        // non-empty). Give it a real size, the same way `AddDeviceWizard`/`HealthView` frame their macOS
        // sheets with a fixed size. iOS/iPadOS sheets already take a sensible height, so the frame is
        // macOS-only. A longer backup list scrolls within the List; a short one leaves trailing space. (#1093)
        #if os(macOS)
        .frame(width: 460, height: 420)
        #endif
    }

    /// The row's headline: a friendly date when we resolved one, else the filename (never the epoch date).
    private func primaryLabel(_ snap: FolderBackup.Snapshot) -> String {
        snap.timeMs > 0 ? absoluteTime(snap.timeMs) : snap.name
    }

    /// VoiceOver label: reads the resolved date when we have one, else the filename (no epoch date).
    private func accessibilityLabel(_ snap: FolderBackup.Snapshot) -> String {
        snap.timeMs > 0 ? String(localized: "Restore backup from \(absoluteTime(snap.timeMs))")
                        : String(localized: "Restore backup \(snap.name)")
    }

    private func absoluteTime(_ ms: Int) -> String {
        let f = DateFormatter()
        // #1821: localized DATE style untouched; only the hour cycle is the reader's. Second copy of
        // this helper in the file - a single-shot replace fixed only the first, which the sweep caught.
        f.locale = AppClock.formattingLocale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
    }
}
