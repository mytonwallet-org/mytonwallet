//
//  SplashVC.swift
//  MyTonWallet
//
//  Created by Sina on 3/16/24.
//

import UIKit
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

fileprivate func loadJSCode() -> String {
    let bundleURL = AirBundle.url(forResource: "mytonwallet-api",
                                  withExtension: "js")!
    let script = try! String(contentsOf: bundleURL)
    return script
}

class SplashVC: WViewController {

    // splash view model, responsible to initialize wallet context and get wallet info
    lazy var splashVM = SplashVM(splashVMDelegate: self)
    
    private var splashImageView = UIImageView(image: UIImage(named: "Splash"))
    
    // if app is loading, the deeplink will be stored here to be handle after app started.
    private var nextDeeplink: Deeplink? = nil

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
        isRTL = Language.current.isRtl
        
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
        }
    }

    func replaceVC(with vc: UIViewController, animationDuration: Double?) {
        guard let window = UIApplication.shared.sceneKeyWindow else { return }
        
        /* Replace RootVC to keep original iOS bottom sheet presentation animations.
         (fullscreen vc presentation makes it not work as expected and scale-down animation goes away!)*/
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
            self?.replaceVC(with: IntroVC(introModel: IntroModel(password: nil)), animationDuration: 0.5)
        }
    }

    func navigateToHome() {
        afterUnlock { [weak self] in
            self?.replaceVC(with: HomeTabBarController(), animationDuration: 0.2)
        }
    }
    
    func errorOccured() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.splashVM.startApp()
        }
    }

}

extension SplashVC: WalletContextDelegate {
    // called when api bridge (WKWebView) is ready to accept api requests. start app should be postponed until the bridge become ready to use!
    func bridgeIsReady() {
        splashVM.bridgeIsReady = true
    }
    
    /*func bridgeTerminated() {
        splashVM.bridgeIsReady = false
        restartApp()
    }*/
    
    // this function is called from WalletContext, after home vc opens up, to handle deeplinks or connect to DApps
    func walletIsReady(isReady: Bool) {
        _isWalletReady = isReady
        if isReady {
            if let nextDeeplink {
                DispatchQueue.main.async {
                    self.handle(deeplink: nextDeeplink)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.requestPushNotificationsPermission()
            }
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
                let locale = Locale(identifier: Language.current.langCode)
                isRTL = locale.isRTL
                LocaleManager.apply(locale: locale, animated: false)
                self.startApp()
            }
        } else {
            startApp()
        }
    }

    func addAnotherAccount(wordList: [String], passedPasscode: String?) -> UIViewController {
        let introModel = IntroModel(password: passedPasscode, words: wordList)
        return WordDisplayVC(introModel: introModel, wordList: wordList)
    }
    
    func importAnotherAccount(passedPasscode: String?, isLedger: Bool) async -> UIViewController {
        if isLedger {
            let introModel = IntroModel(password: passedPasscode)
            let model = await LedgerAddAccountModel()
            let vc = LedgerAddAccountVC(model: model, showBackButton: false)
            vc.onDone = { _ in
                introModel.onDone(successKind: .imported)
            }
            return vc
        } else {
            let introModel = IntroModel(password: passedPasscode)
            return ImportWalletVC(introModel: introModel)
        }
    }
    
    func viewAnyAddress() -> UIViewController {
        AddViewWalletVC(introModel: IntroModel(password: nil))
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
    
    var isCapacitorAppAvailable: Bool {
        return AirLauncher.isCapacitorAppAvailable
    }
}

// MARK: - Navigate to deeplink target screens
extension SplashVC: DeeplinkNavigator {
    func handle(deeplink: Deeplink) {
        if isWalletReady {
            guard let account = AccountStore.account else {
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
                AppActions.showEarn(token: nil)
            
            case .url(let config):
                AppActions.openInBrowser(config.url, title: config.title, injectTonConnect: config.injectTonConnectBridge)
                
            case .switchToClassic:
                WalletContextManager.delegate?.switchToCapacitor()
                
            case .transfer:
                AppActions.showSend(prefilledValues: nil)
                
            case .receive:
                AppActions.showReceive(chain: nil, showBuyOptions: nil, title: nil)

            case .explore:
                AppActions.showExplore()

            case .tokenSlug(slug: let slug):
                AppActions.showTokenBySlug(slug)

            case .tokenAddress(chain: let chain, tokenAddress: let tokenAddress):
                AppActions.showTokenByAddress(chain: chain, tokenAddress: tokenAddress)
            }
            
        } else {
            nextDeeplink = deeplink
        }
    }
}

extension SplashVC {
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
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    return SplashVC()
}
#endif
