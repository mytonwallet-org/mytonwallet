import UIKit
import XCTest
@testable import WalletContext

@MainActor
final class SensitiveDataTraversalTests: XCTestCase {
    func testNestedControllerViewsAreRefreshedOnceAndUnloadedScreensStayUnloaded() {
        let root = SensitiveController()
        let child = SensitiveController()
        let grandchild = SensitiveController()
        let unloaded = SensitiveController()
        let detached = SensitiveController()
        let mask = SensitiveView()

        root.loadViewIfNeeded()
        child.loadViewIfNeeded()
        grandchild.loadViewIfNeeded()
        detached.loadViewIfNeeded()
        root.addChild(child)
        root.view.addSubview(child.view)
        child.didMove(toParent: root)
        child.addChild(grandchild)
        child.view.addSubview(grandchild.view)
        grandchild.didMove(toParent: child)
        grandchild.view.addSubview(mask)
        root.addChild(unloaded)
        unloaded.didMove(toParent: root)
        root.addChild(detached)
        detached.didMove(toParent: root)

        for count in 1...2 {
            WWindow.updateSensitiveData(in: root)
            for controller in [root, child, grandchild, detached] {
                XCTAssertEqual(controller.updates, count)
                XCTAssertEqual((controller.view as? SensitiveView)?.updates, count)
            }
            XCTAssertEqual(mask.updates, count)
            XCTAssertEqual(unloaded.updates, 0)
            XCTAssertFalse(unloaded.isViewLoaded)
        }
    }
}

@MainActor
private final class SensitiveController: UIViewController, WSensitiveDataProtocol {
    var updates = 0
    override func loadView() { view = SensitiveView() }
    func updateSensitiveData() { updates += 1 }
}

@MainActor
private final class SensitiveView: UIView, WSensitiveDataProtocol {
    var updates = 0
    func updateSensitiveData() { updates += 1 }
}
