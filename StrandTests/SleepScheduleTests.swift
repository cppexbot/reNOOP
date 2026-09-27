import XCTest
@testable import Strand

/// The sleep schedule page (Health's Full Schedule) over the strap alarm and the bedtime reminder.
///
/// The old Alarms screen showed two wake times, the alarm's and the reminder's "usual wake", stored
/// apart and routinely different (#2353), and a per-day list that re-timed the alarm while its copy said
/// it moved the reminder (#1864). The schedule shows one wake time per group of days, and every figure
/// for the next wake comes from one resolver against one clock.
final class SleepScheduleTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func inputs(alarmOn: Bool = true, willArm: Bool = true, wake: Int = 6 * 60 + 30,
                        days: Set<Int> = [], overrides: [Int: Int] = [:], goal: Int = 8 * 60) -> SleepScheduleInputs {
        SleepScheduleInputs(alarmOn: alarmOn, alarmWillArm: willArm, baseWake: wake, alarmDays: days,
                            overrides: overrides, sleepGoal: goal)
    }

    // MARK: - Cards

    func testEveryDayWithoutOwnTimesIsOneCard() {
        let entries = SleepSchedule.entries(inputs())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .base)
        XCTAssertEqual(entries[0].days, [2, 3, 4, 5, 6, 7, 1], "Monday first")
        XCTAssertEqual(entries[0].wake, 6 * 60 + 30)
        XCTAssertEqual(entries[0].bed, 22 * 60 + 30, "bedtime is the wake minus the sleep goal, wrapped")
        XCTAssertTrue(entries[0].alarm)
    }

    /// A day with its own time leaves the base card and shows ITS time, so no card names a time that
    /// will not wake anybody on one of its days.
    func testOwnTimeDaysGetTheirOwnCard() {
        let entries = SleepSchedule.entries(inputs(days: Set(2...6), overrides: [7: 9 * 60, 1: 9 * 60, 4: 5 * 60]))
        XCTAssertEqual(entries.map(\.days), [[2, 3, 5, 6], [4], [7, 1]])
        XCTAssertEqual(entries.map(\.wake), [6 * 60 + 30, 5 * 60, 9 * 60])
        XCTAssertEqual(entries.map(\.alarm), [true, true, false],
                       "the weekend is not an alarm day, so its card must say it has no alarm")
    }

    func testNoCardSaysAlarmWhenTheAlarmCannotSound() {
        XCTAssertFalse(SleepSchedule.entries(inputs(alarmOn: false)).contains(where: \.alarm))
        XCTAssertFalse(SleepSchedule.entries(inputs(willArm: false)).contains(where: \.alarm),
                       "#864: a 5/MG without Experimental arms nothing")
    }

    // MARK: - Next wake

    /// Wednesday 2026-09-16 09:00 UTC; base 06:30 every day, Thursday on its own 05:00.
    func testNextWakeResolvesAnOwnTimeDayAndItsEvening() throws {
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 9)))
        let next = try XCTUnwrap(SleepSchedule.nextWake(inputs(overrides: [5: 5 * 60]), from: now, calendar: cal))
        XCTAssertEqual(next.wake, cal.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 5)))
        XCTAssertEqual(next.bed, cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 21)))
        XCTAssertTrue(next.armed)
    }

    /// The schedule's next wake is exactly the instant `applySmartAlarm` arms the strap for.
    func testNextWakeIsTheArmedInstant() throws {
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 23)))
        let i = inputs(days: [2, 3, 4, 5, 6], overrides: [2: 7 * 60])
        let armed = AppModel.nextSmartAlarmDate(minutes: i.baseWake, weekdays: i.alarmDays,
                                                overrides: i.overrides, from: now, calendar: cal)
        XCTAssertEqual(SleepSchedule.nextWake(i, from: now, calendar: cal)?.wake, armed)
    }

    /// A countdown is a promise: none for an alarm that is off or will not arm.
    func testCountdownOnlyForAnArmedAlarm() throws {
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 9)))
        let locale = Locale(identifier: "en_US")
        XCTAssertNotNil(SleepSchedule.countdown(SleepSchedule.nextWake(inputs(), from: now, calendar: cal),
                                                from: now, locale: locale))
        XCTAssertNil(SleepSchedule.countdown(SleepSchedule.nextWake(inputs(alarmOn: false), from: now, calendar: cal),
                                             from: now, locale: locale))
        XCTAssertNil(SleepSchedule.countdown(SleepSchedule.nextWake(inputs(willArm: false), from: now, calendar: cal),
                                             from: now, locale: locale))
    }

    /// The next-wake card resolves once per tick and takes the countdown from that same resolution and
    /// clock — two reads a tick apart can straddle the fire and name two different days.
    func testTheNextWakeCardResolvesOnceFromOneClock() throws {
        let src = try Self.source("Strand/SleepSchedule/SleepScheduleComponents.swift")
        XCTAssertEqual(src.components(separatedBy: "SleepSchedule.nextWake(").count - 1, 1)
        XCTAssertTrue(src.contains("SleepSchedule.countdown(next, from: now"))
        XCTAssertFalse(src.contains("Date()"), "every readout takes the tick's date, never its own clock")
    }

    // MARK: - One wake time

    func testReconciledBaseWakePrefersTheSettingInUse() {
        XCTAssertEqual(SleepSchedule.reconciledBaseWake(alarmOn: true, alarmWake: 360, reminderOn: true, reminderWake: 420), 360)
        XCTAssertEqual(SleepSchedule.reconciledBaseWake(alarmOn: false, alarmWake: 360, reminderOn: true, reminderWake: 420), 420)
        XCTAssertEqual(SleepSchedule.reconciledBaseWake(alarmOn: false, alarmWake: 360, reminderOn: false, reminderWake: 420), 360)
    }

    // MARK: - Editing

    func testEditingTheBaseCardSetsDaysWakeAndGoal() throws {
        let i = inputs(days: Set(2...6), overrides: [3: 5 * 60, 7: 9 * 60])
        let base = SleepSchedule.entries(i)[0]
        let edit = SleepScheduleEdit(original: base, days: [2, 3, 4], bed: 23 * 60, wake: 7 * 60, alarm: true)
        let stored = try XCTUnwrap(SleepSchedule.applying(edit, to: i))
        XCTAssertEqual(stored.baseWake, 7 * 60)
        XCTAssertEqual(stored.alarmDays, [2, 3, 4], "Tuesday was picked into the base card")
        XCTAssertEqual(stored.overrides, [7: 9 * 60], "a day picked into the base card drops its own time")
        XCTAssertEqual(stored.sleepGoal, 8 * 60)
    }

    func testAddingAScheduleGivesItsDaysTheirOwnTimeAndAlarm() throws {
        let i = inputs(days: Set(2...6))
        let edit = SleepScheduleEdit(original: nil, days: [7, 1], bed: 0, wake: 9 * 60, alarm: true)
        let stored = try XCTUnwrap(SleepSchedule.applying(edit, to: i))
        XCTAssertEqual(stored.overrides, [7: 9 * 60, 1: 9 * 60])
        XCTAssertEqual(stored.alarmDays, [], "all seven days ring, stored as every day")
        XCTAssertEqual(stored.sleepGoal, 9 * 60)
    }

    func testAnOwnTimeScheduleCanDropItsAlarm() throws {
        let i = inputs(overrides: [7: 9 * 60])
        let own = SleepSchedule.entries(i)[1]
        var edit = SleepScheduleEdit(original: own, days: [7], bed: own.bed, wake: own.wake, alarm: false)
        XCTAssertEqual(SleepSchedule.applying(edit, to: i)?.alarmDays, [1, 2, 3, 4, 5, 6])
        edit.delete = true
        let deleted = try XCTUnwrap(SleepSchedule.applying(edit, to: i))
        XCTAssertEqual(deleted.overrides, [:], "deleting returns the day to the base card")
        XCTAssertEqual(deleted.alarmDays, [])
    }

    /// The empty set spells "every day", so the last ringing days cannot be switched off from a card.
    func testTheLastRingingDaysCannotLoseTheirAlarm() {
        let i = inputs(days: [7], overrides: [7: 9 * 60])
        let own = SleepSchedule.entries(i)[1]
        let edit = SleepScheduleEdit(original: own, days: [7], bed: own.bed, wake: own.wake, alarm: false)
        XCTAssertNil(SleepSchedule.applying(edit, to: i))
    }

    func testTheGoalStaysInsideTheReminderClamp() {
        XCTAssertEqual(SleepSchedule.goal(bed: 23 * 60, wake: 1 * 60), 5 * 60)
        XCTAssertEqual(SleepSchedule.goal(bed: 18 * 60, wake: 8 * 60), 11 * 60)
        XCTAssertEqual(SleepSchedule.goal(bed: 22 * 60 + 30, wake: 6 * 60 + 30), 8 * 60)
    }

    // MARK: - Helpers

    private struct SourceNotReachable: Error { let path: String }

    private static func source(_ relative: String, file: StaticString = #filePath) throws -> String {
        var dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        for _ in 0..<4 {
            let candidate = dir.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw SourceNotReachable(path: "\(file)")
    }
}
