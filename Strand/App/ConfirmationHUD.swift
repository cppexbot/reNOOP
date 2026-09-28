//  ConfirmationHUD.swift
//  NOOP · the one "done" signal: a short glass capsule at the top and the system's success haptic, as iOS 26
//  confirms a copy or a save — gone on its own, nothing to dismiss.

import SwiftUI
import StrandDesign
import Accessibility
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Posts a confirmation ("Copied", "Backed up", "Logged bedtime at 23:42.") to the capsule the app root hangs
/// (`confirmationHUD()`). Only for an action that succeeded silently otherwise; a failure keeps its alert, which
/// has something to explain.
@MainActor
final class Confirmation: ObservableObject {
    static let shared = Confirmation()

    struct Item: Equatable {
        let id = UUID()
        let title: String
        let systemImage: String
    }

    @Published private(set) var current: Item?
    private var hide: Task<Void, Never>?

    func show(_ title: String, systemImage: String = "checkmark.circle.fill") {
        #if os(iOS)
        installWindow()
        #endif
        hide?.cancel()
        // A capsule is a label, not a sentence: shared copy that ends in a full stop loses it here.
        let label = title.hasSuffix(".") && !title.hasSuffix("..") ? String(title.dropLast()) : title
        current = Item(title: label, systemImage: systemImage)
        announce(label)
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    /// The capsule takes no focus and is gone in moments, so VoiceOver speaks it instead.
    private func announce(_ label: String) {
        #if os(iOS)
        AccessibilityNotification.Announcement(label).post()
        #elseif os(macOS)
        if #available(macOS 14.0, *) {
            AccessibilityNotification.Announcement(label).post()
        } else if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: label,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        #endif
    }

    #if os(iOS)
    /// iOS: the capsule lives in its own see-through window above every sheet and cover, as the system's
    /// own HUDs do — an overlay on the root would sit under the sheet most copies happen in.
    private var window: UIWindow?

    private func installWindow() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return
        }
        if let window, window.windowScene === scene { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: ConfirmationCapsule()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        #if DEBUG
        // The screenshot override (`AppearanceLock.colorScheme`), which this window does not inherit from
        // the scene's root view. Release follows the system, as every window does by default.
        switch AppearanceLock.colorScheme {
        case .light?: w.overrideUserInterfaceStyle = .light
        case .dark?: w.overrideUserInterfaceStyle = .dark
        default: break
        }
        #endif
        w.isHidden = false
        window = w
    }
    #endif
}

/// The capsule itself. A leaf: it alone observes `Confirmation`.
private struct ConfirmationCapsule: View {
    @ObservedObject private var confirmation = Confirmation.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let item = confirmation.current {
                Label(item.title, systemImage: item.systemImage)
                    .font(StrandFont.pro(15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .modifier(CapsuleSurface())
                    .padding(.top, 8)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity))
                    .id(item.id)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 1), value: confirmation.current)
        #if os(iOS)
        .sensoryFeedback(.success, trigger: confirmation.current?.id) { _, new in new != nil }
        #endif
        .allowsHitTesting(false)
    }
}

/// Liquid Glass on iOS 26 / macOS 26, the thick material before.
private struct CapsuleSurface: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
        #else
        content.background(.regularMaterial, in: Capsule())
        #endif
    }
}

#if os(macOS)
extension View {
    /// macOS: hangs the confirmation capsule over the window. Set once on the app root.
    func confirmationHUD() -> some View {
        overlay(alignment: .top) { ConfirmationCapsule() }
    }
}
#endif
