import UIKit
import ProtectedAction
import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Perception

public final class LinkDomainVC: WViewController {

    private let viewModel: LinkDomainViewModel
    private var hostingController: UIHostingController<LinkDomainView>!

    public init(accountSource: AccountSource, nftAddress: String, nft: ApiNft? = nil, isUnlinking: Bool = false) {
        self.viewModel = LinkDomainViewModel(accountSource: accountSource, nftAddress: nftAddress, nft: nft, isUnlinking: isUnlinking)
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 580, height: 480)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        view.backgroundColor = .air.sheetBackground
        navigationItem.titleView = HostingView {
            LinkDomainNavigationHeader(viewModel: viewModel)
        }
        addCloseNavigationItemIfNeeded()
        viewModel.onLink = { [weak self] in
            self?.linkPressed()
        }
        hostingController = addHostingController(makeView(), constraints: .fill)
    }

    private func makeView() -> LinkDomainView {
        LinkDomainView(viewModel: viewModel)
    }

    private func linkPressed() {
        guard let snapshot = viewModel.makeConfirmationSnapshot() else { return }
        let toastMessage = snapshot.isUnlinking ? lang("Domain Unlinked") : lang("Domain Linked")
        let protectedAction = ProtectedAction.linkDomain(
            snapshot: snapshot,
            onCommitted: { [weak self] in
                self?.dismiss(animated: true) {
                    AppActions.showToast(message: toastMessage)
                }
            }
        )
        viewModel.isSubmitting = true
        Task {
            defer { viewModel.isSubmitting = false }
            _ = await ProtectedActionExecutor.execute(protectedAction, on: self)
        }
    }
}

struct LinkDomainAuthHeader: ConfirmationContent {
    let snapshot: LinkDomainConfirmationSnapshot

    var body: some View {
        VStack(spacing: 16) {
            NftPreviewSection(nfts: [snapshot.nft], maxItems: 1, maxRows: 1)

            if let destination {
                CompactActionSummary {
                    Text(destination)
                        .textStyle(.bodyEmphasized, content: destinationContent)
                }
            }
        }
    }

    var compactRepresentation: some View {
        CompactActionSummary {
            NftImage(nft: snapshot.nft, animateIfPossible: false)
                .clipShape(.rect(cornerRadius: 5))
        } label: {
            if let destination {
                domainName
                    + Text(" \(lang("to")) ").textStyle(.body)
                    + Text(destination).textStyle(.bodyEmphasized, content: destinationContent)
            } else {
                domainName
            }
        }
    }

    private var domainName: Text {
        Text(snapshot.nft.name?.nilIfEmpty ?? lang("Domain")).textStyle(.bodyEmphasized)
    }

    private var destination: String? {
        guard let destinationAddress = snapshot.destinationAddress else { return nil }
        return snapshot.destinationName?.nilIfEmpty ?? formatStartEndAddress(destinationAddress)
    }

    private var destinationContent: WTextContent {
        snapshot.destinationName?.nilIfEmpty == nil ? .technical : .default
    }
}
