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
import Combine

public class BuyWithCardVC: WViewController, UIScrollViewDelegate {
    
    let model: BuyWithCardModel
    var observer: AnyCancellable?
    
    public init(chain: ApiChain) {
        self.model = BuyWithCardModel(chain: chain, selectedCurrency: TokenStore.baseCurrency)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        loadOnramp(currency: model.selectedCurrency)
        observer = model.$selectedCurrency.sink { [weak self] currency in
            self?.loadOnramp(currency: currency)
        }
    }

    private let webView = WKWebView()
    private func setupViews() {
        title = lang("Buy with Card")
        
        addNavigationBar(
            title: self.title,
            closeIcon: true,
            addBackButton: { [weak self] in self?.navigationController?.popViewController(animated: true) }
        )
        
        if let navigationBar {
            navigationBar.titleLabel?.isHidden = true
            let header = HostingView(ignoreSafeArea: true, content: {
                BuyWithCardHeader(model: model)
            })
            navigationBar.addSubview(header)
            NSLayoutConstraint.activate([
                navigationBar.titleStackView.centerXAnchor.constraint(equalTo: header.centerXAnchor),
                navigationBar.titleStackView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            ])
        }
        
        webView.isOpaque = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.contentInset.top = navigationBarHeight
        webView.scrollView.delegate = self
        
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leftAnchor.constraint(equalTo: view.leftAnchor),
            webView.rightAnchor.constraint(equalTo: view.rightAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        bringNavigationBarToFront()
    }
    
    private func loadOnramp(currency: MBaseCurrency) {
        
        if currency == .RUB {
            open(url: "https://dreamwalkers.io/ru/mytonwallet/?wallet=\(AccountStore.account?.addressByChain[TON_CHAIN] ?? "")&give=CARDRUB&take=TON&type=buy")
        } else {
            guard let address = AccountStore.account?.addressByChain[model.chain.rawValue] else { return }
            Task {
                let activeTheme = ResolvedTheme(traitCollection: traitCollection)
                do {
                    let url = try await Api.getMoonpayOnrampUrl(chain: model.chain, address: address, activeTheme: activeTheme, selectedCurrency: currency).url
                    open(url: url)
                } catch {
                    showAlert(error: error)
                }
            }
        }
    }
    
    private func open(url: String) {
        if let url = URL(string: url) {
            webView.load(URLRequest(url: url))
        }
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavigationBarProgressiveBlur(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }
}
