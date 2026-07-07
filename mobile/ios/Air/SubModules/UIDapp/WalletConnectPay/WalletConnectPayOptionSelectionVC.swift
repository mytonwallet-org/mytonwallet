import Perception
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import WalletCoreTypes

final class WalletConnectPayOptionSelectionVC: WViewController, UISheetPresentationControllerDelegate {
    private var update: ApiUpdate.WalletConnectPayOptionSelection
    private var onSelect: ((String, ApiUpdate.WalletConnectPayOptionSelection) -> Void)?
    private var onSwitchAccount: ((String, ApiUpdate.WalletConnectPayOptionSelection) -> Void)?
    private var onCancel: ((ApiUpdate.WalletConnectPayOptionSelection) -> Void)?
    private var hostingController: UIHostingController<WalletConnectPayOptionSelectionView>?
    private let loadingOverlayView = UIView()
    private let loadingOverlaySpinnerContainer = UIView()
    private let loadingOverlayIndicator = WActivityIndicator()
    private var isConfirmingOptionSelection = false
    private var showsDelayedLoadingOverlay = false
    private var delayedLoadingOverlayTask: Task<Void, Never>?
    private lazy var accountSwitcher = AccountSwitcher(
        configuration: .init(accountSupport: .walletConnectPay, requiresPositiveBalance: true),
        onSelect: { [weak self] accountId in
            self?.switchAccount(accountId: accountId)
        }
    )

    @AccountContext private var account: MAccount

    init(
        update: ApiUpdate.WalletConnectPayOptionSelection,
        onSelect: @escaping (String, ApiUpdate.WalletConnectPayOptionSelection) -> Void,
        onSwitchAccount: @escaping (String, ApiUpdate.WalletConnectPayOptionSelection) -> Void,
        onCancel: @escaping (ApiUpdate.WalletConnectPayOptionSelection) -> Void
    ) {
        self._account = AccountContext(accountId: update.accountId)
        self.update = update
        self.onSelect = onSelect
        self.onSwitchAccount = onSwitchAccount
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
 
        hostingController = addHostingController(makeView(), constraints: .fill)
        setupToolbarControls()

        navigationItem.title = update.merchant.name
        addCustomNavigationBarBackground(color: .air.sheetBackground)

        setupLoadingOverlay()
        view.backgroundColor = .air.sheetBackground
        (navigationController?.sheetPresentationController ?? sheetPresentationController)?.delegate = self
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelDelayedLoadingOverlay(shouldRender: false)
    }

    deinit {
        delayedLoadingOverlayTask?.cancel()
    }

    func update(_ update: ApiUpdate.WalletConnectPayOptionSelection) {
        isConfirmingOptionSelection = false
        cancelDelayedLoadingOverlay(shouldRender: false)
        self.update = update
        $account.accountId = update.accountId
        render()
    }

    func setLoading(accountId: String) {
        isConfirmingOptionSelection = false
        cancelDelayedLoadingOverlay(shouldRender: false)
        update.accountId = accountId
        update.isLoading = true
        $account.accountId = accountId
        render()
    }

    func stopLoading() {
        isConfirmingOptionSelection = false
        cancelDelayedLoadingOverlay(shouldRender: false)
        update.isLoading = false
        render()
    }

    private func setupToolbarControls() {
        navigationItem.leftBarButtonItem = accountSwitcher.barButtonItem
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.closePressed()
        })
        configureAccountSwitcher()
    }

    private func setupLoadingOverlay() {
        loadingOverlayView.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        loadingOverlayView.alpha = 0
        loadingOverlayView.isHidden = true
        view.addSubview(loadingOverlayView)

        loadingOverlaySpinnerContainer.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlaySpinnerContainer.backgroundColor = .air.groupedItem
        loadingOverlaySpinnerContainer.layer.cornerRadius = 28
        loadingOverlaySpinnerContainer.layer.cornerCurve = .continuous
        loadingOverlayView.addSubview(loadingOverlaySpinnerContainer)

        loadingOverlayIndicator.tintColor = .label
        loadingOverlaySpinnerContainer.addSubview(loadingOverlayIndicator)

        NSLayoutConstraint.activate([
            loadingOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingOverlaySpinnerContainer.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
            loadingOverlaySpinnerContainer.centerYAnchor.constraint(equalTo: loadingOverlayView.centerYAnchor),
            loadingOverlaySpinnerContainer.widthAnchor.constraint(equalToConstant: 56),
            loadingOverlaySpinnerContainer.heightAnchor.constraint(equalToConstant: 56),
            loadingOverlayIndicator.centerXAnchor.constraint(equalTo: loadingOverlaySpinnerContainer.centerXAnchor),
            loadingOverlayIndicator.centerYAnchor.constraint(equalTo: loadingOverlaySpinnerContainer.centerYAnchor),
        ])
    }

    private func makeView() -> WalletConnectPayOptionSelectionView {
        WalletConnectPayOptionSelectionView(
            update: update,
            accountContext: $account,
            isConfirmingOptionSelection: isConfirmingOptionSelection,
            onSelect: { [weak self] optionId in
                self?.select(optionId: optionId)
            }
        )
    }

    private func render() {
        hostingController?.rootView = makeView()
        navigationItem.title = update.merchant.name
        configureAccountSwitcher()
    }

    private func configureAccountSwitcher() {
        accountSwitcher.update(selectedAccountId: update.accountId, isEnabled: update.isLoading != true)
    }

    private func switchAccount(accountId: String) {
        guard accountId != update.accountId else { return }
        onSwitchAccount?(accountId, update)
    }

    private func select(optionId: String) {
        let currentUpdate = update
        update.isLoading = true
        isConfirmingOptionSelection = true
        scheduleDelayedLoadingOverlay()
        render()
        onSelect?(optionId, currentUpdate)
    }

    private func cancel() {
        cancelDelayedLoadingOverlay(shouldRender: false)
        let currentUpdate = update
        onCancel?(currentUpdate)
        onSelect = nil
        onSwitchAccount = nil
        onCancel = nil
    }

    @objc private func closePressed() {
        cancel()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        cancel()
    }

    private func scheduleDelayedLoadingOverlay() {
        delayedLoadingOverlayTask?.cancel()
        showsDelayedLoadingOverlay = false
        delayedLoadingOverlayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled,
                  let self,
                  self.isConfirmingOptionSelection,
                  self.update.isLoading == true,
                  self.view.window != nil else {
                return
            }
            self.showsDelayedLoadingOverlay = true
            self.setLoadingOverlayVisible(true, animated: true)
        }
    }

    private func cancelDelayedLoadingOverlay(shouldRender: Bool) {
        delayedLoadingOverlayTask?.cancel()
        delayedLoadingOverlayTask = nil
        let hadOverlay = showsDelayedLoadingOverlay
        showsDelayedLoadingOverlay = false
        setLoadingOverlayVisible(false, animated: shouldRender && hadOverlay)
        if shouldRender, hadOverlay {
            render()
        }
    }

    private func setLoadingOverlayVisible(_ visible: Bool, animated: Bool) {
        if visible {
            loadingOverlayView.isHidden = false
            loadingOverlayIndicator.startAnimating(animated: false)
        }

        let changes = {
            self.loadingOverlayView.alpha = visible ? 1 : 0
        }

        let completion: (Bool) -> Void = { _ in
            if !visible {
                self.loadingOverlayIndicator.stopAnimating(animated: false)
                self.loadingOverlayView.isHidden = true
            }
        }

        if animated {
            UIView.animate(
                withDuration: visible ? 0.15 : 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes,
                completion: completion
            )
        } else {
            changes()
            completion(true)
        }
    }
}

private struct WalletConnectPayOptionSelectionView: View {
    var update: ApiUpdate.WalletConnectPayOptionSelection
    var accountContext: AccountContext
    var isConfirmingOptionSelection: Bool
    var onSelect: (String) -> Void

    private var isLoading: Bool {
        update.isLoading == true
    }

    var body: some View {
        WithPerceptionTracking {
            InsetList(topPadding: 88, spacing: 34) {
                paymentHeader
                    .padding(.horizontal, 16)

                tokenSection
                    .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .allowsHitTesting(!isLoading)
            .walletConnectPayHideTopEdgeEffect()
            .background(Color.air.sheetBackground)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var paymentHeader: some View {
        WalletConnectPayPaymentHeaderView(
            merchant: update.merchant,
            paymentInfo: update.paymentInfo
        )
    }

    private var tokenSection: some View {
        InsetSection(addDividers: !isLoading && !update.options.isEmpty, dividersInset: 62) {
            if isLoading {
                if isConfirmingOptionSelection, !update.options.isEmpty {
                    optionList
                } else {
                    loadingRow
                }
            } else if update.options.isEmpty {
                emptyRow
            } else {
                optionList
            }
        } header: {
            Text("Choose Token")
        }
    }

    @ViewBuilder
    private var optionList: some View {
        ForEach(update.options, id: \.id) { option in
            InsetButtonCell(horizontalPadding: 0, verticalPadding: 0, action: {
                onSelect(option.id)
            }) {
                WalletConnectPayOptionRow(
                    option: option,
                    displayData: optionDisplayData(for: option),
                    showsSeparator: false
                )
                .contentShape(.rect)
            }
        }
    }

    private var loadingRow: some View {
        InsetCell(horizontalPadding: 0, verticalPadding: 0) {
            VStack {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
        }
    }

    private var emptyRow: some View {
        InsetCell(horizontalPadding: 16, verticalPadding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(update.shouldSwitchWallet == true
                    ? "No matching chains"
                    : "You don't have any eligible tokens for this payment")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.air.primaryLabel)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(update.shouldSwitchWallet == true
                    ? "Select multichain wallet"
                    : "Buy, swap, or receive a supported token to continue.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func optionDisplayData(for option: WcPayPaymentOption) -> WalletConnectPayOptionDisplayData {
        walletConnectPayOptionDisplayData(
            for: option,
            accountContext: accountContext
        )
    }
}

@MainActor func walletConnectPayOptionDisplayData(
    for option: WcPayPaymentOption,
    accountContext: AccountContext
) -> WalletConnectPayOptionDisplayData {
    let token = walletConnectPayToken(for: option)
    let balance = token.map { accountContext.balances[$0.slug] ?? 0 }
    let availableText: String?
    if let token, let balance {
        availableText = formattedWalletConnectPayAvailableBalance(balance, token: token)
    } else {
        availableText = nil
    }
    let badgeLabel = token.flatMap(walletConnectPayTokenBadgeLabel)

    return WalletConnectPayOptionDisplayData(
        title: token?.displayName(strippingLabelWhenShown: badgeLabel != nil).nilIfEmpty
            ?? option.display.assetName.nilIfEmpty
            ?? option.display.assetSymbol,
        subtitle: availableText.map { "Available: \($0)" } ?? option.display.networkName ?? option.display.assetSymbol,
        amount: formattedPayOptionAmount(option),
        baseCurrencyAmount: formattedWalletConnectPayOptionBaseCurrencyAmount(option, token: token),
        badgeLabel: badgeLabel,
        token: token,
        iconUrl: token?.image?.nilIfEmpty ?? option.display.iconUrl ?? option.display.networkIconUrl,
        networkIconUrl: option.display.networkIconUrl
    )
}

struct WalletConnectPayOptionDisplayData {
    var title: String
    var subtitle: String
    var amount: String
    var baseCurrencyAmount: String?
    var badgeLabel: String?
    var token: ApiToken?
    var iconUrl: String?
    var networkIconUrl: String?
}

struct WalletConnectPayOptionRow: View {
    var option: WcPayPaymentOption
    var displayData: WalletConnectPayOptionDisplayData
    var showsSeparator: Bool

    var body: some View {
        HStack(spacing: 10) {
            tokenIcon

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 4) {
                    Text(displayData.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.air.primaryLabel)
                        .lineLimit(1)

                    if let badgeLabel = displayData.badgeLabel {
                        WalletConnectPayTokenBadge(text: badgeLabel)
                            .fixedSize()
                    }
                }
                .frame(height: 22)

                Text(displayData.subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
                    .frame(height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text(displayData.amount)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(height: 22)

                if let baseCurrencyAmount = displayData.baseCurrencyAmount {
                    Text(baseCurrencyAmount)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.air.secondaryLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(height: 18)
                }
            }
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 118, alignment: .trailing)
            .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Color.air.separator)
                    .frame(height: 0.33)
                    .padding(.leading, 62)
                    .padding(.trailing, 12)
            }
        }
    }

    private var tokenIcon: some View {
        WalletConnectPayTokenIcon(
            token: displayData.token,
            iconUrl: displayData.iconUrl,
            networkIconUrl: displayData.networkIconUrl,
            size: 40,
            chainSize: 16,
            chainBorderWidth: 1.333,
            chainHorizontalOffset: 2,
            chainVerticalOffset: 1
        )
        .frame(width: 40, height: 40)
    }
}

private struct WalletConnectPayTokenBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.air.secondaryLabel)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .frame(height: 14)
            .background(Color.air.secondaryLabel.opacity(0.15), in: .rect(cornerRadius: 4))
    }
}

private extension View {
    @ViewBuilder
    func walletConnectPayHideTopEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

private let walletConnectPayCaip2Chains: [String: ApiChain] = [
    "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp": .solana,
    "solana:4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZ": .solana,
    "solana:mainnet": .solana,
    "solana:devnet": .solana,
    "solana:testnet": .solana,
    "eip155:1": .ethereum,
    "eip155:5": .ethereum,
    "eip155:8453": .base,
    "eip155:84532": .base,
    "eip155:137": .polygon,
    "eip155:80002": .polygon,
    "eip155:42161": .arbitrum,
    "eip155:421614": .arbitrum,
    "eip155:56": .bnb,
    "eip155:97": .bnb,
    "eip155:43114": .avalanche,
    "eip155:43113": .avalanche,
    "eip155:143": .monad,
    "eip155:10143": .monad,
    "eip155:999": .hyperliquid,
    "eip155:998": .hyperliquid,
]

private func walletConnectPayToken(for option: WcPayPaymentOption) -> ApiToken? {
    if let slug = option.slug, let token = TokenStore.getToken(slug: slug) {
        return token
    }

    let chain = walletConnectPayChain(for: option.account)
    let symbol = normalizedWalletConnectPayTokenValue(option.display.assetSymbol)
    let name = normalizedWalletConnectPayTokenValue(option.display.assetName)
    let iconUrl = normalizedWalletConnectPayTokenValue(option.display.iconUrl)
    let candidates = TokenStore.tokens.values.filter { token in
        chain.map { token.chain == $0 } ?? true
    }
    let symbolMatches = candidates.filter { normalizedWalletConnectPayTokenValue($0.symbol) == symbol }

    if !iconUrl.isEmpty,
       let match = symbolMatches.first(where: { normalizedWalletConnectPayTokenValue($0.image) == iconUrl }) {
        return match
    }
    if !name.isEmpty,
       let match = symbolMatches.first(where: { normalizedWalletConnectPayTokenValue($0.name) == name }) {
        return match
    }
    if let nativeToken = chain.flatMap({ TokenStore.getToken(slug: $0.nativeToken.slug) }),
       normalizedWalletConnectPayTokenValue(nativeToken.symbol) == symbol {
        return nativeToken
    }
    if let match = symbolMatches.first {
        return match
    }
    return candidates.first { token in
        normalizedWalletConnectPayTokenValue(token.slug) == symbol
            || (!name.isEmpty && normalizedWalletConnectPayTokenValue(token.name) == name)
    }
}

private func walletConnectPayChain(for caip10Account: String) -> ApiChain? {
    let parts = caip10Account.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count >= 2 else { return nil }
    return walletConnectPayCaip2Chains["\(parts[0]):\(parts[1])"]
}

private func normalizedWalletConnectPayTokenValue(_ value: String?) -> String {
    value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
}

private func walletConnectPayTokenBadgeLabel(_ token: ApiToken) -> String? {
    guard token.tokenAddress?.nilIfEmpty != nil else {
        return nil
    }
    return token.label?.nilIfEmpty
}

private func formattedWalletConnectPayAvailableBalance(_ balance: BigInt, token: ApiToken) -> String {
    DecimalAmountFormatStyle<ApiToken>(
        preset: .defaultAdaptive,
        roundHalfUp: false,
        showSymbol: false
    )
    .format(TokenAmount(balance, token))
}

private func formattedWalletConnectPayOptionBaseCurrencyAmount(_ option: WcPayPaymentOption, token: ApiToken?) -> String? {
    if let amount = formattedPayBaseCurrencyEquivalent(option.fiatAmount, includesMatchingBaseCurrency: true) {
        return amount
    }
    guard let token, let price = token.price, price > 0 else {
        return nil
    }

    let amount = AnyDecimalAmount(
        option.amountValue,
        decimals: option.display.decimals,
        symbol: token.symbol,
        forceCurrencyToRight: true
    )
    let converted = BaseCurrencyAmount.fromDouble(amount.doubleValue * price, TokenStore.baseCurrency)
    return "\u{2248}\u{2009}\(converted.formatted(.baseCurrencyEquivalent))"
}

#if DEBUG
@available(iOS 18, *)
#Preview("WC Pay Options - Loading") {
    WalletConnectPayOptionSelectionView(
        update: WalletConnectPayOptionSelectionPreviewData.update(
            options: WalletConnectPayOptionSelectionPreviewData.optionsJson,
            isLoading: true
        ),
        accountContext: WalletConnectPayOptionSelectionPreviewData.accountContext,
        isConfirmingOptionSelection: false,
        onSelect: { _ in }
    )
}

@available(iOS 18, *)
#Preview("WC Pay Options - Empty") {
    WalletConnectPayOptionSelectionView(
        update: WalletConnectPayOptionSelectionPreviewData.update(options: "[]"),
        accountContext: WalletConnectPayOptionSelectionPreviewData.accountContext,
        isConfirmingOptionSelection: false,
        onSelect: { _ in }
    )
}

@available(iOS 18, *)
#Preview("WC Pay Options - Populated") {
    WalletConnectPayOptionSelectionView(
        update: WalletConnectPayOptionSelectionPreviewData.update(
            options: WalletConnectPayOptionSelectionPreviewData.optionsJson
        ),
        accountContext: WalletConnectPayOptionSelectionPreviewData.accountContext,
        isConfirmingOptionSelection: false,
        onSelect: { _ in }
    )
}

@MainActor
@available(iOS 18, *)
private enum WalletConnectPayOptionSelectionPreviewData {
    static let accountContext = AccountContext(source: .constant(DUMMY_ACCOUNT))

    static func update(options: String, isLoading: Bool = false) -> ApiUpdate.WalletConnectPayOptionSelection {
        try! JSONDecoder().decode(ApiUpdate.WalletConnectPayOptionSelection.self, fromString: """
        {
          "type": "walletConnectPayOptionSelection",
          "promiseId": "preview",
          "paymentLink": "wc:preview",
          "accountId": "\(DUMMY_ACCOUNT.id)",
          "merchant": {
            "name": "Preview Store",
            "iconUrl": "https://walletconnect.com/walletconnect-logo.png"
          },
          "paymentInfo": {
            "expiresAt": 1893456000,
            "amount": {
              "value": "2599000",
              "display": {
                "assetSymbol": "USDC",
                "assetName": "USD Coin",
                "decimals": 6
              },
              "fiatAmount": {
                "value": "2599",
                "decimals": 2,
                "slug": "USD"
              }
            }
          },
          "options": \(options),
          "isLoading": \(isLoading)
        }
        """)
    }

    static let optionsJson = """
    [
      {
        "id": "usdc-solana",
        "account": "solana:mainnet:preview",
        "amountValue": "2599000",
        "slug": "solana-usdc",
        "display": {
          "assetSymbol": "USDC",
          "assetName": "USD Coin",
          "decimals": 6,
          "networkName": "Solana"
        },
        "fiatAmount": {
          "value": "2599",
          "decimals": 2,
          "slug": "USD"
        }
      },
      {
        "id": "usdt-ton",
        "account": "ton:mainnet:preview",
        "amountValue": "2599000",
        "slug": "ton-usdt",
        "display": {
          "assetSymbol": "USDT",
          "assetName": "Tether",
          "decimals": 6,
          "networkName": "TON"
        }
      }
    ]
    """
}
#endif
