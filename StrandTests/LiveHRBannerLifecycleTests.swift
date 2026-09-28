import XCTest
@testable import Strand

/// The heart rate banner belongs to a recorded workout: started with it, kept through anything that passes while it
/// runs, and ended with it. iOS lets an app start one only while it is on screen, so an end NOOP made mid-workout left
/// the Lock Screen without it until NOOP was opened.
final class LiveHRBannerLifecycleTests: XCTestCase {

    private func step(switchOn: Bool = true, workoutActive: Bool = true, standsAside: Bool = false,
                      showing: Bool = true, appActive: Bool = false) -> LiveHRBannerLifecycle.Step {
        LiveHRBannerLifecycle.step(switchOn: switchOn, workoutActive: workoutActive, standsAside: standsAside,
                                   showing: showing, appActive: appActive)
    }

    /// While the workout runs the banner is fed, on screen or not. The lifecycle reads neither the heart rate nor
    /// the link, so a dropped link or a strap off the wrist is not a reason to end it.
    func testAWorkoutKeepsItOnScreenOrNot() {
        for appActive in [true, false] {
            XCTAssertEqual(step(appActive: appActive), .push, "on screen \(appActive)")
        }
    }

    /// No workout, no banner: round-the-clock heart rate is the widget's job.
    func testTheWorkoutEndingEndsIt() {
        XCTAssertEqual(step(workoutActive: false), .end)
        XCTAssertEqual(step(workoutActive: false, showing: false, appActive: true), .nothing)
    }

    func testTheSwitchEndsIt() {
        XCTAssertEqual(step(switchOn: false), .end)
        XCTAssertEqual(step(switchOn: false, showing: false, appActive: true), .nothing)
    }

    /// The Lift Log and interval banners are the session's own; the heart rate banner makes room for them.
    func testTheSessionsOwnBannerTakesItsPlace() {
        XCTAssertEqual(step(standsAside: true), .end)
        XCTAssertEqual(step(standsAside: true, showing: false, appActive: true), .nothing)
    }

    /// iOS refuses a new banner to an app in the background: it is not asked for one there. On screen, a workout
    /// starts one before a heart rate arrives (the dash).
    func testANewBannerIsAskedForOnlyOnScreenDuringAWorkout() {
        XCTAssertEqual(step(showing: false, appActive: false), .nothing)
        XCTAssertEqual(step(showing: false, appActive: true), .start)
        XCTAssertEqual(step(workoutActive: false, showing: false, appActive: true), .nothing)
    }

    /// A finished workout's banner stays up for a quarter of an hour, then iOS removes it.
    func testAnEndedWorkoutLingersAQuarterOfAnHour() {
        XCTAssertEqual(LiveHRBannerLifecycle.lingerAfterWorkout, 15 * 60)
    }
}
