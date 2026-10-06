import CoreText
import XCTest
import UIKit
import WalletResources
@testable import UICreateWallet

@MainActor
final class ImportWalletNavigationTests: XCTestCase {
    func testEmbeddingInstallsStickyNavigationWithoutAnAppearanceTransition() throws {
        let (host, navigation, screen) = makeEmbeddedImport()

        let proxy = try XCTUnwrap(screen.navigationItem.titleView)
        XCTAssertTrue(host.navigationItem.titleView === proxy)
        XCTAssertTrue(navigation.navigationBar.topItem === host.navigationItem)
        let appearances: [KeyPath<UINavigationItem, UINavigationBarAppearance?>] = [
            \.standardAppearance, \.scrollEdgeAppearance, \.compactAppearance, \.compactScrollEdgeAppearance,
        ]
        for keyPath in appearances {
            let expected = try XCTUnwrap(screen.navigationItem[keyPath: keyPath])
            let actual = try XCTUnwrap(host.navigationItem[keyPath: keyPath])
            XCTAssertEqual(actual.backgroundColor, expected.backgroundColor)
            XCTAssertEqual(actual.backgroundImage, expected.backgroundImage)
            XCTAssertNil(actual.backgroundEffect)
        }
    }

    func testPushedStepUsesItsOwnNavigationItemAndPopRestoresImport() throws {
        let (host, navigation, screen) = makeEmbeddedImport()
        let proxy = try XCTUnwrap(screen.navigationItem.titleView)
        let nextStep = UIViewController()
        let nextTitle = UIView()
        let nextAppearance = UINavigationBarAppearance()
        nextAppearance.configureWithOpaqueBackground()
        nextAppearance.backgroundColor = .red
        nextStep.navigationItem.titleView = nextTitle
        nextStep.navigationItem.standardAppearance = nextAppearance

        navigation.pushViewController(nextStep, animated: false)

        XCTAssertTrue(navigation.navigationBar.topItem === nextStep.navigationItem)
        XCTAssertTrue(nextStep.navigationItem.titleView === nextTitle)
        XCTAssertEqual(nextStep.navigationItem.standardAppearance?.backgroundColor, .red)

        navigation.popViewController(animated: false)

        XCTAssertTrue(navigation.navigationBar.topItem === host.navigationItem)
        XCTAssertTrue(host.navigationItem.titleView === proxy)
    }

    private func makeEmbeddedImport() -> (UIViewController, UINavigationController, ImportWalletVC) {
        _ = WalletResourcesBundle.bundle.load()
        if let url = WalletResourcesBundle.bundle.url(forResource: "CalSans-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let host = UIViewController()
        host.navigationItem.titleView = UIView()
        let navigation = UINavigationController(rootViewController: host)
        navigation.loadViewIfNeeded()
        let screen = ImportWalletVC(introModel: IntroModel(network: .mainnet, authMode: .requiresPasscodeSetup))

        // Match the sheet's replacement path: load, then embed, without forwarding appearance callbacks.
        screen.loadViewIfNeeded()
        host.addChild(screen)
        host.view.addSubview(screen.view)
        screen.didMove(toParent: host)
        return (host, navigation, screen)
    }
}
