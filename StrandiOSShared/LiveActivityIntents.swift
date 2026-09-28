#if os(iOS)
import AppIntents

/// The buttons on NOOP's Lock Screen banners, as the Fitness banner's pause and the Clock banner's controls.
///
/// A `LiveActivityIntent` runs in the APP's process even when tapped on the Lock Screen, so the widget
/// extension only draws the button; what it does is registered by the app at launch (`handler`), next to the
/// gym session and the interval timer it drives.
public enum LiveActivityAction: Sendable {
    case liftSetDone
    case intervalsToggle
}

@MainActor
public enum LiveActivityActions {
    /// Set once by the app. Nil in the widget extension, which never performs these intents.
    public static var handler: ((LiveActivityAction) -> Void)?
}

/// "Set done" on the gym session's banner — the same step the sheet's button and the strap's double-tap take.
public struct LiftSetDoneIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Next"
    public static var isDiscoverable: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await MainActor.run { LiveActivityActions.handler?(.liftSetDone) }
        return .result()
    }
}

/// Pause / resume on the interval timer's banner.
public struct IntervalsToggleIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Pause"
    public static var isDiscoverable: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await MainActor.run { LiveActivityActions.handler?(.intervalsToggle) }
        return .result()
    }
}
#endif
