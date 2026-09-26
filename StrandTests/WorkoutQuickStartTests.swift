import XCTest
@testable import Strand

/// The Workouts tab's start-card order: recently started first, then most frequent in history, then the
/// Fitness defaults, deduplicated and capped.
final class WorkoutQuickStartTests: XCTestCase {
    func testFreshInstallShowsDefaults() {
        XCTAssertEqual(WorkoutQuickStart.sports(recents: [], history: []), WorkoutQuickStart.defaults)
    }

    func testOrderRecentThenFrequentThenDefaults() {
        let history = ["Tennis", "Yoga", "Tennis", "Running", "Tennis", "Yoga"]
        let got = WorkoutQuickStart.sports(recents: ["Padel"], history: history)
        XCTAssertEqual(got, ["Padel", "Tennis", "Yoga", "Running", "Walking"])
    }

    func testDeduplicatesCaseInsensitivelyAndCaps() {
        let got = WorkoutQuickStart.sports(recents: ["running", "Running"], history: ["Running"])
        XCTAssertEqual(got, ["running", "Walking", "Strength", "Cycling"])
        let many = WorkoutQuickStart.sports(recents: ["Padel", "Yoga", "Tennis", "Golf", "Boxing", "Judo"], history: [])
        XCTAssertEqual(many.count, WorkoutQuickStart.maxCards)
    }

    func testSkipsUnknownAndGenericSports() {
        let got = WorkoutQuickStart.sports(recents: ["Other"], history: ["detected", "TraditionalStrengthTraining"])
        XCTAssertFalse(got.contains("Other"))
        XCTAssertEqual(got, WorkoutQuickStart.defaults)
    }
}
