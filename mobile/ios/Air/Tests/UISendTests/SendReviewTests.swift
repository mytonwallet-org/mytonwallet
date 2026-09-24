import Dependencies
import ProtectedAction
import XCTest
import UIComponents
import UIKit
@testable import UISend
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class SendReviewTests: XCTestCase {
    func testCancellationRestoresConfirmation() async throws {
        try await checkConfirmation(fails: false)
    }

    func testFailureRestoresConfirmation() async throws {
        try await checkConfirmation(fails: true)
    }

    func testNftCancellationRestoresConfirmation() async throws {
        for mode in [NftSendMode.send, .burn] {
            try await checkConfirmation(fails: false, nftMode: mode)
        }
    }

    func testNftFailureRestoresConfirmation() async throws {
        for mode in [NftSendMode.send, .burn] {
            try await checkConfirmation(fails: true, nftMode: mode)
        }
    }

    private func checkConfirmation(fails: Bool, nftMode: NftSendMode? = nil) async throws {
        _ = WalletResourcesBundle.bundle.load()
        try await withDependencies {
            $0.context = .preview
            $0[_TokenStore.self] = .liveValue
            $0[_BalancesStore.self] = .liveValue
            $0[_AccountStore.self] = .liveValue
            $0[AccountSettingsStore.self] = .liveValue
            $0[SavedAddressesStore.self] = .liveValue
            $0[DomainsStore.self] = .liveValue
            $0[AccountConfigStore.self] = .liveValue
        } operation: {
            try await checkButtons(fails: fails, nftMode: nftMode)
        }
    }

    private func checkButtons(fails: Bool, nftMode: NftSendMode?) async throws {
        let previousExecutor = ProtectedActionExecutor
        ProtectedActionExecutor = SuspendedExecutor.self
        SuspendedExecutor.calls = 0
        SuspendedExecutor.fails = fails
        defer {
            SuspendedExecutor.finish()
            ProtectedActionExecutor = previousExecutor
        }

        let controller: WViewController = if let nftMode {
            makeNftReview(mode: nftMode)
        } else {
            makeReview()
        }
        let navigation = WNavigationController()
        navigation.setViewControllers([UIViewController(), controller], animated: false)
        controller.loadViewIfNeeded()
        let buttons = controller.view.subviews.compactMap { $0 as? WButton }
        let confirm = try XCTUnwrap(buttons.first { [lang("Confirm"), lang("Continue")].contains($0.title(for: .normal) ?? "") })
        let edit = buttons.first { $0.title(for: .normal) == lang("Edit") }

        for attempt in 1...2 {
            try tap(confirm)
            try tap(confirm)
            if let edit { try tap(edit) }

            XCTAssertTrue(confirm.showLoading)
            XCTAssertFalse(confirm.isEnabled)
            if let edit { XCTAssertFalse(edit.isEnabled) }
            XCTAssertTrue(navigation.topViewController === controller)

            for _ in 0..<100 where SuspendedExecutor.continuation == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(SuspendedExecutor.calls, attempt)
            XCTAssertNotNil(SuspendedExecutor.continuation)
            SuspendedExecutor.finish()
            for _ in 0..<100 where confirm.showLoading {
                try await Task.sleep(for: .milliseconds(10))
            }

            XCTAssertFalse(confirm.showLoading)
            XCTAssertTrue(confirm.isEnabled)
            if let edit { XCTAssertTrue(edit.isEnabled) }
        }
    }

    private func tap(_ button: UIButton) throws {
        // These package tests have no UIApplication to dispatch control events.
        let target = try XCTUnwrap(button.allTargets.first as? NSObject)
        let action = try XCTUnwrap(button.actions(forTarget: target, forControlEvent: .touchUpInside)?.first)
        target.perform(NSSelectorFromString(action), with: button)
    }

    private func makeReview() -> TokenSendReviewViewController {
        let account = MAccount(
            id: "send-review-mainnet", title: "Send review", type: .mnemonic,
            byChain: [.ton: .init(address: "sender")]
        )
        let flow = TokenSendFlow(api: .init(
            checkDraft: { _, _ in
                try JSONDecoder().decode(ApiCheckTransactionDraftResult.self, from: Data("{}".utf8))
            },
            submit: { _, _ in throw TestError.unexpectedSubmission }
        ))
        let model = TokenSendModel(
            accountContext: AccountContext(source: .constant(account)),
            configuration: .init(
                mode: .send, initialAddress: nil, initialAmount: nil,
                initialTokenSlug: TONCOIN_SLUG, jettonAddress: nil,
                initialComment: "", binaryPayload: nil, stateInit: nil
            ),
            flow: flow,
            recipientResolver: .init { _ in [:] }
        )
        return TokenSendReviewViewController(
            model: model,
            confirmed: .presentationFixture(
                account: account, token: .TONCOIN, amount: 1_000_000_000,
                addressViewModel: .init(chain: .ton, apiAddress: "recipient", apiName: "recipient.ton")
            )
        )
    }

    private func makeNftReview(mode: NftSendMode) -> NftSendReviewViewController {
        let account = MAccount(
            id: "nft-review-mainnet", title: "NFT review", type: .mnemonic,
            byChain: [.ton: .init(address: "sender")]
        )
        let nfts = [makeNft(chain: .ton, address: "nft-1"), makeNft(chain: .ton, address: "nft-2")]
        let model = NftSendModel(
            accountContext: AccountContext(source: .constant(account)),
            configuration: .init(mode: mode, initialAddress: nil, nfts: nfts, chain: .ton, initialComment: ""),
            flow: .init(api: .init(
                checkDraft: { _, _ in
                    try JSONDecoder().decode(ApiCheckTransactionDraftResult.self, from: Data("{}".utf8))
                },
                submit: { _ in throw TestError.unexpectedSubmission }
            )),
            recipientResolver: .init { _ in [:] }
        )
        return NftSendReviewViewController(
            model: model,
            confirmed: .presentationFixture(
                account: account, mode: mode, chain: .ton, nfts: nfts,
                addressViewModel: .init(chain: .ton, apiAddress: "recipient", apiName: nil)
            )
        )
    }
}

@MainActor
private enum SuspendedExecutor: ProtectedActionExecuting {
    static var calls = 0
    static var fails = false
    static var continuation: CheckedContinuation<Void, Never>?

    static func execute<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        _ action: ProtectedAction<HeaderView, Result>,
        in context: ExecutionContext
    ) async -> Outcome<Result> {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
        return fails ? .failed(TestError.unexpectedSubmission) : .cancelled
    }

    static func finish() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

private enum TestError: Error { case unexpectedSubmission }
