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
    
    public init(accountContext: AccountContext, chain: ApiChain) {
        self.model = BuyWithCardModel(accountContext: accountContext, chain: chain, selectedCurrency: TokenStore.baseCurrency)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
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
            webView.leftAnchor.constraint(equalTo: view.leftAnchor),
            webView.rightAnchor.constraint(equalTo: view.rightAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadOnramp(currency: MBaseCurrency) {
        
        if currency == .RUB {
            open(url: model.account.dreamwalkersLink)
        } else {
            guard let address = model.account.getAddress(chain: model.chain) else { return }
            Task {
                let activeTheme = ResolvedTheme(traitCollection: traitCollection)
                do {
                    let url = try await Api.getMoonpayOnrampUrl(
                        params: MoonpayOnrampParams(
                            chain: model.chain,
                            address: address,
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
