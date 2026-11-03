import SwiftUI
import Dependencies
import XCTest
import UIKit
import UIPasscode
@testable import UIAssets
@testable import UIProtectedAction
import WalletCore
import WalletResources

@MainActor
final class RenewDomainConfirmationLayoutTests: XCTestCase {
    func testSmallRenewalSheetsFitTheConfirmationHeaderAndKeypad() async throws {
        try await withDependencies { $0.context = .live } operation: {
            for domainCount in [1, 2] {
                for contentSize in [UIContentSizeCategory.large, .extraExtraExtraLarge] {
                    try await checkLayout(domainCount: domainCount, textSize: contentSize)
                }
            }
        }
    }

    private func checkLayout(domainCount: Int, textSize: UIContentSizeCategory) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(wereAnimationsEnabled) }
        let account = MAccount(id: "renewal-sheet-mainnet", title: "Wallet", type: .mnemonic, byChain: [:])
        let nfts = try (0..<domainCount).map {
            try JSONDecoder().decode(ApiNft.self, from: Data(
                #"{"name":"example\#($0).ton","address":"domain\#($0)","isOnSale":false}"#.utf8
            ))
        }
        let renewal = RenewDomainVC(accountSource: .constant(account), nftsToRenew: nfts.map(\.address))
        let contentSize = renewal.preferredContentSize
        let navigationBarHeight: CGFloat = 54
        let sheetSize = CGSize(width: contentSize.width, height: contentSize.height + navigationBarHeight)
        let header = RenewDomainAuthHeader(snapshot: .init(account: account, nfts: nfts, realFee: 20_000_000))
        let full = PasswordPresenter.makeHeaderController(rootView: header)
        let compact = PasswordPresenter.makeHeaderController(rootView: header.compactRepresentation
            .padding(.horizontal, 16).padding(.vertical, 16).frame(maxWidth: .infinity))
        let confirmation = UnlockVC(
            title: "Confirm Renewing", customHeaderVC: full, compactHeaderVC: compact,
            prefersNavigationTitleWithCustomHeader: true, dissmissWhenAuthorized: false,
            onDone: { _ in XCTFail("Must not authorize") }, cancellable: true,
            useBioOnPresent: false, biometricPassAllowed: false
        )
        // A floating iPad sheet adds navigation chrome to the root's requested content size.
        let window = UIWindow(frame: CGRect(origin: .zero, size: sheetSize))
        window.traitOverrides.preferredContentSizeCategory = textSize
        window.rootViewController = confirmation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        confirmation.beginAppearanceTransition(true, animated: false)
        confirmation.endAppearanceTransition()
        await settle(confirmation)
        for _ in 0..<3 {
            confirmation.additionalSafeAreaInsets.top += navigationBarHeight - confirmation.view.safeAreaInsets.top
            confirmation.additionalSafeAreaInsets.bottom -= confirmation.view.safeAreaInsets.bottom
            await settle(confirmation)
        }
        XCTAssertEqual(confirmation.view.safeAreaInsets.top, navigationBarHeight)
        XCTAssertEqual(confirmation.view.safeAreaInsets.bottom, 0)
        let activeHeader = full.view.isHidden ? compact : full
        let passcode = try XCTUnwrap(confirmation.passcodeScreenView)
        let headerHeight = activeHeader.view.systemLayoutSizeFitting(
            CGSize(width: sheetSize.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        XCTAssertGreaterThanOrEqual(activeHeader.view.bounds.height, headerHeight - 1)
        XCTAssertEqual(activeHeader.view.frame.maxY, passcode.frame.minY, accuracy: 1)
        let keys = descendants(of: passcode).filter { $0.accessibilityIdentifier?.hasPrefix("passcode_key_") == true }
        XCTAssertEqual(keys.count, 12)
        for key in keys {
            let frame = key.convert(key.bounds, to: confirmation.view)
            XCTAssertGreaterThanOrEqual(frame.height, 54)
            XCTAssertGreaterThanOrEqual(frame.minY, passcode.frame.minY)
            XCTAssertLessThanOrEqual(frame.maxY, confirmation.view.safeAreaLayoutGuide.layoutFrame.maxY + 1)
        }
        let title = try XCTUnwrap(descendants(of: passcode).first { $0.accessibilityIdentifier == "passcode_title" } as? UILabel)
        XCTAssertGreaterThanOrEqual(title.bounds.height, title.intrinsicContentSize.height - 1)
        XCTAssertGreaterThanOrEqual(title.convert(title.bounds, to: confirmation.view).minY, passcode.frame.minY + 7)
    }

    private func settle(_ controller: UIViewController) async {
        for _ in 0..<5 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
