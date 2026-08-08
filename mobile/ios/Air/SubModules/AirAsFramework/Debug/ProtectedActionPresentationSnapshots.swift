#if DEBUG

import Foundation
import ProtectedAction
import SwiftUI
import UIKit
@testable import UIAssets
import UIComponents
@testable import UIDapp
@testable import UIEarn
import UIPasscode
@testable import UIProtectedAction
@testable import UISend
@testable import UISettings
@testable import UISwap
@testable import UITransaction
import WalletContext
@testable import WalletCore

@MainActor
public enum ProtectedActionPresentationSnapshots {
    // The capture script reads this array directly, so the app catalog remains the source of truth.
    public static let identifiers = [
        "burn-nft-multiple-mfa",
        "burn-nft-multiple-passcode",
        "burn-nft-multiple-success",
        "burn-nft-single-mfa",
        "burn-nft-single-passcode",
        "burn-nft-single-success",
        "claim-rewards-mfa",
        "claim-rewards-passcode",
        "dapp-connect-mfa",
        "dapp-connect-passcode",
        "dapp-send-multiple-mfa",
        "dapp-send-multiple-passcode",
        "dapp-send-nft-mfa",
        "dapp-send-nft-passcode",
        "dapp-send-token-mfa",
        "dapp-send-token-passcode",
        "dapp-sign-data-mfa",
        "dapp-sign-data-passcode",
        "domain-link-mfa",
        "domain-link-passcode",
        "domain-renew-multiple-mfa",
        "domain-renew-multiple-passcode",
        "domain-renew-single-mfa",
        "domain-renew-single-passcode",
        "mfa-connect-mfa",
        "mfa-connect-passcode",
        "mfa-disconnect-mfa",
        "mfa-disconnect-passcode",
        "sell-to-moonpay-mfa",
        "sell-to-moonpay-passcode",
        "sell-to-moonpay-success",
        "send-nft-multiple-mfa",
        "send-nft-multiple-passcode",
        "send-nft-multiple-success",
        "send-nft-single-mfa",
        "send-nft-single-passcode",
        "send-nft-single-success",
        "send-ton-mfa",
        "send-ton-passcode",
        "send-ton-success",
        "stake-mfa",
        "stake-passcode",
        "stake-success",
        "swap-crosschain-to-wallet-mfa",
        "swap-crosschain-to-wallet-passcode",
        "swap-crosschain-to-wallet-success",
        "swap-onchain-mfa",
        "swap-onchain-passcode",
        "swap-onchain-success",
        "unlock-usde-mfa",
        "unlock-usde-passcode",
        "unstake-mfa",
        "unstake-passcode",
        "unstake-success",
        "wallet-connect-pay-mfa",
        "wallet-connect-pay-passcode",
        "wallet-connect-pay-success",
    ]

    public static func makeViewController(identifier: String) -> UIViewController? {
        precondition(Set(identifiers) == Set(computedIdentifiers), "Protected action snapshot manifest is out of date")
        for snapshotCase in PresentationSnapshotCatalog.all {
            switch identifier {
            case "\(snapshotCase.id)-passcode":
                return snapshotCase.makePasscodeViewController()
            case "\(snapshotCase.id)-mfa":
                return snapshotCase.makeMfaViewController()
            case "\(snapshotCase.id)-success":
                return snapshotCase.makeSuccessViewController?()
            default:
                continue
            }
        }
        return nil
    }

    private static var computedIdentifiers: [String] {
        PresentationSnapshotCatalog.all.flatMap { snapshotCase in
            var identifiers = [
                "\(snapshotCase.id)-passcode",
                "\(snapshotCase.id)-mfa",
            ]
            if snapshotCase.makeSuccessViewController != nil {
                identifiers.append("\(snapshotCase.id)-success")
            }
            return identifiers
        }
    }

    public static func prepareForCapture(_ viewController: UIViewController) {
        prepareViewControllerHierarchy(viewController)
        if let window = viewController.view.window {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            freezeAnimations(in: window)
        }
    }

    private static func prepareViewControllerHierarchy(_ viewController: UIViewController) {
        viewController.loadViewIfNeeded()
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        for child in viewController.children {
            prepareViewControllerHierarchy(child)
        }
        if let presentedViewController = viewController.presentedViewController {
            prepareViewControllerHierarchy(presentedViewController)
        }
    }

    private static func freezeAnimations(in view: UIView) {
        if let sticker = view as? WAnimatedSticker {
            sticker.showFirstFrame()
        }
        for subview in view.subviews {
            freezeAnimations(in: subview)
        }
    }
}

@MainActor
private final class SnapshotSheetHostViewController: UIViewController {
    private let contentViewController: UIViewController
    private let onPresented: () -> Void
    private var didPresentContent = false

    init(contentViewController: UIViewController, onPresented: @escaping () -> Void) {
        self.contentViewController = contentViewController
        self.onPresented = onPresented
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .air.background
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresentContent else { return }
        didPresentContent = true
        contentViewController.modalPresentationStyle = .pageSheet
        present(contentViewController, animated: false, completion: onPresented)
    }
}

@MainActor
private struct PresentationSnapshotCase {
    let id: String
    let title: String
    let account: MAccount
    let presentationStyle: PresentationStyle
    let prefersNavigationTitleWithCustomHeader: Bool
    let header: AnyView
    let compactHeader: AnyView
    let makeSuccessViewController: (() -> UIViewController)?

    init<Header: ConfirmationContent>(
        id: String,
        account: MAccount,
        confirmation: Confirmation<Header>,
        makeSuccessViewController: (() -> UIViewController)? = nil
    ) {
        self.id = id
        self.title = confirmation.title
        self.account = account
        self.presentationStyle = confirmation.presentationStyle
        self.prefersNavigationTitleWithCustomHeader = confirmation.prefersNavigationTitleWithCustomHeader
        self.header = AnyView(confirmation.headerView)
        self.compactHeader = AnyView(confirmation.headerView.compactRepresentation)
        self.makeSuccessViewController = makeSuccessViewController
    }

    func makePasscodeViewController() -> UIViewController {
        let customHeader = UIHostingController(rootView: header)
        customHeader.view.backgroundColor = .air.sheetBackground
        let compactHeader = UIHostingController(rootView: compactHeader)
        compactHeader.view.backgroundColor = .air.sheetBackground

        let unlockViewController = UnlockVC(
            title: title,
            customHeaderVC: customHeader,
            compactHeaderVC: compactHeader,
            prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
            dissmissWhenAuthorized: false,
            onAuthTask: { _, done in done() },
            onDone: { _ in },
            cancellable: true,
            onCancel: nil,
            useBioOnPresent: false,
            successCompletionDelay: 0
        )
        return pushedNavigationController(unlockViewController)
    }

    func makeMfaViewController() -> UIViewController {
        let model = MfaConfirmationModel(
            requestHash: "snapshot-request",
            pollInterval: .seconds(60),
            fetchRequest: { _ in
                ApiMfaRequest(
                    payload: "snapshot",
                    signature: "snapshot",
                    isConfirmed: false,
                    txHash: "snapshot"
                )
            }
        )
        let viewController = MfaConfirmationVC(
            account: account,
            model: model,
            title: title,
            compactRepresentation: compactHeader,
            prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader
        )
        return pushedNavigationController(viewController)
    }

    private func pushedNavigationController(_ viewController: UIViewController) -> UIViewController {
        let predecessor = UIViewController()
        predecessor.view.backgroundColor = .air.sheetBackground
        let navigationController = WNavigationController(rootViewController: predecessor)
        navigationController.pushViewController(viewController, animated: false)
        return navigationController
    }
}

@MainActor
private enum PresentationSnapshotCatalog {
    static var all: [PresentationSnapshotCase] {
        sendCases
            + swapCases
            + earnCases
            + mfaSettingsCases
            + domainCases
            + dappCases
            + walletConnectPayCases
    }

    private static var sendCases: [PresentationSnapshotCase] {
        let sendTon = tokenSendSnapshot(token: ton, amount: 10_500_000_000)
        let sellToMoonPay = tokenSendSnapshot(token: ton, amount: 42_000_000_000)
        let sendOneNft = nftSendSnapshot(mode: .send, chain: .ton, nfts: [domainNft])
        let sendManyNfts = nftSendSnapshot(mode: .send, chain: .ton, nfts: nftCollection)
        let burnOneNft = nftSendSnapshot(mode: .burn, chain: .ton, nfts: [domainNft])
        let burnManyNfts = nftSendSnapshot(mode: .burn, chain: .ton, nfts: nftCollection)

        return [
            tokenSendCase(id: "send-ton", confirmed: sendTon, success: transactionSuccess(amount: -10_500_000_000, slug: ton.slug, context: .sendConfirmation)),
            tokenSendCase(id: "sell-to-moonpay", confirmed: sellToMoonPay, success: transactionSuccess(amount: -42_000_000_000, slug: ton.slug, context: .sendConfirmation)),
            nftSendCase(id: "send-nft-single", confirmed: sendOneNft, success: nftSuccess(confirmed: sendOneNft)),
            nftSendCase(id: "send-nft-multiple", confirmed: sendManyNfts, success: nftSuccess(confirmed: sendManyNfts)),
            nftSendCase(id: "burn-nft-single", confirmed: burnOneNft, success: nftSuccess(confirmed: burnOneNft)),
            nftSendCase(id: "burn-nft-multiple", confirmed: burnManyNfts, success: nftSuccess(confirmed: burnManyNfts)),
        ]
    }

    private static var swapCases: [PresentationSnapshotCase] {
        let onchainHeader = SwapConfirmHeaderView(
            fromAmount: TokenAmount(12_500_000_000, ton),
            toAmount: TokenAmount(37_420_000, usdt)
        )
        let onchainConfirmation = Confirmation(
            title: lang("Confirm Swap"),
            header: onchainHeader,
            prefersNavigationTitleWithCustomHeader: false
        )
        let crosschainHeader = SwapConfirmHeaderView(
            fromAmount: TokenAmount(12_500_000, trx),
            toAmount: TokenAmount(37_420_000, usdt)
        )
        let crosschainConfirmation = Confirmation(
            title: lang("Confirm Swap"),
            header: crosschainHeader,
            prefersNavigationTitleWithCustomHeader: false
        )

        return [
            PresentationSnapshotCase(
                id: "swap-onchain",
                account: account,
                confirmation: onchainConfirmation,
                makeSuccessViewController: swapActivitySuccess
            ),
            PresentationSnapshotCase(
                id: "swap-crosschain-to-wallet",
                account: account,
                confirmation: crosschainConfirmation,
                makeSuccessViewController: crosschainSwapAwaitingDeposit
            ),
        ]
    }

    private static var earnCases: [PresentationSnapshotCase] {
        [
            earnCase(
                id: "stake",
                title: lang("Confirm Staking"),
                mode: .stake,
                amount: TokenAmount(25_000_000_000, ton),
                success: transactionSuccess(amount: -25_000_000_000, slug: ton.slug, type: .stake, context: .stakeConfirmation)
            ),
            earnCase(
                id: "unstake",
                title: lang("Confirm Unstaking"),
                mode: .unstake,
                amount: TokenAmount(15_000_000_000, ton),
                success: transactionSuccess(amount: 15_000_000_000, slug: ton.slug, type: .unstakeRequest, context: .unstakeRequestConfirmation)
            ),
            earnCase(
                id: "claim-rewards",
                title: lang("Confirm Rewards Claim"),
                mode: .claim,
                amount: TokenAmount(3_250_000, usdt),
                success: nil
            ),
            earnCase(
                id: "unlock-usde",
                title: lang("Confirm Unstaking"),
                mode: .unstake,
                amount: TokenAmount(1_200_000, usde),
                success: nil
            ),
        ]
    }

    private static var mfaSettingsCases: [PresentationSnapshotCase] {
        let user = account.getChainInfo(chain: .ton)?.mfa?.user
        return [
            PresentationSnapshotCase(
                id: "mfa-connect",
                account: account,
                confirmation: Confirmation(
                    title: lang("Confirm Connection"),
                    header: MfaConfirmHeaderView(account: account, title: lang("Confirm Connection"), user: user),
                    prefersNavigationTitleWithCustomHeader: false
                )
            ),
            PresentationSnapshotCase(
                id: "mfa-disconnect",
                account: account,
                confirmation: Confirmation(
                    title: lang("Confirm Disconnection"),
                    header: MfaConfirmHeaderView(account: account, title: lang("Confirm Disconnection"), user: user),
                    prefersNavigationTitleWithCustomHeader: false
                )
            ),
        ]
    }

    private static var domainCases: [PresentationSnapshotCase] {
        let linkSnapshot = LinkDomainConfirmationSnapshot(
            account: account,
            nft: domainNft,
            destinationAddress: destinationAddress,
            destinationName: account.displayName,
            realFee: 20_000_000
        )
        let renewSingle = RenewDomainConfirmationSnapshot(account: account, nfts: [domainNft], realFee: 20_000_000)
        let renewMultiple = RenewDomainConfirmationSnapshot(account: account, nfts: nftCollection, realFee: 60_000_000)

        return [
            PresentationSnapshotCase(
                id: "domain-link",
                account: account,
                confirmation: Confirmation(title: lang("Confirm Linking"), header: LinkDomainAuthHeader(snapshot: linkSnapshot))
            ),
            PresentationSnapshotCase(
                id: "domain-renew-single",
                account: account,
                confirmation: Confirmation(title: lang("Confirm Renewing"), header: RenewDomainAuthHeader(snapshot: renewSingle))
            ),
            PresentationSnapshotCase(
                id: "domain-renew-multiple",
                account: account,
                confirmation: Confirmation(title: lang("Confirm Renewing"), header: RenewDomainAuthHeader(snapshot: renewMultiple))
            ),
        ]
    }

    private static var dappCases: [PresentationSnapshotCase] {
        let context = AccountContext(source: .constant(account))
        let dapp = ApiDapp(
            url: "https://example.wallet",
            name: "Example Market",
            iconUrl: "",
            connectedAt: nil,
            urlTrustStatus: .verified,
            sse: nil
        )

        return [
            dappCase(id: "dapp-connect", title: lang("Confirm Connect"), action: lang("Connect"), dapp: dapp, context: context, style: .sheet),
            dappCase(id: "dapp-send-token", title: lang("Confirm Sending"), action: "10.5 TON \(lang("to")) \(formatStartEndAddress(destinationAddress))", dapp: dapp, context: context),
            dappCase(id: "dapp-send-nft", title: lang("Confirm Sending"), action: "1 NFT \(lang("to")) \(formatStartEndAddress(destinationAddress))", dapp: dapp, context: context),
            dappCase(id: "dapp-send-multiple", title: lang("Confirm Sending"), action: lang("$many_transactions", arg1: 3), dapp: dapp, context: context),
            dappCase(id: "dapp-sign-data", title: lang("Sign Data"), action: lang("Sign Data"), dapp: dapp, context: context),
        ]
    }

    private static var walletConnectPayCases: [PresentationSnapshotCase] {
        let header = WalletConnectPayAuthHeaderView(
            merchant: walletConnectPayMerchant,
            paymentContext: walletConnectPayContext,
            accountContext: AccountContext(source: .constant(account))
        )
        let confirmation = Confirmation(
            title: lang("Confirm Sending"),
            header: header,
            prefersNavigationTitleWithCustomHeader: true
        )
        return [
            PresentationSnapshotCase(
                id: "wallet-connect-pay",
                account: account,
                confirmation: confirmation,
                makeSuccessViewController: walletConnectPaySuccess
            )
        ]
    }
}

// MARK: - Case builders

private extension PresentationSnapshotCatalog {
    static func tokenSendCase(
        id: String,
        confirmed: ConfirmedTokenSend,
        success: (() -> UIViewController)?
    ) -> PresentationSnapshotCase {
        PresentationSnapshotCase(
            id: id,
            account: confirmed.account,
            confirmation: Confirmation(
                title: confirmed.protectedActionTitle,
                header: TokenSendingHeaderView(confirmed: confirmed),
                prefersNavigationTitleWithCustomHeader: false
            ),
            makeSuccessViewController: success
        )
    }

    static func nftSendCase(
        id: String,
        confirmed: ConfirmedNftSend,
        success: (() -> UIViewController)?
    ) -> PresentationSnapshotCase {
        PresentationSnapshotCase(
            id: id,
            account: confirmed.account,
            confirmation: Confirmation(
                title: confirmed.protectedActionTitle,
                header: NftSendingHeaderView(confirmed: confirmed),
                prefersNavigationTitleWithCustomHeader: true
            ),
            makeSuccessViewController: success
        )
    }

    static func earnCase(
        id: String,
        title: String,
        mode: StakingConfirmHeaderView.Mode,
        amount: TokenAmount,
        success: (() -> UIViewController)?
    ) -> PresentationSnapshotCase {
        PresentationSnapshotCase(
            id: id,
            account: account,
            confirmation: Confirmation(title: title, header: StakingConfirmHeaderView(mode: mode, tokenAmount: amount)),
            makeSuccessViewController: success
        )
    }

    static func dappCase(
        id: String,
        title: String,
        action: String,
        dapp: ApiDapp,
        context: AccountContext,
        style: PresentationStyle = .push
    ) -> PresentationSnapshotCase {
        PresentationSnapshotCase(
            id: id,
            account: account,
            confirmation: Confirmation(
                title: title,
                header: DappHeaderView(dapp: dapp, accountContext: context, compactAction: action),
                presentationStyle: style
            )
        )
    }
}

// MARK: - Deterministic fixtures

private extension PresentationSnapshotCatalog {
    static let destinationAddress = "UQk3lS5LrtE2hA4h8sZtTW7vFWnRPFDB4FQ45Fa4fK"

    static let account = MAccount(
        id: "presentation-snapshot-mainnet",
        title: "Main Wallet",
        type: .mnemonic,
        byChain: [
            .ton: AccountChain(
                address: "UQDxT8N35Zq9w7Wm9Qxk4WkR7qJ5N3M2B1A0Snapshot",
                domain: "main.ton",
                mfa: AccountMfa(
                    address: "telegram-mfa",
                    user: AccountMfa.User(name: "Artemii Ledenev", username: "artemii")
                )
            ),
            .ethereum: AccountChain(address: "0x7A3fD8a1F0B2A84B4191234567890abcDEF12345"),
        ]
    )

    static let ton = ApiToken.TONCOIN
    static let trx = ApiChain.tron.nativeToken
    static let usdt = ApiToken.TON_USDT
    static let usde = ApiToken.TON_USDE

    static let domainNft = ApiNft(
        index: 1,
        ownerAddress: account.getAddress(chain: .ton),
        name: "beautiful-domain.ton",
        address: "EQDomainOne",
        thumbnail: nil,
        image: nil,
        description: "TON domain",
        collectionName: "TON DNS",
        collectionAddress: ApiNft.TON_DNS_COLLECTION_ADDRESS,
        isOnSale: false
    )
    static let nftCollection = [
        domainNft,
        ApiNft(name: "Moon Caller #2048", address: "EQNftTwo", isOnSale: false),
        ApiNft(name: "My Wallet Card #1806", address: "EQNftThree", isOnSale: false),
        ApiNft(name: "Telegram Gift #728", address: "EQNftFour", isOnSale: false),
        ApiNft(name: "Cosmic Duck #42", address: "EQNftFive", isOnSale: false),
    ]

    static func tokenSendSnapshot(
        token: ApiToken,
        amount: BigInt
    ) -> ConfirmedTokenSend {
        ConfirmedTokenSend.presentationFixture(
            account: account,
            token: token,
            amount: amount,
            addressViewModel: AddressViewModel(
                chain: token.chain,
                apiAddress: destinationAddress,
                apiName: "recipient.ton"
            )
        )
    }

    static func nftSendSnapshot(
        mode: NftSendMode,
        chain: ApiChain,
        nfts: [ApiNft]
    ) -> ConfirmedNftSend {
        ConfirmedNftSend.presentationFixture(
            account: account,
            mode: mode,
            chain: chain,
            nfts: nfts,
            addressViewModel: AddressViewModel(
                chain: chain,
                apiAddress: mode == .burn ? nil : destinationAddress,
                apiName: mode == .burn ? nil : "recipient.ton"
            )
        )
    }

    static let walletConnectPayMerchant = WcPayMerchant(name: "Merchant Name", iconUrl: nil)
    static let walletConnectPayContext = WalletConnectPayPaymentContext(
        paymentInfo: try! JSONDecoder().decode(WcPayPaymentInfo.self, from: Data(#"{"expiresAt":1893456000,"amount":{"value":"10500000000","display":{"assetSymbol":"TON","assetName":"Toncoin","decimals":9},"fiatAmount":{"value":"3150","decimals":2,"slug":"USD"}}}"#.utf8)),
        paymentOption: try! JSONDecoder().decode(WcPayPaymentOption.self, from: Data(#"{"id":"ton","account":"ton:mainnet:snapshot","amountValue":"10500000000","slug":"toncoin","display":{"assetSymbol":"TON","assetName":"Toncoin","decimals":9,"networkName":"TON"}}"#.utf8))
    )
}

// MARK: - Success controllers

private extension PresentationSnapshotCatalog {
    static func presentedSheet(
        _ viewController: UIViewController,
        onPresented: @escaping () -> Void = { }
    ) -> UIViewController {
        SnapshotSheetHostViewController(
            contentViewController: WNavigationController(rootViewController: viewController),
            onPresented: onPresented
        )
    }

    static func nftSuccess(confirmed: ConfirmedNftSend) -> () -> UIViewController {
        {
            let viewController = NftSendSuccessViewController(
                confirmed: confirmed
            )
            return presentedSheet(viewController) { [weak viewController] in
                viewController?.animateToCollapsed()
            }
        }
    }

    static func transactionSuccess(
        amount: BigInt,
        slug: String,
        type: ApiTransactionType? = nil,
        context: ActivityDetailsContext
    ) -> () -> UIViewController {
        {
            let transaction = ApiTransactionActivity(
                id: "snapshot-transaction",
                kind: "transaction",
                externalMsgHashNorm: nil,
                shouldReload: false,
                shouldLoadDetails: false,
                timestamp: 1_893_456_000,
                amount: amount,
                fromAddress: account.getAddress(chain: .ton) ?? "",
                toAddress: destinationAddress,
                comment: nil,
                encryptedComment: nil,
                fee: 12_500_000,
                slug: slug,
                isIncoming: amount > 0,
                normalizedAddress: destinationAddress,
                type: type,
                metadata: ApiAddressInfo(name: "recipient.ton", isScam: false, isMemoRequired: false),
                nft: nil,
                status: .confirmed
            )
            let viewController = ActivityVC(
                activity: .transaction(transaction),
                accountSource: .constant(account),
                context: context
            )
            return presentedSheet(viewController) { [weak viewController] in
                viewController?.animateToCollapsed()
            }
        }
    }

    static func swapActivitySuccess() -> UIViewController {
        let activity = try! JSONDecoder().decode(ApiActivity.self, from: Data(#"{"kind":"swap","id":"snapshot-swap","timestamp":1893456000,"from":"toncoin","fromAmount":"12.5","to":"tether-usdt","toAmount":"37.42","networkFee":"0.05","swapFee":"0.1","status":"confirmed","transactionIds":{}}"#.utf8))
        let viewController = ActivityVC(
            activity: activity,
            accountSource: .constant(account),
            context: .onchainSwapConfirmation
        )
        return presentedSheet(viewController) { [weak viewController] in
            viewController?.animateToCollapsed()
        }
    }

    static func crosschainSwapAwaitingDeposit() -> UIViewController {
        let now = Date(timeIntervalSince1970: 1_893_456_000)
        let payment = CrosschainToWalletPayment(
            sellingAmount: TokenAmount(12_500_000, trx),
            buyingAmount: TokenAmount(37_420_000, usdt),
            payinAddress: "TVjsyZ7fYF3qLF6BQgPmTEZy1xrNNyVAAA",
            payoutAddress: account.getAddress(chain: .ton) ?? "",
            payinExtraId: nil,
            exchangerTxId: "exchange-snapshot-id",
            cexLabel: .changelly,
            providerName: "Changelly",
            supportUrl: nil,
            supportEmail: "support@example.com",
            createdAt: now,
            cexStatus: .waiting,
            isInternalSwap: false
        )
        return presentedSheet(CrosschainToWalletVC(payment: payment, fixedNow: now))
    }

    static func walletConnectPaySuccess() -> UIViewController {
        let complete = try! JSONDecoder().decode(
            ApiUpdate.WalletConnectPayPaymentComplete.self,
            from: Data(#"{"type":"walletConnectPayPaymentComplete","accountId":"presentation-snapshot-mainnet","merchant":{"name":"Merchant Name"},"operationChain":"ton","txId":"snapshot-payment","paymentAmount":{"value":"10500000000","display":{"assetSymbol":"TON","assetName":"Toncoin","decimals":9}}}"#.utf8)
        )
        return presentedSheet(
            WalletConnectPayPaymentStatusVC(
                complete: complete,
                paymentContext: walletConnectPayContext,
                onClose: { }
            )
        )
    }
}

#endif
