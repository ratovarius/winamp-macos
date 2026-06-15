@testable import Winamp
import XCTest

final class WinampEQBandsTests: XCTestCase {
    func testDisplayLabelsMatchBandCount() {
        XCTAssertEqual(WinampEQBands.displayLabels.count, WinampEQBands.bandCount)
        XCTAssertEqual(WinampEQBands.centerFrequenciesHz.count, WinampEQBands.bandCount)
    }

    func testBandCenterXAlignsWithEvenSpacing() {
        let width: CGFloat = 300
        let first = WinampEQBands.bandCenterX(bandIndex: 0, width: width)
        let last = WinampEQBands.bandCenterX(bandIndex: 9, width: width)
        XCTAssertEqual(first, width / 20, accuracy: 0.001)
        XCTAssertEqual(last, width * 19 / 20, accuracy: 0.001)
    }

    func testResponseCurveEndpointsFollowPreamp() {
        let points = WinampEQBands.responseCurvePoints(
            bandValues: Array(repeating: 0, count: 10),
            preampValue: 0.25,
            width: 200,
            height: 40
        )
        XCTAssertEqual(points.first?.x, 0)
        XCTAssertEqual(points.last?.x, 200)
        let startY = points.first?.y ?? 0
        let endY = points.last?.y ?? 0
        XCTAssertEqual(startY, endY, accuracy: 0.001)
    }
}
