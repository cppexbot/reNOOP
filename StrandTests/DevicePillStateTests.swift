import XCTest
@testable import Strand

/// Pins the Devices card's state-pill priority (#221): "Connected · not paired" must beat "Connected"
/// but yield to a reboot's "Reconnecting…". A silent
/// reorder would otherwise only be caught by eyeballing a screenshot.
final class DevicePillStateTests: XCTestCase {

    func testBondRefused_beatsActiveLive_butYieldsToReconnecting() {
        XCTAssertEqual(
            DevicePillState.resolve(isArchived: false, isActive: true, isReconnecting: false,
                                     bondRefused: true, isLiveConnected: true).label,
            "Connected · not paired")
        XCTAssertEqual(
            DevicePillState.resolve(isArchived: false, isActive: true, isReconnecting: true,
                                     bondRefused: true, isLiveConnected: true).label,
            "Reconnecting…")
    }

    func testNormalConnect_isUnaffected() {
        XCTAssertEqual(
            DevicePillState.resolve(isArchived: false, isActive: true, isReconnecting: false,
                                     bondRefused: false, isLiveConnected: true).label,
            "Connected")
        XCTAssertEqual(
            DevicePillState.resolve(isArchived: false, isActive: true, isReconnecting: false,
                                     bondRefused: false, isLiveConnected: false).label,
            "Not connected")
    }

    func testNonActiveAndArchived() {
        XCTAssertEqual(
            DevicePillState.resolve(isArchived: false, isActive: false, isReconnecting: false,
                                     bondRefused: false, isLiveConnected: false).label,
            "Not connected")
        XCTAssertEqual(
            DevicePillState.resolve(isArchived: true, isActive: false, isReconnecting: false,
                                     bondRefused: false, isLiveConnected: false).label,
            "Removed")
    }
}
