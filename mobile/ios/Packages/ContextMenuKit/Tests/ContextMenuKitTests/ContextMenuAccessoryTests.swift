import UIKit
import XCTest
@testable import ContextMenuKit

@MainActor
final class ContextMenuAccessoryTests: XCTestCase {
    private static let screenSize = CGSize(width: 390.0, height: 844.0)
    private static let accessorySize = CGSize(width: 104.0, height: 70.0)
    private static let accessoryOffset = CGVector(dx: 16.0, dy: -40.0)

    func testAccessoryHangsOverTheSourceTopTrailingCornerAndTapsOnItKeepTheMenuOpen() throws {
        let sourceRect = CGRect(x: 16.0, y: 400.0, width: 250.0, height: 120.0)
        let overlay = makeOverlay(sourceRect: sourceRect)

        let accessoryFrame = try XCTUnwrap(overlay.accessoryFrame)
        let panelFrame = try XCTUnwrap(overlay.panelFrame)
        XCTAssertEqual(accessoryFrame, CGRect(x: 178.0, y: 360.0, width: 104.0, height: 70.0))
        XCTAssertEqual(panelFrame.minY, sourceRect.maxY + ContextMenuStyle.default.sourceSpacing)
        XCTAssertFalse(overlay.shouldDismissMenu(at: CGPoint(x: accessoryFrame.midX, y: accessoryFrame.midY)))
        XCTAssertFalse(overlay.shouldDismissMenu(at: CGPoint(x: panelFrame.midX, y: panelFrame.midY)))
        XCTAssertTrue(overlay.shouldDismissMenu(at: CGPoint(x: 40.0, y: 100.0)))
    }

    func testRightToLeftAccessoryHangsPastTheSourceLeftEdge() throws {
        let overlay = makeOverlay(
            sourceRect: CGRect(x: 124.0, y: 400.0, width: 250.0, height: 120.0),
            layoutDirection: .rightToLeft
        )

        XCTAssertEqual(try XCTUnwrap(overlay.accessoryFrame).minX, 108.0)
    }

    func testPanelOfASourceTallerThanTheScreenOverlapsItAtTheBottomClearOfTheAccessory() throws {
        let overlay = makeOverlay(sourceRect: CGRect(x: 16.0, y: -300.0, width: 300.0, height: 1600.0))

        let accessoryFrame = try XCTUnwrap(overlay.accessoryFrame)
        let panelFrame = try XCTUnwrap(overlay.panelFrame)
        XCTAssertEqual(accessoryFrame.minY, ContextMenuStyle.default.screenInsets.top)
        XCTAssertEqual(panelFrame.maxY, Self.screenSize.height)
        XCTAssertGreaterThan(panelFrame.height, 44.0)
        XCTAssertFalse(panelFrame.intersects(accessoryFrame))
    }

    func testMenuWithoutAnAccessoryKeepsItsPanelAttachedBelowTheSource() throws {
        let sourceRect = CGRect(x: 16.0, y: 400.0, width: 250.0, height: 120.0)
        let overlay = makeOverlay(sourceRect: sourceRect, hasAccessory: false)

        XCTAssertNil(overlay.accessoryFrame)
        XCTAssertEqual(try XCTUnwrap(overlay.panelFrame).minY, sourceRect.maxY + ContextMenuStyle.default.sourceSpacing)
        XCTAssertTrue(overlay.shouldDismissMenu(at: CGPoint(x: 230.0, y: 395.0)))
    }

    func testOverlayKeepsVoiceOverInsideTheMenuAndClosesOnEscape() {
        let overlay = makeOverlay(sourceRect: CGRect(x: 16.0, y: 400.0, width: 250.0, height: 120.0))

        XCTAssertTrue(overlay.accessibilityViewIsModal)
        XCTAssertTrue(overlay.accessibilityPerformEscape())
        XCTAssertFalse(overlay.isUserInteractionEnabled)
    }

    func testOverlayReportsTheStartOfItsDismissalOnce() {
        let overlay = makeOverlay(sourceRect: CGRect(x: 16.0, y: 400.0, width: 250.0, height: 120.0), hasAccessory: false)
        var dismissalStarts = 0
        overlay.onWillDismiss = { dismissalStarts += 1 }

        XCTAssertTrue(overlay.accessibilityPerformEscape())
        XCTAssertTrue(overlay.accessibilityPerformEscape())

        XCTAssertEqual(dismissalStarts, 1)
    }

    private func makeOverlay(
        sourceRect: CGRect,
        layoutDirection: UIUserInterfaceLayoutDirection = .leftToRight,
        hasAccessory: Bool = true
    ) -> ContextMenuOverlayView {
        let accessory = ContextMenuAccessory(
            size: Self.accessorySize,
            topTrailingOffset: Self.accessoryOffset,
            backgroundCapsules: [CGRect(x: 0.0, y: 0.0, width: 104.0, height: 52.0)]
        ) { _ in
            UIView()
        }
        let configuration = ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(ContextMenuAction(title: "Copy")),
                .action(ContextMenuAction(title: "Report a Problem"))
            ]),
            accessory: hasAccessory ? accessory : nil
        )
        let overlay = ContextMenuOverlayView(
            configuration: configuration,
            sourceRectInWindow: sourceRect,
            appearanceSourceView: nil,
            portalSourceView: nil,
            portalMaskRectInWindow: nil,
            portalMask: nil,
            portalShowsBackdropCutout: false,
            portalAppliesRightToLeftTransformCorrection: true,
            sourceUserInterfaceStyle: .light,
            sourceUserInterfaceLayoutDirection: layoutDirection
        )
        overlay.frame = CGRect(origin: .zero, size: Self.screenSize)
        overlay.layoutIfNeeded()
        return overlay
    }
}
