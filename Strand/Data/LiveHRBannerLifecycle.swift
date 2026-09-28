import Foundation

/// What NOOP's heart-rate banner does with the latest live values: start, push, end, or nothing.
///
/// THE BANNER BELONGS TO A WORKOUT. A Live Activity is for a task with a defined beginning and end (HIG), and
/// round-the-clock heart rate has neither: the banner used to run all day, renewed every hour while NOOP was on
/// screen so iOS's eight-hour limit never reached it, and spent most of that time showing the dash. So it now starts
/// with a recorded workout and ends with it, and round-the-clock heart rate is the heart-rate widget's job. Its
/// switch keeps its place and its meaning becomes "during workouts".
///
/// Within a workout nothing that passes ends it: not a dropped link however long, not a strap off the wrist, not a
/// sync. It shows the dash then and the number again by itself, because iOS lets an app START a Live Activity only
/// while it is on screen, and a banner ended mid-workout could come back only once NOOP was opened (24 Sep 2026). It
/// ends when the workout ends, when its switch is turned off, or while the Lift Log or interval banner, which is the
/// session's own banner, is on screen. A new one is asked for only in the foreground, which is where a workout starts.
///
/// Pure and platform-free so `StrandTests` covers it; the controller it serves is in the iOS app target.
enum LiveHRBannerLifecycle {

    enum Step: Equatable { case nothing, start, push, end }

    /// `switchOn`: the banner's switch. `workoutActive`: a workout is being recorded. `standsAside`: the Lift Log or
    /// interval banner is on screen. `showing`: a banner exists. `appActive`: NOOP is on screen, the only time iOS
    /// lets it start a banner.
    static func step(switchOn: Bool, workoutActive: Bool, standsAside: Bool, showing: Bool,
                     appActive: Bool) -> Step {
        guard switchOn, workoutActive, !standsAside else { return showing ? .end : .nothing }
        if showing { return .push }
        return appActive ? .start : .nothing
    }

    /// How long an ended banner stays on the Lock Screen, showing the workout's last reading, before iOS removes it.
    /// Only for the workout ending: the switch turned off, or the session's own banner taking the screen, removes it at
    /// once, because a second banner there is the thing being avoided.
    static let lingerAfterWorkout: TimeInterval = 15 * 60
}
