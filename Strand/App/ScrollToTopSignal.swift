import SwiftUI

/// Coarse relative-time label for the "History synced N ago" sync-status line. Pure — `now` is
/// injectable so the bucket edges are unit-testable (RelativeAgoTests) — and deliberately the same
/// buckets as the Android `relativeAgo` (LiveScreen.kt, ed6a31d) so the two apps read identically.
/// Clamps future timestamps (strap-clock skew) to "just now", never negative.
func relativeAgo(_ epochSeconds: TimeInterval,
                 now: TimeInterval = Date().timeIntervalSince1970) -> String {
    let d = max(0, Int(now - epochSeconds))
    switch d {
    case ..<60:     return String(localized: "just now")
    case ..<3600:   return String(localized: "\(d / 60) min ago")
    case ..<86_400: return String(localized: "\(d / 3600) h ago")
    default:        return String(localized: "\(d / 86_400) d ago")
    }
}

// MARK: - Scroll-to-top signal (#198 follow-up)

/// An incrementing token the iOS tab shell bumps when the user re-taps the ALREADY-at-root active tab,
/// to scroll that tab's root screen to the top (the other half of the iOS tab convention #197/#198 left
/// unserved — an at-root re-tap is otherwise a no-op). `SummaryView` and `SleepHealthView` observe it
/// and scroll to their top anchor when it changes. Default 0 is never bumped outside the tab shell, so
/// macOS (sidebar, no tab re-tap) and every non-tab screen are completely unaffected.
private struct ScrollToTopSignalKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

extension EnvironmentValues {
    var scrollToTopSignal: Int {
        get { self[ScrollToTopSignalKey.self] }
        set { self[ScrollToTopSignalKey.self] = newValue }
    }
}
