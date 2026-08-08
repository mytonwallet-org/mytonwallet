import Testing
import UIKit
@testable import UIComponents

@Suite("Drawer Container")
@MainActor
struct DrawerContainerViewControllerTests {
    @Test
    func `drawer scaling stays centered`() throws {
        let configuration = DrawerContainerConfiguration(
            drawerParallaxFactor: 0,
            drawerMinimumScale: 0.9
        )
        let viewController = DrawerContainerViewController(
            mainViewController: UIViewController(),
            drawerViewController: UIViewController(),
            configuration: configuration
        )
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let drawerPresentationView = try #require(reflectedView(
            named: "drawerPresentationView",
            in: viewController
        ))
        let transform = drawerPresentationView.layer.sublayerTransform

        #expect(abs(transform.m11 - 0.9) < 0.0001)
        #expect(abs(transform.m22 - 0.9) < 0.0001)
        #expect(abs(transform.m41) < 0.0001)
        #expect(abs(transform.m42) < 0.0001)
    }

    private func reflectedView(named name: String, in object: Any) -> UIView? {
        Mirror(reflecting: object).children.first { $0.label == name }?.value as? UIView
    }

    @Test
    func `interrupted close restores main content interaction`() throws {
        let configuration = DrawerContainerConfiguration(
            transitionDuration: 10,
            minimumTransitionDuration: 10
        )
        let viewController = DrawerContainerViewController(
            mainViewController: UIViewController(),
            drawerViewController: UIViewController(),
            configuration: configuration
        )
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let mainContentView = try #require(
            Mirror(reflecting: viewController).children.first {
                $0.label == "mainContentView"
            }?.value as? UIView
        )

        viewController.setDrawerOpen(true, animated: false)
        viewController.setDrawerOpen(false, animated: true)
        #expect(!mainContentView.isUserInteractionEnabled)

        viewController.applyConfiguration(configuration)

        #expect(mainContentView.isUserInteractionEnabled)
    }
}
