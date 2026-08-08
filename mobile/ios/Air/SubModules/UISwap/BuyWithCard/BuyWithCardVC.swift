//
//  BuyWithCardVC.swift
//  UISwap
//
//  Created by Sina on 5/14/24.
//

import WebKit
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception
import SwiftNavigation

public class BuyWithCardVC: WViewController {
    
    let model: BuyWithCardModel
    var observer: ObserveToken?
    
    /// Nil when no currency is offered on this chain, so the caller refuses instead of pushing a screen
    /// that has nothing to show.
    public init?(accountContext: AccountContext, chain: ApiChain) {
        guard let model = BuyWithCardModel(accountContext: accountContext, chain: chain, selectedCurrency: TokenStore.baseCurrency) else {
            return nil
        }
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WalletCoreData.add(eventObserver: self)
        observer = observe { [weak self] in
            guard let self else { return }
            loadOnramp(currency: model.selectedCurrency)
        }
    }

    private let webView = WKWebView()
    private func setupViews() {
        title = lang("Buy with Card")
        navigationItem.titleView = HostingView {
            BuyWithCardHeader(model: model)
        }
        addCloseNavigationItemIfNeeded()
        
        webView.isOpaque = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadOnramp(currency: MBaseCurrency) {
        // Last checkpoint before a provider URL is built: a currency dropped by the server must
        // never reach the web view, whichever provider would serve it.
        guard model.supportedCurrencies.contains(currency) else { return }

        if currency == .RUB {
            open(url: model.account.dreamwalkersLink)
        } else {
            guard model.account.getAddress(chain: model.chain) != nil else { return }
            let addressByChain = model.account.byChain.mapValues { $0.address }
            Task {
                let activeTheme = ResolvedTheme(traitCollection: traitCollection)
                do {
                    let url = try await Api.getMoonpayOnrampUrl(
                        params: MoonpayOnrampParams(
                            chain: model.chain,
                            addressByChain: addressByChain,
                            theme: activeTheme,
                            currency: currency
                        )
                    ).url
                    open(url: url)
                } catch {
                    showAlert(error: error)
                }
            }
        }
    }
    
    private func open(url string: String?) {
        if let string, let url = URL(string: string) {
            webView.load(URLRequest(url: url))
        }
    }

}

extension BuyWithCardVC: WalletCoreData.EventsObserver {
    /// An already open screen must follow the server narrowing the allowed currencies: leave
    /// entirely when nothing is left, otherwise move to a still allowed currency, which reloads
    /// the web view through the existing observer.
    public func walletCore(event: WalletCoreData.Event) {
        guard case .configChanged = event else { return }
        guard let currency = OnRampCurrencyPolicy.preferredCurrency(
            for: model.chain,
            preferences: [model.selectedCurrency]
        ) else {
            if navigationController?.topViewController === self {
                navigationController?.popViewController(animated: true)
            } else {
                dismiss(animated: true)
            }
            return
        }
        model.selectedCurrency = currency
    }
}
