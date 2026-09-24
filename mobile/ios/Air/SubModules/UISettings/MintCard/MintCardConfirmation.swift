import ProtectedAction
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

@MainActor
func executeMintCard(_ submission: MintCardSubmission, on viewController: WViewController) async {
    let startedAt = Date.now
    let action = ProtectedAction.mintCard(submission: submission) { [weak viewController] in
        Task { @MainActor in
            await ActivityStore.markCardMintSubmitted(accountId: submission.account.id, since: startedAt)
            let showToast = {
                AppActions.showToast(
                    style: .large,
                    icon: .symbolImage("checkmark"),
                    message: lang("$mint_card_result").replacingOccurrences(of: "**", with: ""),
                    duration: 5
                )
            }
            Haptics.play(.success)
            if let viewController, viewController.presentingViewController != nil {
                viewController.dismiss(animated: true, completion: showToast)
            } else {
                showToast()
            }
        }
    }
    _ = await ProtectedActionExecutor.execute(action, on: viewController)
}

struct MintCardSubmission: Sendable {
    let account: MAccount
    let token: ApiToken
    let tokenAddress: String
    let cardType: ApiMtwCardType
    let amount: BigInt

    var cardName: String {
        MintCardTypeInfo.ordered.first(where: { $0.type == cardType })
            .map { lang($0.displayNameKey) }
            ?? cardType.rawValue.capitalized
    }

    func submit(enclaveToken: EnclaveToken?) async throws -> ApiSubmitTransferResult {
        try await Api.submitTransfer(
            chain: .ton,
            options: transferOptions(enclaveToken: enclaveToken)
        )
    }

    @MainActor
    func hardwareOperation() -> HardwareOperation<ApiSubmitTransferResult> {
        .single {
            let result = try await submit(enclaveToken: nil)
            if let error = result.error {
                throw SdkError.apiReturnedError(error: error, context: result)
            }
            if result.mfaRequestHash != nil {
                throw DisplayError(text: lang("Unexpected error"))
            }
            return ActionSubmissionReceipt(
                payload: result,
                activityIds: [result.activityId].compactMap { $0 }
            )
        }
    }

    private func transferOptions(enclaveToken: EnclaveToken?) -> ApiSubmitTransferOptions {
        ApiSubmitTransferOptions(
            accountId: account.id,
            toAddress: MINT_CARD_ADDRESS,
            amount: amount,
            payload: .comment(text: MINT_CARD_COMMENT, shouldEncrypt: false),
            stateInit: nil,
            tokenAddress: tokenAddress,
            realFee: nil,
            isGasless: nil,
            dieselAmount: nil,
            isGaslessWithStars: nil,
            gaslessTransaction: nil,
            enclaveToken: enclaveToken,
            fee: nil,
            noFeeCheck: nil
        )
    }
}

private extension ProtectedAction
where HeaderView == MintCardConfirmationView,
      Result == ApiSubmitTransferResult {
    static func mintCard(submission: MintCardSubmission, onCommitted: @escaping @MainActor () -> Void) -> Self {
        Self(
            account: submission.account,
            software: .single { enclaveToken in
                try await submission.submit(enclaveToken: enclaveToken)
            },
            hardware: {
                submission.hardwareOperation()
            },
            confirmation: .init(
                title: lang("Confirm Upgrading"),
                header: MintCardConfirmationView(submission: submission),
                prefersNavigationTitleWithCustomHeader: true
            ),
            completion: .handoff { _ in
                onCommitted()
            }
        )
    }
}

private struct MintCardConfirmationView: ConfirmationContent {
    let submission: MintCardSubmission

    var body: some View {
        VStack(spacing: 12) {
            WUIIconViewToken(
                token: submission.token,
                isWalletView: false,
                showldShowChain: true,
                size: 60,
                chainSize: 24,
                chainBorderWidth: 1.5,
                chainHorizontalOffset: 6,
                chainVerticalOffset: 2
            )
            .frame(width: 60, height: 60)

            Text(TokenAmount(submission.amount, submission.token).formatted(.defaultAdaptive))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color.air.primaryLabel)

            Text(submission.cardName)
                .textStyle(.body)
                .foregroundStyle(Color.air.secondaryLabel)
        }
        .padding(.bottom, 12)
    }

    var compactRepresentation: some View {
        CompactActionSummary {
            WUIIconViewToken(
                token: submission.token,
                isWalletView: false,
                showldShowChain: false,
                size: 20,
                chainSize: 0,
                chainBorderWidth: 0,
                chainHorizontalOffset: 0,
                chainVerticalOffset: 0
            )
        } label: {
            Text(submission.cardName)
                .textStyle(.bodyEmphasized)
        }
    }
}
