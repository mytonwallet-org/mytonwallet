
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("Home-Actions")

@MainActor let actionsRowHeight = WScalableButton.preferredHeight

final class ActionsVC: WViewController, WalletCoreData.EventsObserver {
    
    var actionsContainerView: ActionsContainerView { view as! ActionsContainerView }
    var actionsView: ActionsView { actionsContainerView.actionsView }
    
    @AccountContext var account: MAccount
    
    init(accountSource: AccountSource) {
        self._account = AccountContext(source: accountSource)
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = ActionsContainerView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        actionsView.accountContext = $account
        WalletCoreData.add(eventObserver: self)
    }
    
    func setAccountId(accountId: String, animated: Bool)  {
        self.$account.accountId = accountId
        hideUnsupportedActions()
    }
    
    private func hideUnsupportedActions() {
        if account.isView {
            view.alpha = 0
        } else {
            view.alpha = 1
            actionsView.sendButton.isHidden = !account.supportsSend
            actionsView.swapButton.isHidden = !account.supportsSwap
            actionsView.earnButton.isHidden = !account.supportsEarn
            actionsView.sendButton.alpha = account.supportsSend ? 1 : 0
            actionsView.swapButton.alpha = account.supportsSwap ? 1 : 0
            actionsView.earnButton.alpha = account.supportsEarn ? 1 : 0
            actionsView.update()
        }
    }
    
    var calculatedHeight: CGFloat {
        account.isView ? 0 : actionsRowHeight
    }

    nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        MainActor.assumeIsolated {
            switch event {
            case .configChanged:
                hideUnsupportedActions()
            default:
                break
            }
        }
    }
}


final class ActionsContainerView: UIView {
    
    let actionsView = ActionsView()
    
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionsView)
        NSLayoutConstraint.activate([
            actionsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionsView.topAnchor.constraint(equalTo: topAnchor).withPriority(.defaultLow), // will be broken when pushed against the top
            actionsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: actionsRowHeight),
        ])
        setContentHuggingPriority(.required, for: .vertical)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ActionsView: ButtonsToolbar {
    var accountContext: AccountContext?
    var addButton: UIView!
    var sendButton: UIView!
    var swapButton: UIView!
    var earnButton: UIView!
    
    init() {
        super.init(frame: .zero)
        setup() 
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        
        addButton = WScalableButton(
            title: lang("Fund"),
            image: .airBundle("AddIconBold"),
            onTap: { [weak self] in
                guard let accountContext = self?.accountContext else { return }
                AppActions.showReceive(accountContext: accountContext, chain: nil, title: nil)
            }
        )
        addArrangedSubview(addButton)
        
        let sendButton = WScalableButton(
            title: lang("Send"),
            image: .airBundle("SendIconBold"),
            onTap: { [weak self] in
                guard let accountContext = self?.accountContext else { return }
                AppActions.showSend(accountContext: accountContext, prefilledValues: .init())
            }
        )
        sendButton.attachMenu(makeConfig: { [weak self] in
            guard let accountContext = self?.accountContext else { return MenuConfig(menuItems: []) }
            var menuItems: [MenuItem] = [
                .button(id: "0-send", title: lang("Send"), trailingIcon: .air("MenuSend26")) {
                    AppActions.showSend(accountContext: accountContext, prefilledValues: .init())
                },
                .button(id: "0-multisend", title: lang("Multisend"), trailingIcon: .air("MenuMultisend26")) { AppActions.showMultisend() },
            ]
            if !ConfigStore.shared.shouldRestrictSell {
                menuItems += .button(id: "0-sell", title: lang("Sell"), trailingIcon: .air("MenuSell26")) {
                    AppActions.showSell(accountContext: accountContext, tokenSlug: nil)
                }
            }
            return MenuConfig(menuItems: menuItems)
        })
        addArrangedSubview(sendButton)
        self.sendButton = sendButton
        
        swapButton = WScalableButton(
            title: lang("Swap"),
            image: .airBundle("SwapIconBold"),
            onTap: { [weak self] in
                guard let accountContext = self?.accountContext else { return }
                AppActions.showSwap(accountContext: accountContext, defaultSellingToken: nil, defaultBuyingToken: nil, defaultSellingAmount: nil, push: nil)
            }
        )
        addArrangedSubview(swapButton)
        
        earnButton = WScalableButton(
            title: lang("Earn"),
            image: .airBundle("EarnIconBold"),
            onTap: { [weak self] in
                guard let accountContext = self?.accountContext else { return }
                AppActions.showEarn(accountContext: accountContext, tokenSlug: nil)
            }
        )
        addArrangedSubview(earnButton)
    }
}
