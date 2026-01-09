
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext


@MainActor
public class EarnRootVC: WViewController, WSegmentedController.Delegate {
    
    public let tokenSlug: String?
    
    private var tonVC: EarnVC!
    private var mycoinVC: EarnVC!
    private var ethenaVC: EarnVC!

    @AccountContext(source: .current) private var account: MAccount
    
    private var segmentedController: WSegmentedController!
    
    private lazy var _allSegmentedControlItems: [String: SegmentedControlItem] = [
        TONCOIN_SLUG: SegmentedControlItem(
            id: TONCOIN_SLUG,
            title: "TON",
            viewController: tonVC,
        ),
        MYCOIN_SLUG: SegmentedControlItem(
            id: MYCOIN_SLUG,
            title: "MY",
            viewController: mycoinVC,
        ),
        TON_USDE_SLUG: SegmentedControlItem(
            id: TON_USDE_SLUG,
            title: "USDe",
            viewController: ethenaVC,
        ),
    ]
    private var segmentedControlItems: [SegmentedControlItem] {
        var items: [SegmentedControlItem] = []
        let stakingState = $account.stakingData
        
        items += _allSegmentedControlItems[TONCOIN_SLUG]!
        if stakingState?.mycoinState != nil {
            items += _allSegmentedControlItems[MYCOIN_SLUG]!
        }
        if stakingState?.ethenaState != nil {
            items += _allSegmentedControlItems[TON_USDE_SLUG]!
        }
        return items
    }
    
    public init(tokenSlug: String?) {
        self.tokenSlug = tokenSlug ?? TONCOIN_SLUG
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
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
        let items = segmentedControlItems
        segmentedController = WSegmentedController(
            items: items,
            defaultItemId: tokenSlug,
            barHeight: 0,
            goUnderNavBar: true,
            animationSpeed: .slow,
            capsuleFillColor: capsuleColor,
            delegate: self
        )
        
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
        
        updateWithStakingState()
        
        // Select the correct tab after replace() async completes
        DispatchQueue.main.async { [self] in
            let currentItems = segmentedControlItems
            let idx = currentItems.firstIndex(where: { $0.id == tokenSlug }) ?? 0
            segmentedController.switchTo(tabIndex: idx)
            segmentedController.handleSegmentChange(to: idx, animated: false)
        }

        let segmentedControl = segmentedController.segmentedControl!
        segmentedControl.removeFromSuperview()
        navigationItem.titleView = segmentedControl
        segmentedControl.widthAnchor.constraint(equalToConstant: 200).isActive = true
        addCloseNavigationItemIfNeeded()
        addCustomNavigationBarBackground()
        configureNavigationItemWithTransparentBackground()
        
        updateTheme()

        WalletCoreData.add(eventObserver: self)
    }

    func updateWithStakingState() {
        let items = self.segmentedControlItems
        segmentedController.scrollView.isScrollEnabled = items.count > 1
        segmentedController.replace(items: items)
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
        segmentedController.updateTheme()
    }
    
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
}

extension EarnRootVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            updateWithStakingState()
        case .stakingAccountData(let data):
            if data.accountId == $account.accountId {
                updateWithStakingState()
            }
        default:
            break
        }
    }
}
