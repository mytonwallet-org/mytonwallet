
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("Home-Actions")

let actionsRowHeight: CGFloat = IOS_26_MODE_ENABLED ? 70 : 60

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
        WalletCoreData.add(eventObserver: self)
    }
    
    func setAccountId(accountId: String, animated: Bool)  {
        self.$account.accountId = accountId
        hideUnsupportedActions()
    }
    
    func hideUnsupportedActions() {
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
            actionsView.updateSpacing()
        }
    }
    
    var calculatedHeight: CGFloat {
        account.isView ? 0 : actionsRowHeight + 16
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
        if IOS_26_MODE_ENABLED {
            NSLayoutConstraint.activate([
                actionsView.centerXAnchor.constraint(equalTo: centerXAnchor),
                actionsView.topAnchor.constraint(equalTo: topAnchor).withPriority(.defaultLow), // will be broken when pushed against the top
                actionsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

        } else {
            NSLayoutConstraint.activate([
                actionsView.leadingAnchor.constraint(equalTo: leadingAnchor),
                actionsView.trailingAnchor.constraint(equalTo: trailingAnchor),
                actionsView.topAnchor.constraint(equalTo: topAnchor).withPriority(.defaultLow), // will be broken when pushed against the top
                actionsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        setContentHuggingPriority(.required, for: .vertical)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


final class ActionsView: WTouchPassStackView, WThemedView {
    
    var addButton: WScalableButton!
    var sendButton: WScalableButton!
    var swapButton: WScalableButton!
    var earnButton: WScalableButton!
    
    init() {
        super.init(frame: .zero)
        setup() 
        updateTheme()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        spacing = S.actionButtonSpacing(forButtonCount: 4)
        distribution = IOS_26_MODE_ENABLED ? .equalSpacing : .fillEqually
        clipsToBounds = false
        
        addButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Add / Buy") : lang("Add").lowercased(),
            image: IOS_26_MODE_ENABLED ? .airBundle("AddIconBold") : .airBundle("AddIcon"),
            onTap: { AppActions.showReceive(chain: nil, title: nil) }
        )
        addArrangedSubview(addButton)
        
        sendButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Send") : lang("Send").lowercased(),
            image: IOS_26_MODE_ENABLED ? .airBundle("SendIconBold") : .airBundle("SendIcon"),
            onTap: { AppActions.showSend(prefilledValues: nil) }
        )
        addArrangedSubview(sendButton)
        
        swapButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Swap") : lang("Swap").lowercased(),
            image: IOS_26_MODE_ENABLED ? .airBundle("SwapIconBold") : .airBundle("SwapIcon"),
            onTap: { AppActions.showSwap(defaultSellingToken: nil, defaultBuyingToken: nil, defaultSellingAmount: nil, push: nil) }
        )
        addArrangedSubview(swapButton)
        
        earnButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Earn") : lang("Earn").lowercased(),
            image: IOS_26_MODE_ENABLED ? .airBundle("EarnIconBold") : .airBundle("EarnIcon"),
            onTap: { AppActions.showEarn(tokenSlug: nil) }
        )
        addArrangedSubview(earnButton)
        
    }
    
    func updateSpacing() {
        let visibleCount = arrangedSubviews.filter { !$0.isHidden }.count
        spacing = S.actionButtonSpacing(forButtonCount: visibleCount)
    }
    
    override func layoutSubviews() {
        let height = bounds.height
        let actionButtonAlpha = height < actionsRowHeight ? height / actionsRowHeight : 1
        let maxRadius = S.actionButtonCornerRadius
        let actionButtonRadius = min(maxRadius, height / 2)
        for btn in arrangedSubviews {
            guard let btn = btn as? WScalableButton else { continue }
            btn.set(scale: actionButtonAlpha, radius: actionButtonRadius)
        }
        super.layoutSubviews()
    }

    nonisolated public func updateTheme() {
        MainActor.assumeIsolated {
            addButton.tintColor = WTheme.tint
            sendButton.tintColor = WTheme.tint
            swapButton.tintColor = WTheme.tint
            earnButton.tintColor = WTheme.tint
        }
    }
}
