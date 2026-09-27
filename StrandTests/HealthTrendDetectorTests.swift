import XCTest
@testable import Strand

/// Pins the Trends page's one calculation: a trend is called only on a clear, consistent, recent change;
/// its recent period starts where the change did; weeks are preferred over days; and good/bad follows the
/// metric's better direction.
final class HealthTrendDetectorTests: XCTestCase {

    private let today = "2026-09-27"

    private func key(daysBefore n: Int) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let end = c.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        let d = c.date(byAdding: .day, value: -n, to: end)!
        let p = c.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }

    /// One reading a day for `count` days ending `endingDaysBefore` days before today; `value(i)` gets the
    /// number of days back from today.
    private func daily(_ count: Int, endingDaysBefore end: Int = 0,
                       _ value: (Int) -> Double) -> [(day: String, value: Double)] {
        (end..<(end + count)).reversed().map { (day: key(daysBefore: $0), value: value($0)) }
    }

    /// A fixed wobble between −2 and +2, so tests do not depend on a random generator.
    private func wobble(_ i: Int) -> Double { Double((i * 7) % 5) - 2 }

    private func trend(_ r: HealthTrendResult, file: StaticString = #filePath, line: UInt = #line) -> HealthTrend? {
        guard case .trend(let t) = r else {
            XCTFail("expected a trend, got \(r)", file: file, line: line)
            return nil
        }
        return t
    }

    func testDayNumberCountsCalendarDays() {
        XCTAssertEqual(HealthTrendDetector.dayNumber("1970-01-01"), 0)
        XCTAssertEqual(HealthTrendDetector.dayNumber("1970-01-02"), 1)
        XCTAssertEqual(HealthTrendDetector.dayNumber("2024-03-01")! - HealthTrendDetector.dayNumber("2024-02-28")!, 2)
        XCTAssertEqual(HealthTrendDetector.dayNumber("2026-03-01")! - HealthTrendDetector.dayNumber("2026-02-28")!, 1)
        XCTAssertNil(HealthTrendDetector.dayNumber("2026-13-01"))
        XCTAssertNil(HealthTrendDetector.dayNumber("garbage"))
    }

    func testAFlatSeriesIsSteady() {
        let series = daily(200) { 60 + wobble($0) }
        XCTAssertEqual(HealthTrendDetector.detect(series: series, today: today, higherIsBetter: false), .steady)
    }

    func testAWeeksLongDropIsCalledInWeeksFromWhereItStarted() {
        // Resting heart rate six beats lower for the last eight weeks.
        let series = daily(200) { 60 + wobble($0) - ($0 < 56 ? 6 : 0) }
        guard let t = trend(HealthTrendDetector.detect(series: series, today: today, higherIsBetter: false)) else { return }
        XCTAssertEqual(t.direction, .lower)
        XCTAssertEqual(t.unit, .week)
        XCTAssertEqual(t.recentCount, 8)
        XCTAssertEqual(t.baselineCount, 18)
        XCTAssertEqual(t.slots.count, 26)
        XCTAssertEqual(t.baselineAverage, 60, accuracy: 0.5)
        XCTAssertEqual(t.recentAverage, 54, accuracy: 0.5)
        XCTAssertEqual(t.isImprovement, true)   // lower resting heart rate is better
    }

    func testARecentRiseInShortHistoryIsCalledInDays() {
        // Four weeks of history only: not enough weeks, so the daily scale reads it.
        let series = daily(28) { 70 + wobble($0) + ($0 < 7 ? 8 : 0) }
        guard let t = trend(HealthTrendDetector.detect(series: series, today: today, higherIsBetter: true)) else { return }
        XCTAssertEqual(t.direction, .higher)
        XCTAssertEqual(t.unit, .day)
        XCTAssertEqual(t.recentCount, 7)
        XCTAssertEqual(t.slots.count, 28)
        XCTAssertEqual(t.isImprovement, true)
    }

    func testTheBaselineIsMeasuredFromItsFirstReading() {
        // Twelve weeks of history in a 26-week span: the earlier average covers eight weeks, not 22.
        let series = daily(84) { 60 + wobble($0) - ($0 < 28 ? 6 : 0) }
        guard let t = trend(HealthTrendDetector.detect(series: series, today: today, higherIsBetter: false)) else { return }
        XCTAssertEqual(t.recentCount, 4)
        XCTAssertEqual(t.baselineCount, 22)
        XCTAssertEqual(t.baselineLength, 8)
    }

    func testARiseInAMetricWithNoBetterDirectionHasNoVerdict() {
        let series = daily(28) { 70 + wobble($0) + ($0 < 7 ? 8 : 0) }
        XCTAssertEqual(trend(HealthTrendDetector.detect(series: series, today: today, higherIsBetter: nil))?.isImprovement,
                       .some(nil))
    }

    func testAWorseningMoveIsNotAnImprovement() {
        let series = daily(28) { 60 + wobble($0) + ($0 < 7 ? 8 : 0) }
        XCTAssertEqual(trend(HealthTrendDetector.detect(series: series, today: today, higherIsBetter: false))?.isImprovement,
                       false)
    }

    func testTwoOutliersDoNotMakeATrend() {
        // Two wild days at the end lift the recent mean, but most recent days sit where they always did.
        let series = daily(28) { 60 + wobble($0) + ($0 < 2 ? 30 : 0) }
        XCTAssertEqual(HealthTrendDetector.detect(series: series, today: today, higherIsBetter: false), .steady)
    }

    func testTooFewReadingsAreInsufficient() {
        let series = daily(10) { 60 + wobble($0) + ($0 < 5 ? 8 : 0) }
        XCTAssertEqual(HealthTrendDetector.detect(series: series, today: today, higherIsBetter: false), .insufficient)
    }

    func testAHistoryThatStoppedIsNotATrendNow() {
        // A clear change, but the newest reading is ten days old: nothing to say about now.
        let series = daily(60, endingDaysBefore: 10) { 60 + wobble($0) - ($0 < 20 ? 8 : 0) }
        XCTAssertEqual(HealthTrendDetector.detect(series: series, today: today, higherIsBetter: false), .insufficient)
    }

    func testWorseNewsIsListedFirstThenTheClearerTrend() {
        func make(_ improvement: Bool?, _ strength: Double) -> HealthTrend {
            HealthTrend(direction: .higher, unit: .day, slots: [], recentCount: 0, baselineAverage: 0,
                        recentAverage: 0, strength: strength, isImprovement: improvement)
        }
        let sorted = [make(nil, 9), make(true, 4), make(false, 3), make(true, 8)]
            .sorted(by: HealthTrendDetector.precedes)
        XCTAssertEqual(sorted.map(\.isImprovement), [false, true, true, nil])
        XCTAssertEqual(sorted.map(\.strength), [3, 8, 4, 9])
    }
}
