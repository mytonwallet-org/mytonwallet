import UIKit
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
        guard viewModel.canLink, viewModel.nft != nil else { return }
        Task {
            do {
                _ = try await AppActions.authorizeProtectedAction(
                    on: self,
                    account: viewModel.account,
                    title: lang("Confirm Linking"),
                    headerView: LinkDomainAuthHeader(viewModel: viewModel),
                    passwordAction: { [weak self] passcode in
                        guard let self else { return ApiMfaProtectedResult() }
                        return try await self.viewModel.submit(password: passcode)
                    },
                    ledgerSignData: { [weak self] in
                        guard let self else { throw CancellationError() }
                        return try await self.viewModel.makeLedgerPayload()
                    },
                    ledgerFromAddress: viewModel.account.getAddress(chain: viewModel.nft?.chain ?? .ton),
                    mfaTitle: lang("Confirm Linking")
                )
                self.dismiss(animated: true) {
                    AppActions.showToast(message: lang("Domain Linked"))
                }
            } catch is CancellationError {
            } catch {
                showAlert(error: error)
            }
        }
    }
}

private struct LinkDomainAuthHeader: View {
    var viewModel: LinkDomainViewModel

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 8) {
                if let nft = viewModel.nft {
                    NftPreviewRow(nft: nft, horizontalPadding: 12, verticalPadding: 8)
                }
                let display = viewModel.displayComponents()
                VStack(spacing: 4) {
                    Text(viewModel.addressLabel)
                        .font13()
                        .foregroundStyle(Color.air.secondaryLabel)
                    HStack(spacing: 4) {
                        if let primary = display.primary {
                            Text(primary)
                                .foregroundStyle(Color.air.primaryLabel)
                                .truncationMode(.middle)
                        }
                        if let secondary = display.secondary {
                            Text("·")
                                .foregroundStyle(Color.air.secondaryLabel)
                            Text(secondary)
                                .foregroundStyle(Color.air.secondaryLabel)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
        }
    }
}
