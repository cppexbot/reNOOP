//  SummaryGlass.swift
//  NOOP · Summary home — the ONE place that decides between native Liquid Glass and its fallback.
//
//  Native glass needs both the Xcode 26 toolchain (Swift 6.2, whose SDK declares `glassEffect`) and an
//  iOS 26 / macOS 26 runtime. The compiler guard keeps an Xcode 16 build compiling the fallback, so the
//  deployment targets (iOS 17 / macOS 13) are unchanged. Views never call `glassEffect` directly.

import SwiftUI
import StrandDesign

extension View {
    /// Interactive circular glass behind a header control; `.ultraThinMaterial` circle otherwise. The
    /// glass inset matches the strap control's (`nativeLiquidGlassSyncButton`) so the header row is even.
    @ViewBuilder
    func summaryGlassCircle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .padding(NoopMetrics.syncIndicatorGlassPadding)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.summaryMaterialCircle()
        }
        #else
        self.summaryMaterialCircle()
        #endif
    }

    /// Groups sibling glass shapes so they blend and morph as one surface on iOS 26 / macOS 26.
    @ViewBuilder
    func summaryGlassGroup(spacing: CGFloat) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
        #else
        self
        #endif
    }

    private func summaryMaterialCircle() -> some View {
        self
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
    }
}
