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

    /// The top has its rim, the widest ring, 0.68 from the axis, and its cap 1.48 above the point; leaning and
    /// seen from the camera's elevation, it stays inside its box whichever way the lean goes
    @MainActor
    func testGeometryIsShapeG2AndStaysInItsBox() {
        let geometry = SpinningTopGeometry.shared
        let radii = geometry.vertices.map { simd_length(SIMD2($0.position.x, $0.position.z)) }
        let heights = geometry.vertices.map(\.position.y)
        XCTAssertEqual(radii.max() ?? 0, 0.679, accuracy: 0.003, "The rim")
        XCTAssertEqual(heights.max() ?? 0, 1.4797, accuracy: 0.001, "The cap")
        XCTAssertEqual(heights.min() ?? 1, 0, accuracy: 0.001, "The point")

        let halfExtent = SpinningTopGeometry.boxHalfExtent
        for step in 0..<24 {
            let direction = Float(step) / 24 * 2 * .pi
            let rotation = SpinningTopRenderer.transform(
                yaw: 0, pitch: SpinningTopGeometry.viewPitch, lean: SpinningTopGeometry.lean, leanDirection: direction
            )
            for vertex in geometry.vertices {
                let shown = rotation * SIMD4(vertex.position, 1)
                let inBox = SIMD2(shown.x, shown.y) + SpinningTopGeometry.restingOffset
                XCTAssertLessThanOrEqual(abs(inBox.x), halfExtent + 0.001, "In the box leaning toward \(direction)")
                XCTAssertLessThanOrEqual(abs(inBox.y), halfExtent + 0.001, "In the box leaning toward \(direction)")
            }
        }
    }

    /// At its most lean, its own, thinking's and a knock's together, the resting top stays inside its canvas,
    /// which reaches a tenth of its side past each edge of its box
    @MainActor
    func testMostLeanedTopStaysInsideItsCanvas() {
        let geometry = SpinningTopGeometry.shared
        let canvasHalfExtent = SpinningTopGeometry.boxHalfExtent * 1.2
        for step in 0..<24 {
            let direction = Float(step) / 24 * 2 * .pi
            let rotation = SpinningTopRenderer.transform(
                yaw: 0, pitch: SpinningTopGeometry.viewPitch, lean: 0.6, leanDirection: direction
            )
            for vertex in geometry.vertices {
                let shown = rotation * SIMD4(vertex.position, 1)
                let inCanvas = SIMD2(shown.x, shown.y) + SpinningTopGeometry.restingOffset
                XCTAssertLessThanOrEqual(abs(inCanvas.x), canvasHalfExtent, "Leaning toward \(direction)")
                XCTAssertLessThanOrEqual(abs(inCanvas.y), canvasHalfExtent, "Leaning toward \(direction)")
            }
        }
    }

    /// The flat mark is the top's silhouette in the 48 pt design box, its point where the 3D top's is
    @MainActor
    func testFlatMarkIsTheG2Silhouette() {
        let bounds = AgentSpinningTopIcon.makeSilhouette().cgPath.boundingBoxOfPath
        XCTAssertEqual(bounds.minX, 5.62, accuracy: 0.05)
        XCTAssertEqual(bounds.maxX, 40.45, accuracy: 0.05)
        XCTAssertEqual(bounds.minY, 5.40, accuracy: 0.05)
        XCTAssertEqual(bounds.maxY, 42.93, accuracy: 0.05, "The point")
        XCTAssertLessThanOrEqual(bounds.maxX, AgentSpinningTopIcon.designSize)
        XCTAssertLessThanOrEqual(bounds.maxY, AgentSpinningTopIcon.designSize)
    }

    /// Thinking spins the top up to about seven times its speed over about 0.6 s, the answer's end eases it back over
    /// about 0.9 s, and a failure knocks it over by about 0.3 rad, costing it spin, with a 3.2 Hz wobble that settles
    /// within about 2 s
    func testAgentStateDrivesTheSpinAsSpecified() {
        var motion = SpinningTopStateMotion()
        let frame: Float = 1 / 60
        func run(_ seconds: Float, _ sample: (SpinningTopStateMotion) -> Void = { _ in }) {
            for _ in 0..<Int(seconds * 60) {
                motion.step(dt: frame, isReduceMotionEnabled: false)
                sample(motion)
            }
        }
        XCTAssertEqual(motion.getSpinMultiple(tapBoost: 0), 1, "Its own speed")

        motion.isThinking = true
        run(0.6)
        XCTAssertEqual(motion.boost, 6 * (1 - exp(-1)), accuracy: 0.2, "Most of the way up after 0.6 s")
        run(3)
        XCTAssertEqual(motion.getSpinMultiple(tapBoost: 0), 7, accuracy: 0.1, "About seven times its speed")
        XCTAssertEqual(motion.thinking, 1, accuracy: 0.02)

        motion.isThinking = false
        let before = motion.boost
        run(0.9)
        XCTAssertEqual(motion.boost, before * exp(-1), accuracy: 0.2, "Easing back over about 0.9 s")
        run(6)
        XCTAssertLessThan(motion.boost, 0.05, "Back to its own speed")

        motion.knock()
        XCTAssertEqual(motion.getSpinMultiple(tapBoost: 0), 0.45, accuracy: 0.01, "The knock costs spin")
        var tilts: [Float] = []
        var wobbles: [Float] = []
        run(2.5) { tilts.append($0.knockTerms.tilt); wobbles.append($0.knockTerms.wobble) }
        // The knock's tilt with the wobble's share of the lean, over the regular lean
        let leans = zip(tilts, wobbles).map { 0.3 * $0 + 0.05 * $1 }
        XCTAssertEqual(leans.max() ?? 0, 0.27, accuracy: 0.05, "About 0.3 rad over the lean")
        let firstSecond = wobbles.prefix(60)
        let crossings = zip(firstSecond, firstSecond.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        XCTAssertEqual(Float(crossings) / 2, 3.2, accuracy: 0.6, "A 3.2 Hz wobble")
        XCTAssertLessThan(tilts[119], 0.05, "Settled after 2 s")
        XCTAssertLessThan(abs(wobbles[119]), 0.06)
        XCTAssertGreaterThan(motion.getSpinMultiple(tapBoost: 0), 0.95, "Its spin back")
    }

    /// With Reduce Motion the top keeps its own spin: thinking doesn't spin it up and a failure doesn't knock it
    func testReduceMotionKeepsTheTopsOwnSpin() {
        var motion = SpinningTopStateMotion()
        motion.isThinking = true
        motion.knock()
        for _ in 0..<60 { motion.step(dt: 1 / 60, isReduceMotionEnabled: true) }
        XCTAssertEqual(motion.boost, 0)
        XCTAssertEqual(motion.knockTerms.tilt, 0)
        XCTAssertEqual(motion.knockTerms.wobble, 0)
        XCTAssertEqual(motion.getSpinMultiple(tapBoost: 0), 1)
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

    /// The resting canvas is 76.8 points wide and takes a whole number of pixels, so `contentScaleFactor` reads back a
    /// scale derived from the drawable's size rather than the screen's scale
    @MainActor
    func testOnlyAFrameThatResizesTheCanvasPresentsWithItsTransaction() throws {
        let (top, window) = makeVisibleTop()
        defer {
            top.isActive = false
            window.isHidden = true
        }
        let metal = try XCTUnwrap(top.subviews.compactMap { $0 as? MTKView }.first)
        let metalLayer = try XCTUnwrap(metal.layer as? CAMetalLayer)
        let log = TransactionPresentLog()
        let observation = metalLayer.observe(\.presentsWithTransaction, options: [.new]) { _, change in
            guard let isSynchronous = change.newValue else { return }
            MainActor.assumeIsolated { log.values.append(isSynchronous) }
        }
        defer { observation.invalidate() }
        for _ in 0..<5 { metal.draw() }
        XCTAssertEqual(log.values, [], "Frames of a top at rest")
        top.perform(NSSelectorFromString("handlePress:"), with: TestPress(state: .began))
        for _ in 0..<5 { metal.draw() }
        // The flag goes back once a frame has presented synchronously: the growth's own, or the first held frame the
        // GPU has room for
        XCTAssertEqual(log.values, [true, false], "One synchronous present for the growth, none for the held top")
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

private final class TransactionPresentLog {
    var values: [Bool] = []
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
