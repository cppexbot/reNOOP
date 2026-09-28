import SwiftUI
import StrandDesign

/// First-run acknowledgment gate (clickwrap). Shown over EVERYTHING — before onboarding, pairing, or
/// any Bluetooth access — until the current `Terms.currentVersion` is accepted, and again if the
/// terms materially change. The user must tick each (un-pre-checked) statement and tap Accept; the accepted
/// version is then stored locally, the on-device equivalent of a consent record. See `Terms` / `TERMS.md`.
/// Laid out as the setup page the onboarding wizard opens with (`SetupPage`).
struct TermsGateView: View {
    let onAccept: () -> Void
    /// One flag per `Terms.attestations` entry; every one must be ticked before Accept enables.
    @State private var checks: [Bool] = Array(repeating: false, count: Terms.attestations.count)
    @State private var showingTerms = false

    private var allChecked: Bool { checks.allSatisfy { $0 } }

    var body: some View {
        SetupPage(isFirst: true,
                  title: String(localized: "Before you use NOOP"),
                  message: String(localized: "Please read the points below, then confirm each statement."),
                  art: { SetupGlyph(systemName: "doc.text") }) {
            VStack(alignment: .leading, spacing: 24) {
                TermsPoints()

                // Each statement is its own row with a trailing tick, as setup lists a choice.
                SetupCard {
                    ForEach(Array(Terms.attestations.enumerated()), id: \.offset) { idx, line in
                        if idx > 0 { SetupDivider() }
                        Button { checks[idx].toggle() } label: {
                            SetupRow(stacks: false) {
                                Text(verbatim: line)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.vertical, 11)
                            } trailing: {
                                Image(systemName: "checkmark")
                                    .font(StrandFont.pro(17, weight: .semibold))
                                    .foregroundStyle(StrandPalette.settingsBlue)
                                    .opacity(checks[idx] ? 1 : 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(checks[idx] ? .isSelected : [])
                    }
                }

                SetupCard {
                    Button { showingTerms = true } label: {
                        SetupRow(stacks: false) {
                            Text("Terms of Use")
                        } trailing: {
                            Image(systemName: "chevron.right")
                                .font(StrandFont.pro(15, weight: .semibold))
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } tray: {
            SetupButton(title: "Accept", action: onAccept)
                .disabled(!allChecked)
                .keyboardShortcut(.defaultAction)
        }
        .sheet(isPresented: $showingTerms) { TermsSheet() }
    }
}

/// The plain-English points of `Terms`, headline over body.
private struct TermsPoints: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Terms.points, id: \.0) { point in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: point.0)
                        .font(StrandFont.pro(17, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(verbatim: point.1)
                        .font(StrandFont.pro(15))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The terms as NOOP carries them in code (`TERMS.md` itself isn't in the app bundle), readable on a phone.
private struct TermsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TermsPoints()
                    Text("The full terms are in TERMS.md, shipped with NOOP. This is not legal advice.")
                        .font(StrandFont.pro(15))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: SetupMetrics.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(StrandPalette.plainPage.ignoresSafeArea())
            .navigationTitle(Text("Terms of Use"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }
}
