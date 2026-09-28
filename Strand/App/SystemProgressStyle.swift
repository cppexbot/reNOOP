//  SystemProgressStyle.swift
//  NOOP · the one loading indicator: the system spinner in Apple's grey, set once at the app root.

import SwiftUI
import StrandDesign

/// Every indeterminate `ProgressView` in NOOP is the system activity indicator, grey as in Mail, Photos and
/// Settings — not tinted with the app's accent, which the root `.tint` would otherwise hand it. A progress with
/// a fraction keeps the platform's bar. Set once on each root (`systemProgressStyle()`), so a screen never picks
/// its own spinner; a call site that sets a style of its own still wins, as the closer modifier does.
struct SystemProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        if configuration.fractionCompleted == nil {
            ProgressView(configuration)
                .progressViewStyle(.circular)
                .tint(StrandPalette.textSecondary)
        } else {
            ProgressView(configuration)
                .progressViewStyle(.linear)
        }
    }
}

extension View {
    func systemProgressStyle() -> some View { progressViewStyle(SystemProgressStyle()) }
}
