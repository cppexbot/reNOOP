import XCTest
import WhoopStore
@testable import Strand

/// The pure pieces behind the Heart Rate (Live) page and Breathe: today's hourly range folded from the
/// five-minute buckets, the RMSSD the session shows, and the session length a protocol recommends.
final class LiveBreathHelpersTests: XCTestCase {

    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func bucket(_ ts: Int, _ lo: Double, _ hi: Double) -> HRBucket {
        HRBucket(ts: ts, bpm: (lo + hi) / 2, minBpm: lo, maxBpm: hi, conf: 1)
    }

    func testHoursFoldBucketsIntoPerHourExtremes() {
        let day = Date(timeIntervalSince1970: TimeInterval(1_790_000_000 - 1_790_000_000 % 86_400))   // UTC midnight
        let t0 = Int(day.timeIntervalSince1970)
        let cases: [(name: String, buckets: [HRBucket], want: [LiveDay.Hour])] = [
            ("empty", [], []),
            ("one bucket", [bucket(t0 + 3_600, 60, 70)], [.init(hour: 1, low: 60, high: 70)]),
            ("two buckets, same hour: min of mins, max of maxes",
             [bucket(t0 + 3_600, 60, 70), bucket(t0 + 3_900, 55, 90)], [.init(hour: 1, low: 55, high: 90)]),
            ("sorted by hour",
             [bucket(t0 + 7_200 * 5, 80, 120), bucket(t0, 50, 58)],
             [.init(hour: 0, low: 50, high: 58), .init(hour: 10, low: 80, high: 120)]),
            ("before the day start is dropped", [bucket(t0 - 300, 40, 45)], []),
        ]
        for c in cases {
            XCTAssertEqual(LiveDay.hours(from: c.buckets, dayStart: day, calendar: utc), c.want, c.name)
        }
    }

    func testRangeIsTheDaysLowestAndHighest() {
        let d = LiveDay(hours: [.init(hour: 3, low: 52.4, high: 61), .init(hour: 9, low: 58, high: 127.6)],
                        resting: nil, last: nil)
        XCTAssertEqual(d.low, 52)
        XCTAssertEqual(d.high, 128)
        XCTAssertNil(LiveDay(hours: [], resting: nil, last: nil).low)
    }

    @MainActor
    func testRMSSD() {
        let cases: [(rr: [Int], want: Double?)] = [
            ([], nil),
            ([800], nil),
            ([800, 800], 0),
            ([800, 810, 790], (((10.0 * 10) + (20.0 * 20)) / 2).squareRoot()),
        ]
        for c in cases {
            let got = BreathHub.rmssd(c.rr)
            if let want = c.want {
                XCTAssertEqual(got ?? -1, want, accuracy: 1e-9, "\(c.rr)")
            } else {
                XCTAssertNil(got, "\(c.rr)")
            }
        }
    }

    func testRecommendedLength() {
        let cases: [(ms: Int, want: BreathLength)] = [
            (0, .five), (5 * 60_000, .five), (7 * 60_000 - 1, .five),
            (7 * 60_000, .ten), (10 * 60_000, .ten), (12 * 60_000, .fifteen), (20 * 60_000, .fifteen),
        ]
        for c in cases { XCTAssertEqual(BreathLength.from(recommendedMs: c.ms), c.want, "\(c.ms)") }
        XCTAssertNil(BreathLength.open.targetSeconds)
        XCTAssertEqual(BreathLength.fifteen.targetSeconds, 900)
    }

    @MainActor
    func testClock() {
        XCTAssertEqual(BreathHub.clock(0), "0:00")
        XCTAssertEqual(BreathHub.clock(65), "1:05")
        XCTAssertEqual(BreathHub.clock(600), "10:00")
    }
}
