import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

/// Pins the Summary home's pure pieces: which readiness signals become highlights, how a ring fills, and
/// that a pinned card shows the same value (and honest no-data state) the old Key Metrics tile did.
final class SummaryHomeTests: XCTestCase {

    // MARK: - Highlights

    private func signal(_ key: String, _ flag: ReadinessEngine.Flag) -> ReadinessEngine.Signal {
        ReadinessEngine.Signal(key: key, label: key, detail: "", flag: flag)
    }

    private func readiness(_ level: ReadinessEngine.Level,
                           _ signals: [ReadinessEngine.Signal]) -> ReadinessEngine.Readiness {
        ReadinessEngine.Readiness(level: level, headline: "", summary: "", signals: signals,
                                  acwr: nil, monotony: nil)
    }

    func testHighlightsDropNeutralAndOrderMostConcerningFirst() {
        let r = readiness(.strained, [
            signal("hrv", .good),
            signal("rhr", .neutral),
            signal("respRate", .watch),
            signal("monotony", .bad),
        ])
        XCTAssertEqual(SummaryHighlight.from(r).map(\.key), ["monotony", "respRate", "hrv"])
    }

    func testHighlightsCapAtThreeAndKeepEngineOrderWithinASeverity() {
        let r = readiness(.rundown, [
            signal("hrv", .bad), signal("rhr", .bad), signal("respRate", .bad), signal("acwr", .bad),
        ])
        XCTAssertEqual(SummaryHighlight.from(r).map(\.key), ["hrv", "rhr", "respRate"])
    }

    func testInsufficientHistoryOrNoReadinessHasNoHighlights() {
        XCTAssertTrue(SummaryHighlight.from(readiness(.insufficient, [signal("hrv", .bad)])).isEmpty)
        XCTAssertTrue(SummaryHighlight.from(nil).isEmpty)
    }

    func testHighlightRoutes() {
        let cases: [(String, String)] = [
            ("hrv", "hrv"), ("rhr", "rhr"), ("respRate", "resp_rate"),
            ("acwr", HeroRingMetric.effort), ("monotony", HeroRingMetric.effort),
        ]
        for (key, route) in cases {
            XCTAssertEqual(SummaryHighlight.routeKey(for: key), route, key)
        }
    }

    // MARK: - Ring fill

    func testRingFractionClamps() {
        let cases: [(Double?, Double, Double)] = [
            (nil, 100, 0), (-5, 100, 0), (0, 100, 0), (50, 100, 0.5), (100, 100, 1), (140, 100, 1),
            (10, 0, 0), (.nan, 100, 0),
        ]
        for (value, max, expected) in cases {
            XCTAssertEqual(RingFraction.of(value, max: max), expected, accuracy: 1e-9,
                           "\(String(describing: value)) / \(max)")
        }
    }

    // MARK: - Pinned metric readings

    private func day(hrv: Double? = nil, rhr: Int? = nil, resp: Double? = nil, spo2: Double? = nil,
                     steps: Int? = nil, kcal: Double? = nil) -> DailyMetric {
        DailyMetric(day: "2026-09-26", totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: spo2, respRateBpm: resp, steps: steps,
                    activeKcalEst: kcal)
    }

    private func inputs(day: DailyMetric? = nil, hrvDay: DailyMetric? = nil, spo2Candidate: Double? = nil,
                        importedSteps: Int? = nil, stepsEstimate: Double? = nil,
                        importedKcal: Double? = nil) -> SummaryMetricInputs {
        SummaryMetricInputs(day: day, vitalsDay: nil, respDay: nil, hrvDay: hrvDay, restingHrDay: nil,
                            skinTempReading: nil, spo2Candidate: spo2Candidate, importedSteps: importedSteps,
                            stepsEstimate: stepsEstimate, importedActiveKcal: importedKcal,
                            healthWeightKg: nil, profileWeightKg: 70, unitSystem: .metric, fahrenheit: false)
    }

    func testRingMetricsAreNeverPinnedCards() {
        for metric in [KeyMetric.charge, .effort, .rest] {
            XCTAssertNil(SummaryMetricReading.resolve(metric, inputs()), metric.rawValue)
        }
    }

    func testEveryOtherMetricResolves() {
        for metric in KeyMetric.allCases where ![.charge, .effort, .rest].contains(metric) {
            XCTAssertNotNil(SummaryMetricReading.resolve(metric, inputs()), metric.rawValue)
        }
    }

    func testMissingValueShowsDashWithoutUnit() {
        let r = SummaryMetricReading.resolve(.hrv, inputs())
        XCTAssertEqual(r?.value, SummaryMetricReading.noValue)
        XCTAssertEqual(r?.unit, "")
        XCTAssertEqual(r?.hasValue, false)
    }

    func testHrvPrefersTheDayThenTheCarry() {
        XCTAssertEqual(SummaryMetricReading.resolve(.hrv, inputs(day: day(hrv: 61.6), hrvDay: day(hrv: 40)))?.value, "62")
        XCTAssertEqual(SummaryMetricReading.resolve(.hrv, inputs(day: day(), hrvDay: day(hrv: 40)))?.value, "40")
        XCTAssertEqual(SummaryMetricReading.resolve(.hrv, inputs(day: day(hrv: 58)))?.unit, String(localized: "ms"))
    }

    func testBloodOxygenFallsBackToTheCandidateOnlyWithoutARealReading() {
        let real = SummaryMetricReading.resolve(.bloodOxygen, inputs(day: day(spo2: 96.4), spo2Candidate: 91))
        XCTAssertEqual(real?.value, "96")
        XCTAssertNil(real?.caption)
        XCTAssertEqual(real?.seriesKey, "spo2")

        let candidate = SummaryMetricReading.resolve(.bloodOxygen, inputs(day: day(), spo2Candidate: 91))
        XCTAssertEqual(candidate?.value, "91")
        XCTAssertNotNil(candidate?.caption)
        XCTAssertEqual(candidate?.seriesKey, "spo2_candidate")
    }

    func testStepsPrecedenceMeasuredThenImportedThenEstimate() {
        XCTAssertEqual(SummaryMetricReading.resolve(.steps, inputs(day: day(steps: 1200), importedSteps: 900,
                                                                   stepsEstimate: 500))?.value,
                       SummaryMetricReading.grouped(1200))
        XCTAssertEqual(SummaryMetricReading.resolve(.steps, inputs(day: day(), importedSteps: 900,
                                                                   stepsEstimate: 500))?.value,
                       SummaryMetricReading.grouped(900))
        XCTAssertEqual(SummaryMetricReading.resolve(.steps, inputs(day: day(), stepsEstimate: 500))?.value,
                       SummaryMetricReading.grouped(500))
    }

    func testCaloriesPreferImportedEnergy() {
        XCTAssertEqual(SummaryMetricReading.resolve(.calories, inputs(day: day(kcal: 300), importedKcal: 420))?.value,
                       "420")
        XCTAssertEqual(SummaryMetricReading.resolve(.calories, inputs(day: day(kcal: 300)))?.value, "300")
    }

    func testWeightFallsBackToProfileWithHonestCaption() {
        let r = SummaryMetricReading.resolve(.weight, inputs())
        XCTAssertEqual(r?.value, SummaryMetricReading.decimal(70))
        XCTAssertEqual(r?.unit, String(localized: "kg"))
        XCTAssertEqual(r?.caption, String(localized: "from profile"))
        XCTAssertNil(r?.stampDay, "a typed-in profile weight was never measured on a day")
    }

    // MARK: - Recency stamps

    func testStampFollowsTheDayTheValueCameFrom() {
        let carried = DailyMetric(day: "2026-09-24", totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                                  lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: 40, recovery: nil,
                                  strain: nil, exerciseCount: nil)
        XCTAssertEqual(SummaryMetricReading.resolve(.hrv, inputs(day: day(hrv: 58)))?.stampDay, "2026-09-26")
        XCTAssertEqual(SummaryMetricReading.resolve(.hrv, inputs(day: day(), hrvDay: carried))?.stampDay, "2026-09-24")
        XCTAssertNil(SummaryMetricReading.resolve(.hrv, inputs(day: day()))?.stampDay, "no value, no stamp")
    }

    func testStampWords() {
        XCTAssertEqual(SummaryStamp.text(dayKey: "2026-09-26", todayKey: "2026-09-26"), String(localized: "Today"))
        XCTAssertEqual(SummaryStamp.text(dayKey: "2026-09-25", todayKey: "2026-09-26"), String(localized: "Yesterday"))
        XCTAssertEqual(SummaryStamp.text(dayKey: "2026-08-31", todayKey: "2026-09-01"), String(localized: "Yesterday"),
                       "across a month boundary")
        XCTAssertNotNil(SummaryStamp.text(dayKey: "2026-09-20", todayKey: "2026-09-26"))
        XCTAssertNil(SummaryStamp.text(dayKey: nil, todayKey: "2026-09-26"))
        XCTAssertNil(SummaryStamp.text(dayKey: "garbage", todayKey: "2026-09-26"))
    }

    // MARK: - Monogram

    func testInitialsTakeTheFirstLetterOfUpToTwoWords() {
        XCTAssertEqual(ProfileStore.initials(of: "Денис Баласов"), "ДБ")
        XCTAssertEqual(ProfileStore.initials(of: "  denis   balasov  extra "), "DB")
        XCTAssertEqual(ProfileStore.initials(of: "Denis"), "D")
        XCTAssertEqual(ProfileStore.initials(of: "   "), "")
    }

    // MARK: - Highlight sentences

    func testEveryFlaggedSignalHasItsOwnWholeSentence() {
        let keys = ["hrv", "rhr", "respRate", "acwr", "monotony"]
        let flags: [ReadinessEngine.Flag] = [.good, .watch, .bad]
        for key in keys {
            for flag in flags {
                let sentence = ReadinessCopy.sentence(signal(key, flag))
                XCTAssertFalse(sentence.isEmpty, "\(key) \(flag)")
                XCTAssertTrue(sentence.hasSuffix("."), "\(key) \(flag): a highlight is a full sentence")
            }
        }
    }
}
