import Dependencies
import UIKit
import UIComponents
import WalletCore
import WalletResources
import XCTest
@testable import UIBrowser

@MainActor
final class ExploreCategoryTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
        } operation: {
            super.invokeTest()
        }
    }

    func testListFillsTheScreenAndScrollsToTheAutomaticTopInset() throws {
        let controller = try makeController()
        let navigation = WNavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        navigation.view.layoutIfNeeded()
        controller.view.layoutIfNeeded()

        let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
        XCTAssertEqual(collection.frame, controller.view.bounds)
        XCTAssertTrue(controller.contentScrollView(for: .top) === collection)
        XCTAssertEqual(collection.contentInset, .zero)
        XCTAssertGreaterThan(collection.adjustedContentInset.top, 0)
        XCTAssertEqual(collection.contentOffset.y, -collection.adjustedContentInset.top, accuracy: 0.5)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 12)

        collection.setContentOffset(CGPoint(x: 0, y: 180), animated: false)
        controller.scrollToTop(animated: false)
        XCTAssertEqual(collection.contentOffset.y, -collection.adjustedContentInset.top, accuracy: 0.5)

        controller.additionalSafeAreaInsets.top = 24
        navigation.view.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        collection.setContentOffset(CGPoint(x: 0, y: 180), animated: false)
        controller.scrollToTop(animated: false)
        XCTAssertEqual(collection.frame, controller.view.bounds)
        XCTAssertEqual(collection.contentOffset.y, -collection.adjustedContentInset.top, accuracy: 0.5)
    }

    func testDraggingCanCancelAnOpenButtonPress() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()
        let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
        let button = UIButton(type: .system)
        XCTAssertTrue(collection.canCancelContentTouches)
        XCTAssertTrue(collection.touchesShouldCancel(in: button))
        XCTAssertFalse(collection.touchesShouldCancel(in: UISwitch()))
    }

    func testReconfiguredAndReusedCellsDoNotOpenThePreviousSite() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = ExploreCategoryCell(frame: CGRect(x: 0, y: 0, width: 390, height: 114))
        let button = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? UIButton }.first)
        let action = try XCTUnwrap(button.actions(forTarget: cell, forControlEvent: .touchUpInside)?.first)
        let site = try makeSites().sites[0]
        var opened: [String] = []
        cell.configure(site: site) { opened.append("first") }
        cell.configure(site: site) { opened.append("second") }
        cell.perform(NSSelectorFromString(action))
        XCTAssertEqual(opened, ["second"])
        cell.prepareForReuse()
        cell.perform(NSSelectorFromString(action))
        XCTAssertEqual(opened, ["second"])
    }

    private func makeController() throws -> ExploreCategoryVC {
        _ = WalletResourcesBundle.bundle.load()
        let sites = try makeSites()
        let model = ExploreVM(fetchSites: { sites }, fetchDapps: { _ in [] }, accountId: { nil })
        model.reachability.stopNotifier()
        model.updateExploreSites(sites)
        return ExploreCategoryVC(exploreVM: model, categoryId: 1)
    }

    private func makeSites() throws -> ApiExploreSitesResult {
        let sites = (0..<12).map { index in
            ["url": "https://example.com/\(index)", "name": "Site \(index)", "icon": "",
             "description": "Site description", "categoryId": 1, "canBeRestricted": false] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "categories": [["id": 1, "name": "Games"]], "sites": sites,
        ])
        return try JSONDecoder().decode(ApiExploreSitesResult.self, from: data)
    }
}
