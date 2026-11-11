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

    func testThoughtBubbleBodySlidesInsideTheScreenWhileItsTailStaysAtTheSource() throws {
        let sourceRect = CGRect(x: 16.0, y: 400.0, width: 344.0, height: 120.0)
        let overlay = self.makeOverlay(sourceRect: sourceRect, accessory: Self.makeThoughtBubble())

        // The body would end past the screen's side, so it slides back to 12 pt inside it, and the frame spans it
        // and the tail
        let bodyOffset = Self.screenSize.width - 12.0 - (sourceRect.maxX + 47.0)
        let accessoryFrame = try XCTUnwrap(overlay.accessoryFrame)
        XCTAssertEqual(accessoryFrame.minX, sourceRect.maxX + 47.0 - 108.0 + bodyOffset, accuracy: 0.01)
        XCTAssertEqual(accessoryFrame.maxX, sourceRect.maxX + 47.0, accuracy: 0.01)
        XCTAssertEqual(accessoryFrame.minY, sourceRect.minY - 62.0, accuracy: 0.01)
        let placement = Self.makeThoughtBubble().getPlacement(
            sourceRect: sourceRect,
            minX: 0.0,
            maxX: Self.screenSize.width,
            screenInsets: ContextMenuStyle.default.screenInsets,
            isRightToLeft: false
        )
        XCTAssertEqual(placement.bodyOffset, bodyOffset, accuracy: 0.01)
        XCTAssertEqual(placement.tailOffset, 0.0)
        XCTAssertEqual(placement.frame, accessoryFrame)
    }

    func testThoughtBubbleTailGoesWithTheBodyNearTheScreensSide() {
        // At the source's corner the small circle would end 3 pt from the screen's side, nearer than its 4 pt
        let sourceRect = CGRect(x: 16.0, y: 400.0, width: 356.0, height: 120.0)
        let placement = Self.makeThoughtBubble(edgeSpacing: 4.0).getPlacement(
            sourceRect: sourceRect,
            minX: 0.0,
            maxX: Self.screenSize.width,
            screenInsets: ContextMenuStyle.default.screenInsets,
            isRightToLeft: false
        )
        XCTAssertEqual(placement.tailOffset, placement.bodyOffset)
        XCTAssertEqual(placement.frame.maxX, Self.screenSize.width - 12.0, accuracy: 0.01)
        XCTAssertEqual(placement.frame.width, 108.0, accuracy: 0.01)

        let mirrored = Self.makeThoughtBubble(edgeSpacing: 4.0).getPlacement(
            sourceRect: CGRect(x: 18.0, y: 400.0, width: 356.0, height: 120.0),
            minX: 0.0,
            maxX: Self.screenSize.width,
            screenInsets: ContextMenuStyle.default.screenInsets,
            isRightToLeft: true
        )
        XCTAssertEqual(mirrored.tailOffset, mirrored.bodyOffset)
        XCTAssertEqual(mirrored.frame.minX, 12.0, accuracy: 0.01)
    }

    func testThoughtBubbleTailGoesWithTheBodyWhenItWouldComeOffIt() {
        // A body kept 80 pt from the side leaves the large circle's centre past the body's end
        var accessory = Self.makeThoughtBubble()
        accessory.tail?.screenInset = 80.0
        let placement = accessory.getPlacement(
            sourceRect: CGRect(x: 16.0, y: 400.0, width: 300.0, height: 120.0),
            minX: 0.0,
            maxX: Self.screenSize.width,
            screenInsets: ContextMenuStyle.default.screenInsets,
            isRightToLeft: false
        )
        XCTAssertLessThan(placement.bodyOffset, 0.0)
        XCTAssertEqual(placement.tailOffset, placement.bodyOffset)
    }

    func testAccessoryOverALongSourceStaysAtTheTopLimitUntilTheSourceComesDown() {
        let ridingFrame = CGRect(x: 100.0, y: -300.0, width: 108.0, height: 74.0)
        XCTAssertEqual(ContextMenuOverlayView.getPinnedAccessoryFrame(ridingFrame, topLimit: 60.0).minY, 60.0)
        XCTAssertEqual(
            ContextMenuOverlayView.getPinnedAccessoryFrame(ridingFrame.offsetBy(dx: 0.0, dy: 420.0), topLimit: 60.0).minY,
            120.0
        )
        XCTAssertEqual(ContextMenuOverlayView.getPinnedAccessoryFrame(ridingFrame, topLimit: 60.0).minX, 100.0)
    }

    func testThoughtBubbleWithoutRoomToSlideKeepsItsPlace() {
        let placement = Self.makeThoughtBubble().getPlacement(
            sourceRect: CGRect(x: 16.0, y: 400.0, width: 200.0, height: 120.0),
            minX: 0.0,
            maxX: Self.screenSize.width,
            screenInsets: ContextMenuStyle.default.screenInsets,
            isRightToLeft: false
        )
        XCTAssertEqual(placement.bodyOffset, 0.0)
        XCTAssertEqual(placement.frame, CGRect(x: 216.0 + 47.0 - 108.0, y: 338.0, width: 108.0, height: 74.0))
    }

    func testAppearanceRevealsTheContentFromTheTailsEnd() {
        let appearance = ContextMenuAccessoryAppearance(isReduced: false, bodyDelay: 0.08, growthStartX: 52.0, growthEndX: 0.0)
        XCTAssertEqual(appearance.getRevealDelay(forX: 78.0), 0.08, accuracy: 0.0001)
        XCTAssertEqual(
            appearance.getRevealDelay(forX: 30.0),
            0.08 + ContextMenuAccessoryAppearance.revealSpan * 22.0 / 52.0,
            accuracy: 0.0001
        )
        let reduced = ContextMenuAccessoryAppearance(isReduced: true, bodyDelay: 0.08, growthStartX: 52.0, growthEndX: 0.0)
        XCTAssertEqual(reduced.getRevealDelay(forX: 30.0), 0.0)
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

    /// A 108 pt capsule over a two-circle tail that goes down beside the source's top trailing corner
    private static func makeThoughtBubble(edgeSpacing: CGFloat = 0.0) -> ContextMenuAccessory {
        ContextMenuAccessory(
            size: CGSize(width: 108.0, height: 74.0),
            topTrailingOffset: CGVector(dx: 47.0, dy: -62.0),
            backgroundCapsules: [
                CGRect(x: 0.0, y: 0.0, width: 108.0, height: 56.0),
                CGRect(x: 57.0, y: 48.0, width: 16.0, height: 16.0),
                CGRect(x: 70.0, y: 66.0, width: 8.0, height: 8.0),
            ],
            tail: ContextMenuAccessoryTail(capsuleIndices: [1, 2], screenInset: 12.0, edgeSpacing: edgeSpacing),
            motion: .thoughtBubble
        ) { _ in
            UIView()
        }
    }

    private func makeOverlay(
        sourceRect: CGRect,
        layoutDirection: UIUserInterfaceLayoutDirection = .leftToRight,
        hasAccessory: Bool = true,
        accessory customAccessory: ContextMenuAccessory? = nil
    ) -> ContextMenuOverlayView {
        let accessory = customAccessory ?? ContextMenuAccessory(
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
