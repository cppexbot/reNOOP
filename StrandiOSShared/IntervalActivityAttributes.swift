#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for the interval timer — laid out as the Clock app's timer banner on the Lock
/// Screen and in the Dynamic Island.
///
/// Its own activity type for the same reason as the gym session's: a different question with a different
/// lifetime, from the first "start" until the timer is finished or reset. Time travels as DATES so the banner's
/// countdown ticks on its own (`Text(timerInterval:)`); the app pushes only when the phase, round or pause
/// changes. Every word arrives localized app-side, because the widget extension ships no catalog.
public struct IntervalActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Work (the stand hue) vs rest (the exercise green) — the running screen's colour language.
        public var isWork: Bool
        /// "Work · 3/8", localized app-side.
        public var label: String
        /// When the current phase began and is due to end; the banner counts down between them.
        public var phaseStartedAt: Date
        public var phaseEndsAt: Date
        /// Seconds left in the phase while paused; nil while running.
        public var pausedRemaining: Int?

        public init(isWork: Bool, label: String, phaseStartedAt: Date, phaseEndsAt: Date, pausedRemaining: Int?) {
            self.isWork = isWork
            self.label = label
            self.phaseStartedAt = phaseStartedAt
            self.phaseEndsAt = phaseEndsAt
            self.pausedRemaining = pausedRemaining
        }
    }

    /// "Intervals", localized app-side.
    public var title: String

    public init(title: String) {
        self.title = title
    }
}
#endif
