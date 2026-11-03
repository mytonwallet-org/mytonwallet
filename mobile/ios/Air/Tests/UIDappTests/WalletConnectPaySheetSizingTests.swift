import Dependencies
import XCTest
import UIKit
import UIComponents
import WalletCore
import WalletResources
@testable import UIDapp

@MainActor
final class WalletConnectPaySheetSizingTests: XCTestCase {
    private final class Confirmation: WViewController {
        override var shouldPreserveSheetSizeOnPush: Bool { true }
    }

    func testPaymentStatusResizesTheSheetAfterReplacingAuthorization() throws {
        try withDependencies {
            $0.context = .live
            $0.accountStore = .shared
        } operation: {
            for isComplete in [false, true] {
                try checkStatusReplacement(isComplete: isComplete)
            }
        }
    }

    private func checkStatusReplacement(isComplete: Bool) throws {
        _ = WalletResourcesBundle.bundle.load()
        let source = WViewController()
        let navigation = WNavigationController(rootViewController: source)
        navigation.preferredContentSize = CGSize(width: 640, height: 650)
        let signingSize = navigation.preferredContentSize
        let authorization = Confirmation()
        authorization.preferredContentSize = CGSize(width: 640, height: 800)
        navigation.pushViewController(authorization, animated: false)
        XCTAssertEqual(navigation.preferredContentSize, signingSize)

        let type = isComplete ? "walletConnectPayPaymentComplete" : "walletConnectPayProcessing"
        let data = Data(#"{"type":"\#(type)","accountId":"0-mainnet","merchant":{"name":"Test Shop"},"operationChain":"ton"}"#.utf8)
        let status: WalletConnectPayPaymentStatusVC
        if isComplete {
            status = WalletConnectPayPaymentStatusVC(
                complete: try JSONDecoder().decode(ApiUpdate.WalletConnectPayPaymentComplete.self, from: data),
                paymentContext: nil, onClose: {}
            )
        } else {
            status = WalletConnectPayPaymentStatusVC(
                processing: try JSONDecoder().decode(ApiUpdate.WalletConnectPayProcessing.self, from: data),
                paymentContext: nil, onClose: {}
            )
        }
        status.prepareForReplacementTransition()
        navigation.setViewControllers([status], animated: false)
        status.animateToContentHeight()
        XCTAssertEqual(navigation.viewControllers, [status])
        XCTAssertEqual(navigation.preferredContentSize.width, 580)
        XCTAssertGreaterThanOrEqual(navigation.preferredContentSize.height, 360)
        XCTAssertLessThan(navigation.preferredContentSize.height, signingSize.height)
    }
}
