import UIKitNavigation
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let REQUIRED_TON_FOR_MINT_CARD_FEE = BigInt(65_000_000)
private let SWAP_AMOUNT_RESERVE_MULTIPLIER = BigInt(105)

public final class MintCardVC: WViewController {
    private static var initialPreload: Task<Void, Never>?

    public static func preloadMedia() {
        guard initialPreload == nil, AppStorageHelper.animations, !UIAccessibility.isReduceMotionEnabled else { return }
        initialPreload = Task(priority: .utility) {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, UIApplication.shared.applicationState == .active else {
                initialPreload = nil
                return
            }
            _ = await MintCardVideoCache.shared.fileURL(for: .standard, priority: .utility)
        }
    }

    private let accountContext: AccountContext
    private let sheet = MintCardView(frame: .zero)
    private var observation: ObserveToken?
    private var notifications: [NSObjectProtocol] = []
    private var isVisible = false
    private var previousNavigationBarStyle: UIUserInterfaceStyle = .unspecified

    public init(accountContext: AccountContext) {
        self.accountContext = accountContext
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .air.sheetBackground
        configureNavigationItemWithTransparentBackground()
        addCloseNavigationItemIfNeeded()
        navigationItem.rightBarButtonItem?.tintColor = .white
        sheet.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheet)
        NSLayoutConstraint.activate([
            sheet.topAnchor.constraint(equalTo: view.topAnchor),
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        sheet.onUpgrade = { [weak self] type in
            guard let self, !sheet.isSubmitting else { return }
            sheet.isSubmitting = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { sheet.isSubmitting = false }
                await upgrade(type: type)
            }
        }
        observation = observe { [weak self] in
            guard let self else { return }
            sheet.configure(cardsInfo: accountContext.config.cardsInfo, token: TokenStore.getToken(slug: MYCOIN_SLUG))
        }
        for name in [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification, UIAccessibility.reduceMotionStatusDidChangeNotification, AppStorageHelper.animationsChangedNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let isResigning = notification.name == UIApplication.willResignActiveNotification
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    sheet.setPlaybackActive(isVisible && !isResigning && UIApplication.shared.applicationState == .active)
                }
            })
        }
    }

    isolated deinit {
        for notification in notifications { NotificationCenter.default.removeObserver(notification) }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavigationBarStyle = navigationController?.navigationBar.overrideUserInterfaceStyle ?? .unspecified
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        sheet.setPlaybackActive(UIApplication.shared.applicationState == .active)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = previousNavigationBarStyle
        isVisible = false
        sheet.setPlaybackActive(false)
    }

    private func upgrade(type: ApiMtwCardType) async {
        let account = accountContext.account
        guard account.supportsSend else {
            AppActions.showError(error: DisplayError(text: lang("Read-only account")))
            return
        }
        guard let cardInfo = accountContext.config.cardsInfo?[type], cardInfo.notMinted > 0,
              let mycoin = TokenStore.getToken(slug: MYCOIN_SLUG),
              let tokenAddress = mycoin.tokenAddress?.nilIfEmpty,
              cardInfo.all > 0, cardInfo.price.isFinite, cardInfo.price > 0
        else {
            AppActions.showError(error: DisplayError(text: lang("Unexpected error")))
            return
        }

        let amount = doubleToBigInt(cardInfo.price, decimals: mycoin.decimals)
        guard amount > 0 else {
            AppActions.showError(error: DisplayError(text: lang("Unexpected error")))
            return
        }
        let mycoinBalance = accountContext.balances[MYCOIN_SLUG] ?? 0
        if mycoinBalance < amount {
            let missingAmount = amount - mycoinBalance
            let missingAmountWithReserve = missingAmount * SWAP_AMOUNT_RESERVE_MULTIPLIER / 100
            let buyingAmount = bigIntToDouble(amount: missingAmountWithReserve, decimals: mycoin.decimals)
            dismiss(animated: true) { [accountContext] in
                Task {
                    await AppActions.showSwap(
                        accountContext: accountContext,
                        defaultSellingToken: TONCOIN_SLUG,
                        defaultBuyingToken: MYCOIN_SLUG,
                        defaultSellingAmount: nil,
                        defaultBuyingAmount: buyingAmount,
                        push: nil
                    )
                }
            }
            return
        }

        let toncoinBalance = accountContext.balances[TONCOIN_SLUG] ?? 0
        guard toncoinBalance >= REQUIRED_TON_FOR_MINT_CARD_FEE else {
            showAlert(
                title: lang("Insufficient Fee"),
                text: L10n.pleaseTopUpYourTokenBalance(token: ApiToken.TONCOIN.symbol),
                button: lang("OK")
            )
            return
        }

        let submission = MintCardSubmission(
            account: account,
            token: mycoin,
            tokenAddress: tokenAddress,
            cardType: type,
            amount: amount
        )
        Haptics.prepare(.success)
        await executeMintCard(submission, on: self)
    }
}
