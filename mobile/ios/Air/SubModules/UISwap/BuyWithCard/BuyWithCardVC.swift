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

public class BuyWithCardVC: WViewController {
    
    private let chain: ApiChain
    public init(chain: ApiChain) {
        self.chain = chain
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private let webView = WKWebView()
    private func setupViews() {
        title = lang("Buy with Card")
        addCloseToNavBar()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leftAnchor.constraint(equalTo: view.leftAnchor),
            webView.rightAnchor.constraint(equalTo: view.rightAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if ConfigStore.shared.config?.countryCode == "RU" {
            open(url: "https://dreamwalkers.io/ru/mytonwallet/?wallet=\(AccountStore.account?.tonAddress ?? "")&give=CARDRUB&take=TON&type=buy")
            return
        }
        
        guard let address = AccountStore.account?.addressByChain[chain.rawValue] else { return }
        Task {
            let activeTheme = AppStorageHelper.activeNightMode
            print(chain, address, activeTheme)
            do {
                let url = try await Api.getMoonpayOnrampUrl(chain: chain, address: address, activeTheme: activeTheme).url
                open(url: url)
            } catch {
                print(error)
                showAlert(error: error)
            }
        }
    }
    
    private func open(url: String) {
        if let url = URL(string: url) {
            webView.load(URLRequest(url: url))
        }
    }
}
