import UIKit
import SwiftUI
import UIDapp
import UIInAppBrowser
import UIComponents
import WalletContext
import WalletCore

private let log = Log("AirRuntimeCoordinator")

@MainActor
final class AirRuntimeCoordinator: NSObject {
    private lazy var deeplinkHandler = DeeplinkHandler(deeplinkNavigator: self)
    private let lockCoordinator = AirAppLockCoordinator()
    private lazy var startupCoordinator = AirStartupCoordinator(lockCoordinator: lockCoordinator)

    private var nextDeeplink: Deeplink?
    private var nextNotification: UNNotification?
    private var _isWalletReady = false
    private var didSchedulePushPermissionRequest = false

    #if DEBUG
    @AppStorage("debug_displayLogOverlay") private var displayLogOverlayEnabled = false
    #endif

    override init() {
        super.init()
        lockCoordinator.onUnlock = { [weak self] in
            self?.flushPendingActionsIfPossible()
        }
    }

    func start() {
        WalletContextManager.delegate = self
        TonConnect.shared.start()
        StartupTrace.mark("splash.tonConnect.start")
        InAppBrowserSupport.shared.start()
        StartupTrace.mark("splash.inAppBrowserSupport.start")
        LocaleManager.rootViewController = { _ in
            RootStateCoordinator.shared.rootHostViewController
        }
        Api.prepare(on: RootStateCoordinator.shared.rootHostViewController)
        StartupTrace.mark("splash.api.prepare")
        #if DEBUG
        setDisplayLogOverlayEnabled(displayLogOverlayEnabled)
        #endif
    }

    func beginLaunch() {
        startupCoordinator.beginLaunch()
    }

    func walletCoreBootstrapDidFinish() {
        startupCoordinator.walletCoreBootstrapDidFinish()
    }

    func lockApp(animated: Bool) {
        lockCoordinator.lockApp(animated: animated)
    }

    func reset() {
        nextDeeplink = nil
        nextNotification = nil
        _isWalletReady = false
        didSchedulePushPermissionRequest = false
        lockCoordinator.reset()
    }

    func handle(url: URL, source: DeeplinkOpenSource = .generic) -> Bool {
        deeplinkHandler.handle(url, source: source)
    }

    func handle(notification: UNNotification) {
        handleNotification(notification)
    }

    private func flushPendingActionsIfPossible() {
        guard _isWalletReady, lockCoordinator.isAppUnlocked else { return }

        if let nextDeeplink {
            self.nextDeeplink = nil
            DispatchQueue.main.async {
                self.handle(deeplink: nextDeeplink)
            }
        }
        if let nextNotification {
            self.nextNotification = nil
            DispatchQueue.main.async {
                self.handleNotification(nextNotification)
            }
        }
    }
}

extension AirRuntimeCoordinator: WalletContextDelegate {
    func bridgeIsReady() {
        startupCoordinator.bridgeDidBecomeReady()
    }

    func walletIsReady(isReady: Bool) {
        _isWalletReady = isReady
        if isReady {
            StartupTrace.markOnce("wallet.ready", details: "source=AirRuntimeCoordinator")
            flushPendingActionsIfPossible()
            if !didSchedulePushPermissionRequest {
                didSchedulePushPermissionRequest = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.requestPushNotificationsPermission()
                }
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
        WalletCoreData.removeObservers()
        _isWalletReady = false
        StartupTrace.reset(flow: "restart-app")
        startupCoordinator.restart()
    }

    func handleDeeplink(url: URL, source: DeeplinkOpenSource) -> Bool {
        deeplinkHandler.handle(url, source: source)
    }

    var isWalletReady: Bool {
        _isWalletReady
    }

    var isAppUnlocked: Bool {
        lockCoordinator.isAppUnlocked
    }
}

extension AirRuntimeCoordinator: DeeplinkNavigator {
    func handle(deeplink: Deeplink) {
        if isWalletReady, isAppUnlocked {
            guard AccountStore.account != nil else {
                nextDeeplink = nil
                return
            }
            let accountContext = AccountContext(source: .current)
            defer { nextDeeplink = nil }

            switch deeplink {
            case .invoice(address: let address, amount: let amount, comment: let comment, binaryPayload: let binaryPayload, token: let token, jetton: let jetton, stateInit: let stateInit):
                AppActions.showSend(accountContext: accountContext, prefilledValues: SendPrefilledValues(
                    address: address,
                    amount: amount,
                    token: token,
                    jetton: jetton,
                    commentOrMemo: comment,
                    binaryPayload: binaryPayload,
                    stateInit: stateInit,
                ))

            case .tonConnect2(requestLink: let requestLink):
                TonConnect.shared.handleDeeplink(requestLink)

            case .walletConnect(requestLink: let requestLink):
                WalletConnect.shared.handleDeeplink(requestLink)

            case .swap(from: let from, to: let to, amountIn: let amountIn):
                AppActions.showSwap(accountContext: accountContext, defaultSellingToken: from, defaultBuyingToken: to, defaultSellingAmount: amountIn, push: nil)

            case .buyWithCard:
                AppActions.showBuyWithCard(accountContext: accountContext, chain: nil, push: nil)

            case .sell(let cell):
                handleSell(cell)

            case .stake:
                AppActions.showEarn(accountContext: accountContext, tokenSlug: nil)

            case .url(let config):
                AppActions.openInBrowser(config.url, title: config.title, injectDappConnect: config.injectDappConnect)

            case .switchToClassic:
                WalletContextManager.delegate?.switchToCapacitor()

            case .transfer:
                AppActions.showSend(accountContext: accountContext, prefilledValues: .init())

            case .receive:
                AppActions.showReceive(accountContext: accountContext, chain: nil, title: nil)

            case .explore(siteHost: let siteHost):
                if let siteHost {
                    AppActions.showExploreSite(siteHost: siteHost)
                } else {
                    AppActions.showExplore()
                }

            case .tokenSlug(slug: let slug):
                AppActions.showTokenBySlug(slug)

            case .tokenAddress(chain: let chain, tokenAddress: let tokenAddress):
                AppActions.showTokenByAddress(chain: chain, tokenAddress: tokenAddress)

            case .transaction(let chain, let txId):
                AppActions.showActivityDetailsById(chain: chain, txId: txId, showError: true)

            case .nftAddress(let nftAddress):
                AppActions.showNftByAddress(nftAddress)

            case .view(let addressOrDomainByChain):
                AppActions.showTemporaryViewAccount(addressOrDomainByChain: addressOrDomainByChain)
            }
        } else {
            nextDeeplink = deeplink
        }
    }

    func handleNotification(_ notification: UNNotification) {
        guard isWalletReady, isAppUnlocked else {
            nextNotification = notification
            return
        }
        nextNotification = nil
        guard AccountStore.account != nil else { return }
        Task {
            try await _handleNotification(notification)
        }
    }

    private func handleSell(_ deeplinkSellData: Deeplink.Sell) {
        guard let address = deeplinkSellData.depositWalletAddress?.nilIfEmpty else {
            AppActions.showError(error: DisplayError(text: lang("$missing_offramp_deposit_address")))
            return
        }

        var slug: String?
        var chain: ApiChain?
        if let normalizedCode = deeplinkSellData.baseCurrencyCode?.lowercased() {
            if normalizedCode == "ton" || normalizedCode == "toncoin" {
                slug = TONCOIN_SLUG
                chain = .ton
            } else if let token = TokenStore.getToken(slug: normalizedCode) {
                slug = token.slug
                chain = token.chain
            }
        }
        guard let slug, let chain else {
            AppActions.showError(error: DisplayError(text: lang("$unsupported_deeplink_parameter")))
            return
        }

        var amount: BigInt?
        if let baseCurrencyAmount = deeplinkSellData.baseCurrencyAmount?.nilIfEmpty,
           let token = TokenStore.getToken(slug: slug) {
            let parsedAmount = amountValue(baseCurrencyAmount, digits: token.decimals)
            if parsedAmount == 0 {
                log.error("Unable to parse amount '\(baseCurrencyAmount)'")
            } else {
                amount = parsedAmount
            }
        }

        let depositWalletAddressTag = deeplinkSellData.depositWalletAddressTag?.nilIfEmpty
        assert(depositWalletAddressTag != nil)

        let savedAddress = SavedAddress(name: "MoonPay Off-Ramp", address: address, chain: chain)
        AccountContext(source: .current).savedAddresses.save(savedAddress, addOnly: true)

        AppActions.showSend(accountContext: AccountContext(source: .current), prefilledValues: .init(
            mode: .sellToMoonpay,
            address: address,
            amount: amount,
            token: slug,
            commentOrMemo: depositWalletAddressTag
        ))
    }

    @MainActor private func _handleNotification(_ notification: UNNotification) async throws {
        let userInfo = notification.request.content.userInfo
        let action = userInfo["action"] as? String
        let address = userInfo["address"] as? String ?? ""
        guard let chain = ApiChain(rawValue: userInfo["chain"] as? String ?? "") else { return }
        let accountId = AccountStore.orderedAccounts.first(where: { $0.getAddress(chain: chain) == address })?.id
        if action == "openUrl" {
            if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
                if userInfo["isExternal"] as? Bool == true {
                    await UIApplication.shared.open(url)
                } else {
                    AppActions.openInBrowser(url, title: userInfo["title"] as? String, injectDappConnect: true)
                }
            }
            return
        }

        guard let accountId else { return }
        switch action {
        case "nativeTx", "swap":
            if chain.isSupported, let txId = userInfo["txId"] as? String {
                AppActions.showAnyAccountTx(accountId: accountId, chain: chain, txId: txId, showError: false)
            }
        case "jettonTx":
            if chain.isSupported, let txId = userInfo["txId"] as? String {
                AppActions.showAnyAccountTx(accountId: accountId, chain: chain, txId: txId, showError: false)
            } else if let slug = userInfo["slug"] as? String {
                try await AccountStore.activateAccount(accountId: accountId)
                AppActions.showTokenBySlug(slug)
            }
        case "staking":
            if let stakingId = userInfo["stakingId"] as? String {
                try await AccountStore.activateAccount(accountId: accountId)
                AppActions.showEarn(accountContext: AccountContext(accountId: accountId), tokenSlug: stakingId)
            }
        case "expiringDns":
            try await AccountStore.activateAccount(accountId: accountId)
            _ = userInfo["domainAddress"] as? String
        default:
            break
        }
    }
}

extension AirRuntimeCoordinator: UNUserNotificationCenterDelegate {
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
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
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
