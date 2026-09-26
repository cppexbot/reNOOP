import XCTest
@testable import Strand

/// Provenance label (Component 4 of the explainability spec, 2026-06-20): a raw resolver source id
/// maps onto the label a readings table shows — On-device / WHOOP / Apple Health for the real per-day
/// merge winner, never a blanket claim. Kept byte-for-byte in step with the Kotlin mapper.
final class ProvenanceDisplayLabelTests: XCTestCase {

    func testProvenance_computedStrapSibling_isOnDevice() {
        XCTAssertEqual(provenanceDisplayLabel(rawSource: "my-whoop-noop", deviceId: "my-whoop"),
                       "On-device")
    }

    func testProvenance_importedStrapSource_isWhoop() {
        XCTAssertEqual(provenanceDisplayLabel(rawSource: "my-whoop", deviceId: "my-whoop"),
                       "WHOOP")
    }

    func testProvenance_appleHealthSource_isAppleHealth() {
        XCTAssertEqual(provenanceDisplayLabel(rawSource: "apple-health", deviceId: "my-whoop"),
                       "Apple Health")
    }

    func testProvenance_nonDefaultDeviceId_stillMapsComputedAndImported() {
        // A strap with a non-"my-whoop" device id still resolves its own sibling + imported source.
        XCTAssertEqual(provenanceDisplayLabel(rawSource: "whoop5-AB12-noop", deviceId: "whoop5-AB12"),
                       "On-device")
        XCTAssertEqual(provenanceDisplayLabel(rawSource: "whoop5-AB12", deviceId: "whoop5-AB12"),
                       "WHOOP")
    }

    func testProvenance_crossStrapComputedSibling_stillOnDevice() {
        // A "-noop" sibling banked under a DIFFERENT strap id (the user re-paired straps) is still a
        // score NOOP computed on-device. The resolver matches the "-noop" suffix, not the exact
        // "\(deviceId)-noop" — otherwise these rows would fall through to the raw id verbatim.
        XCTAssertEqual(provenanceDisplayLabel(rawSource: "whoop5-C0FF-noop", deviceId: "my-whoop"),
                       "On-device")
        XCTAssertEqual(provenanceDisplayLabel(rawSource: "my-whoop-noop", deviceId: "strap-42"),
                       "On-device")
    }

    func testProvenance_otherKnownSource_keepsItsDisplayName() {
        // Mi Band is a real merge winner — keep its own name, never a blanket on-device claim.
        XCTAssertEqual(provenanceDisplayLabel(rawSource: "xiaomi-band", deviceId: "my-whoop"),
                       "Mi Band")
    }
}
