
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("Home-Actions")


@MainActor final class ActionsVC: WViewController, WalletCoreData.EventsObserver {
    
    
    var actionsContainerView: ActionsContainerView { view as! ActionsContainerView }
    var actionsView: ActionsView { actionsContainerView.actionsView }
    
    // dependencies
    private var account: MAccount { AccountStore.account ?? DUMMY_ACCOUNT }
    
    override func loadView() {
        view = ActionsContainerView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        actionsView.addButton.addTarget(self, action: #selector(addPressed))
        actionsView.sendButton.addTarget(self, action: #selector(sendPressed))
        actionsView.swapButton.addTarget(self, action: #selector(swapPressed))
        actionsView.earnButton.addTarget(self, action: #selector(earnPressed))
        hideUnsupportedActions()
        WalletCoreData.add(eventObserver: self)
    }
    
    func hideUnsupportedActions() {
        if account.isView {
            view.isHidden = true
        } else {
            view.isHidden = false
            actionsView.sendButton.isHidden = !account.supportsSend
            actionsView.swapButton.isHidden = !account.supportsSwap 
            actionsView.earnButton.isHidden = !account.supportsEarn
        }
    }
    
    var calcilatedHeight: CGFloat {
        account.isView ? 0 : 60 + 16
    }

    nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        MainActor.assumeIsolated {
            switch event {
            case .accountChanged:
                hideUnsupportedActions()
            case .configChanged:
                hideUnsupportedActions()
            default:
                break
            }
        }
    }

    // MARK: - Actions

    @objc func addPressed() {
        AppActions.showReceive(chain: nil, showBuyOptions: nil, title: nil)
    }

    @objc func sendPressed() {
        AppActions.showSend(prefilledValues: nil)
    }

    @objc func earnPressed() {
        AppActions.showEarn(token: nil)
    }

    @objc func swapPressed() {
        AppActions.showSwap(defaultSellingToken: nil, defaultBuyingToken: nil, defaultSellingAmount: nil, push: nil)
    }
}


@MainActor final class ActionsContainerView: UIView {
    
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
        ])
        setContentHuggingPriority(.required, for: .vertical)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


@MainActor final class ActionsView: WTouchPassStackView, WThemedView {
    
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
        spacing = 8
        distribution = .fillEqually
        layer.masksToBounds = true
        
        addButton = WScalableButton(title: lang("Add").lowercased(),
                                        image: UIImage(named: "AddIcon",
                                                       in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
                                        onTap: nil)
        addArrangedSubview(addButton)
        
        sendButton = WScalableButton(title: lang("Send").lowercased(),
                        image: UIImage(named: "SendIcon",
                                       in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
                        onTap: nil)
        addArrangedSubview(sendButton)
        
        swapButton = WScalableButton(title: lang("Swap").lowercased(),
                                         image: UIImage(named: "SwapIcon",
                                                        in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
                                         onTap: nil)
        addArrangedSubview(swapButton)
        
        earnButton = WScalableButton(title: lang("Earn").lowercased(),
                                         image: UIImage(named: "EarnIcon",
                                                        in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
                                         onTap: nil)
        addArrangedSubview(earnButton)
    }
    
    override func layoutSubviews() {
        let height = bounds.height
        let actionButtonAlpha = height < 60 ? height / 60 : 1
        let maxRadius = S.actionButtonCornerRadius
        let actionButtonRadius = min(maxRadius, height / 2)
        for btn in arrangedSubviews {
            guard let btn = btn as? WScalableButton else { continue }
            btn.innerButton.titleLabel?.alpha = actionButtonAlpha
            btn.innerButton.imageView?.alpha = actionButtonAlpha
            btn.layer.cornerRadius = actionButtonRadius
            btn.set(scale: actionButtonAlpha)
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
