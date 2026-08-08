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

    public init(accountSource: AccountSource, nftAddress: String, nft: ApiNft? = nil) {
        self.viewModel = LinkDomainViewModel(accountSource: accountSource, nftAddress: nftAddress, nft: nft)
        super.init(nibName: nil, bundle: nil)
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
        Task {
            do {
                guard let snapshot = try await viewModel.makeConfirmationSnapshot() else {
                    return
                }
                let protectedAction = ProtectedAction.linkDomain(
                    snapshot: snapshot,
                    onCommitted: { [weak self] in
                        self?.dismiss(animated: true) {
                            AppActions.showToast(message: lang("Domain Linked"))
                        }
                    }
                )
                _ = await ProtectedActionExecutor.execute(protectedAction, on: self)
            } catch {
                viewModel.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}

struct LinkDomainAuthHeader: ConfirmationContent {
    let snapshot: LinkDomainConfirmationSnapshot

    var body: some View {
        VStack(spacing: 16) {
            NftPreviewSection(nfts: [snapshot.nft], maxItems: 1, maxRows: 1)

            CompactActionSummary {
                Text(destination)
                    .textStyle(.bodyEmphasized, content: destinationContent)
            }
        }
    }

    var compactRepresentation: some View {
        CompactActionSummary {
            NftImage(nft: snapshot.nft, animateIfPossible: false)
                .clipShape(.rect(cornerRadius: 5))
        } label: {
            Text(snapshot.nft.name?.nilIfEmpty ?? lang("Domain")).textStyle(.bodyEmphasized)
                + Text(" \(lang("to")) ").textStyle(.body)
                + Text(destination).textStyle(.bodyEmphasized, content: destinationContent)
        }
    }

    private var destination: String {
        snapshot.destinationName?.nilIfEmpty ?? formatStartEndAddress(snapshot.destinationAddress)
    }

    private var destinationContent: WTextContent {
        snapshot.destinationName?.nilIfEmpty == nil ? .technical : .default
    }
}
