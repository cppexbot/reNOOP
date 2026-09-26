import XCTest
import StrandDesign
import WhoopStore
import StrandAnalytics
@testable import Strand

/// Pins "Show More Sleep Data": the averages behind Stages / Amounts and the vitals behind Comparisons.
final class SleepMoreDataTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.date(from: DateComponents(year: 2026, month: 9, day: 26))!)!
    }

    /// A night ending on `day(offset)`, in bed from 23:00 (300 min after 18:00) for the stage total.
    private func night(_ offset: Int, awake: Double = 20, light: Double = 240, deep: Double = 60,
                       rem: Double = 100) -> SleepNightDetail {
        let onset = SleepNightEntry.nightOrigin(day(offset)).addingTimeInterval(300 * 60)
        let stages = Stages(awake: awake, light: light, deep: deep, rem: rem)
        return SleepNightDetail(navIndex: -offset, day: day(offset), onset: onset,
                                wake: onset.addingTimeInterval(stages.total * 60), stages: stages, intervals: [])
    }

    func testSingleNightSummaryIsTheNightItself() {
        let s = SleepMoreData.summary([night(0)])
        XCTAssertEqual(s.nights, 1)
        XCTAssertEqual(s.inBedMin ?? 0, 420, accuracy: 0.001)
        XCTAssertEqual(s.asleepMin ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(s.stageMin[.rem] ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(s.share(.awake) ?? 0, 20.0 / 420, accuracy: 0.0001)
        XCTAssertEqual(s.efficiency ?? 0, 400.0 / 420, accuracy: 0.0001)
        XCTAssertEqual(s.bedtimeOfNightMin ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(s.wakeOfNightMin ?? 0, 720, accuracy: 0.001)
    }

    func testRangeSummaryAveragesEveryStage() {
        let s = SleepMoreData.summary([night(-1, deep: 40), night(0, deep: 80)])
        XCTAssertEqual(s.stageMin[.deep] ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(s.asleepMin ?? 0, 400, accuracy: 0.001)
        // Stage shares of a period still add up to the whole time in bed.
        let shares = SleepStage.allCases.compactMap { s.share($0) }.reduce(0, +)
        XCTAssertEqual(shares, 1, accuracy: 0.0001)
    }

    func testEmptySummaryHasNoFigures() {
        let s = SleepMoreData.summary([])
        XCTAssertEqual(s.nights, 0)
        XCTAssertNil(s.inBedMin)
        XCTAssertNil(s.efficiency)
        XCTAssertNil(s.share(.deep))
    }

    func testRangeNightsFollowTheChartWindow() {
        let all = [night(-40), night(-7), night(-6), night(0)]
        let week = SleepMoreData.nights(in: .week, all, anchor: day(0), calendar: cal)
        XCTAssertEqual(week.map(\.day), [day(-6), day(0)])
        let month = SleepMoreData.nights(in: .month, all, anchor: day(0), calendar: cal)
        XCTAssertEqual(month.count, 3)
    }

    func testHeartRatePointsStayInsideTheNight() {
        let n = night(0)
        let from = Int(n.onset.timeIntervalSince1970), to = Int(n.wake.timeIntervalSince1970)
        let buckets = [from - 600, from, from + 300, to, to + 300].map {
            HRBucket(ts: $0, bpm: 55, minBpm: 50, maxBpm: 60)
        }
        let pts = SleepMoreData.heartRatePoints(n, buckets: buckets)
        XCTAssertEqual(pts.map(\.x), [0, 300, Double(to - from)])
        XCTAssertEqual(SleepMoreData.nightlyHeartRate([n], buckets: buckets)[n.day] ?? 0, 55, accuracy: 0.001)
    }

    func testSlotValuesPerNightAndPerWeek() {
        let values: [Date: Double] = [day(0): 14, day(-1): 16, day(-10): 20]
        let week = SleepHistory.window(.week, entries: [], anchor: day(0), calendar: cal)
        let perNight = SleepMoreData.slotValues(window: week, valueByDay: values, calendar: cal)
        XCTAssertEqual(perNight, [SleepComparisonPoint(x: 5, value: 16), SleepComparisonPoint(x: 6, value: 14)])

        let sixMonths = SleepHistory.window(.sixMonths, entries: [], anchor: day(0), calendar: cal)
        let perWeek = SleepMoreData.slotValues(window: sixMonths, valueByDay: values, calendar: cal)
        XCTAssertEqual(perWeek.map(\.value).reduce(0, +), 20 + (values[day(0)]! + values[day(-1)]!) / (
            // 26 Sep 2026 is a Saturday: with a Sunday-first calendar 25 and 26 Sep share a week.
            cal.isDate(day(0), equalTo: day(-1), toGranularity: .weekOfYear) ? 2 : 1), accuracy: 0.001)
    }

    func testOverlayScaleIsNeverNarrowerThanAFifthOfTheLevel() {
        let flat = [14.5, 14.9].enumerated().map { SleepComparisonPoint(x: Double($0.offset), value: $0.element) }
        let d = SleepMoreData.overlayDomain(flat)!
        XCTAssertEqual(d.upperBound - d.lowerBound, 14.7 * 0.2, accuracy: 0.0001)
        XCTAssertEqual((d.upperBound + d.lowerBound) / 2, 14.7, accuracy: 0.0001)
        let wide = [48.0, 70.0].enumerated().map { SleepComparisonPoint(x: Double($0.offset), value: $0.element) }
        XCTAssertEqual(SleepMoreData.overlayDomain(wide), 48...70)
        XCTAssertNil(SleepMoreData.overlayDomain([]))
    }

    func testSkinTempsAreNeverMixedAcrossScales() {
        // The newest reading is a deviation, so the absolute import reading drops out.
        let kept = SleepMoreData.sameScaleSkinTemps([day(-2): 34.1, day(-1): -0.2, day(0): 0.3])
        XCTAssertEqual(Set(kept.keys), [day(-1), day(0)])
    }
}

/// Pins the Sleep score ring: its parts are the Rest composite's parts and always add up to its number.
final class SleepScoreTests: XCTestCase {
    private func day(tst: Double, eff: Double, deep: Double?, rem: Double?) -> DailyMetric {
        DailyMetric(day: "2026-09-26", totalSleepMin: tst, efficiency: eff, deepMin: deep, remMin: rem,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    func testPartsAddUpToTheScoreShownEverywhere() {
        for (tst, eff, deep, rem) in [(417.0, 0.94, 62.0, 95.0), (300, 0.8, 10, 40), (540, 0.99, 120, 130), (95, 0.61, 3, 9)] {
            let d = day(tst: tst, eff: eff, deep: deep, rem: rem)
            let s = try! XCTUnwrap(SleepScore.make(daily: d, importedPct: nil))
            XCTAssertEqual(s.value, Int(AnalyticsEngine.Rest.composite(daily: d)!.rounded()))
            XCTAssertEqual(s.parts.compactMap(\.points).reduce(0, +), s.value)
            XCTAssertEqual(s.parts.map(\.part), SleepScore.Part.allCases)
            for p in s.parts { XCTAssertLessThanOrEqual(p.points ?? .max, p.part.maxPoints) }
        }
    }

    func testPartsAreWorthTheCompositeWeights() {
        XCTAssertEqual(SleepScore.Part.allCases.map(\.maxPoints).reduce(0, +), 100)
    }

    func testImportedScoreKeepsTheNightsFiguresWithoutPoints() {
        let s = try! XCTUnwrap(SleepScore.make(daily: day(tst: 400, eff: 0.9, deep: 60, rem: 90), importedPct: 87.6))
        XCTAssertEqual(s.value, 88)
        XCTAssertTrue(s.imported)
        // The night's own figures are still drawn, without points and without the neutral regularity.
        XCTAssertEqual(s.parts.map(\.part), [.duration, .interruptions, .restorative])
        XCTAssertTrue(s.parts.allSatisfy { $0.points == nil })
        XCTAssertEqual(SleepScore.make(daily: nil, importedPct: 70)?.parts, [])
    }

    func testApportionKeepsTheTotal() {
        XCTAssertEqual(SleepScore.apportion([43.6, 18.8, 16.9, 5], total: 84), [43, 19, 17, 5])
        XCTAssertEqual(SleepScore.apportion([10.2, 10.2], total: 20), [10, 10])
        XCTAssertEqual(SleepScore.apportion([10.6, 10.4], total: 21), [11, 10])
    }

    func testNoScoreWithoutSleep() {
        XCTAssertNil(SleepScore.make(daily: nil, importedPct: nil))
    }
}

/// The Summary's Sleep card and the Sleep page must name the same night for a day.
final class SleepNightLoaderTests: XCTestCase {
    private func block(_ endTs: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: endTs - 8 * 3600, endTs: endTs, efficiency: nil, restingHr: nil,
                           avgHrv: nil, stagesJSON: nil)
    }

    func testANightIsFiledUnderTheDayItEnded() {
        let noon = Int(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 7))!.timeIntervalSince1970)
        let navDays = [[block(noon)], [block(noon - 86_400)]]
        let key = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(noon)))
        XCTAssertEqual(SleepNightLoader.wakeDayKey(navDays[0]), key)
        XCTAssertEqual(SleepNightLoader.index(ofWakeDay: key, in: navDays), 0)
        XCTAssertEqual(SleepNightLoader.index(ofWakeDay: SleepNightLoader.wakeDayKey(navDays[1])!, in: navDays), 1)
        XCTAssertNil(SleepNightLoader.index(ofWakeDay: "1999-01-01", in: navDays))
    }
}
