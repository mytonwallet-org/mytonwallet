import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

public final class CrosschainToWalletVC: WViewController {

    private let payment: CrosschainToWalletPayment
    private var didApplyExpiredTitle = false

    private var overviewVC: UIHostingController<SwapOverviewView>?
    private var crossChainToTonVC: UIHostingController<CrosschainToWalletView>?

    public convenience init(swap: ApiSwapActivity, accountId: String?) {
        let fallbackToken = TokenStore.tokens[TONCOIN_SLUG]!
        let fromToken = swap.fromToken ?? fallbackToken
        let toToken = swap.toToken ?? fallbackToken
        let account = AccountStore.get(accountIdOrCurrent: accountId)
        let cex = swap.cex
        self.init(
            payment: CrosschainToWalletPayment(
                sellingAmount: TokenAmount(swap.fromAmountInt64 ?? 0, fromToken),
                buyingAmount: TokenAmount(swap.toAmountInt64 ?? 0, toToken),
                payinAddress: cex?.payinAddress ?? "",
                payoutAddress: cex?.payoutAddress ?? "",
                payinExtraId: cex?.payinExtraId,
                exchangerTxId: cex?.transactionId ?? "",
                cexLabel: swap.cexLabel,
                providerName: cex?.providerName,
                supportUrl: cex?.supportUrl,
                supportEmail: cex?.supportEmail,
                createdAt: Date(timeIntervalSince1970: TimeInterval(swap.timestamp / 1000)),
                cexStatus: cex?.status,
                isInternalSwap: Self.isInternalSwap(
                    fromToken: fromToken,
                    toToken: toToken,
                    payoutAddress: cex?.payoutAddress ?? "",
                    account: account
                )
            )
        )
    }

    public convenience init(
        sellingAmount: TokenAmount,
        buyingAmount: TokenAmount,
        payinAddress: String,
        exchangerTxId: String,
        dt: Date
    ) {
        self.init(
            payment: CrosschainToWalletPayment(
                sellingAmount: sellingAmount,
                buyingAmount: buyingAmount,
                payinAddress: payinAddress,
                payoutAddress: "",
                payinExtraId: nil,
                exchangerTxId: exchangerTxId,
                cexLabel: .changelly,
                providerName: nil,
                supportUrl: nil,
                supportEmail: nil,
                createdAt: dt,
                cexStatus: nil,
                isInternalSwap: false
            )
        )
    }

    init(payment: CrosschainToWalletPayment) {
        self.payment = payment
        super.init(nibName: nil, bundle: nil)
    }

    private static func isInternalSwap(
        fromToken: ApiToken,
        toToken: ApiToken,
        payoutAddress: String,
        account: MAccount
    ) -> Bool {
        if fromToken.chain == toToken.chain && fromToken.chain.isOnchainSwapSupported {
            return true
        }
        return account.supports(chain: fromToken.chain)
            && account.getAddress(chain: toToken.chain) == payoutAddress
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        navigationItem.hidesBackButton = true
        updateNavigationTitle(isExpired: payment.isExpired(at: Date()))
        addCloseNavigationItemIfNeeded()

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let headerVC = UIHostingController(
            rootView: SwapOverviewView(
                fromAmount: payment.sellingAmount,
                toAmount: payment.buyingAmount
            )
        )
        overviewVC = headerVC
        addChild(headerVC)
        scrollView.addSubview(headerVC.view)
        headerVC.view.backgroundColor = .clear
        headerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerVC.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 28),
            headerVC.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
            headerVC.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            headerVC.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16)
        ])
        headerVC.didMove(toParent: self)

        let toTonVC = UIHostingController(rootView: CrosschainToWalletView(payment: payment) { [weak self] in
            self?.applyExpiredTitle()
        })
        crossChainToTonVC = toTonVC
        addChild(toTonVC)
        let toTonView: UIView = toTonVC.view
        toTonView.backgroundColor = .clear
        toTonView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(toTonView)
        NSLayoutConstraint.activate([
            toTonView.topAnchor.constraint(equalTo: headerVC.view.bottomAnchor, constant: 32),
            toTonView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            toTonView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            toTonView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            toTonView.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16)
        ])
        toTonVC.didMove(toParent: self)

        updateTheme()
    }

    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }

    private func applyExpiredTitle() {
        guard !didApplyExpiredTitle else { return }
        didApplyExpiredTitle = true
        updateNavigationTitle(isExpired: true)
    }

    private func updateNavigationTitle(isExpired: Bool) {
        navigationItem.titleView = HostingView {
            NavigationHeader {
                Text(lang(isExpired ? "Swap Expired" : "Swap"))
            } subtitle: {
                if !isExpired && payment.showsPaymentInstructions(at: Date()) {
                    Text(lang("Waiting for Payment").lowercased())
                }
            }
        }
    }

    @objc private func containerPressed() {
        view.endEditing(true)
    }
}
