import SwiftUI
import XCTest
@testable import StrandDesign

/// CR-1: a literal point size from an Apple spec maps to the text style whose Large default it is, so it
/// looks identical at the default setting and follows Dynamic Type; other sizes stay fixed.
final class TypographyTextStyleTests: XCTestCase {
    func testSpecSizesMapToTextStyles() {
        let cases: [(CGFloat, Font.TextStyle)] = [
            (11, .caption2), (12, .caption), (13, .footnote), (15, .subheadline), (16, .callout),
            (17, .body), (20, .title3), (22, .title2), (28, .title), (34, .largeTitle),
        ]
        for (size, style) in cases {
            XCTAssertEqual(StrandFont.textStyle(for: size), style, "\(size) pt")
        }
    }

    func testOffSpecSizesStayFixed() {
        for size: CGFloat in [8, 9, 10, 14, 18, 19, 24, 30, 40, 64, 72, 88] {
            XCTAssertNil(StrandFont.textStyle(for: size), "\(size) pt")
        }
    }
}
