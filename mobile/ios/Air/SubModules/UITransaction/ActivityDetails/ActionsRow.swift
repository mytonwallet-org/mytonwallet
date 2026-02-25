
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

struct ActionsRow: View {

    var model: ActivityDetailsViewModel
    
    var shouldShowRepeat: Bool {
        guard let account  = AccountStore.account, account.type != .view else { return false }
        
        switch model.activity {
        case .transaction(let tx):
            if tx.isStaking {
                return account.supportsEarn
            }
            if tx.isIncoming || tx.type != nil || tx.nft != nil {
                return false
            }
            return account.supportsSend
        case .swap:
            return account.supportsSwap
        }
    }

    private var shouldShowShare: Bool {
        !model.activity.isBackendSwapId
    }

    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            let toolbarModel = ActivityDetailsActionsToolbar.Model(
                showDetails: model.detailsCollapseEnabled,
                showRepeat: shouldShowRepeat,
                showShare: shouldShowShare,
                onDetailsExpanded: { model.onDetailsExpanded() },
                onRepeat: { AppActions.repeatActivity(model.activity) },
                onShare: {
                    if let chain = TokenStore.tokens[model.activity.slug]?.chain, chain.isSupported {
                        let txHash = model.activity.parsedTxId.hash
                        let url = ExplorerHelper.viewTransactionUrl(network: model.accountContext.account.network, chain: chain, txHash: txHash)
                        AppActions.shareUrl(url)
                    }
                }
            )
            ActivityDetailsActionsToolbarRepresentable(model: toolbarModel)
                .frame(height: WScalableButton.preferredHeight)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .tint(Color(WTheme.tint))
        }
    }
}

private final class ActivityDetailsActionsToolbar: ButtonsToolbar {
    var detailsButton: WScalableButton!
    var repeatButton: WScalableButton!
    var shareButton: WScalableButton!
    private var model: Model!

    struct Model {
        let showDetails: Bool
        let showRepeat: Bool
        let showShare: Bool
        let onDetailsExpanded: () -> Void
        let onRepeat: () -> Void
        let onShare: () -> Void
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(model: Model) {
        self.model = model
        if detailsButton == nil {
            setupButtons()
        }
        detailsButton.isHidden = !model.showDetails
        repeatButton.isHidden = !model.showRepeat
        shareButton.isHidden = !model.showShare
        update()
    }

    private func setupButtons() {
        let details = WScalableButton(title: lang("Details"), image: UIImage.airBundle("DetailsIconBold"), onTap: { [weak self] in self?.model?.onDetailsExpanded() })
        addArrangedSubview(details)
        detailsButton = details

        let repeatBtn = WScalableButton(title: lang("Repeat"), image: UIImage.airBundle("RepeatIconBold"), onTap: { [weak self] in self?.model?.onRepeat() })
        addArrangedSubview(repeatBtn)
        repeatButton = repeatBtn

        let share = WScalableButton(title: lang("Share"), image: UIImage.airBundle("ShareIconBold"), onTap: { [weak self] in  self?.model?.onShare() })
        addArrangedSubview(share)
        shareButton = share
    }
}

private struct ActivityDetailsActionsToolbarRepresentable: UIViewRepresentable {
    var model: ActivityDetailsActionsToolbar.Model

    func makeUIView(context: Context) -> ActivityDetailsActionsToolbar {
        let toolbar = ActivityDetailsActionsToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.configure(model: model)
        toolbar.updateTheme()
        return toolbar
    }

    func updateUIView(_ uiView: ActivityDetailsActionsToolbar, context: Context) {
        uiView.configure(model: model)
    }
}

