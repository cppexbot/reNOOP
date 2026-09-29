import XCTest
@testable import Strand
import WhoopStore

/// The Sleep page's Vitals: no range until seven earlier nights carry a vital, then each vital read
/// against the mean ± 2 SD of the nights before it, never narrower than its resolution floor.
final class SleepVitalsTests: XCTestCase {

    private func row(_ day: String, hr: Int? = nil, resp: Double? = nil, sleep: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: hr, avgHrv: nil, recovery: nil, strain: nil,
                    exerciseCount: nil, respRateBpm: resp)
    }

    private func history(_ count: Int, hr: Int = 60) -> [DailyMetric] {
        (1...count).map { row(String(format: "2026-09-%02d", $0), hr: hr + ($0 % 2 == 0 ? 1 : -1)) }
    }

    func testCountsNightsStillNeeded() {
        let v = SleepVitals.make(rows: history(4) + [row("2026-09-20", hr: 60)], day: "2026-09-20")
        XCTAssertEqual(v.nightsRemaining, 3)
        XCTAssertEqual(v.nightsRecorded, 4)
        XCTAssertTrue(v.readings.isEmpty)
    }

    func testReadingInsideRangeIsTypical() throws {
        let v = SleepVitals.make(rows: history(10) + [row("2026-09-20", hr: 61)], day: "2026-09-20")
        XCTAssertEqual(v.nightsRemaining, 0)
        let hr = try XCTUnwrap(v.readings.first { $0.metric == .heartRate })
        // History alternates 59 / 61: mean 60, SD 1, so ± 2 — exactly the heart-rate floor.
        XCTAssertEqual(hr.range.lowerBound, 58, accuracy: 1e-9)
        XCTAssertEqual(hr.range.upperBound, 62, accuracy: 1e-9)
        XCTAssertFalse(hr.isOutlier)
        XCTAssertEqual(v.outliers, 0)
    }

    func testReadingOutsideRangeIsOutlier() throws {
        let v = SleepVitals.make(rows: history(10) + [row("2026-09-20", hr: 70)], day: "2026-09-20")
        let hr = try XCTUnwrap(v.readings.first { $0.metric == .heartRate })
        XCTAssertTrue(hr.isOutlier)
        XCTAssertGreaterThan(hr.position, 1)
        XCTAssertEqual(v.outliers, 1)
    }

    func testLaterNightsDoNotFormTheRange() throws {
        let later = row("2026-09-25", hr: 90)
        let v = SleepVitals.make(rows: history(10) + [row("2026-09-20", hr: 61), later], day: "2026-09-20")
        let hr = try XCTUnwrap(v.readings.first { $0.metric == .heartRate })
        XCTAssertEqual(hr.range.upperBound, 62, accuracy: 1e-9)
    }

    func testMetricWithoutHistoryHasNoReading() {
        let v = SleepVitals.make(rows: history(10) + [row("2026-09-20", hr: 61, resp: 14)], day: "2026-09-20")
        XCTAssertNil(v.readings.first { $0.metric == .respiratory })
    }
}
