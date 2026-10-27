import SwiftUI
import XCTest
import UIComponents
import UIPasscode
import WalletCore
import WalletResources
@testable import UIDapp
@testable import UIProtectedAction

@MainActor
final class DappConfirmationLayoutTests: XCTestCase {
    func testHeaderMeasurementExcludesContainerSafeArea() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let header = PasswordPresenter.makeHeaderController(rootView: makeUnknownTransferHeader())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = header
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        // During presentation, the hosting controller can inherit navigation
        // insets before UnlockVC positions it below the navigation bar.
        for topInset: CGFloat in [0, 70, 0] {
            header.additionalSafeAreaInsets.top = topInset
            await settleLayout(window)
            let height = header.view.systemLayoutSizeFitting(
                CGSize(width: 393, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            XCTAssertEqual(height, 238, accuracy: 1)
        }
    }

    func testFullHeaderFitsOn14ProAndCompactsOnlyWhenNecessary() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let header = makeUnknownTransferHeader()
        let full = PasswordPresenter.makeHeaderController(rootView: header)
        let compact = PasswordPresenter.makeHeaderController(rootView: header.compactRepresentation
            .padding(.horizontal, 16).padding(.vertical, 16).frame(maxWidth: .infinity))
        let unlock = UnlockVC(
            title: "Confirm", customHeaderVC: full, compactHeaderVC: compact,
            prefersNavigationTitleWithCustomHeader: true, dissmissWhenAuthorized: false,
            onDone: { _ in XCTFail("Layout inspection must not authorize a transaction") },
            cancellable: true, biometricPassAllowed: false
        )
        let navigation = WNavigationController(rootViewController: unlock)
        // SwiftPM tests have no application scene. Mount the sheet's content at the
        // iPhone 14 Pro's actual large-sheet size, including its safe-area insets.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 793))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = navigation
        navigation.view.frame = window.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        navigation.beginAppearanceTransition(true, animated: false)
        navigation.endAppearanceTransition()
        await settleLayout(window)
        navigation.additionalSafeAreaInsets.top = 70 - unlock.view.safeAreaInsets.top
        navigation.additionalSafeAreaInsets.bottom = 34 - unlock.view.safeAreaInsets.bottom
        await settleLayout(window)
        XCTAssertEqual(unlock.view.bounds.width, 393)
        XCTAssertEqual(unlock.view.bounds.height, 793)
        XCTAssertEqual(unlock.view.safeAreaInsets.top, 70)
        XCTAssertEqual(unlock.view.safeAreaInsets.bottom, 34)

        XCTAssertFalse(full.view.isHidden, "Use the full header when the keypad fits")
        XCTAssertTrue(compact.view.isHidden)
        XCTAssertEqual(full.view.bounds.height, 238, accuracy: 1, "Do not count the navigation safe area twice")
        assertContentFits(unlock, activeHeader: full)

        // Exercise the fallback and the return to full size on the same controller.
        unlock.additionalSafeAreaInsets.top = 150
        await settleLayout(window)
        XCTAssertTrue(full.view.isHidden, "Retain compact mode when the full header cannot fit")
        XCTAssertFalse(compact.view.isHidden)
        assertContentFits(unlock, activeHeader: compact)

        unlock.additionalSafeAreaInsets.top = 0
        await settleLayout(window)
        XCTAssertFalse(full.view.isHidden, "Restore the full header after space becomes available")
        assertContentFits(unlock, activeHeader: full)
    }

    private func settleLayout(_ window: UIWindow) async {
        for _ in 0..<3 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func assertContentFits(_ unlock: UnlockVC, activeHeader: UIViewController) {
        let passcode = unlock.passcodeScreenView!
        XCTAssertGreaterThan(activeHeader.view.bounds.height, 0)
        XCTAssertGreaterThanOrEqual(activeHeader.view.frame.minY, unlock.view.safeAreaInsets.top - 1)
        XCTAssertEqual(activeHeader.view.frame.maxY, passcode.frame.minY, accuracy: 1)
        let keys = descendants(of: passcode).filter { $0.accessibilityIdentifier?.hasPrefix("passcode_key_") == true }
        XCTAssertEqual(keys.count, 12)
        for key in keys {
            let frame = key.convert(key.bounds, to: unlock.view)
            XCTAssertGreaterThanOrEqual(frame.height, 54)
            XCTAssertGreaterThanOrEqual(frame.minY, passcode.frame.minY)
            XCTAssertLessThanOrEqual(frame.maxY, unlock.view.safeAreaLayoutGuide.layoutFrame.maxY)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, unlock.view.bounds.width)
        }
        if let title = descendants(of: passcode).first(where: { $0.accessibilityIdentifier == "passcode_title" }) as? UILabel {
            XCTAssertGreaterThanOrEqual(title.bounds.height, title.intrinsicContentSize.height - 1)
            XCTAssertEqual(title.convert(title.bounds, to: passcode).minY, 32, accuracy: 1,
                           "Preserve the design's padding above Enter code")
        } else {
            XCTFail("Passcode title is missing")
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func makeUnknownTransferHeader() -> DappConfirmationHeaderView {
        let dapp = ApiDapp(url: "https://dedust.io", name: "DeDust", connectedAt: nil, urlTrustStatus: .verified, sse: nil)
        let transaction = ApiDappTransfer(toAddress: "contract", amount: 1_250_000_000,
            isDangerous: true, normalizedAddress: "contract", displayedToAddress: "contract", networkFee: 15_000_000)
        return DappConfirmationHeaderView(dapp: dapp, action: .send(.init(
            promiseId: "layout-test", accountId: "layout-test", dapp: dapp, operationChain: .ton,
            transactions: [transaction], emulation: nil, shouldHideTransfers: false
        )))
    }
}
