
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("BalanceHeaderVC")


@MainActor
class BalanceHeaderVC: WViewController {
    
    weak var delegate: BalanceHeaderViewDelegate?
    
    var balanceHeaderView: BalanceHeaderView { view as! BalanceHeaderView }
    private(set) var isLoading: Bool = false
    
    init(delegate: BalanceHeaderViewDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = BalanceHeaderView(vc: self, delegate: delegate)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WalletCoreData.add(eventObserver: self)
    }
    
    private func setupViews() {
        balanceHeaderView.walletCardView.isHidden = true
    }
    
    func setLoading(_ isLoading: Bool) {
        self.isLoading = isLoading
    }
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        UIView.performWithoutAnimation {
            balanceHeaderView.walletCardView.updateWithCurrentNft(accountChanged: false)
        }
    }
    
    public func addressCopy(address: String) {
        UIPasteboard.general.string = address
        showToast(animationName: "Copy", message: lang("Address was copied!"))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    
    public func addressOpenInExplorer(address: String) {
        if let chain = AccountStore.account?.addressByChain.first(where: { (k, v) in v == address })?.key {
            let url = ExplorerHelper.addressUrl(chain: ApiChain(rawValue: chain)!, address: address)
            AppActions.openInBrowser(url)
        }
    }
}


extension BalanceHeaderVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCore.WalletCoreData.Event) {
        switch event {
        case .cardBackgroundChanged(_, _):
            balanceHeaderView.walletCardView.updateWithCurrentNft(accountChanged: false)
        default:
            break
        }
    }
}
