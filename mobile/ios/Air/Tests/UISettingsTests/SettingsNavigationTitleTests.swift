import Dependencies
import IssueReportingTestSupport
import UIKit
import UIComponents
import WalletCore
import WalletResources
import XCTest
@testable import UISettings

@MainActor
final class SettingsNavigationTitleTests: XCTestCase {
    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
    }

    func testTitleWidthSurvivesAppearanceTransitionsWithoutScrolling() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let settings = SettingsVC()
        let navigation = WNavigationController(rootViewController: settings)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            WalletCoreData.remove(observer: settings)
        }
        try await waitForNavigation(navigation, on: settings)
        window.layoutIfNeeded()
        let collection = try XCTUnwrap(settings.view.subviews.compactMap { $0 as? UICollectionView }.first)
        let header = try XCTUnwrap(settings.view.subviews.compactMap { $0 as? SettingsHeaderView }.first)
        let title = try XCTUnwrap(findTitleLabel(in: header))
        collection.contentInset.bottom += 500

        for scrollOffset: CGFloat in [0, 80, 200] {
            collection.contentOffset.y = scrollOffset - collection.adjustedContentInset.top
            settings.scrollViewDidScroll(collection)
            window.layoutIfNeeded()
            let expectedWidth = title.bounds.width
            XCTAssertGreaterThan(expectedWidth, 100)

            let appearance = AppearanceSettingsVC()
            navigation.pushViewController(appearance, animated: true)
            try await waitForNavigation(navigation, on: appearance) {
                XCTAssertEqual(title.bounds.width, expectedWidth, accuracy: 0.5,
                               "Pushing Appearance must preserve the title width throughout the transition")
            }
            navigation.popViewController(animated: true)
            try await waitForNavigation(navigation, on: settings) {
                XCTAssertEqual(title.bounds.width, expectedWidth, accuracy: 0.5,
                               "Popping Appearance must preserve the title width throughout the transition")
            }

            XCTAssertEqual(title.bounds.width, expectedWidth, accuracy: 0.5,
                           "Returning from Appearance must restore the title width before another scroll")

            let transition = try XCTUnwrap(navigation.beginInteractivePush(AppearanceSettingsVC()))
            try await Task.sleep(for: .milliseconds(100))
            transition.update(0.4)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(title.bounds.width, expectedWidth, accuracy: 0.5)
            transition.cancel()
            try await waitForNavigation(navigation, on: settings) {
                XCTAssertEqual(title.bounds.width, expectedWidth, accuracy: 0.5,
                               "Cancelling navigation must preserve the title width")
            }
        }

        collection.contentOffset.y = header.layoutGeometry.fullScrollRange - collection.adjustedContentInset.top
        settings.scrollViewDidScroll(collection)
        let expectedWidth = title.bounds.width
        let titleView = try XCTUnwrap(settings.navigationItem.titleView)
        let expectedSize = titleView.bounds.size
        settings.beginAppearanceTransition(false, animated: true)
        settings.endAppearanceTransition()

        // A navigation transition can restore the title view's position without changing its size
        titleView.transform = CGAffineTransform(translationX: window.bounds.width, y: 0)
        settings.beginAppearanceTransition(true, animated: true)
        XCTAssertEqual(title.bounds.width, expectedWidth, accuracy: 0.5,
                       "A temporary navigation position must not shrink the title during its appearance")
        titleView.transform = .identity
        settings.endAppearanceTransition()

        XCTAssertEqual(titleView.bounds.size, expectedSize)
        XCTAssertEqual(title.bounds.width, expectedWidth, accuracy: 0.5,
                       "The settled navigation position must replace the transition's temporary title width")
    }

    private func waitForNavigation(
        _ navigation: UINavigationController,
        on controller: UIViewController,
        checkTransition: (() -> Void)? = nil
    ) async throws {
        try await Task.sleep(for: .milliseconds(50))
        for _ in 0..<200 {
            checkTransition?()
            if navigation.topViewController === controller, navigation.transitionCoordinator == nil,
               controller.viewIfLoaded?.window != nil { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Navigation did not finish")
    }

    private func findTitleLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.lineBreakMode == .byTruncatingMiddle {
            return label
        }
        for subview in view.subviews {
            if let label = findTitleLabel(in: subview) { return label }
        }
        return nil
    }
}
