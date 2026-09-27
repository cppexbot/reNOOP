import SwiftUI
import StrandDesign

/// #590 — on-device storage diagnostics. iOS users saw "Documents & Data" balloon to ~19 GB after an
/// Apple Health import: the document picker's `asCopy:true` duplicate sat in `Documents/Inbox/` forever
/// and the WAL never truncated. AppModel now reclaims both automatically (Inbox cleanup on import +
/// launch, WAL truncate after each import); this screen makes the footprint VISIBLE and gives a manual
/// "Clean up now" escape hatch for anyone who already grew a backlog before the fix shipped.
///
/// Read-only otherwise: it shows the database size, the leftover Inbox size, and any stranded import
/// temp files. The button purges Inbox + temp and truncates the WAL — never touches live rows. Drawn as
/// sections at the foot of Settings → Backup.
struct StorageSections: View {
    @EnvironmentObject var model: AppModel

    @State private var report: AppModel.StorageReport?
    @State private var loading = true
    @State private var cleaning = false
    @State private var lastCleanedSummary: String?

    var body: some View {
        // One section carries the load: a modifier on a Group inside a Form lands on EVERY child section.
        Section {
            if let report {
                sizeRow("Health database", bytes: report.db)
                sizeRow("Leftover import copies", bytes: report.inbox, reclaimable: report.inbox > 0)
                sizeRow("Import temp files", bytes: report.importTemp, reclaimable: report.importTemp > 0)
            } else if loading {
                HStack {
                    Text("Measuring…")
                    Spacer()
                    ProgressView().controlSize(.small)
                }
            } else {
                Text("Storage unavailable")
            }
        } header: {
            Text("Storage")
        }
        .task { await load() }

        if let report { cleanUpSection(report) }
    }

    // MARK: - Sections

    private func cleanUpSection(_ r: AppModel.StorageReport) -> some View {
        let reclaimable = r.inbox + r.importTemp
        return Section {
            Button {
                Task { await cleanUp() }
            } label: {
                HStack {
                    Text(cleaning ? "Cleaning up…" : "Clean up now")
                    if cleaning {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(cleaning || reclaimable == 0)
            .accessibilityLabel("Clean up leftover import files")

            if let lastCleanedSummary {
                HStack(spacing: 8) {
                    Circle()
                        .fill(StrandPalette.settingsGreen)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(lastCleanedSummary)
                }
            }
        }
    }

    // MARK: - Row

    /// One footprint line: the size on the right, with a "Reclaimable" subtitle on scratch space that
    /// Clean up can free.
    private func sizeRow(_ label: LocalizedStringKey, bytes: Int64?, reclaimable: Bool = false) -> some View {
        LabeledContent {
            Text(verbatim: bytes.map(Self.format) ?? "—")
                .monospacedDigit()
        } label: {
            Text(label)
            if reclaimable {
                Text("Reclaimable")
            }
        }
    }

    // MARK: - Data

    private func load() async {
        loading = true
        let r = await model.storageReport()
        report = r
        loading = false
    }

    private func cleanUp() async {
        guard !cleaning else { return }
        cleaning = true
        let before = (report?.inbox ?? 0) + (report?.importTemp ?? 0)
        let r = await model.cleanUpStorage()
        let after = r.inbox + r.importTemp
        let freed = max(0, before - after)
        report = r
        lastCleanedSummary = freed > 0 ? String(localized: "Reclaimed \(Self.format(freed)).") : String(localized: "Already clean.")
        cleaning = false
    }

    /// Human byte size, decimal (matches iOS Settings' "Documents & Data" presentation).
    static func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }
}
