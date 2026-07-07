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
    private var nextSystemActions: [AirSystemAction] = []
    private var _isWalletReady = false
    private var didSchedulePushPermissionRequest = false
    private var startupImportError: Error?

    #if DEBUG
    @AppStorage("debug_displayLogOverlay") private var displayLogOverlayEnabled = false
    #endif

    override init() {
        super.init()
        lockCoordinator.onUnlock = { [weak self] in
            self?.flushPendingActionsIfPossible()
            self?.presentStartupImportErrorIfNeeded()
        }
    }

    func start() {
        WalletContextManager.delegate = self
        if #available(iOS 18.4, *) {
            TokenSpotlightIndexer.shared.start()
        }
        TonConnect.shared.start()
        StartupTrace.mark("splash.tonConnect.start")
        WalletConnect.shared.start()
        StartupTrace.mark("splash.walletConnect.start")
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

    func walletCoreBootstrapDidFinish() async {
        #if DEBUG && targetEnvironment(simulator)
        startupImportError = await AppWalletsExport.runStartupImportIfConfigured()
        #endif
        
        startupCoordinator.walletCoreBootstrapDidFinish()
        presentStartupImportErrorIfNeeded()
    }

    func lockApp(animated: Bool) {
        lockCoordinator.lockApp(animated: animated)
    }

    func reset() {
        nextDeeplink = nil
        nextNotification = nil
        nextSystemActions.removeAll()
        _isWalletReady = false
        didSchedulePushPermissionRequest = false
        startupImportError = nil
        lockCoordinator.reset()
    }

    private func presentStartupImportErrorIfNeeded() {
        guard let error = startupImportError else { return }
        guard lockCoordinator.isAppUnlocked else { return }
        guard topViewController() != nil else { return }
        startupImportError = nil
        AppActions.showError(error: error)
    }

    func handle(url: URL, source: DeeplinkOpenSource = .generic) -> Bool {
        deeplinkHandler.handle(url, source: source)
    }

    func handle(notification: UNNotification) {
        handleNotification(notification)
    }

    func handle(systemAction: AirSystemAction) {
        if isWalletReady, lockCoordinator.isAppUnlocked {
            perform(systemAction)
        } else {
            nextSystemActions.append(systemAction)
        }
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
        if !nextSystemActions.isEmpty {
            let actions = nextSystemActions
            nextSystemActions.removeAll()
            DispatchQueue.main.async {
                for action in actions {
                    self.perform(action)
                }
            }
        }
    }

    private func perform(_ systemAction: AirSystemAction) {
        guard AccountStore.account != nil else { return }

        switch systemAction {
        case .scanQR:
            AppActions.scanAndHandleQR(accountContext: AccountContext(source: .current))
        case let .openReceive(accountId, chain):
            Task {
                await openReceive(accountId: accountId, chain: chain)
            }
        case let .openToken(accountId, tokenSlug):
            Task {
                await openToken(accountId: accountId, tokenSlug: tokenSlug)
            }
        case let .sendToken(accountId, recipient, tokenSlug, amount, comment):
            Task {
                await sendToken(
                    accountId: accountId,
                    recipient: recipient,
                    tokenSlug: tokenSlug,
                    amount: amount,
                    comment: comment
                )
            }
        }
    }

    private func openReceive(accountId: String?, chain chainRawValue: String?) async {
        let account: MAccount

        if let accountId, accountId != AccountStore.accountId {
            do {
                account = try await AccountStore.activateAccount(accountId: accountId)
            } catch {
                return
            }
        } else if let currentAccount = AccountStore.account {
            account = currentAccount
        } else {
            return
        }

        let requestedChain = chainRawValue.flatMap(ApiChain.init(rawValue:))
        let chain = account.supports(chain: requestedChain) ? requestedChain : nil
        AppActions.showReceive(accountContext: AccountContext(source: .current), chain: chain)
    }

    private func openToken(accountId: String?, tokenSlug: String) async {
        guard await activateAccountIfNeeded(accountId: accountId) != nil else { return }
        guard let token = TokenStore.getToken(slug: tokenSlug) ?? ApiChain.allCases.first(where: { $0.nativeToken.slug == tokenSlug })?.nativeToken else { return }
        AppActions.showToken(accountSource: .current, token: token, isInModal: false)
    }

    private func sendToken(
        accountId: String?,
        recipient: AirSendTokenRecipient?,
        tokenSlug: String?,
        amount: Double?,
        comment: String?
    ) async {
        guard let account = await activateAccountIfNeeded(accountId: accountId) else { return }

        let accountContext = accountId == nil
            ? AccountContext(source: .current)
            : AccountContext(accountId: account.id)
        let selectedToken = tokenSlug
            .flatMap(TokenStore.getToken(slug:))
            .flatMap { account.supports(chain: $0.chain) ? $0 : nil }
        let recipientToken = tokenForRecipient(recipient, senderAccount: account, selectedToken: selectedToken, accountContext: accountContext)
        let amountToken = selectedToken ?? amount.flatMap { _ in bestToken(accountContext: accountContext) }
        let amountValue = amount
            .flatMap { $0 > 0 ? $0 : nil }
            .flatMap { amount in amountToken.map { doubleToBigInt(amount, decimals: $0.decimals) } }
        let prefilledToken = selectedToken ?? (amountValue == nil ? recipientToken : amountToken)
        let address = addressOrDomain(for: recipient, token: prefilledToken)

        AppActions.showSend(
            accountContext: accountContext,
            prefilledValues: SendPrefilledValues(
                address: address,
                amount: amountValue,
                token: prefilledToken?.slug,
                commentOrMemo: comment?.nilIfEmpty
            )
        )
    }

    private func tokenForRecipient(
        _ recipient: AirSendTokenRecipient?,
        senderAccount: MAccount,
        selectedToken: ApiToken?,
        accountContext: AccountContext
    ) -> ApiToken? {
        guard let recipient else { return nil }

        if let selectedToken {
            return selectedToken
        }

        switch recipient.kind {
        case .account:
            guard let accountId = recipient.accountId, let recipientAccount = AccountStore.accountsById[accountId] else {
                return nil
            }
            if let bestToken = bestToken(accountContext: accountContext), recipientAccount.supports(chain: bestToken.chain) {
                return bestToken
            }
            return senderAccount.supportedChains
                .first { recipientAccount.supports(chain: $0) }
                .map(TokenStore.getNativeToken(chain:))
        case .savedAddress:
            guard let chain = recipient.chain.flatMap(ApiChain.init(rawValue:)), senderAccount.supports(chain: chain) else {
                return nil
            }
            return TokenStore.getNativeToken(chain: chain)
        case .rawAddressOrDomain:
            return nil
        }
    }

    private func addressOrDomain(for recipient: AirSendTokenRecipient?, token: ApiToken?) -> String? {
        guard let recipient else { return nil }

        switch recipient.kind {
        case .account:
            guard
                let accountId = recipient.accountId,
                let token,
                let account = AccountStore.accountsById[accountId],
                account.supports(chain: token.chain)
            else {
                return nil
            }
            return account.getAddress(chain: token.chain)?.nilIfEmpty
        case .savedAddress:
            guard
                let addressOrDomain = recipient.addressOrDomain?.nilIfEmpty,
                let chain = recipient.chain.flatMap(ApiChain.init(rawValue:))
            else {
                return nil
            }
            if let token, token.chain != chain {
                return nil
            }
            return addressOrDomain
        case .rawAddressOrDomain:
            return recipient.addressOrDomain?.nilIfEmpty
        }
    }

    private func activateAccountIfNeeded(accountId: String?) async -> MAccount? {
        guard let accountId, accountId != AccountStore.accountId else {
            return AccountStore.account
        }

        do {
            return try await AccountStore.activateAccount(accountId: accountId)
        } catch {
            return nil
        }
    }

    private func bestToken(accountContext: AccountContext) -> ApiToken? {
        let account = accountContext.account
        let preferredTokenSlug = ApiToken.defaultSlugs(forNetwork: account.network, account: account).first ?? TONCOIN_SLUG
        var maxBalance: Double = 0
        var tokens: [String: Double] = [:]

        for (tokenSlug, balance) in accountContext.balances {
            let tokenBalance = MTokenBalance(tokenSlug: tokenSlug, balance: balance, isStaking: false)
            guard let baseCurrencyBalance = tokenBalance.toBaseCurrency, baseCurrencyBalance > 0 else { continue }
            maxBalance = max(maxBalance, baseCurrencyBalance)
            tokens[tokenSlug] = baseCurrencyBalance
        }

        let mostValuableTokenSlugs = tokens.filter { _, value in value == maxBalance }.keys.sorted()
        let tokenSlug = if let first = mostValuableTokenSlugs.first, !mostValuableTokenSlugs.contains(preferredTokenSlug) {
            first
        } else {
            preferredTokenSlug
        }
        return TokenStore.getToken(slug: tokenSlug)
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
            presentStartupImportErrorIfNeeded()
            if #available(iOS 18.4, *) {
                TokenSpotlightIndexer.shared.reindexSoon()
            }
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
            case .agent:
                AppActions.showAgent()

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

            case .portfolio:
                AppActions.showPortfolio(accountContext: accountContext)

            case .url(let url, let title, let injectDappConnect):
                AppActions.openInBrowser(url, title: title, injectDappConnect: injectDappConnect)

            case .switchToClassic:
                WalletContextManager.delegate?.switchToCapacitor()

            case .send(chain: _, address: let address, amount: let amount, comment: let comment, binaryPayload: let binaryPayload, tokenSlug: let tokenSlug, stateInit: let stateInit):
                AppActions.showSend(accountContext: accountContext, prefilledValues: SendPrefilledValues(
                    address: address,
                    amount: amount,
                    token: tokenSlug,
                    commentOrMemo: comment,
                    binaryPayload: binaryPayload,
                    stateInit: stateInit,
                ))

            case .transfer:
                AppActions.showSend(accountContext: accountContext, prefilledValues: .init())

            case .receive:
                AppActions.showReceive(accountContext: accountContext, chain: nil)

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

            case .view(let network, let addressOrDomainByChain):
                AppActions.showTemporaryViewAccount(network: network, addressOrDomainByChain: addressOrDomainByChain)

            case .settings(let section):
                AppActions.showSettings(section: section)
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
        let payload = PushNotificationPayload(userInfo: notification.request.content.userInfo)
        let accountId = payload.address.flatMap { address in
            AccountStore.orderedAccounts.first { $0.getAddress(chain: payload.chain) == address }?.id
        }

        if payload.action == .openUrl {
            try await handleOpenUrlNotification(payload, accountId: accountId)
            return
        }

        guard let accountId else { return }
        switch payload.action {
        case .nativeTx, .swap:
            if payload.chain.isSupported, let txId = payload.txId {
                AppActions.showAnyAccountTx(accountId: accountId, chain: payload.chain, txId: txId, showError: false)
            }
        case .jettonTx:
            if payload.chain.isSupported, let txId = payload.txId {
                AppActions.showAnyAccountTx(accountId: accountId, chain: payload.chain, txId: txId, showError: false)
            } else if let slug = payload.slug {
                try await AccountStore.activateAccount(accountId: accountId)
                AppActions.showTokenBySlug(slug)
            }
        case .staking:
            if let stakingId = payload.stakingId {
                try await AccountStore.activateAccount(accountId: accountId)
                AppActions.showEarn(accountContext: AccountContext(accountId: accountId), tokenSlug: stakingId)
            }
        case .expiringDns:
            try await AccountStore.activateAccount(accountId: accountId)
            if let domainAddress = payload.domainAddress {
                AppActions.showRenewDomain(accountSource: .accountId(accountId), nftsToRenew: [domainAddress])
            }
        default:
            break
        }
    }

    private func handleOpenUrlNotification(_ payload: PushNotificationPayload, accountId: String?) async throws {
        guard let url = payload.url else { return }
        if let accountId {
            try await AccountStore.activateAccount(accountId: accountId)
        }
        if deeplinkHandler.handle(url) {
            return
        }
        if payload.isExternal || url.isTelegramURL {
            await UIApplication.shared.open(url)
        } else {
            AppActions.openInBrowser(url, title: payload.title, injectDappConnect: true)
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
