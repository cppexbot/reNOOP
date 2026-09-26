import XCTest
@testable import Strand

final class StepsAverageCardPrefsTests: XCTestCase {
    func testAverageRequiresExplicitOptInAndUsesAndroidPreferenceKey() {
        let initial = DashboardCardPrefs.decodeEnabled("")
        XCTAssertFalse(initial.contains(.stepsAverage30))
        let draft = EditableLayoutDraft(visible: initial, allItems: DashboardCard.canonicalOrder)
        XCTAssertTrue(draft.hidden.contains(.stepsAverage30))
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(DashboardCardPrefs.encode([.stepsAverage30])), [.stepsAverage30])
        XCTAssertNil(KeyMetric(rawValue: "stepsAverage30"))
    }

    func testLegacyOptInMovesOnceAndDoesNotReturnAfterHiding() throws {
        let suite = "RollingStepsAverageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        DashboardCardPrefs.migrateLegacyStepsAverage(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: DashboardCardPrefs.selectionKey))
        defaults.set("hrv,stepsAverage30", forKey: "today.keyMetrics")
        DashboardCardPrefs.migrateLegacyStepsAverage(defaults: defaults)
        XCTAssertTrue(DashboardCardPrefs.decodeEnabled(defaults.string(forKey: DashboardCardPrefs.selectionKey) ?? "").contains(.stepsAverage30))
        XCTAssertEqual(defaults.string(forKey: "today.keyMetrics"), "hrv")
        defaults.set(DashboardCardPrefs.encode([.hrv]), forKey: DashboardCardPrefs.selectionKey)
        DashboardCardPrefs.migrateLegacyStepsAverage(defaults: defaults)
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(defaults.string(forKey: DashboardCardPrefs.selectionKey) ?? ""), [.hrv])
    }

    func testCombinedDestinationDoesNotReplaceSourceSpecificCatalogEntries() throws {
        let combined = try XCTUnwrap(MetricCatalog.metric(key: "steps", source: MetricCatalog.combinedStepsSource))
        XCTAssertEqual(combined.source, MetricCatalog.combinedStepsSource)
        XCTAssertFalse(MetricCatalog.all.contains(combined))
        for source in ["my-whoop", "apple-health", "xiaomi-band"] {
            XCTAssertEqual(MetricCatalog.metric(key: "steps", source: source)?.source, source)
        }
        XCTAssertEqual(MetricCatalog.metric(key: "steps_est", source: "my-whoop")?.key, "steps_est")
    }
}
