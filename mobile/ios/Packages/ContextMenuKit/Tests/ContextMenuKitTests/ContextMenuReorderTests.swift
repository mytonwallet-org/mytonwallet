import UIKit
import XCTest
@testable import ContextMenuKit

@MainActor
final class ContextMenuReorderTests: XCTestCase {
    // Five 56 pt rows, as in the tab menu, with the middle one lifted
    private let frames = (0..<5).map { CGRect(x: 0.0, y: 8.0 + CGFloat($0) * 56.0, width: 340.0, height: 56.0) }

    private func destination(at originY: CGFloat) -> Int {
        ContextMenuPageView.reorderDestination(of: 2, at: originY, among: frames)
    }

    func testMiddleRowHeldAtTheTopReachesTheFirstPlace() {
        XCTAssertEqual(destination(at: frames[0].minY), 0)
    }

    func testMiddleRowHeldAtTheBottomReachesTheLastPlace() {
        XCTAssertEqual(destination(at: frames[4].minY), 4)
    }

    func testRowPassesANeighborOnlyOnceItsEdgeCrossesTheNeighborsMiddle() {
        XCTAssertEqual(destination(at: frames[1].midY), 2)
        XCTAssertEqual(destination(at: frames[1].midY - 1.0), 1)
        XCTAssertEqual(destination(at: frames[3].midY - 56.0), 2)
        XCTAssertEqual(destination(at: frames[3].midY - 55.0), 3)
    }
}
