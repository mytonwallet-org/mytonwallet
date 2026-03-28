import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception
import SwiftNavigation
import Dependencies

public class NftDetailsVC: NftDetailsBaseVC {
    private let nfts: [ApiNft]
    private let accountId: String
    
    public init(accountId: String, nft selectedNft: ApiNft, listContext: NftCollectionFilter, fixedNfts: [ApiNft]? = nil) {

        var nfts: [ApiNft] = []
        
        nfts = fixedNfts ?? Array(listContext.apply(to: NftStore.getAccountShownNfts(accountId: accountId) ?? [:]).values.map(\.nft))
        if !nfts.contains(where: { $0.id == selectedNft.id }) {
            nfts.append(selectedNft)
        }

        self.nfts = nfts
        self.accountId = accountId
        
        let accountContext = AccountContext(accountId: accountId)
        let accountType = accountContext.account.type
        let domains = accountContext.domains
        
        let items: [NftDetailsItem] = nfts.map {
            
            let attributes: [NftDetailsItem.Attribute]? = $0.metadata?.attributes?.map { .init(traitType: $0.trait_type, value: $0.value) }
            
            var collection: NftDetailsItem.Collection? = nil
            if let c = $0.collection {
                collection = .init(name: c.name)
            }

            let tonDomain = domains.expirationDays(for: $0).map {
                NftDetailsItem.TonDomain(
                    expirationDays: $0,
                    canRenew: accountType == .mnemonic
                )
            }

            return .init(
                id: $0.id,
                name: $0.displayName,
                description: $0.description,
                thumbnailUrl: $0.thumbnail,
                lottieUrl: $0.metadata?.lottie,
                attributes: attributes,
                collection: collection,
                tonDomain: tonDomain,
            )
        }
        let selectedIndex = nfts.firstIndex(where: { $0 == selectedNft }) ?? 0
        
        super.init(nfts:  items, selectedIndex: selectedIndex)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func resolveNft(for model: NftDetailsItemModel) -> ApiNft? {
        guard let result = nfts.first(where: { $0.id == model.id}) else {
            assertionFailure("Unable to find nft '\(model.name)'")
            return nil
        }
        return result
    }
    
    // MARK: - Actions
    
    override func nftDetailsOnShowCollection(forModel model: NftDetailsItemModel) {
        guard let nft = resolveNft(for: model) else { return }
        guard let collection = nft.collection else {
            assertionFailure()
            return
        }
        AppActions.showAssets(accountSource: .accountId(accountId), selectedTab: 1, collectionsFilter: .collection(collection))
    }
    
    override func nftDetailsOnRenewDomain(forModel model: NftDetailsItemModel) {
        guard let nft = resolveNft(for: model) else { return }
        AppActions.showRenewDomain(accountSource: .accountId(accountId), nftsToRenew: [nft.address])
    }

    override func ntfDetailsOnConfigureToolbarButton(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsToolbarButtonConfig? {
        guard let nft = resolveNft(for: model) else { return nil }
        
        switch action {
        case .wear:
            guard nft.isMtwCard else { return nil }
            return .init(
                onMenuConfiguration: { [weak self] in
                    guard let self else { return MenuConfig(menuItems: []) }
                    @Dependency(\.accountSettings) var _accountSettings
                    let accountSettings = _accountSettings.for(accountId: self.accountId)
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
                }
            )
        case .send:
            return .init(
                onTap: { [weak self] in
                    guard let self else { return }
                    AppActions.showSend(accountContext: AccountContext(accountId: self.accountId), prefilledValues: .init(mode: .sendNft, nfts: [nft]))
                }
            )
            
        case .share:
            return .init(
                onTap: { [weak self] in
                    guard let self else { return }
                    let accountContext = AccountContext(accountId: accountId)
                    AppActions.shareUrl(ExplorerHelper.viewNftUrl(network: accountContext.account.network, nftAddress: nft.address))
                }
            )
                
        case .more:
            return .init(
                onMenuConfiguration: { [weak self] in
                    guard let self else { return MenuConfig(menuItems: []) }
                    
                    let accountContext = AccountContext(accountId: accountId)
                    let accountType = accountContext.account.type
                    let accountId = self.accountId
                    var items: [MenuItem] = []
                    if nft.isTonDns && !nft.isOnSale && accountType == .mnemonic {
                        let linkedAddress = accountContext.domains.linkedAddressByAddress[nft.address]?.nilIfEmpty
                        let title = linkedAddress == nil ? lang("Link to Wallet") : lang("Change Linked Wallet")
                        items += .button(id: "0-link", title: title, trailingIcon: .system("link")) {
                            AppActions.showLinkDomain(accountSource: .accountId(accountId), nftAddress: nft.address)
                        }
                    }
                    items += .button(id: "0-hide", title: lang("Hide"), trailingIcon: .air("MenuHide26")) {
                        NftStore.setHiddenByUser(accountId: accountId, nftId: nft.id, isHidden: true)
                    }
                    items += .button(id: "0-burn", title: lang("Burn"), trailingIcon: .air("MenuBurn26"), isDangerous: true) {
                        AppActions.showSend(accountContext: AccountContext(accountId: self.accountId), prefilledValues: .init(mode: .burnNft, nfts: [nft]))
                    }
                    items += .wideSeparator()
                    if nft.chain == .ton, !ConfigStore.shared.shouldRestrictBuyNfts {
                        items += .button(id: "0-getgems", title: "Getgems", trailingIcon: .air("MenuGetgems26")) {
                            let url = ExplorerHelper.nftUrl(nft)
                            AppActions.openInBrowser(url)
                        }
                    }
                    items += .button(id: "0-tonscan", title: ExplorerHelper.selectedExplorerName(for: nft.chain),
                                     trailingIcon: .air(ExplorerHelper.selectedExplorerMenuIconName(for: nft.chain))) {
                        let url = ExplorerHelper.explorerNftUrl(nft)
                        AppActions.openInBrowser(url)
                    }
                    return MenuConfig(menuItems: items)
                }
            )
        }
    }
}
