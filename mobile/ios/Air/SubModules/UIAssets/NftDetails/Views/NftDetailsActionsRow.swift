import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Dependencies
import Perception

struct NftDetailsActionsRow: View {

    var viewModel: NftDetailsViewModel

    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            NftDetailsActionsToolbarRepresentable(model: .init(
                nft: viewModel.nft,
                accountId: viewModel.account.id,
                accountNetwork: viewModel.account.network,
                accountType: viewModel.account.type,
                linkedAddressForNft: viewModel.$account.domains.linkedAddressByAddress[viewModel.nft.address]?.nilIfEmpty
            ))
                .frame(height: WScalableButton.preferredHeight)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .tint(Color(WTheme.tint))
        }
    }
}

private final class NftDetailsActionsToolbar: ButtonsToolbar {
    var wearButton: WScalableButton!
    var sendButton: WScalableButton!
    var shareButton: WScalableButton!
    var moreButton: WScalableButton!
    

    struct Model: Equatable {
        let nft: ApiNft
        let accountId: String
        let accountNetwork: ApiNetwork
        let accountType: AccountType
        let linkedAddressForNft: String?
    }

    private var model: Model!

    func configure(model: Model) {
        self.model = model
        if wearButton == nil {
            setupButtons()
        }
        wearButton.isHidden = !model.nft.isMtwCard
        wearButton.titleLabel.text = lang("Wear")
        wearButton.imageView.image = UIImage.airBundle("WearIconBold")
        
        sendButton.titleLabel.text = lang("Send")
        sendButton.imageView.image = UIImage.airBundle("SendIconBold" )
        
        shareButton.titleLabel.text = lang("Share")
        shareButton.imageView.image = UIImage.airBundle("ShareIconBold")
        
        moreButton.titleLabel.text = lang("More")
        moreButton.imageView.image = UIImage.airBundle("MoreIconBold")
        update()
    }

    private func setupButtons() {
        let wear = WScalableButton(title: "", image: nil, onTap: {})
        wear.attachMenu(presentOnTap: true, makeConfig: { [weak self] in
            guard let self, let model = self.model else { return MenuConfig(menuItems: []) }
            @Dependency(\.accountSettings) var _accountSettings
            let accountSettings = _accountSettings.for(accountId: model.accountId)
            let nft = model.nft
            var items: [MenuItem] = []
            if let mtwCardId = nft.metadata?.mtwCardId {
                let isCurrent = mtwCardId == accountSettings.backgroundNft?.metadata?.mtwCardId
                if isCurrent {
                    items += .button(id: "0-card", title: lang("Reset Card"), trailingIcon: .air("MenuInstallCard26")) {
                        accountSettings.setBackgroundNft(nil)
                    }
                } else {
                    items += .button(id: "0-card", title: lang("Install Card"), trailingIcon: .air("MenuInstallCard26")) {
                        accountSettings.setBackgroundNft(nft)
                        accountSettings.setAccentColorNft(nft)
                    }
                }
                let isCurrentAccent = mtwCardId == accountSettings.accentColorNft?.metadata?.mtwCardId
                if isCurrentAccent {
                    items += .button(id: "0-palette", title: lang("Reset Palette"), trailingIcon: .air("custom.paintbrush.badge.xmark")) {
                        accountSettings.setAccentColorNft(nil)
                    }
                } else {
                    items += .button(id: "0-palette", title: lang("Apply Palette"), trailingIcon: .air("MenuBrush26")) {
                        accountSettings.setAccentColorNft(nft)
                    }
                }
            }
            return MenuConfig(menuItems: items)
        })
        addArrangedSubview(wear)
        wearButton = wear

        let send = WScalableButton(
            title: "",
            image: nil,
            onTap: { [weak self] in
                guard let model = self?.model else { return }
                AppActions.showSend(prefilledValues: .init(mode: .sendNft, nfts: [model.nft]))
            }
        )
        addArrangedSubview(send)
        sendButton = send

        let share = WScalableButton(
            title: "",
            image: nil,
            onTap: { [weak self] in
                guard let model = self?.model else { return }
                AppActions.shareUrl(ExplorerHelper.viewNftUrl(network: model.accountNetwork, nftAddress: model.nft.address))
            }
        )
        addArrangedSubview(share)
        shareButton = share

        let more = WScalableButton(title: "", image: nil, onTap: {})
        more.attachMenu(presentOnTap: true, makeConfig: { [weak self] in
            guard let model = self?.model else { return MenuConfig(menuItems: []) }
            let accountId = model.accountId
            var items: [MenuItem] = []
            if model.nft.isTonDns && !model.nft.isOnSale && model.accountType == .mnemonic {
                let linkedAddress = model.linkedAddressForNft
                let title = linkedAddress == nil ? lang("Link to Wallet") : lang("Change Linked Wallet")
                items += .button(id: "0-link", title: title, trailingIcon: .system("link")) {
                    AppActions.showLinkDomain(accountSource: .accountId(accountId), nftAddress: model.nft.address)
                }
            }
            items += .button(id: "0-hide", title: lang("Hide"), trailingIcon: .air("MenuHide26")) {
                NftStore.setHiddenByUser(accountId: accountId, nftId: model.nft.id, isHidden: true)
            }
            items += .button(id: "0-burn", title: lang("Burn"), trailingIcon: .air("MenuBurn26"), isDangerous: true) {
                AppActions.showSend(prefilledValues: .init(mode: .burnNft, nfts: [model.nft]))
            }
            items += .wideSeparator()
            if model.nft.chain == .ton, !ConfigStore.shared.shouldRestrictBuyNfts {
                items += .button(id: "0-getgems", title: "Getgems", trailingIcon: .air("MenuGetgems26")) {
                    let url = ExplorerHelper.nftUrl(model.nft)
                    AppActions.openInBrowser(url)
                }
            }
            items += .button(id: "0-tonscan", title: ExplorerHelper.selectedExplorerName(for: model.nft.chain), trailingIcon: .air(ExplorerHelper.selectedExplorerMenuIconName(for: model.nft.chain))) {
                let url = ExplorerHelper.explorerNftUrl(model.nft)
                AppActions.openInBrowser(url)
            }
            return MenuConfig(menuItems: items)
        })
        addArrangedSubview(more)
        moreButton = more
    }
}

private struct NftDetailsActionsToolbarRepresentable: UIViewRepresentable {
    var model: NftDetailsActionsToolbar.Model

    func makeUIView(context: Context) -> NftDetailsActionsToolbar {
        let toolbar = NftDetailsActionsToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.configure(model: model)
        toolbar.updateTheme()
        return toolbar
    }

    func updateUIView(_ uiView: NftDetailsActionsToolbar, context: Context) {
        uiView.configure(model: model)
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable var viewModel = NftDetailsViewModel(accountId: "0-mainnet", nft: .sampleMtwCard, listContext: .none)
    VStack {
        NftDetailsActionsRow(viewModel: viewModel)
        Button("Toggle isExplanded") {
            withAnimation(.spring(duration: 2)) {
                viewModel.state  = .expanded
            }
        }
    }
    .padding(32)
    .background(Color.blue.opacity(0.2))
}
#endif
