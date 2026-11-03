import XCTest
import MetalKit
import UIKit
@testable import UIComponents
import WalletResources

final class AgentSpinningTopViewTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    @MainActor
    func testFirstHoldExpandsItsCanvasBeforeDrawingAboveTheOwner() throws {
        let (top, window) = makeVisibleTop()
        defer {
            top.isActive = false
            window.isHidden = true
        }
        let metal = try XCTUnwrap(top.subviews.compactMap { $0 as? MTKView }.first)
        let restingSize = metal.drawableSize
        XCTAssertTrue(restingSize.width.isFinite && restingSize.height.isFinite,
                      "Resting drawable must be finite: bounds=\(metal.bounds), contentScale=\(metal.contentScaleFactor), screenScale=\(window.screen.scale)")
        XCTAssertGreaterThan(restingSize.width, 0)
        XCTAssertGreaterThan(restingSize.height, 0)
        let restingBounds = metal.bounds.size
        top.perform(NSSelectorFromString("handlePress:"), with: TestPress(state: .began))
        XCTAssertTrue(metal.superview === window)
        XCTAssertGreaterThan(metal.drawableSize.width, restingSize.width)
        XCTAssertGreaterThan(metal.drawableSize.height, restingSize.height)
        XCTAssertGreaterThan(metal.bounds.width, restingBounds.width)
        XCTAssertGreaterThan(metal.bounds.height, restingBounds.height)
        let heldSize = metal.drawableSize
        top.layoutIfNeeded()
        metal.draw()
        XCTAssertEqual(metal.drawableSize, heldSize)
    }

    @MainActor
    func testDefaultExpansionKeepsTheOriginalSizeAndConsentCanRequestASmallerTop() throws {
        var heldSizes: [CGSize] = []
        for scale in [CGFloat?.none, 2] {
            let (top, window) = makeVisibleTop(expandedScale: scale)
            defer {
                top.isActive = false
                window.isHidden = true
            }
            top.frame.size = CGSize(width: 96, height: 96)
            top.layoutIfNeeded()
            let metal = try XCTUnwrap(top.subviews.compactMap { $0 as? MTKView }.first)
            top.perform(NSSelectorFromString("handlePress:"), with: TestPress(state: .began))
            heldSizes.append(metal.bounds.size)
        }
        XCTAssertEqual(heldSizes[0].width / heldSizes[1].width, 1.5, accuracy: 0.01)
        XCTAssertEqual(heldSizes[0].height / heldSizes[1].height, 1.5, accuracy: 0.01)
    }

    @MainActor
    func testDeactivationShrinksTheLiftedTopAwayThenReturnsIt() throws {
        let (top, window) = makeVisibleTop()
        defer { window.isHidden = true }
        let metal = try XCTUnwrap(top.subviews.compactMap { $0 as? MTKView }.first)
        top.perform(NSSelectorFromString("handlePress:"), with: TestPress(state: .began))
        XCTAssertTrue(metal.superview === window)

        top.isActive = false

        XCTAssertTrue(top.gestureRecognizers?.allSatisfy { !$0.isEnabled } == true)
        waitForReturn(of: metal, to: top)
        XCTAssertFalse(window.subviews.contains { $0 === metal })
        XCTAssertEqual(metal.transform, .identity)
        XCTAssertEqual(metal.alpha, 1)
        XCTAssertTrue(metal.isPaused)
    }

    @MainActor
    func testRemovingTheOwnerDoesNotLeaveItsLiftedCanvasInTheWindow() throws {
        let (top, window) = makeVisibleTop()
        defer { window.isHidden = true }
        let metal = try XCTUnwrap(top.subviews.compactMap { $0 as? MTKView }.first)
        top.perform(NSSelectorFromString("handlePress:"), with: TestPress(state: .began))
        XCTAssertTrue(metal.superview === window)

        top.removeFromSuperview()

        waitForReturn(of: metal, to: top)
        XCTAssertNil(metal.window)
        XCTAssertFalse(window.subviews.contains { $0 === metal })
        XCTAssertTrue(metal.isPaused)
    }

    /// The lifted canvas shrinks away over 0.28 s before it returns to its owner
    @MainActor
    private func waitForReturn(of metal: UIView, to top: UIView) {
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in metal.superview === top },
            object: nil
        )
        wait(for: [returned], timeout: 2)
    }

    @MainActor
    private func makeVisibleTop(expandedScale: CGFloat? = nil) -> (AgentSpinningTopView, UIWindow) {
        let controller = UIViewController()
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow()
        }
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let top = expandedScale.map { AgentSpinningTopView(expandedScale: $0) } ?? AgentSpinningTopView()
        top.frame = CGRect(x: 169, y: 180, width: 64, height: 64)
        controller.view.addSubview(top)
        window.layoutIfNeeded()
        top.layoutIfNeeded()
        return (top, window)
    }
}

private final class TestPress: UILongPressGestureRecognizer {
    private let reportedState: UIGestureRecognizer.State

    init(state: UIGestureRecognizer.State) {
        reportedState = state
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { reportedState }
        set { }
    }

    override func location(in view: UIView?) -> CGPoint {
        CGPoint(x: 32, y: 32)
    }
}
