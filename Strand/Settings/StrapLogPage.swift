//  StrapLogPage.swift
//  NOOP · Settings → Developer → Strap Log: the live strap log, newest line at the bottom, with Copy and
//  Save in the bar — the same `exportableLogText` the Test Centre export rows share. Moved here from the
//  Live screen.

import SwiftUI
import StrandDesign

struct StrapLogPage: View {
    /// How many trailing lines the page RENDERS; Copy / Save still read the whole buffer (#2521).
    private static let renderedTailLines = 200

    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let tail = LiveState.renderedTail(live.log, tailLines: Self.renderedTailLines)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // Absolute indices into `live.log` as identity, so an append adds one row (#2521).
                    ForEach(tail.indices, id: \.self) { idx in
                        Text(verbatim: tail[idx])
                            .font(StrandFont.mono)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(16)
            }
            .onAppear { scrollToEnd(proxy) }
            .onChangeCompat(of: live.logRevision) { _ in scrollToEnd(proxy) }
        }
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        .navigationTitle("Strap Log")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy", systemImage: "doc.on.doc") { PlatformPasteboard.copy(live.exportableLogText()) }
                    .barGlyph()
                Button("Save…", systemImage: "square.and.arrow.down") { save() }
                    .barGlyph()
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = live.log.indices.last { proxy.scrollTo(last, anchor: .bottom) }
    }

    /// The extras Test Centre adds before exporting, so every export button produces the same file.
    private func save() {
        Task {
            let extra = await DebugDataDiagnostics.dynamicLines(repo: model.repo)
            FileExport.exportText(live.exportableLogText(extraHeaderLines: extra),
                                  suggestedName: FileExport.timestampedName("noop-strap-log", ext: "txt"))
        }
    }
}
