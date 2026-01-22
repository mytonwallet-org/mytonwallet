//
//  SplashVC.swift
//  MyTonWallet
//
//  Created by Sina on 3/16/24.
//

import UIKit
import SwiftUI
import Ledger
import UICreateWallet
import UIPasscode
import UIHome
import UIDapp
import UIInAppBrowser
import UIComponents
import WalletContext
import WalletCore

private let log = Log("SplashVC")

class SplashVC: WViewController {

    // splash view model, responsible to initialize wallet context and get wallet info
    lazy var splashVM = SplashVM(splashVMDelegate: self)
    
    private var splashImageView = UIImageView(image: UIImage(named: "Splash"))
    
    // if app is loading, the deeplink will be stored here to be handle after app started.
    private var nextDeeplink: Deeplink? = nil
    private var nextNotification: UNNotification? = nil
    
    #if DEBUG
    @AppStorage("debug_displayLogOverlay") private var displayLogOverlayEnabled = false
    #endif
    
    private var _isWalletReady = false

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    private func setupViews() {
        splashImageView.contentMode = .scaleAspectFill
        
        splashImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splashImageView)
        NSLayoutConstraint.activate([
            splashImageView.topAnchor.constraint(equalTo: view.topAnchor),
            splashImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splashImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splashImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        updateTheme()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        WalletContextManager.delegate = self
        TonConnect.shared.start()
        InAppBrowserSupport.shared.start()
        
        LocaleManager.rootViewController = { [weak self] window in
            return self
        }
        
        // prepare the core logic functions to work on splash vc
        Api.prepare(on: self)
    }

    override func updateTheme() {
        view.backgroundColor = .green // WTheme.background
    }
    
    private var firstTime = true
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if firstTime {
            firstTime = false
            splashVM.startApp()
            #if DEBUG
            setDisplayLogOverlayEnabled(displayLogOverlayEnabled)
            #endif
        }
    }

    func replaceVC(with vc: UIViewController, animationDuration: Double?) {
        let rootVC = vc is UITabBarController ? vc : WNavigationController(rootViewController: vc)
        AppActions.transitionToNewRootViewController(rootVC, animationDuration: animationDuration)
    }
    
    // start the app by initializing the wallet context and getting the wallet info
    private func startApp() {
        UIApplication.shared.delegate?.window??.backgroundColor = UIColor(named: "SplashBackgroundColor", in: AirBundle, compatibleWith: nil)!
        splashVM.startApp()
    }

    // present unlockVC if required and continue tasks assigned, after unlock
    func afterUnlock(completion: @escaping () -> Void) {
        if AirLauncher.appUnlocked {
            completion()
            return
        }

        if AuthSupport.accountsSupportAppLock {
            // should unlock
            let unlockVC = UnlockVC(title: lang("Wallet is Locked"),
                                    replacedTitle: lang("Enter your Wallet Passcode"),
                                    animatedPresentation: true,
                                    dissmissWhenAuthorized: false,
                                    shouldBeThemedLikeHeader: true) { _ in
                AirLauncher.appUnlocked = true
                completion()
            }
            unlockVC.modalPresentationStyle = .overFullScreen
            unlockVC.modalTransitionStyle = .crossDissolve
            unlockVC.modalPresentationCapturesStatusBarAppearance = true
            // present unlock animated
            present(unlockVC, animated: true)
            // try biometric unlock after appearance of the `UnlockVC`
            unlockVC.tryBiometric()
        } else {
            // app is not locked
            AirLauncher.appUnlocked = true
            completion()
        }
    }
}

extension SplashVC: SplashVMDelegate {
    
    func navigateToIntro() {
        afterUnlock { [weak self] in
            self?.replaceVC(with: IntroVC(introModel: IntroModel(network: .mainnet, password: nil)), animationDuration: 0.5)
        }
    }

    func navigateToHome() {
        afterUnlock { [weak self] in
            self?.replaceVC(with: HomeTabBarController(), animationDuration: 0.2)
        }
    }
}

extension SplashVC: WalletContextDelegate {
    // called when api bridge (WKWebView) is ready to accept api requests. start app should be postponed until the bridge become ready to use!
    func bridgeIsReady() {
        splashVM.bridgeIsReady = true
    }
    
    // this function is called from WalletContext, after home vc opens up, to handle deeplinks or connect to DApps
    func walletIsReady(isReady: Bool) {
        _isWalletReady = isReady
        if isReady {
            if let nextDeeplink {
                DispatchQueue.main.async {
                    self.handle(deeplink: nextDeeplink)
                }
            }
            if let nextNotification {
                DispatchQueue.main.async {
                    self.handleNotification(nextNotification)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.requestPushNotificationsPermission()
            }
            UNUserNotificationCenter.current().delegate = self
        }
    }
    
    func switchToCapacitor() {
        log.info("switch to capacitor")
        Task {
            await AirLauncher.switchToCapacitor()
        }
    }
    
    func restartApp() {
        if topViewController() !== self {
            WalletCoreData.removeObservers()
            _isWalletReady = false
            
            // Reset RootVC to self
            guard let window = UIApplication.shared.sceneKeyWindow else { return }
            UIView.transition(with: window, duration: 0.5,
                              options: .transitionCrossDissolve,
                              animations: {
                window.rootViewController = self
            }) { _ in
                self.startApp()
            }
        } else {
            startApp()
        }
    }

    func handleDeeplink(url: URL) -> Bool {
        return AirLauncher.deeplinkHandler?.handle(url) ?? false
    }
    
    var isWalletReady: Bool {
        return _isWalletReady
    }
    
    var isAppUnlocked: Bool {
        return AirLauncher.appUnlocked
    }
}

// MARK: - Navigate to deeplink target screens
extension SplashVC: DeeplinkNavigator {
    func handle(deeplink: Deeplink) {
        if isWalletReady, isAppUnlocked {
            guard AccountStore.account != nil else {
                // we ignore depplinks when wallet is not ready yet, wallet gets ready when home page appears
                nextDeeplink = nil
                return
            }
            defer { nextDeeplink = nil }
            
            switch deeplink {
            case .invoice(address: let address, amount: let amount, comment: let comment, binaryPayload: let binaryPayload, token: let token, jetton: let jetton, stateInit: let stateInit):
                let addressObj = MRecentAddress(chain: "ton",
                                                address: address,
                                                addressAlias: nil,
                                                timstamp: Date().timeIntervalSince1970)
                RecentAddressesHelper.saveRecentAddress(accountId: AccountStore.accountId!, recentAddress: addressObj)
                
                AppActions.showSend(prefilledValues: SendPrefilledValues(
                    address: addressObj.address,
                    amount: amount,
                    token: token,
                    jetton: jetton,
                    commentOrMemo: comment,
                    binaryPayload: binaryPayload,
                    stateInit: stateInit,
                ))

            case .tonConnect2(requestLink: let requestLink):
                TonConnect.shared.handleDeeplink(requestLink)
                
            case .swap(from: let from, to: let to, amountIn: let amountIn):
                AppActions.showSwap(defaultSellingToken: from, defaultBuyingToken: to, defaultSellingAmount: amountIn, push: nil)
                
            case .buyWithCard:
                AppActions.showBuyWithCard(chain: nil, push: nil)
                
            case .stake:
                AppActions.showEarn(tokenSlug: nil)
            
            case .url(let config):
                AppActions.openInBrowser(config.url, title: config.title, injectTonConnect: config.injectTonConnectBridge)
                
            case .switchToClassic:
                WalletContextManager.delegate?.switchToCapacitor()
                
            case .transfer:
                AppActions.showSend(prefilledValues: nil)
                
            case .receive:
                AppActions.showReceive(chain: nil, title: nil)

            case .explore:
                AppActions.showExplore()

            case .tokenSlug(slug: let slug):
                AppActions.showTokenBySlug(slug)

            case .tokenAddress(chain: let chain, tokenAddress: let tokenAddress):
                AppActions.showTokenByAddress(chain: chain, tokenAddress: tokenAddress)
                
            case .transaction(let chain, let txId):
                AppActions.showActivityDetailsById(chain: chain, txId: txId, showError: true)
                
            case .view(let addressOrDomainByChain):
                AppActions.showTemporaryViewAccount(addressOrDomainByChain: addressOrDomainByChain)
            }
            
        } else {
            nextDeeplink = deeplink
        }
    }
    
    func handleNotification(_ notification: UNNotification) {
        guard isWalletReady, isAppUnlocked else {
            self.nextNotification = notification
            return
        }
        self.nextNotification = nil
        guard AccountStore.account != nil else { return }
        Task {
            try await _handleNotification(notification)
        }
    }
    
    @MainActor private func _handleNotification(_ notification: UNNotification) async throws {
        let userInfo = notification.request.content.userInfo
        let action = userInfo["action"] as? String
        let address = userInfo["address"] as? String ?? ""
        let chain = ApiChain(rawValue: userInfo["chain"] as? String ?? "") ?? FALLBACK_CHAIN
        let accountId = AccountStore.orderedAccounts.first(where: { $0.addressByChain[chain.rawValue] == address })?.id
        if action == "openUrl" {
            if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
                if userInfo["isExternal"] as? Bool == true {
                    await UIApplication.shared.open(url)
                } else {
                    AppActions.openInBrowser(url, title: userInfo["title"] as? String, injectTonConnect: true)
                }
            }
            return
        }
        
        guard let accountId else { return }
        switch action {
        case "nativeTx", "swap":
            if let txId = userInfo["txId"] as? String {
                AppActions.showAnyAccountTx(accountId: accountId, chain: chain, txId: txId, showError: false)
            }
        case "jettonTx":
            if let txId = userInfo["txId"] as? String {
                AppActions.showAnyAccountTx(accountId: accountId, chain: chain, txId: txId, showError: false)
            } else if let slug = userInfo["slug"] as? String {
                try await AccountStore.activateAccount(accountId: accountId)
                AppActions.showTokenBySlug(slug)
            }
        case "staking":
            if let stakingId = userInfo["stakingId"] as? String {
                try await AccountStore.activateAccount(accountId: accountId)
                AppActions.showEarn(tokenSlug: stakingId)
            }
        case "expiringDns":
            try await AccountStore.activateAccount(accountId: accountId)
            let domainAddress = userInfo["domainAddress"] as? String
            _ = domainAddress
            // TODO: openDomainRenewalModal
        default:
            break
        }
    }
}

extension SplashVC: UNUserNotificationCenterDelegate {
    private func requestPushNotificationsPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .denied:
                break
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
                break
            case .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        handleNotification(response.notification)
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    return SplashVC()
}
#endif
