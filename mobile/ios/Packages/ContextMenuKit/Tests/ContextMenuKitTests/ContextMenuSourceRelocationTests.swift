import UIKit
import XCTest
@testable import ContextMenuKit

@MainActor
final class ContextMenuSourceRelocationTests: XCTestCase {
    private static let screenSize = CGSize(width: 390.0, height: 844.0)
    private static let topLimit: CGFloat = 8.0
    private static let bottomLimit: CGFloat = 834.0
    private static let sourceSpacing: CGFloat = 7.0

    func testVisibleSourceWithRoomForThePanelStaysInPlace() {
        XCTAssertEqual(offset(for: CGRect(x: 16.0, y: 200.0, width: 250.0, height: 120.0), panelHeight: 200.0), 0.0)
    }

    func testSourceWhosePanelDoesNotFitBelowItRisesOnlyUntilThePanelFits() {
        let source = CGRect(x: 16.0, y: 700.0, width: 250.0, height: 120.0)
        let offset = offset(for: source, panelHeight: 200.0)

        XCTAssertEqual(source.maxY + offset + Self.sourceSpacing + 200.0, Self.bottomLimit)
    }

    func testSourceAboveTheTopComesDownToIt() {
        let source = CGRect(x: 16.0, y: -50.0, width: 250.0, height: 120.0)

        XCTAssertEqual(source.minY + offset(for: source, panelHeight: 200.0), Self.topLimit)
    }

    func testSourceAndPanelTallerThanTheAreaStartAtItsTop() {
        let source = CGRect(x: 16.0, y: -300.0, width: 300.0, height: 1600.0)

        XCTAssertEqual(source.minY + offset(for: source, panelHeight: 200.0), Self.topLimit)
    }

    func testRelocatedMenuHangsItsPanelUnderTheMovedSource() throws {
        let source = CGRect(x: 16.0, y: 760.0, width: 250.0, height: 120.0)
        let overlay = makeOverlay(sourceRect: source)

        let offset = try XCTUnwrap(overlay.relocationOffset)
        let panelFrame = try XCTUnwrap(overlay.panelFrame)
        XCTAssertLessThan(offset, 0.0)
        XCTAssertEqual(panelFrame.minY, source.maxY + offset + Self.sourceSpacing)
        XCTAssertEqual(panelFrame.maxY, Self.bottomLimit)
        XCTAssertEqual(panelFrame.minX, source.minX)
        XCTAssertFalse(overlay.relocationScrollView.isScrollEnabled)
        XCTAssertEqual(overlay.relocationScrollView.contentOffset.y, 0.0)
        XCTAssertFalse(overlay.shouldDismissMenu(at: CGPoint(x: panelFrame.midX, y: panelFrame.midY)))
    }

    func testReplicaTallerThanTheScreenScrollsAndOpensAtThePanel() throws {
        let source = CGRect(x: 16.0, y: -300.0, width: 300.0, height: 1600.0)
        let overlay = makeOverlay(sourceRect: source)

        let offset = try XCTUnwrap(overlay.relocationOffset)
        let panelFrame = try XCTUnwrap(overlay.panelFrame)
        let scrollView = overlay.relocationScrollView
        XCTAssertEqual(source.minY + offset, Self.topLimit)
        XCTAssertTrue(scrollView.isScrollEnabled)
        XCTAssertEqual(scrollView.contentSize.height, panelFrame.maxY + Self.screenSize.height - Self.bottomLimit)
        XCTAssertEqual(panelFrame.maxY - scrollView.contentOffset.y, Self.bottomLimit)
        let panelCenterOnScreen = CGPoint(x: panelFrame.midX, y: panelFrame.midY - scrollView.contentOffset.y)
        XCTAssertFalse(overlay.shouldDismissMenu(at: panelCenterOnScreen))
        XCTAssertTrue(overlay.shouldDismissMenu(at: CGPoint(x: panelFrame.midX, y: panelFrame.midY)))
    }

    func testRelocatedAccessoryStaysOverTheSourceAndBelowTheTop() throws {
        let source = CGRect(x: 16.0, y: 20.0, width: 250.0, height: 120.0)
        let overlay = makeOverlay(sourceRect: source, hasAccessory: true)

        let offset = try XCTUnwrap(overlay.relocationOffset)
        let accessoryFrame = try XCTUnwrap(overlay.accessoryFrame)
        XCTAssertEqual(accessoryFrame.minY, Self.topLimit)
        XCTAssertEqual(accessoryFrame.minY, source.minY + offset - 40.0)
        XCTAssertEqual(try XCTUnwrap(overlay.panelFrame).minY, source.maxY + offset + Self.sourceSpacing)
    }

    func testMenuWithoutASourcePortalKeepsItsUsualPlacement() throws {
        let source = CGRect(x: 16.0, y: 400.0, width: 250.0, height: 120.0)
        let overlay = makeOverlay(sourceRect: source, hasPortal: false)

        XCTAssertNil(overlay.relocationOffset)
        XCTAssertEqual(try XCTUnwrap(overlay.panelFrame).minY, source.maxY + Self.sourceSpacing)
    }

    private func offset(for attachmentRect: CGRect, panelHeight: CGFloat) -> CGFloat {
        ContextMenuOverlayView.getMinimalRelocationOffset(
            attachmentRect: attachmentRect,
            panelHeight: panelHeight,
            sourceSpacing: Self.sourceSpacing,
            topLimit: Self.topLimit,
            bottomLimit: Self.bottomLimit
        )
    }

    private func makeOverlay(
        sourceRect: CGRect,
        hasAccessory: Bool = false,
        hasPortal: Bool = true
    ) -> ContextMenuOverlayView {
        var style = ContextMenuStyle.default
        style.sourceSpacing = Self.sourceSpacing
        style.horizontalAlignment = .leading
        let accessory = ContextMenuAccessory(
            size: CGSize(width: 104.0, height: 70.0),
            topTrailingOffset: CGVector(dx: 16.0, dy: -40.0),
            backgroundCapsules: [CGRect(x: 0.0, y: 0.0, width: 104.0, height: 52.0)]
        ) { _ in
            UIView()
        }
        let configuration = ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(ContextMenuAction(title: "Copy")),
                .action(ContextMenuAction(title: "Report a Problem"))
            ]),
            style: style,
            accessory: hasAccessory ? accessory : nil,
            sourceRelocation: ContextMenuSourceRelocation()
        )
        let overlay = ContextMenuOverlayView(
            configuration: configuration,
            sourceRectInWindow: sourceRect,
            appearanceSourceView: nil,
            portalSourceView: hasPortal ? UIView(frame: sourceRect) : nil,
            portalMaskRectInWindow: nil,
            portalMask: nil,
            portalShowsBackdropCutout: false,
            portalAppliesRightToLeftTransformCorrection: true,
            sourceUserInterfaceStyle: .light,
            sourceUserInterfaceLayoutDirection: .leftToRight
        )
        overlay.frame = CGRect(origin: .zero, size: Self.screenSize)
        overlay.layoutIfNeeded()
        return overlay
    }
}
