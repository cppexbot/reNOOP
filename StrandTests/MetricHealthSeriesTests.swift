import XCTest
@testable import Strand

/// Pins the metric page's pure half: which days a range covers, how 6M / Y fold days into weeks and
/// months, the stale-series fallback, and the Highlights card's latest-against-average.
final class MetricHealthSeriesTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // Monday
        return c
    }

    private func day(_ key: String) -> Date { MetricHealthSeries.date(key, calendar: calendar)! }

    private func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// One reading a day, `value(i)` for the i-th day back from `end`.
    private func daily(_ count: Int, endingOn end: String, _ value: (Int) -> Double) -> [(day: String, value: Double)] {
        (0..<count).reversed().map { i in
            (day: key(calendar.date(byAdding: .day, value: -i, to: day(end))!), value: value(i))
        }
    }

    func testWeekIsTheSevenDaysEndingToday() {
        let series = daily(20, endingOn: "2026-09-26") { Double($0) }
        let w = MetricHealthSeries.window(series: series, range: .week, today: day("2026-09-26"), calendar: calendar)
        XCTAssertEqual(w.start, day("2026-09-20"))
        XCTAssertEqual(w.end, day("2026-09-27"))
        XCTAssertEqual(w.points.count, 7)
        XCTAssertEqual(w.points.last?.lastDay, "2026-09-26")
        XCTAssertEqual(w.average, 3)   // days 6…0 back → values 6…0
    }

    func testSixMonthsFoldsDaysIntoWholeWeeks() {
        let series = daily(14, endingOn: "2026-09-27") { $0 < 7 ? 10 : 20 }   // Mon 14 … Sun 27 Sep
        let w = MetricHealthSeries.window(series: series, range: .sixMonths, today: day("2026-09-27"), calendar: calendar)
        XCTAssertEqual(w.points.map(\.value), [20, 10])
        XCTAssertEqual(w.points.map(\.count), [7, 7])
        XCTAssertEqual(w.points.first?.start, day("2026-09-14"))
        XCTAssertEqual(w.average, 15)
    }

    func testYearFoldsIntoMonthsAndEndsWithTheCurrentMonth() {
        let series = [(day: "2026-08-10", value: 2.0), (day: "2026-08-20", value: 4.0), (day: "2026-09-01", value: 9.0)]
        let w = MetricHealthSeries.window(series: series, range: .year, today: day("2026-09-26"), calendar: calendar)
        XCTAssertEqual(w.points.map(\.value), [3, 9])
        XCTAssertEqual(w.end, day("2026-10-01"))
        XCTAssertEqual(w.start, day("2025-10-01"))
    }

    func testAStoppedSeriesEndsOnItsNewestReadingInsteadOfShowingNoData() {
        let series = [(day: "2026-03-01", value: 80.0), (day: "2026-03-04", value: 81.0)]
        let w = MetricHealthSeries.window(series: series, range: .week, today: day("2026-09-26"), calendar: calendar)
        XCTAssertEqual(w.anchor, day("2026-03-04"))
        XCTAssertEqual(w.points.count, 2)
    }

    func testNoSeriesIsAnEmptyWindowOnToday() {
        let w = MetricHealthSeries.window(series: [], range: .month, today: day("2026-09-26"), calendar: calendar)
        XCTAssertTrue(w.points.isEmpty)
        XCTAssertNil(w.average)
        XCTAssertEqual(w.start, day("2026-08-26"))
    }

    func testHighlightSetsTheLatestAgainstTheFortnightBeforeIt() {
        let series = daily(20, endingOn: "2026-09-26") { $0 == 0 ? 70 : 50 }
        let h = MetricHealthSeries.highlight(series: series, calendar: calendar)
        XCTAssertEqual(h?.latest, 70)
        XCTAssertEqual(h?.average, 50)
        XCTAssertEqual(h?.values.count, 14)
        XCTAssertEqual(h?.firstDay, "2026-09-13")
        XCTAssertEqual(h?.direction, .above)
    }

    func testHighlightCallsAMoveWithinFivePercentClose() {
        let series = daily(8, endingOn: "2026-09-26") { $0 == 0 ? 102 : 100 }
        XCTAssertEqual(MetricHealthSeries.highlight(series: series, calendar: calendar)?.direction, .close)
    }

    func testHighlightNeedsFourEarlierReadings() {
        let series = daily(4, endingOn: "2026-09-26") { _ in 50 }
        XCTAssertNil(MetricHealthSeries.highlight(series: series, calendar: calendar))
    }
}
