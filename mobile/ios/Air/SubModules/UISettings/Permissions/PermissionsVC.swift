import UIKit
import UIComponents
import WalletCore
import WalletContext

private let excludedPermissionChains: Set<ApiChain> = [.solana, .tron]

public final class PermissionsVC: SettingsBaseVC {
    @AccountContext private var account: MAccount

    private var segmentedController: WSegmentedController!

    public init(accountContext: AccountContext = AccountContext(source: .current)) {
        self._account = accountContext
        super.init(nibName: nil, bundle: nil)
        title = lang("Permissions")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        let chains = permissionChains
        let items = chains.map { chain in
            SegmentedControlItem(
                id: chain.rawValue,
                title: chain.title,
                isDeletable: false,
                viewController: PermissionsListVC(accountContext: _account, chain: chain)
            )
        }

        segmentedController = WSegmentedController(
            items: items,
            barHeight: 0,
            goUnderNavBar: true,
            animationSpeed: .slow,
            capsuleFillColor: .air.darkCapsule,
            style: .header
        )
        segmentedController.backgroundColor = .clear
        segmentedController.blurView.isHidden = true
        segmentedController.separator.isHidden = true
        segmentedController.translatesAutoresizingMaskIntoConstraints = false
        segmentedController.scrollView.bounces = false
        segmentedController.scrollView.alwaysBounceHorizontal = false

        view.addSubview(segmentedController)
        NSLayoutConstraint.activate([
            segmentedController.topAnchor.constraint(equalTo: view.topAnchor),
            segmentedController.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedController.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        view.backgroundColor = .air.groupedBackground
        addCustomNavigationBarBackground(color: .air.groupedBackground)
        addCloseNavigationItemIfNeeded()

        if chains.count > 1 {
            segmentedController.segmentedControl.embed(in: navigationItem)
        } else {
            segmentedController.segmentedControl.isHidden = true
        }
    }

    private var permissionChains: [ApiChain] {
        account.orderedChains
            .map(\.0)
            .filter { !excludedPermissionChains.contains($0) }
    }
}
