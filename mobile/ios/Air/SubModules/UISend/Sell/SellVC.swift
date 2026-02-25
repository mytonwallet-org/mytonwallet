import WebKit
import UIKit
import UIComponents
import WalletCore
@preconcurrency import WalletContext

public class SellVC: WViewController, UIScrollViewDelegate {
    private enum State {
        case idle
        case loadingMoonpayUrl
        case stoppedForFatalError
        case openingMoonpayUrl
        case initiallyLoaded
    }
    
    private var state = State.idle {
        didSet {
            if state != oldValue {
                updateState()
            }
        }
    }
    
    private let account: MAccount
    private let tokenSlug: String
    private let webView = WKWebView()
    private let activityIndicator = WActivityIndicator()
    private var hasCompletedInitialWebViewLoad = false
    
    public init(account: MAccount, tokenSlug: String) {
        self.tokenSlug = tokenSlug
        self.account = account
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        updateState()
        
        // Let's wait for screen opened a little
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.getOfframpUrl()
        }
    }
    
    private func setupViews() {
        title = lang("Sell on Card")
        
        addNavigationBar(title: title, closeIcon: true)
        if let navigationBar {
            navigationBar.titleLabel?.isHidden = true
            let titleLabel = UILabel()
            titleLabel.text = lang("Sell on Card")
            titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            navigationBar.addSubview(titleLabel)
            NSLayoutConstraint.activate([
                navigationBar.titleStackView.centerXAnchor.constraint(equalTo: titleLabel.centerXAnchor),
                navigationBar.titleStackView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            ])
        }
        
#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif
        webView.isOpaque = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.contentInset.top = navigationBarHeight
        webView.scrollView.delegate = self
        webView.navigationDelegate = self
        
        view.addSubview(webView)
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leftAnchor.constraint(equalTo: view.leftAnchor),
            webView.rightAnchor.constraint(equalTo: view.rightAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        bringNavigationBarToFront()
    }
    
    private func updateState() {
        var showActivity = false
        switch state {
        case .idle, .loadingMoonpayUrl, .openingMoonpayUrl:
            showActivity = true
            
        case .stoppedForFatalError, .initiallyLoaded:
            break
        }
        
        if showActivity {
            activityIndicator.startAnimating(animated: true)
        } else {
            activityIndicator.stopAnimating(animated: true)
        }
    }
    
    private func showDisplayErrorThenDismiss(_ text: String) {
        showErrorThenDismiss(DisplayError(text: text))
    }
    
    private func showErrorThenDismiss(_ error: Error) {
        state = .stoppedForFatalError
        showAlert(error: error) { [weak self] in
            self?.dismiss(animated: true)
        }
    }
    
    private func getOfframpUrl() {
        guard let chain = getChainBySlug(tokenSlug), let address = account.getAddress(chain: chain) else {
            showDisplayErrorThenDismiss(lang("$missing_offramp_deposit_address"))
            return
        }
        
        guard let token = TokenStore.getToken(slug: tokenSlug) else {
            showDisplayErrorThenDismiss(lang("Token not found"))
            return
        }
        
        Task { @MainActor in
            do {
                // Get max available amount to transfer
                let amountString: String
                do {
                    let balance = BalanceStore.getAccountBalances(accountId: account.id)[tokenSlug] ?? .zero
                    let chainConfig = getChainConfig(chain: chain)
                    var amount: BigInt?
                    if chainConfig.canTransferFullNativeBalance {
                        amount = balance
                    } else {
                        do {
                            let draftResult = try await Api.checkTransactionDraft(chain: chain, options: .init(
                                accountId: account.id,
                                toAddress: chainConfig.feeCheckAddress,
                                amount: balance,
                                payload: nil,
                                stateInit: nil,
                                tokenAddress: nil,
                                allowGasless: nil
                            ))
                            let explainedFee = explainApiTransferFee(input: draftResult, tokenSlug: tokenSlug)
                            amount = getMaxTransferAmount(.init(
                                tokenBalance: balance,
                                tokenSlug: tokenSlug,
                                fullFee: explainedFee.fullFee?.terms,
                                canTransferFullBalance: explainedFee.canTransferFullBalance
                            ))
                        } catch {
                            amount = balance
                        }
                    }
                    guard var amount, amount > 0 else {
                        throw DisplayError(text: lang("Insufficient balance"))
                    }
                    if let limit = Moonpay.Offramp.limitsBySlug[tokenSlug] {
                        let limitAsBigInt = doubleToBigInt(limit, decimals: token.decimals)
                        if amount > limitAsBigInt {
                            amount = limitAsBigInt
                        }
                    }
                    amountString = bigIntToDoubleString(amount, decimals: token.decimals)
                }
                
                // Get the best currency
                let preferredCurrency = TokenStore.baseCurrency;
                let currency = Moonpay.Offramp.supportedCurrencies.first { $0 == preferredCurrency } ?? Moonpay.Offramp.supportedCurrencies.first!
                
                // fetch signed moonpay url
                let result = try await Api.getMoonpayOfframpUrl(
                    params: .init(
                        chain: chain,
                        address: address,
                        theme: ResolvedTheme(traitCollection: traitCollection),
                        currency: currency,
                        amount: amountString,
                        baseUrl: SHORT_UNIVERSAL_URL + "offramp/"
                    )
                )
                openOfframpUrl(result.url)
            } catch {
                showErrorThenDismiss(error)
            }
        }
    }
    
    private func openOfframpUrl(_ url: String) {
        guard let url = URL(string: url) else {
            showDisplayErrorThenDismiss("An error on the server side. Please try again.")
            return
        }
        
        state = .openingMoonpayUrl
        webView.load(URLRequest(url: url))
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavigationBarProgressiveBlur(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }
    
}

extension SellVC: WKNavigationDelegate {
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let handled = WalletContextManager.delegate?.handleDeeplink(url: url) ?? false
            if handled {
                decisionHandler(.cancel)
                return
            }
        }
        
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state = .initiallyLoaded
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        showErrorThenDismiss(error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        showErrorThenDismiss(error)
    }
}
