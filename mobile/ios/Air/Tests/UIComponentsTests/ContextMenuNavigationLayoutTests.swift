import Testing
import UIKit
@testable import ContextMenuKit

@Suite("Context Menu Navigation Layout")
@MainActor
struct ContextMenuNavigationLayoutTests {
    @Test
    func `short submenu push and pop remain above the source without changing the animation anchor`() async throws {
        let fixture = try self.makeFixture(
            sourceRect: CGRect(x: 145, y: 500, width: 100, height: 40),
            rootActionCount: 6,
            submenuActionCount: 1
        )
        let initialFrame = fixture.navigationView.frame
        let initialAnchorPoint = fixture.navigationView.layer.anchorPoint

        fixture.navigationView.pageView(
            fixture.rootPageView,
            didActivate: .submenu(fixture.submenuPage)
        )

        #expect(fixture.navigationView.isTransitioningPages)
        #expect(abs(fixture.navigationView.frame.maxY - initialFrame.maxY) < 0.5)
        #expect(fixture.navigationView.layer.anchorPoint == initialAnchorPoint)

        try await Task.sleep(nanoseconds: 600_000_000)

        #expect(!fixture.navigationView.isTransitioningPages)
        #expect(abs(fixture.navigationView.frame.maxY - initialFrame.maxY) < 0.5)

        let submenuAnchorPoint = fixture.navigationView.layer.anchorPoint
        fixture.navigationView.popToPreviousPageIfNeeded()

        #expect(fixture.navigationView.isTransitioningPages)
        #expect(abs(fixture.navigationView.frame.maxY - initialFrame.maxY) < 0.5)
        #expect(fixture.navigationView.layer.anchorPoint == submenuAnchorPoint)

        try await Task.sleep(nanoseconds: 600_000_000)

        #expect(!fixture.navigationView.isTransitioningPages)
        #expect(abs(fixture.navigationView.frame.maxY - initialFrame.maxY) < 0.5)
    }

    @Test
    func `scrollable submenu push and pop remain below the source without changing the animation anchor`() async throws {
        let fixture = try self.makeFixture(
            sourceRect: CGRect(x: 145, y: 150, width: 100, height: 40),
            rootActionCount: 1,
            submenuActionCount: 16
        )
        let initialFrame = fixture.navigationView.frame
        let initialAnchorPoint = fixture.navigationView.layer.anchorPoint

        fixture.navigationView.pageView(
            fixture.rootPageView,
            didActivate: .submenu(fixture.submenuPage)
        )

        #expect(fixture.navigationView.isTransitioningPages)
        #expect(abs(fixture.navigationView.frame.minY - initialFrame.minY) < 0.5)
        #expect(fixture.navigationView.layer.anchorPoint == initialAnchorPoint)

        try await Task.sleep(nanoseconds: 600_000_000)

        #expect(!fixture.navigationView.isTransitioningPages)
        #expect(abs(fixture.navigationView.frame.minY - initialFrame.minY) < 0.5)

        let submenuAnchorPoint = fixture.navigationView.layer.anchorPoint
        fixture.navigationView.popToPreviousPageIfNeeded()

        #expect(fixture.navigationView.isTransitioningPages)
        #expect(abs(fixture.navigationView.frame.minY - initialFrame.minY) < 0.5)
        #expect(fixture.navigationView.layer.anchorPoint == submenuAnchorPoint)

        try await Task.sleep(nanoseconds: 600_000_000)

        #expect(!fixture.navigationView.isTransitioningPages)
        #expect(abs(fixture.navigationView.frame.minY - initialFrame.minY) < 0.5)
    }

    private func makeFixture(
        sourceRect: CGRect,
        rootActionCount: Int,
        submenuActionCount: Int
    ) throws -> Fixture {
        let submenuPage = ContextMenuPage(items: [
            .back(ContextMenuBackAction(title: "Back")),
            .separator,
        ] + self.actions(count: submenuActionCount))
        let submenu = ContextMenuSubmenu(title: "Submenu") { submenuPage }
        let configuration = ContextMenuConfiguration(
            rootPage: ContextMenuPage(
                items: [.submenu(submenu)] + self.actions(count: rootActionCount)
            ),
            backdrop: .none,
            style: ContextMenuStyle(minWidth: 220, maxWidth: 220)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let overlayView = ContextMenuOverlayView(
            configuration: configuration,
            sourceRectInWindow: sourceRect,
            appearanceSourceView: nil,
            portalSourceView: nil,
            portalMaskRectInWindow: nil,
            portalMask: nil,
            portalShowsBackdropCutout: false,
            portalAppliesRightToLeftTransformCorrection: false,
            sourceUserInterfaceStyle: .light,
            sourceUserInterfaceLayoutDirection: .leftToRight
        )
        overlayView.frame = window.bounds
        window.addSubview(overlayView)
        overlayView.setNeedsLayout()
        overlayView.layoutIfNeeded()

        let navigationView = try #require(
            overlayView.subviews.first { $0 is ContextMenuNavigationView } as? ContextMenuNavigationView
        )
        let rootPageView = try #require(
            self.firstSubview(of: ContextMenuPageView.self, in: navigationView)
        )
        return Fixture(
            window: window,
            overlayView: overlayView,
            navigationView: navigationView,
            rootPageView: rootPageView,
            submenuPage: submenuPage
        )
    }

    private func actions(count: Int) -> [ContextMenuItem] {
        (0..<count).map { index in
            .action(ContextMenuAction(title: "Action \(index)"))
        }
    }

    private func firstSubview<T: UIView>(
        of type: T.Type,
        in view: UIView
    ) -> T? {
        for subview in view.subviews {
            if let match = subview as? T {
                return match
            }
            if let match = self.firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private struct Fixture {
        let window: UIWindow
        let overlayView: ContextMenuOverlayView
        let navigationView: ContextMenuNavigationView
        let rootPageView: ContextMenuPageView
        let submenuPage: ContextMenuPage
    }
}
