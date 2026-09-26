import XCTest
@testable import Strand

/// Pins the Today-hosted card selection (#today-hosted-cards): the origin-namespaced rawValues (a
/// byte-identical cross-platform contract), the EMPTY opt-in default, and the encode/decode idiom (JSON
/// array, unknown-id drop, de-dupe, order-preserving). Mirrors the Android `HostedCardPrefsTest`
/// case-for-case; a drift on either side fails one of the twins.
final class HostedCardPrefsTests: XCTestCase {

    /// The rawValues are persisted + cross the .noopbak wire, so they are frozen. Origin-namespaced.
    func testRawValuesAreTheFrozenNamespacedContract() {
        XCTAssertEqual(HostedCard.sleepMarks.rawValue, "sleep.sleepMarks")
        XCTAssertEqual(HostedCard.asleepDuration.rawValue, "sleep.asleepDuration")
        // Byte-identical to the Kotlin `HostedCard.STRESS_TODAY`. This id rides .noopbak, so a
        // difference of one character means an Android backup restored here silently drops the card.
        XCTAssertEqual(HostedCard.stressToday.rawValue, "stress.today")
        XCTAssertEqual(HostedCard.trendHRV.rawValue, "trends.hrv")
        XCTAssertEqual(HostedCard.trendRestingHR.rawValue, "trends.restingHr")
        XCTAssertEqual(HostedCard.trendEffort.rawValue, "trends.effort")
    }

    /// The two local-day counters have to agree, and nothing but this test can check them.
    ///
    /// `StressDayCurve` returns the day the widget then STORES, and the widget's read path compares
    /// that against `WidgetSnapshot.localDayNumber` to decide whether the stored curve is still today's.
    /// They are separate copies because no module sees both: the macOS app does not compile the widget
    /// sources, and the widget extension links no packages. This target sees both, so it is the only
    /// place a divergence can be caught, and a divergence would silently drop a valid curve.
    func testTheTwoLocalDayCountersAgree() {
        var cal = Calendar(identifier: .gregorian)
        for zone in ["Europe/London", "America/New_York", "Australia/Lord_Howe", "UTC"] {
            cal.timeZone = TimeZone(identifier: zone)!
            for offset in stride(from: 0, to: 400, by: 7) {
                let d = Date(timeIntervalSince1970: 1_735_732_800 + Double(offset) * 86_400 + 43_200)
                XCTAssertEqual(StressDayCurve.localDayNumber(d, calendar: cal),
                               WidgetSnapshot.localDayNumber(d, calendar: cal),
                               "\(zone) at \(d)")
            }
        }
        // Every id must be origin-namespaced so it routes to the right provider and can't collide with a
        // Today DashboardCard id.
        for card in HostedCard.allCases {
            XCTAssertTrue(card.rawValue.contains("."), "hosted id must be namespaced: \(card.rawValue)")
        }
    }

    /// Opt-in surface: nothing is hosted until the user adds a card.
    func testDefaultIsEmpty() {
        XCTAssertEqual(HostedCard.defaultSelection, [])
        XCTAssertEqual(HostedCardPrefs.decodeEnabled(""), [])
        XCTAssertEqual(HostedCardPrefs.decodeEnabled("   "), [])
    }

    func testEncodeDecodeRoundTripsInOrder() {
        let selection: [HostedCard] = [.sleepMarks]
        let encoded = HostedCardPrefs.encode(selection)
        XCTAssertEqual(encoded, "[\"sleep.sleepMarks\"]")
        XCTAssertEqual(HostedCardPrefs.decodeEnabled(encoded), selection)
    }

    /// Unknown ids are dropped, duplicates collapsed — and an all-unknown decode stays EMPTY (unlike the
    /// dashboard, an opt-in surface has no sensible non-empty default to back-fill).
    func testDecodeDropsUnknownAndDedupesNeverBackfills() {
        XCTAssertEqual(
            HostedCardPrefs.decodeEnabled("[\"sleep.sleepMarks\",\"trends.bogus\",\"sleep.sleepMarks\"]"),
            [.sleepMarks]
        )
        XCTAssertEqual(HostedCardPrefs.decodeEnabled("[\"nope\",\"also.nope\"]"), [])
    }

    /// Accepts the legacy comma-joined form as well as the canonical JSON array.
    func testDecodeAcceptsLegacyCommaForm() {
        XCTAssertEqual(HostedCardPrefs.decodeEnabled("sleep.sleepMarks"), [.sleepMarks])
    }
}
