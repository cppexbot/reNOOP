import XCTest
@testable import Strand

/// All Metrics: which Health category a catalog metric lands in, which source a key recorded by several
/// shows, and the order of sections and cards.
final class AllMetricsGroupingTests: XCTestCase {

    private func metric(_ key: String, _ source: String) -> MetricDescriptor {
        guard let m = MetricCatalog.metric(key: key, source: source) else {
            XCTFail("no catalog entry \(source):\(key)")
            return MetricCatalog.all[0]
        }
        return m
    }

    func testCategoryMapping() {
        let cases: [(String, String, HealthCategory)] = [
            ("recovery", "my-whoop", .heart),
            ("hrv", "my-whoop", .heart),
            ("rhr", "my-whoop", .heart),
            ("vo2max", "apple-health", .heart),
            ("fitness_age", "my-whoop", .heart),
            ("resp_rate", "my-whoop", .respiratory),
            ("spo2", "my-whoop", .respiratory),
            ("spo2", "xiaomi-band", .respiratory),
            ("skin_temp", "my-whoop", .bodyMeasurements),
            ("weight", "apple-health", .bodyMeasurements),
            ("body_fat", "apple-health", .bodyMeasurements),
            ("strain", "my-whoop", .activity),
            ("steps", "apple-health", .activity),
            ("energy_kcal", "my-whoop", .activity),
            ("active_kcal", "apple-health", .activity),
            ("hr_zones45_min", "my-whoop", .activity),
            ("sleep_performance", "my-whoop", .sleep),
            ("sleep_score", "xiaomi-band", .sleep),
            ("protein_g", "nutrition-csv", .nutrition),
            ("stress", "my-whoop", .mentalWellbeing),
            ("stress", "xiaomi-band", .mentalWellbeing),
            ("mood", "noop-mood", .mentalWellbeing),
        ]
        for (key, source, expected) in cases {
            XCTAssertEqual(AllMetricsCatalog.category(metric(key, source)), expected, "\(source):\(key)")
        }
    }

    func testEveryCatalogMetricHasACategory() {
        let covered = Set(MetricCatalog.all.map { AllMetricsCatalog.category($0) })
        XCTAssertEqual(covered, Set(HealthCategory.allCases))
    }

    func testNewestSourceWins() {
        let steps = ["apple-health", "my-whoop", "xiaomi-band"].map { metric("steps", $0) }
        let latest = ["apple-health:steps": "2026-09-20", "my-whoop:steps": "2026-09-18",
                      "xiaomi-band:steps": "2026-09-25"]
        let picked = AllMetricsCatalog.oneSourcePerKey(steps, latestDay: latest)
        XCTAssertEqual(picked.map(\.id), ["xiaomi-band:steps"])
    }

    func testTieFallsToPriority() {
        let steps = ["xiaomi-band", "apple-health", "my-whoop"].map { metric("steps", $0) }
        let sameDay = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, "2026-09-25") })
        XCTAssertEqual(AllMetricsCatalog.oneSourcePerKey(steps, latestDay: sameDay).map(\.id), ["my-whoop:steps"])
        // No readings anywhere (the "without data" list): priority alone.
        XCTAssertEqual(AllMetricsCatalog.oneSourcePerKey(Array(steps.dropLast()), latestDay: [:]).map(\.id),
                       ["apple-health:steps"])
    }

    func testOneCardPerKeyKeepsFirstAppearanceOrder() {
        let metrics = [metric("rhr", "xiaomi-band"), metric("hrv", "my-whoop"), metric("rhr", "my-whoop")]
        let picked = AllMetricsCatalog.oneSourcePerKey(metrics, latestDay: [:])
        XCTAssertEqual(picked.map(\.id), ["my-whoop:rhr", "my-whoop:hrv"])
    }

    func testWholeCatalogHasNoDuplicateKeys() {
        let picked = AllMetricsCatalog.oneSourcePerKey(MetricCatalog.all, latestDay: [:])
        XCTAssertEqual(picked.count, Set(MetricCatalog.all.map(\.key)).count)
        XCTAssertEqual(Set(picked.map(\.key)).count, picked.count)
    }

    func testSectionsSortAlphabeticallyByTitle() {
        let metrics = [metric("sleep_performance", "my-whoop"), metric("rhr", "my-whoop"),
                       metric("hrv", "my-whoop"), metric("steps", "apple-health"), metric("weight", "apple-health")]
        let names: [HealthCategory: String] = [.activity: "Activity", .bodyMeasurements: "Body Measurements",
                                               .heart: "Heart", .sleep: "Sleep"]
        let sections = AllMetricsCatalog.sections(metrics, title: { names[$0] ?? "" })
        XCTAssertEqual(sections.map(\.category), [.activity, .bodyMeasurements, .heart, .sleep])
        let heart = sections.first { $0.category == .heart }!.metrics.map(\.title)
        XCTAssertEqual(heart, heart.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertEqual(heart.count, 2)
    }

    func testSearchMatchesNameOrCategoryIgnoringCase() {
        let hrv = metric("hrv", "my-whoop")
        XCTAssertTrue(AllMetricsCatalog.matches(hrv, query: ""))
        XCTAssertTrue(AllMetricsCatalog.matches(hrv, query: hrv.title.uppercased()))
        XCTAssertTrue(AllMetricsCatalog.matches(hrv, query: HealthCategory.heart.title.lowercased()))
        XCTAssertFalse(AllMetricsCatalog.matches(hrv, query: "zzzz"))
    }
}
