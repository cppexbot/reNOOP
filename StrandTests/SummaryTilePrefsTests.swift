import XCTest
@testable import Strand

/// The Summary's two Fitness tiles: what a stored pair decodes to, and how "Change Card" rewrites it.
final class SummaryTilePrefsTests: XCTestCase {

    func testDecode() {
        let cases: [(raw: String, expected: [KeyMetric], why: String)] = [
            ("", [.steps, .calories], "unset falls back to the default pair"),
            ("hrv,weight", [.hrv, .weight], "a stored pair reads back in order"),
            (" hrv , weight ", [.hrv, .weight], "spaces around tokens are ignored"),
            ("hrv", [.steps, .calories], "one metric is not a pair"),
            ("hrv,hrv", [.steps, .calories], "the two slots never repeat a metric"),
            ("charge,hrv", [.steps, .calories], "ring metrics are not tile choices"),
            ("hrv,bogus", [.steps, .calories], "an unknown key voids the pair"),
            ("hrv,weight,steps", [.steps, .calories], "more than two is not a pair"),
        ]
        for c in cases {
            XCTAssertEqual(SummaryTilePrefs.decode(c.raw), c.expected, c.why)
        }
    }

    func testReplacing() {
        let cases: [(raw: String, slot: Int, metric: KeyMetric, expected: String, why: String)] = [
            ("steps,calories", 0, .hrv, "hrv,calories", "a new metric takes the slot"),
            ("steps,calories", 1, .weight, "steps,weight", "the second slot changes alone"),
            ("steps,calories", 0, .calories, "calories,steps", "picking the other tile's metric swaps them"),
            ("steps,calories", 0, .steps, "steps,calories", "re-picking the same metric changes nothing"),
            ("steps,calories", 0, .charge, "steps,calories", "a ring metric is refused"),
            ("steps,calories", 2, .hrv, "steps,calories", "an out-of-range slot is refused"),
            ("", 1, .hrv, "steps,hrv", "an unset pair edits the default"),
        ]
        for c in cases {
            XCTAssertEqual(SummaryTilePrefs.replacing(c.raw, slot: c.slot, with: c.metric), c.expected, c.why)
        }
    }
}
