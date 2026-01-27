import UIKit
import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import UIPasscode
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
        view.backgroundColor = WTheme.sheetBackground
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
        if viewModel.account.isHardware {
            AppActions.showError(error: BridgeCallError.message(.unsupportedHardwareContract, nil))
            return
        }
        var renewalSuccessful = false
        var renewalError: (any Error)?
        let headerVC = UIHostingController(rootView: RenewDomainAuthHeader(viewModel: viewModel))
        headerVC.view.backgroundColor = .clear
        UnlockVC.pushAuth(
            on: self,
            title: lang("Confirm Renewing"),
            customHeaderVC: headerVC,
            onAuthTask: { [weak self] passcode, onTaskDone in
                guard let self else { return }
                Task {
                    do {
                        try await self.viewModel.submit(password: passcode)
                        renewalSuccessful = true
                    } catch {
                        renewalSuccessful = false
                        renewalError = error
                    }
                    onTaskDone()
                }
            },
            onDone: { [weak self] _ in
                guard let self else { return }
                if renewalSuccessful {
                    let message = self.viewModel.nfts.count > 1
                        ? lang("Domains have been renewed!")
                        : lang("Domain has been renewed!")
                    self.dismiss(animated: true) {
                        AppActions.showToast(message: message)
                    }
                } else if let renewalError {
                    self.navigationController?.popViewController(animated: true)
                    self.showAlert(error: renewalError)
                }
            }
        )
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
