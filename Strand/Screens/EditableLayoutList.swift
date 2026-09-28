import SwiftUI
import StrandDesign

/// Shared Shown / Hidden list used by Today sections, Key Metrics, and Your Cards.
struct EditableLayoutList<Item, Options>: View
where Item: Identifiable & Equatable, Options: View {
    @Binding var draft: EditableLayoutDraft<Item>

    let shownTitle: String
    let hiddenTitle: String
    let title: (Item) -> String
    let subtitle: (Item) -> String?
    let icon: (Item) -> String
    let tint: (Item) -> Color
    let configurationLabel: (Item) -> String?
    let onConfigure: (Item) -> Void
    let onReset: () -> Void
    /// Whether the Shown list may go EMPTY. Default false — every visible item can be hidden EXCEPT the
    /// last, so surfaces that need ≥1 item (Today sections, Key Metrics, Your Cards) can't be emptied. The
    /// hosted-cards page (#today-hosted-cards) is opt-in, so it passes `true` to allow un-hosting the last.
    var allowEmpty: Bool = false
    /// Optional grouping key for the Hidden ("Available") list. When set (the hosted-cards page passes the
    /// card's origin, e.g. "Sleep" / "Trends"), the Available items are split into one titled Section per
    /// group so a user browses by origin instead of one flat list. nil (Today sections, Key Metrics, Your
    /// Cards) keeps the single flat Available section. The Shown list stays flat — it is the user's own
    /// cross-origin order.
    var group: ((Item) -> String)? = nil
    @ViewBuilder let options: () -> Options

    var body: some View {
        List {
            options()

            Section {
                ForEach(draft.visible) { item in
                    EditableLayoutRow(
                        title: title(item),
                        subtitle: subtitle(item),
                        icon: icon(item),
                        tint: tint(item),
                        configurationLabel: configurationLabel(item),
                        isVisible: true,
                        canHide: draft.visible.count > (allowEmpty ? 0 : 1),
                        onConfigure: { onConfigure(item) },
                        onVisibilityChange: { hide(item) }
                    )
                }
                .onMove(perform: moveVisible)
            } header: {
                EditableLayoutHeader(title: shownTitle)
            }

            if draft.hidden.isEmpty {
                Section {
                    Text("Nothing hidden")
                        .foregroundStyle(StrandPalette.textSecondary)
                } header: {
                    EditableLayoutHeader(title: hiddenTitle)
                }
            } else if group != nil {
                // Grouped Available list: one titled Section per origin (e.g. "Sleep", "Trends"), so the
                // hidden cards read by category.
                let groups = groupedHidden
                ForEach(groups.indices, id: \.self) { i in
                    Section {
                        ForEach(groups[i].items) { item in hiddenRow(item) }
                    } header: {
                        EditableLayoutHeader(title: groups[i].name)
                    }
                }
            } else {
                Section {
                    ForEach(draft.hidden) { item in hiddenRow(item) }
                } header: {
                    EditableLayoutHeader(title: hiddenTitle)
                }
            }

            Section {
                Button("Reset This Layout", role: .destructive, action: onReset)
                    .foregroundStyle(StrandPalette.settingsRed)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(StrandPalette.summaryCanvas.ignoresSafeArea())
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
    }

    /// One Available (hidden) row — the show affordance. Shared by the flat and grouped Available lists.
    @ViewBuilder
    private func hiddenRow(_ item: Item) -> some View {
        EditableLayoutRow(
            title: title(item),
            subtitle: subtitle(item),
            icon: icon(item),
            tint: tint(item),
            configurationLabel: configurationLabel(item),
            isVisible: false,
            canHide: true,
            onConfigure: { onConfigure(item) },
            onVisibilityChange: { show(item) }
        )
    }

    /// The hidden items bucketed by `group`, groups in first-appearance order (which follows the draft's
    /// canonical order). Only read when `group != nil`.
    private var groupedHidden: [(name: String, items: [Item])] {
        guard let group else { return [] }
        var order: [String] = []
        var buckets: [String: [Item]] = [:]
        for item in draft.hidden {
            let key = group(item)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { (name: $0, items: buckets[$0] ?? []) }
    }

    private func moveVisible(from offsets: IndexSet, to destination: Int) {
        draft.moveVisible(from: offsets, to: destination)
    }

    private func hide(_ item: Item) {
        withAnimation(StrandMotion.interactive) {
            draft.hide(item)
        }
    }

    private func show(_ item: Item) {
        withAnimation(StrandMotion.interactive) {
            draft.show(item)
        }
    }
}

/// A section title as Health's edit lists set theirs: bold, sentence case, primary text.
private struct EditableLayoutHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(StrandFont.pro(20, weight: .bold))
            .foregroundStyle(StrandPalette.textPrimary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct EditableLayoutRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let tint: Color
    let configurationLabel: String?
    let isVisible: Bool
    let canHide: Bool
    let onConfigure: () -> Void
    let onVisibilityChange: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 24
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onVisibilityChange) {
                Image(systemName: isVisible ? "minus.circle.fill" : "plus.circle.fill")
                    .font(StrandFont.pro(20))
                    .foregroundStyle(isVisible ? StrandPalette.settingsRed : StrandPalette.settingsGreen)
            }
            .buttonStyle(.plain)
            .disabled(isVisible && !canHide)
            .opacity(isVisible && !canHide ? 0.35 : 1)
            .accessibilityLabel(visibilityLabel)

            Image(systemName: icon)
                .font(StrandFont.pro(15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(dts.isAccessibilitySize ? nil : 1)
                }
            }

            Spacer(minLength: 8)

            if let configurationLabel {
                Button(configurationLabel, action: onConfigure)
                    .buttonStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.settingsBlue)
                    .accessibilityLabel(String(localized: "Edit \(title)"))
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(StrandPalette.summaryCard)
    }

    private var visibilityLabel: String {
        isVisible
            ? String(localized: "Hide \(title)")
            : String(localized: "Show \(title)")
    }
}
