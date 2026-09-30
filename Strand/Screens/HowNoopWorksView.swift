import SwiftUI
import StrandDesign

// MARK: - How NOOP works (primer)
//
// The four "how does this work?" answers (sleep sorting, scores, recording, provenance) and the method
// family behind each score, one line each. A settings-style sheet from Settings → About.

struct HowNoopWorksView: View {
    let onClose: () -> Void

    /// The four primer answers.
    private enum Topic: CaseIterable, Identifiable {
        case sleepSorting, scores, recording, provenance

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .sleepSorting: return "Main sleep"
            case .scores:       return "Scores"
            case .recording:    return "Recording"
            case .provenance:   return "Sources"
            }
        }

        var detail: LocalizedStringKey {
            switch self {
            case .sleepSorting: return "Your longest block near your usual bedtime. The rest are naps."
            case .scores:       return "Scored on your device. Charge calibrates over about four nights."
            case .recording:    return "Connected means saving live. Not recording? Reconnect."
            case .provenance:   return "A badge shows whether reNOOP, WHOOP or Apple Health made a number."
            }
        }

        var icon: String {
            switch self {
            case .sleepSorting: return "moon.zzz.fill"
            case .scores:       return "gauge.with.dots.needle.67percent"
            case .recording:    return "dot.radiowaves.left.and.right"
            case .provenance:   return "checkmark.seal.fill"
            }
        }

        var tint: Color {
            switch self {
            case .sleepSorting: return StrandPalette.healthSleepCore
            case .scores:       return StrandPalette.summaryChargeRing
            case .recording:    return StrandPalette.settingsGreen
            case .provenance:   return StrandPalette.settingsBlue
            }
        }
    }

    /// Each score with the published method family it follows.
    private enum ScoreMethod: CaseIterable, Identifiable {
        case charge, effort, rest, fitnessAge
        var id: Self { self }

        var name: LocalizedStringKey {
            switch self {
            case .charge:     return "Charge"
            case .effort:     return "Effort"
            case .rest:       return "Rest"
            case .fitnessAge: return "Fitness Age"
            }
        }

        var family: LocalizedStringKey {
            switch self {
            case .charge:     return "HRV + resting HR + sleep"
            case .effort:     return "HR zones (TRIMP)"
            case .rest:       return "Duration + efficiency + stages"
            case .fitnessAge: return "VO₂max (HUNT)"
            }
        }

        var icon: String {
            switch self {
            case .charge:     return "heart.circle.fill"
            case .effort:     return "flame.fill"
            case .rest:       return "moon.stars.fill"
            case .fitnessAge: return "figure.run"
            }
        }

        var tint: Color {
            switch self {
            case .charge:     return StrandPalette.summaryChargeRing
            case .effort:     return StrandPalette.summaryEffortRing
            case .rest:       return StrandPalette.summaryRestRing
            case .fitnessAge: return StrandPalette.settingsTeal
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Topic.allCases) { topic in
                        GuideGlyphRow(icon: topic.icon, tint: topic.tint,
                                      title: Text(topic.title), detail: Text(topic.detail))
                    }
                }
                Section {
                    ForEach(ScoreMethod.allCases) { method in
                        GuideGlyphRow(icon: method.icon, tint: method.tint,
                                      title: Text(method.name), value: Text(method.family))
                    }
                } header: {
                    Text("How your scores are computed")
                } footer: {
                    Text("reNOOP never makes up a number.")
                }
            }
            .settingsForm()
            .navigationTitle(Text("How reNOOP works"))
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
        .frame(width: 520, height: 600)
        #else
        .noopSheetPresentation(largeFirst: true)
        #endif
    }
}

/// A row of an explainer sheet: a tinted glyph, a bold short title, then one grey line under it or a
/// grey value at the trailing edge.
struct GuideGlyphRow: View {
    let icon: String
    let tint: Color
    let title: Text
    var detail: Text? = nil
    var value: Text? = nil
    @ScaledMetric(relativeTo: .title3) private var glyphWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(StrandFont.pro(20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: glyphWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(StrandFont.pro(17, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let detail {
                    detail
                        .font(StrandFont.pro(15))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value {
                value
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("How reNOOP works") {
    HowNoopWorksView(onClose: {})
}
#endif
