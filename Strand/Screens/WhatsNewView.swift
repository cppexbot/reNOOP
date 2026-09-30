import SwiftUI
import StrandDesign

/// "What's New", as Apple's own sheets draw it: a big title, one row per change of the latest release
/// (its own glyph, bold title, one line) and a single Continue button. Earlier releases are one tap
/// away. Shown automatically after an update and from Settings → About.
struct WhatsNewView: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(spacing: 6) {
                        Text("What's new")
                            .font(StrandFont.pro(34, weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(verbatim: "reNOOP \(AppChangelog.currentVersion)")
                            .font(StrandFont.pro(17))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                    if let latest = AppChangelog.releases.first {
                        WhatsNewRows(release: latest)
                    }

                    if AppChangelog.releases.count > 1 {
                        NavigationLink {
                            WhatsNewEarlierReleases()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Earlier releases")
                                Image(systemName: "chevron.right").font(StrandFont.pro(13, weight: .semibold))
                            }
                            .font(StrandFont.pro(15, weight: .semibold))
                            .foregroundStyle(StrandPalette.settingsBlue)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            #endif
            .background(StrandPalette.plainPage.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button(action: onClose) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .guideProminentButton()
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: 540)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
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
        .frame(width: 560, height: 640)
        #else
        .noopSheetPresentation(largeFirst: true)
        #endif
    }
}

/// One release as What's New rows. Each changelog entry's lead phrase becomes the bold title and its
/// first sentence the grey line; issue references and credits stay in the full changelog. Both are
/// looked up in the string catalog by their English text, so a translated release reads in the app's
/// language and an untranslated one falls back to English.
private struct WhatsNewRows: View {
    let release: AppChangelog.Release
    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 26
    @ScaledMetric(relativeTo: .title2) private var glyphWidth: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(release.items.enumerated()), id: \.offset) { _, raw in
                let item = WhatsNewItem(raw)
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: WhatsNewItem.symbol(for: item.title))
                        .font(.system(size: glyphSize))
                        .foregroundStyle(StrandPalette.settingsBlue)
                        .frame(width: glyphWidth)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: String(localized: String.LocalizationValue(item.title)))
                            .font(StrandFont.pro(15, weight: .semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        if let line = item.line {
                            Text(verbatim: String(localized: String.LocalizationValue(line)))
                                .font(StrandFont.pro(15))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .lineLimit(dts.isAccessibilitySize ? nil : 2)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Every release before the current one, newest first.
private struct WhatsNewEarlierReleases: View {
    var body: some View {
        Form {
            Section {
                ForEach(AppChangelog.releases.dropFirst()) { release in
                    NavigationLink {
                        ScrollView {
                            WhatsNewRows(release: release)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 20)
                                .frame(maxWidth: 560)
                                .frame(maxWidth: .infinity)
                        }
                        .background(StrandPalette.plainPage.ignoresSafeArea())
                        .navigationTitle(Text(verbatim: "reNOOP \(release.version)"))
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                    } label: {
                        LabeledContent {
                            Text(verbatim: release.date)
                        } label: {
                            Text(verbatim: release.version)
                                .font(StrandFont.pro(17, weight: .semibold))
                        }
                    }
                }
            }
        }
        .settingsPage("Earlier releases")
    }
}

/// A changelog entry split into a short title and one line.
private struct WhatsNewItem {
    let title: String
    let line: String?

    init(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var head = ""
        var rest = ""
        if text.hasPrefix("**"),
           let close = text.range(of: "**", range: text.index(text.startIndex, offsetBy: 2)..<text.endIndex) {
            head = String(text[text.index(text.startIndex, offsetBy: 2)..<close.lowerBound])
            rest = String(text[close.upperBound...])
        } else if let colon = text.range(of: ": "),
                  text.distance(from: text.startIndex, to: colon.lowerBound) <= 40 {
            head = String(text[..<colon.lowerBound])
            rest = String(text[colon.upperBound...])
        } else {
            head = Self.firstSentence(text)
            rest = String(text.dropFirst(head.count))
        }
        // Older entries run the title and the detail together with a dash.
        if head.count > 60, let dash = head.range(of: " - ") ?? head.range(of: " — ") {
            rest = String(head[dash.upperBound...]) + rest
            head = String(head[..<dash.lowerBound])
        }
        let title = Self.clean(head)
        let body = String(rest.drop(while: { $0 == "." || $0 == ":" || $0.isWhitespace }))
        let line = Self.clean(Self.firstSentence(body))
        self.title = title.isEmpty ? Self.clean(text) : title
        self.line = line.isEmpty ? nil : line + "."
    }

    /// The row's glyph, as Apple's What's New gives each change its own symbol rather than a number (the
    /// changes are not a sequence). Keyed by the entry's English title; a title without one gets the
    /// neutral sparkles.
    static func symbol(for title: String) -> String {
        symbols[title] ?? "sparkles"
    }

    private static let symbols: [String: String] = [
        "A lift log you advance from the strap": "dumbbell.fill",
        "A Coach you can turn off completely": "bubble.left.and.bubble.right.fill",
        "Sync the strap from a shortcut, and watch it work": "arrow.triangle.2.circlepath",
        "Workouts that are easier to keep tidy": "figure.run",
        "An Oura ring that reads its own packets correctly": "circle.circle.fill",
        "WHOOP 5 readings that admit when they failed": "checkmark.shield.fill",
        "Charts that stop redrawing the whole screen": "chart.xyaxis.line",
        "Steps charts, and an optional 30-day average": "figure.walk",
        "Apple Health that keeps up": "heart.fill",
        "Smaller corrections": "wrench.and.screwdriver.fill",
        "Localization": "globe",
    ]

    /// Up to and excluding the first sentence-ending ". ", skipping "e.g." / "i.e." style abbreviations.
    private static func firstSentence(_ s: String) -> String {
        var search = s.startIndex..<s.endIndex
        while let dot = s.range(of: ". ", range: search) {
            let before = s[s.startIndex..<dot.lowerBound]
            let lastWord = before.split(separator: " ").last.map(String.init) ?? ""
            if lastWord.count > 1, !lastWord.contains(".") {
                return String(before)
            }
            search = dot.upperBound..<s.endIndex
        }
        return s
    }

    /// Drops markdown emphasis, issue references / credits in parentheses, and the closing period.
    private static func clean(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "**", with: "")
        out = out.replacingOccurrences(of: #"\s*\([^()]*(#\d|thanks @)[^()]*\)"#, with: "",
                                       options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasSuffix(".") || out.hasSuffix(":") { out.removeLast() }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension View {
    /// The one prominent action at the foot of an explainer sheet: a full-width blue capsule, in glass
    /// on iOS 26.
    @ViewBuilder
    func guideProminentButton() -> some View {
        let styled = self
            .font(StrandFont.pro(17, weight: .semibold))
            .controlSize(.large)
            .tint(StrandPalette.settingsBlue)
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            styled.buttonStyle(.glassProminent)
        } else {
            styled.buttonStyle(.borderedProminent)
        }
        #else
        styled.buttonStyle(.borderedProminent)
        #endif
    }
}
