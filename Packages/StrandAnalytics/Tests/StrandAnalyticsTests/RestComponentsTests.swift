import XCTest
@testable import StrandAnalytics
import WhoopStore

/// The Rest composite is exactly its weighted components, so a screen that draws the parts (the Sleep
/// score ring) can never add up to a different number than the score it sits beside.
final class RestComponentsTests: XCTestCase {
    private func day(tst: Double?, eff: Double?, deep: Double?, rem: Double?) -> DailyMetric {
        DailyMetric(day: "2026-09-26", totalSleepMin: tst, efficiency: eff, deepMin: deep, remMin: rem,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    func testCompositeIsTheWeightedComponents() {
        let cases: [(Double, Double, Double?, Double?)] = [
            (417, 0.94, 62, 95), (300, 0.8, 10, 40), (540, 0.99, 120, 130), (480, 0.9, nil, nil), (45, 0.5, 0, 0),
        ]
        for (tst, eff, deep, rem) in cases {
            let d = day(tst: tst, eff: eff, deep: deep, rem: rem)
            let c = try! XCTUnwrap(AnalyticsEngine.Rest.components(daily: d))
            let score = try! XCTUnwrap(AnalyticsEngine.Rest.composite(daily: d))
            XCTAssertEqual((c.weighted * 10000).rounded() / 100, score)
            for part in [c.duration, c.efficiency, c.restorative, c.consistency] {
                XCTAssertTrue((0...1).contains(part))
            }
        }
    }

    func testNoSleepHasNoComponents() {
        XCTAssertNil(AnalyticsEngine.Rest.components(daily: day(tst: 0, eff: 0.9, deep: 1, rem: 1)))
        XCTAssertNil(AnalyticsEngine.Rest.components(daily: day(tst: 400, eff: nil, deep: 1, rem: 1)))
    }

    func testMissingConsistencyIsNeutral() {
        let c = AnalyticsEngine.Rest.components(daily: day(tst: 480, eff: 0.9, deep: 70, rem: 100))
        XCTAssertEqual(c?.consistency, AnalyticsEngine.Rest.neutralConsistency)
        XCTAssertEqual(c?.duration, 1)
    }
}
