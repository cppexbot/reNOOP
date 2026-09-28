import SwiftUI
import MarkdownUI
import StrandDesign

/// The MarkdownUI theme for Coach replies.
///
/// LLM chat replies (OpenAI / Anthropic / Gemini) arrive as GitHub-flavored
/// Markdown — overwhelmingly bold, bullet/numbered lists, `###` headings, and the
/// occasional table for a weekly plan. This theme renders that set in the Strand
/// look, sized for a Messages bubble: headings stay at body size (a `#` must
/// not shout inside a bubble), and tables get hairline borders.
extension Theme {
    static let strand = Theme()
        // Base body text — Messages' 17 pt.
        .text {
            ForegroundColor(StrandPalette.messageIncomingText)
            FontSize(17)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(StrandPalette.messageIncomingText)
            BackgroundColor(StrandPalette.surfaceInset)
        }
        .link {
            ForegroundColor(StrandPalette.messageLink)
        }
        // Headings: h1/h2 land at headline (17 / semibold), h3 just above body,
        // h4–h6 as overline-ish small caps labels. Sizes are relative to the body size, which Markdown
        // scales with Dynamic Type; a point size here would pin the heading at Large.
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 14, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.rem(1))
                    ForegroundColor(StrandPalette.messageIncomingText)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 14, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.rem(1))
                    ForegroundColor(StrandPalette.messageIncomingText)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 12, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.rem(1))
                    ForegroundColor(StrandPalette.messageIncomingText)
                }
        }
        .heading4 { configuration in
            configuration.label
                .markdownMargin(top: 10, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.rem(1))
                    ForegroundColor(StrandPalette.messageIncomingText)
                }
        }
        .heading5 { configuration in
            configuration.label
                .markdownMargin(top: 10, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.rem(13.0 / 17))
                    ForegroundColor(StrandPalette.textSecondary)
                }
        }
        .heading6 { configuration in
            configuration.label
                .markdownMargin(top: 10, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.rem(12.0 / 17))
                    ForegroundColor(StrandPalette.textSecondary)
                }
        }
        // Messages sets a reply at the plain 17 pt line height; blocks sit 8 pt apart and list items
        // follow each other with no extra gap.
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 0)
        }
        .blockquote { configuration in
            configuration.label
                .padding(.leading, 12)
                .markdownTextStyle {
                    ForegroundColor(StrandPalette.textSecondary)
                }
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(StrandPalette.textTertiary)
                        .frame(width: 3)
                }
                .markdownMargin(top: 4, bottom: 8)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.88))
                    }
                    .padding(10)
            }
            .background(StrandPalette.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(StrandPalette.hairline, lineWidth: 1))
            .markdownMargin(top: 4, bottom: 8)
        }
        .thematicBreak {
            StrandPalette.hairline
                .frame(height: 1)
                .markdownMargin(top: 10, bottom: 10)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: StrandPalette.hairline))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, StrandPalette.surfaceInset)
                )
                .markdownMargin(top: 4, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    FontSize(.em(0.9))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .relativeLineSpacing(.em(0.2))
        }
}
