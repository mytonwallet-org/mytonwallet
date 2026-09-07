import ProtectedAction
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let REQUIRED_TON_FOR_MINT_CARD_FEE = BigInt(65_000_000)
private let SWAP_AMOUNT_RESERVE_MULTIPLIER = BigInt(105)

public final class MintCardVC: WViewController {
    private let accountContext: AccountContext
    private var hostingController: UIHostingController<MintCardView>?

    public init(accountContext: AccountContext) {
        self.accountContext = accountContext
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .air.sheetBackground
        configureNavigationItemWithTransparentBackground()
        addCloseNavigationItemIfNeeded()
        hostingController = addHostingController(
            MintCardView(
                accountContext: accountContext,
                onUpgrade: { [weak self] type in
                    self?.upgrade(type: type)
                }
            ),
            constraints: .fill
        )
    }

    private func upgrade(type: ApiMtwCardType) {
        let account = accountContext.account
        guard account.supportsSend else {
            AppActions.showError(error: DisplayError(text: lang("Read-only account")))
            return
        }
        guard let cardInfo = accountContext.config.cardsInfo?[type], cardInfo.notMinted > 0,
              let mycoin = TokenStore.getToken(slug: MYCOIN_SLUG),
              let tokenAddress = mycoin.tokenAddress,
              cardInfo.price > 0
        else {
            AppActions.showError(error: DisplayError(text: lang("Unexpected error")))
            return
        }

        let amount = doubleToBigInt(cardInfo.price, decimals: mycoin.decimals)
        let mycoinBalance = accountContext.balances[MYCOIN_SLUG] ?? 0
        if mycoinBalance < amount {
            let missingAmount = amount - mycoinBalance
            let missingAmountWithReserve = missingAmount * SWAP_AMOUNT_RESERVE_MULTIPLIER / 100
            let buyingAmount = bigIntToDouble(amount: missingAmountWithReserve, decimals: mycoin.decimals)
            dismiss(animated: true) { [accountContext] in
                Task {
                    await AppActions.showSwap(
                        accountContext: accountContext,
                        defaultSellingToken: TONCOIN_SLUG,
                        defaultBuyingToken: MYCOIN_SLUG,
                        defaultSellingAmount: nil,
                        defaultBuyingAmount: buyingAmount,
                        push: nil
                    )
                }
            }
            return
        }

        let toncoinBalance = accountContext.balances[TONCOIN_SLUG] ?? 0
        guard toncoinBalance >= REQUIRED_TON_FOR_MINT_CARD_FEE else {
            showAlert(
                title: lang("Insufficient Fee"),
                text: L10n.pleaseTopUpYourTokenBalance(token: ApiToken.TONCOIN.symbol),
                button: lang("OK")
            )
            return
        }

        let submission = MintCardSubmission(
            account: account,
            token: mycoin,
            tokenAddress: tokenAddress,
            cardType: type,
            amount: amount
        )
        Task {
            let action = ProtectedAction.mintCard(submission: submission)
            _ = await ProtectedActionExecutor.execute(action, on: self)
        }
        Haptics.prepare(.success)
    }
}

private struct MintCardSubmission: Sendable {
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
    static func mintCard(submission: MintCardSubmission) -> Self {
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
            completion: .replace { _ in
                Replacement(
                    viewController: MintCardSuccessVC(cardName: submission.cardName)
                )
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

private final class MintCardSuccessVC: WViewController {
    private let cardName: String

    init(cardName: String) {
        self.cardName = cardName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .air.sheetBackground
        navigationItem.title = lang("Card has been upgraded!")
        navigationItem.hidesBackButton = true
        addCloseNavigationItemIfNeeded()
        _ = addHostingController(
            MintCardSuccessView(
                cardName: cardName,
                onDone: { [weak self] in
                    self?.dismiss(animated: true)
                }
            ),
            constraints: .fill
        )
    }
}

private struct MintCardSuccessView: View {
    let cardName: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 112, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)

            Text(cardName)
                .textStyle(.title2)
                .foregroundStyle(Color.air.primaryLabel)

            successDescription
                .textStyle(.calloutEmphasized)
                .foregroundStyle(Color.air.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(16)
                .background(Color.air.secondaryFill, in: .rect(cornerRadius: 12))
                .padding(.horizontal, 32)

            Spacer()

            Button(lang("Done"), action: onDone)
                .buttonStyle(.airPrimary)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 16)
        .background(Color.air.sheetBackground)
    }

    @ViewBuilder
    private var successDescription: some View {
        let description = lang("$mint_card_result")
        if let markdown = try? AttributedString(
            markdown: description,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(markdown)
        } else {
            Text(description)
        }
    }
}
