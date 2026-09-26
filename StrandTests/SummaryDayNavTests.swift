import XCTest
@testable import Strand

/// #817 - the Summary day-selector bounds. `maxDayOffset` caps how far back the pager may go (never older
/// than the earliest banked day) and `pickedDayOffset` maps a date-picker choice onto a days-back offset
/// anchored on the LOGICAL day, so a pick can never reach a FUTURE day (offset < 0).
final class SummaryDayNavTests: XCTestCase {

    // MARK: - maxDayOffset

    func testMaxDayOffsetCountsWholeDaysBackToEarliest() {
        // Earliest banked day is 4 days before today -> 4 reachable past days.
        XCTAssertEqual(SummaryDay.maxDayOffset(earliestDayKey: "2026-06-24", todayKey: "2026-06-28"), 4)
    }

    func testMaxDayOffsetZeroWhenEarliestIsToday() {
        XCTAssertEqual(SummaryDay.maxDayOffset(earliestDayKey: "2026-06-28", todayKey: "2026-06-28"), 0)
    }

    func testMaxDayOffsetZeroWhenNoData() {
        XCTAssertEqual(SummaryDay.maxDayOffset(earliestDayKey: nil, todayKey: "2026-06-28"), 0)
    }

    func testMaxDayOffsetZeroForUnparseableKey() {
        XCTAssertEqual(SummaryDay.maxDayOffset(earliestDayKey: "not-a-date", todayKey: "2026-06-28"), 0)
    }

    func testMaxDayOffsetClampsFutureEarliestToZero() {
        // A stray future-dated earliest key must not yield a negative reach.
        XCTAssertEqual(SummaryDay.maxDayOffset(earliestDayKey: "2026-07-01", todayKey: "2026-06-28"), 0)
    }

    // MARK: - pickedDayOffset (#16 - 00:00-04:00 rollover)

    /// Picking the logical day itself is always offset 0, whatever the wall clock says.
    func testPickedDayOffsetSameLogicalDayIsZero() {
        let cal = Calendar.current
        let logical = cal.date(from: DateComponents(year: 2026, month: 6, day: 28))!
        XCTAssertEqual(SummaryDay.pickedDayOffset(pickedDate: logical, anchorLogicalDay: logical), 0)
    }

    /// THE rollover case: at 02:00 on the 29th the logical day is still the 28th. Picking the 28th must be
    /// offset 0 (today), and picking the 29th - the calendar day that raw Date() would have used as the
    /// anchor - must clamp to 0, never a negative/future offset.
    func testPickedDayOffsetInRolloverWindowAnchorsToLogicalDay() {
        let cal = Calendar.current
        let logical = cal.date(from: DateComponents(year: 2026, month: 6, day: 28))!          // logical "today"
        let calendarDay = cal.date(from: DateComponents(year: 2026, month: 6, day: 29))!      // wall-clock day at 02:00
        // The logical day reads as today.
        XCTAssertEqual(SummaryDay.pickedDayOffset(pickedDate: logical, anchorLogicalDay: logical), 0)
        // The wall-clock-ahead day clamps to today rather than going negative.
        XCTAssertEqual(SummaryDay.pickedDayOffset(pickedDate: calendarDay, anchorLogicalDay: logical), 0)
    }

    /// A genuine past pick counts whole days back from the logical anchor.
    func testPickedDayOffsetCountsWholeDaysBack() {
        let cal = Calendar.current
        let logical = cal.date(from: DateComponents(year: 2026, month: 6, day: 28))!
        let picked = cal.date(from: DateComponents(year: 2026, month: 6, day: 24))!
        XCTAssertEqual(SummaryDay.pickedDayOffset(pickedDate: picked, anchorLogicalDay: logical), 4)
    }
}
