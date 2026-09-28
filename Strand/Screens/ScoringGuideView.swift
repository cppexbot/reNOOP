import SwiftUI
import StrandDesign

// MARK: - Scoring guide
//
// "How scores work": the three daily scores and the confidence labels, one line each. A settings-style
// sheet from Settings → Scores.

/// The three score sections the guide can open at. The raw value is the scroll anchor id.
enum ScoreSection: String, CaseIterable, Identifiable {
    case charge
    case effort
    case rest

    var id: String { rawValue }

    /// The score's ring hue, so a row reads as that score's colour.
    var accent: Color {
        switch self {
        case .charge: return StrandPalette.summaryChargeRing
        case .effort: return StrandPalette.summaryEffortRing
        case .rest:   return StrandPalette.summaryRestRing
        }
    }

    var icon: String {
        switch self {
        case .charge: return "heart.circle.fill"
        case .effort: return "flame.fill"
        case .rest:   return "moon.stars.fill"
        }
    }

    /// Localized display name for the section (the raw value stays the stable anchor id).
    var displayName: String {
        switch self {
        case .charge: return String(localized: "Charge")
        case .effort: return String(localized: "Effort")
        case .rest:   return String(localized: "Rest")
        }
    }

    /// What the score answers, in one line.
    var summary: LocalizedStringKey {
        switch self {
        case .charge: return "How recovered you are, led by HRV against your baseline."
        case .effort: return "How hard your heart worked, from time in heart-rate zones."
        case .rest:   return "How restorative your sleep was against what you needed."
        }
    }
}

struct ScoringGuideView: View {
    /// When set, the guide scrolls to this section on appear.
    var initialSection: ScoreSection? = nil
    let onClose: () -> Void

    /// The confidence labels every score carries, in their order.
    private enum Confidence: CaseIterable, Identifiable {
        case solid, building, calibrating
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .solid:       return "Solid"
            case .building:    return "Building"
            case .calibrating: return "Calibrating"
            }
        }

        var detail: LocalizedStringKey {
            switch self {
            case .solid:       return "All inputs present."
            case .building:    return "Enough to show, still thin."
            case .calibrating: return "Still learning your baseline."
            }
        }

        var tint: Color {
            switch self {
            case .solid:       return StrandPalette.settingsGreen
            case .building:    return StrandPalette.settingsOrange
            case .calibrating: return StrandPalette.settingsGray
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        ForEach(ScoreSection.allCases) { section in
                            GuideGlyphRow(icon: section.icon, tint: section.accent,
                                          title: Text(verbatim: section.displayName),
                                          detail: Text(section.summary))
                                .id(section.id)
                        }
                    } footer: {
                        Text("0–100, computed on your device. Not WHOOP's scores.")
                    }
                    Section {
                        ForEach(Confidence.allCases) { level in
                            GuideGlyphRow(icon: "circle.fill", tint: level.tint,
                                          title: Text(level.title), detail: Text(level.detail))
                        }
                    } header: {
                        Text("Confidence")
                    } footer: {
                        Text("Informational only, not medical advice.")
                    }
                }
                .settingsForm()
                .onAppear { jump(to: initialSection, using: proxy) }
            }
            .navigationTitle(Text("How scores work"))
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
        .frame(width: 520, height: 560)
        #else
        .noopSheetPresentation(largeFirst: true)
        #endif
    }

    /// Scroll to the requested section.
    private func jump(to section: ScoreSection?, using proxy: ScrollViewProxy) {
        guard let section else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(section.id, anchor: .top)
            }
        }
    }
}

#if DEBUG
#Preview("Scoring guide") {
    ScoringGuideView(initialSection: .effort, onClose: {})
}
#endif
