
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext


@MainActor
public class EarnRootVC: WViewController, WSegmentedController.Delegate {
    
    public let onlyToken: ApiToken?
    public let customTitle: String?
    
    private var tonVC: EarnVC!
    private var mycoinVC: EarnVC!
    private var ethenaVC: EarnVC!
    
    private var segmentedController: WSegmentedController!
    private var progress: CGFloat = 0
    
    private let segmentedControlItems: [SegmentedControlItem] = [
        SegmentedControlItem(index: 0, id: "TON", content: AnyView(Text("TON"))),
        SegmentedControlItem(index: 1, id: "MY", content: AnyView(Text("MY"))),
        SegmentedControlItem(index: 2, id: "USDe", content: AnyView(Text("USDe"))),
    ]
    
    public init(token: ApiToken? = nil, title: String? = nil) {
        self.onlyToken = token
        self.customTitle = title
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    func setupViews() {
        view.backgroundColor = WTheme.sheetBackground
      
        tonVC = EarnVC(earnVM: .sharedTon)
        mycoinVC = EarnVC(earnVM: .sharedMycoin)
        ethenaVC = EarnVC(earnVM: .sharedEthena)

        addChild(tonVC)
        addChild(mycoinVC)
        addChild(ethenaVC)
        
        let capsuleColor = UIColor { WTheme.secondaryLabel.withAlphaComponent($0.userInterfaceStyle == .dark ? 0.2 : 0.12 ) }
        segmentedController = WSegmentedController(viewControllers: [tonVC, mycoinVC, ethenaVC],
                                                   defaultIndex: onlyToken?.slug == STAKED_MYCOIN_SLUG ? 1 : 0,
                                                   barHeight: 56.333,
                                                   animationSpeed: .slow,
                                                   capsuleFillColor: capsuleColor,
                                                   delegate: self)
        
        segmentedController.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedController)
        NSLayoutConstraint.activate([
            segmentedController.topAnchor.constraint(equalTo: view.topAnchor),
            segmentedController.leftAnchor.constraint(equalTo: view.leftAnchor),
            segmentedController.rightAnchor.constraint(equalTo: view.rightAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        segmentedController.backgroundColor = .clear
        segmentedController.blurView.isHidden = true
        segmentedController.separator.isHidden = true
        
        view.bringSubviewToFront(segmentedController)
        
        let navigationBar = WNavigationBar(navHeight: 60, title: title, titleColor: .white, closeIcon: true, closeIconColor: WTheme.secondaryLabel, closeIconFillColor: capsuleColor)
        self.navigationBar = navigationBar
        navigationBar.blurView.isHidden = true
        navigationBar.shouldPassTouches = true
        navigationBar.backgroundColor = .clear
        view.addSubview(navigationBar)
        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBar.leftAnchor.constraint(equalTo: view.leftAnchor),
            navigationBar.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])

        updateWithStakingState()

        updateTheme()

        WalletCoreData.add(eventObserver: self)
    }

    func updateWithStakingState() {
        let twoTabs = true
        segmentedController.scrollView.isScrollEnabled = twoTabs
        let title: String? = twoTabs ? nil : (customTitle ?? lang("Add Crypto"))
        navigationBar?.set(title: title)
        
        var vcs: [any WSegmentedControllerContent] = [tonVC]
        var items: [SegmentedControlItem] = [segmentedControlItems[0]]
        if StakingStore.currentAccount?.mycoinState != nil {
            vcs.append(mycoinVC)
            items.append(segmentedControlItems[1])
        }
        if StakingStore.currentAccount?.ethenaState != nil {
            vcs.append(ethenaVC)
            items.append(segmentedControlItems[2])
        }
        segmentedController.replace(viewControllers: vcs, items: items)
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
        segmentedController.updateTheme()
    }
    
    public override var hideNavigationBar: Bool { true }
    
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
    
    public func switchToTokensTab() {
        segmentedController?.switchTo(tabIndex: 0)
    }
    
    public func segmentedController(scrollOffsetChangedTo progress: CGFloat) {
        self.progress = progress
    }
    
    public func segmentedControllerDidStartDragging() {
    }
    
    public func segmentedControllerDidEndScrolling() {
    }
}

extension EarnRootVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            updateWithStakingState()
        case .stakingAccountData(let data):
            if data.accountId == AccountStore.accountId {
                updateWithStakingState()
            }
        default:
            break
        }
    }
}
