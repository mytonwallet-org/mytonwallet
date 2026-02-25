import UIKit
import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import UIPasscode
import Perception

public final class LinkDomainVC: WViewController {

    private let viewModel: LinkDomainViewModel
    private var hostingController: UIHostingController<LinkDomainView>!

    public init(accountSource: AccountSource, nftAddress: String) {
        self.viewModel = LinkDomainViewModel(accountSource: accountSource, nftAddress: nftAddress)
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
        view.backgroundColor = WTheme.sheetBackground
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
        if viewModel.account.isHardware {
            AppActions.showError(error: BridgeCallError.message(.unsupportedHardwareContract, nil))
            return
        }
        var linkingSuccessful = false
        var linkingError: (any Error)?
        let headerVC = UIHostingController(rootView: LinkDomainAuthHeader(viewModel: viewModel))
        headerVC.view.backgroundColor = .clear
        UnlockVC.pushAuth(
            on: self,
            title: lang("Confirm Linking"),
            customHeaderVC: headerVC,
            onAuthTask: { [weak self] passcode, onTaskDone in
                guard let self else { return }
                Task {
                    do {
                        try await self.viewModel.submit(password: passcode)
                        linkingSuccessful = true
                    } catch {
                        linkingSuccessful = false
                        linkingError = error
                    }
                    onTaskDone()
                }
            },
            onDone: { [weak self] _ in
                guard let self else { return }
                if linkingSuccessful {
                    self.dismiss(animated: true) {
                        AppActions.showToast(message: lang("Domain Linked"))
                    }
                } else if let linkingError {
                    self.navigationController?.popViewController(animated: true)
                    self.showAlert(error: linkingError)
                }
            }
        )
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
