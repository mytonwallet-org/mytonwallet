import UIKit
import ProtectedAction
import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Perception

public final class RenewDomainVC: WViewController {
    
    private let viewModel: RenewDomainViewModel
    private var hostingController: UIHostingController<RenewDomainView>!
    
    public init(accountSource: AccountSource, nftsToRenew: [String]) {
        self.viewModel = RenewDomainViewModel(accountSource: accountSource, nftsToRenew: nftsToRenew)
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        view.backgroundColor = .air.sheetBackground
        navigationItem.titleView = HostingView {
            RenewDomainNavigationHeader(viewModel: viewModel)
        }
        addCloseNavigationItemIfNeeded()
        viewModel.onRenew = { [weak self] in
            self?.renewPressed()
        }
        hostingController = addHostingController(makeView(), constraints: .fill)
    }
    
    private func makeView() -> RenewDomainView {
        RenewDomainView(viewModel: viewModel)
    }

    private func renewPressed() {
        guard let snapshot = viewModel.makeConfirmationSnapshot() else { return }
        let message = snapshot.nfts.count > 1
            ? lang("Domains Renewed")
            : lang("Domain Renewed")
        let protectedAction = ProtectedAction.renewDomains(
            snapshot: snapshot,
            onCommitted: { [weak self] in
                self?.dismiss(animated: true) {
                    AppActions.showToast(message: message)
                }
            }
        )
        Task {
            _ = await ProtectedActionExecutor.execute(protectedAction, on: self)
        }
    }
}

struct RenewDomainAuthHeader: ConfirmationContent {
    let snapshot: RenewDomainConfirmationSnapshot
    
    var body: some View {
        NftPreviewSection(nfts: snapshot.nfts, maxItems: 3, maxRows: 3)
    }

    @ViewBuilder
    var compactRepresentation: some View {
        if snapshot.nfts.count > 1 {
            CompactActionSummary {
                compactLabel
            }
        } else {
            CompactActionSummary {
                if let nft = snapshot.nfts.first {
                    NftImage(nft: nft, animateIfPossible: false)
                        .clipShape(.rect(cornerRadius: 5))
                } else {
                    Image(systemName: "calendar.badge.clock")
                }
            } label: {
                compactLabel
            }
        }
    }

    private var compactLabel: Text {
        Text(lang("Renew") + " ").textStyle(.body)
            + Text(compactSubject).textStyle(.bodyEmphasized)
    }

    private var compactSubject: String {
        guard snapshot.nfts.count == 1 else {
            return lang("%amount% NFTs", arg1: snapshot.nfts.count)
        }
        return snapshot.nfts[0].name?.nilIfEmpty ?? lang("%amount% NFTs", arg1: 1)
    }
}
