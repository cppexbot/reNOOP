//  EmptyStateView.swift
//  NOOP · the one empty state every screen shows: the system's ContentUnavailableView (iOS 17 /
//  macOS 14), and the same glyph, title, line and action stacked by hand on macOS 13.

import SwiftUI
import StrandDesign

struct EmptyStateView<Actions: View>: View {
    let title: Text
    let systemImage: String
    var description: Text?
    @ViewBuilder var actions: () -> Actions
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 44

    var body: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            ContentUnavailableView {
                Label { title } icon: { Image(systemName: systemImage) }
            } description: {
                description
            } actions: {
                actions()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: glyphSize))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.bottom, 4)
                title
                    .font(StrandFont.pro(22, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                description
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.textSecondary)
                actions()
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: Text, systemImage: String, description: Text? = nil) {
        self.init(title: title, systemImage: systemImage, description: description) { EmptyView() }
    }
}
