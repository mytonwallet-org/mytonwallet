import UIKit
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
        guard viewModel.canRenew, !viewModel.nfts.isEmpty else { return }
        Task {
            do {
                _ = try await AppActions.authorizeProtectedAction(
                    on: self,
                    account: viewModel.account,
                    title: lang("Confirm Renewing"),
                    headerView: RenewDomainAuthHeader(viewModel: viewModel),
                    passwordAction: { [weak self] passcode in
                        guard let self else { return ApiMfaProtectedResult() }
                        return try await self.viewModel.submit(password: passcode)
                    },
                    ledgerSignData: { [weak self] in
                        guard let self else { throw CancellationError() }
                        return try await self.viewModel.makeLedgerPayload()
                    },
                    ledgerFromAddress: viewModel.account.getAddress(chain: .ton),
                    mfaTitle: lang("Confirm Renewing")
                )
                let message = viewModel.nfts.count > 1
                    ? lang("Domains have been renewed!")
                    : lang("Domain has been renewed!")
                dismiss(animated: true) {
                    AppActions.showToast(message: message)
                }
            } catch is CancellationError {
            } catch {
                showAlert(error: error)
            }
        }
    }
}

private struct RenewDomainAuthHeader: View {
    var viewModel: RenewDomainViewModel
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 8) {
                ForEach(viewModel.nfts, id: \.id) { nft in
                    NftPreviewRow(nft: nft, horizontalPadding: 12, verticalPadding: 8)
                }
            }
            .padding(.horizontal, 32)
        }
    }
}
