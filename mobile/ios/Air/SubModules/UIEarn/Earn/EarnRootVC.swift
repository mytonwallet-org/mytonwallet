
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext


@MainActor
public class EarnRootVC: WViewController, WSegmentedController.Delegate, Sendable {
    
    public let tokenSlug: String?
    
    private var tonVC: EarnVC!
    private var mycoinVC: EarnVC!
    private var ethenaVC: EarnVC!

    @AccountContext private var account: MAccount
    
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
    
    public init(accountContext: AccountContext, tokenSlug: String?) {
        self._account = accountContext
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
        view.backgroundColor = .air.sheetBackground
      
        tonVC = EarnVC(earnVM: EarnVM(config: .ton, accountContext: _account))
        mycoinVC = EarnVC(earnVM: EarnVM(config: .mycoin, accountContext: _account))
        ethenaVC = EarnVC(earnVM: EarnVM(config: .ethena, accountContext: _account))

        addChild(tonVC)
        addChild(mycoinVC)
        addChild(ethenaVC)
        
        segmentedController = WSegmentedController(
            items: segmentedControlItems,
            defaultItemId: tokenSlug,
            barHeight: 0,
            goUnderNavBar: true,
            animationSpeed: .slow,
            capsuleFillColor: .airBundle("DarkCapsuleColor") ,
            style: .header,
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

        segmentedController.segmentedControl?.embed(in: navigationItem)
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
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }
    
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
}

extension EarnRootVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            if $account.source == .current {
                updateWithStakingState()
            }
        case .stakingAccountData(let data):
            if data.accountId == $account.accountId {
                updateWithStakingState()
            }
        default:
            break
        }
    }
}
