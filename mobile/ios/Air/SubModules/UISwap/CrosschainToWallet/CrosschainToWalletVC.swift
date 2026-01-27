import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

public final class CrosschainToWalletVC: WViewController {
    
    private let sellingAmount: TokenAmount
    private let buyingAmount: TokenAmount
    private let payinAddress: String
    private let exchangerTxId: String
    private let dt: Date
    
    private var overviewVC: UIHostingController<SwapOverviewView>?
    private var crossChainToTonVC: UIHostingController<CrosschainToWalletView>?
    
    public convenience init(swap: ApiSwapActivity, accountId: String?) {
        let fallbackToken = TokenStore.tokens[TONCOIN_SLUG]!
        let fromToken = swap.fromToken ?? fallbackToken
        let toToken = swap.toToken ?? fallbackToken
        self.init(
            sellingAmount: TokenAmount(swap.fromAmountInt64 ?? 0, fromToken),
            buyingAmount: TokenAmount(swap.toAmountInt64 ?? 0, toToken),
            payinAddress: swap.cex?.payinAddress ?? "",
            exchangerTxId: swap.cex?.transactionId ?? "",
            dt: Date(timeIntervalSince1970: TimeInterval(swap.timestamp / 1000))
        )
    }
    
    public init(
        sellingAmount: TokenAmount,
        buyingAmount: TokenAmount,
        payinAddress: String,
        exchangerTxId: String,
        dt: Date
    ) {
        self.sellingAmount = sellingAmount
        self.buyingAmount = buyingAmount
        self.payinAddress = payinAddress
        self.exchangerTxId = exchangerTxId
        self.dt = dt
        super.init(nibName: nil, bundle: nil)
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
        navigationItem.titleView = HostingView {
            NavigationHeader {
                Text(lang("Swapping"))
            } subtitle: {
                Text(lang("Waiting for Payment").lowercased())
            }
        }
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
                fromAmount: sellingAmount,
                toAmount: buyingAmount
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
        
        let toTonVC = UIHostingController(rootView: CrosschainToWalletView(
            sellingToken: sellingAmount.type,
            amount: sellingAmount.amount.doubleAbsRepresentation(decimals: sellingAmount.decimals),
            address: payinAddress,
            dt: dt,
            exchangerTxId: exchangerTxId
        ))
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
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    @objc private func containerPressed() {
        view.endEditing(true)
    }
}
