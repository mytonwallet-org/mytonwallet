
import UIKit
import ContextMenuKit
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
    private var sendMenuInteraction: ContextMenuInteraction?
    
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
        let sendMenuInteraction = ContextMenuInteraction(
            triggers: [.longPress],
            longPressDuration: 0.25,
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(
                    cornerRadius: WScalableButton.preferredCornerRadius,
                    cornerCurve: .continuous
                ),
                showsBackdropCutout: true
            ),
            onWillPresent: {
                sendButton.cancelCurrentInteractionAndSuppressNextTap()
            },
            onDidDismiss: {
                sendButton.consumeSuppressedTapIfNeeded()
            }
        ) { [weak self] _ in
            self?.makeSendMenuConfiguration() ?? ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: []),
                backdrop: .defaultBlurred()
            )
        }
        sendMenuInteraction.attach(to: sendButton)
        self.sendMenuInteraction = sendMenuInteraction
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

    private func makeSendMenuConfiguration() -> ContextMenuConfiguration {
        guard let accountContext else {
            return ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: []),
                backdrop: .defaultBlurred()
            )
        }

        var items: [ContextMenuItem] = [
            .action(
                ContextMenuAction(
                    title: lang("Send"),
                    icon: .airBundle("MenuSend26"),
                    handler: {
                        AppActions.showSend(accountContext: accountContext, prefilledValues: .init())
                    }
                )
            ),
            .action(
                ContextMenuAction(
                    title: lang("Multisend"),
                    icon: .airBundle("MenuMultisend26"),
                    handler: {
                        AppActions.showMultisend()
                    }
                )
            ),
        ]

        if !ConfigStore.shared.shouldRestrictSell {
            items.append(
                .action(
                    ContextMenuAction(
                        title: lang("Sell"),
                        icon: .airBundle("MenuSell26"),
                        handler: {
                            AppActions.showSell(accountContext: accountContext, tokenSlug: nil)
                        }
                    )
                )
            )
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .defaultBlurred(),
            style: ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)
        )
    }
}
