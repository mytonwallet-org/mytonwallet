import XCTest
import UIKit
@testable import UIHome

@MainActor
final class HomeCardEdgeGradientAnimatorTests: XCTestCase {
    func testDisablingMotionRestoresStaticGradientEvenDuringReturnAnimation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true }
        let leading = UIView(frame: CGRect(x: 0, y: 100, width: 24, height: 232))
        let trailing = UIView(frame: CGRect(x: 378, y: 100, width: 24, height: 232))
        window.rootViewController?.view.addSubview(leading)
        window.rootViewController?.view.addSubview(trailing)
        let animator = HomeCardEdgeGradientAnimator()
        animator.update(leading: leading, trailing: trailing, leadingOffset: -24, trailingOffset: 24, animated: false)
        window.layoutIfNeeded()
        animator.update(leading: leading, trailing: trailing, leadingOffset: 0, trailingOffset: 0, animated: true)
        try await Task.sleep(for: .milliseconds(60))
        // The destination is already zero, but disabling animations must cancel
        // the in-flight return immediately, instead of being ignored as a repeat.
        animator.update(leading: leading, trailing: trailing, leadingOffset: 0, trailingOffset: 0,
                        animated: false, motionEnabled: false)
        for view in [leading, trailing] {
            XCTAssertEqual(view.transform, .identity)
            XCTAssertTrue(view.layer.animationKeys()?.isEmpty ?? true)
        }
        for offset: CGFloat in [24, 0, 32] {
            animator.update(leading: leading, trailing: trailing, leadingOffset: -offset, trailingOffset: offset,
                            animated: true, motionEnabled: false)
            XCTAssertEqual(leading.transform, .identity)
            XCTAssertEqual(trailing.transform, .identity)
        }
        animator.update(leading: leading, trailing: trailing, leadingOffset: -24, trailingOffset: 24,
                        animated: false, motionEnabled: true)
        XCTAssertEqual(leading.transform.tx, -24)
        XCTAssertEqual(trailing.transform.tx, 24)
    }

    func testSwipeTransitionSurvivesLayoutAndReturnsSmoothly() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        let leading = UIView(frame: CGRect(x: 0, y: 100, width: 24, height: 232))
        let trailing = UIView(frame: CGRect(x: 378, y: 100, width: 24, height: 232))
        host.view.addSubview(leading)
        host.view.addSubview(trailing)
        let animator = HomeCardEdgeGradientAnimator()
        animator.update(leading: leading, trailing: trailing, leadingOffset: 0, trailingOffset: 0, animated: false)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        for away in [true, false] {
            let destination: CGFloat = away ? 24 : 0
            animator.update(leading: leading, trailing: trailing, leadingOffset: -destination, trailingOffset: destination, animated: true)
            try await Task.sleep(for: .milliseconds(60))
            let beforeLayout = try XCTUnwrap(trailing.layer.presentation()).transform.m41
            XCTAssertGreaterThan(beforeLayout, 0)
            XCTAssertLessThan(beforeLayout, 24)
            animator.update(leading: leading, trailing: trailing, leadingOffset: -destination, trailingOffset: destination, animated: false)
            window.layoutIfNeeded()
            CATransaction.flush()
            let afterLayout = try XCTUnwrap(trailing.layer.presentation()).transform.m41
            XCTAssertEqual(afterLayout, beforeLayout, accuracy: 1, "Relayout must not jump to the final opacity/position")
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(trailing.layer.presentation()?.transform.m41 ?? trailing.transform.tx, destination, accuracy: 0.01)
            XCTAssertEqual(leading.transform.tx, -destination)
        }
    }
}
