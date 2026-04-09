import ContextMenuKit
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
        
        let items: [NftDetailsItem] = nfts.map { nft in
            
            let attributes: [NftDetailsItem.Attribute]? = nft.metadata?.attributes?.map { .init(traitType: $0.trait_type, value: $0.value) }
            
            var collection: NftDetailsItem.Collection? = nil
            if let c = nft.collection {
                collection = .init(name: c.name)
            }

            let tonDomain = domains.expirationDays(for: nft).map {
                NftDetailsItem.TonDomain(
                    expirationDays: $0,
                    canRenew: accountType == .mnemonic && !nft.isOnSale
                )
            }

            return .init(
                id: nft.id,
                name: nft.displayName,
                description: nft.description,
                thumbnailUrl: nft.thumbnail,
                imageUrl: nft.image,
                lottieUrl: nft.metadata?.lottie,
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
    
    override func ntfDetailsOnConfigureAction(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsActionConfig? {
        guard let nft = resolveNft(for: model) else { return nil }
        
        switch action {
        case .wear:
            guard nft.isMtwCard else { return nil }
            return .init(
                onMenuConfiguration: { [weak self] in
                    guard let self else {
                        return ContextMenuConfiguration(
                            rootPage: ContextMenuPage(items: []),
                            backdrop: .defaultBlurred(),
                            style: ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)
                        )
                    }
                    @Dependency(\.accountSettings) var _accountSettings
                    let accountSettings = _accountSettings.for(accountId: self.accountId)
                    var items: [ContextMenuItem] = []
                    if let mtwCardId = nft.metadata?.mtwCardId {
                        let isCurrent = mtwCardId == accountSettings.backgroundNft?.metadata?.mtwCardId
                        if isCurrent {
                            items.append(
                                .action(
                                    ContextMenuAction(
                                        title: lang("Reset Card"),
                                        icon: .airBundle("MenuInstallCard26"),
                                        handler: {
                                            accountSettings.setBackgroundNft(nil)
                                        }
                                    )
                                )
                            )
                        } else {
                            items.append(
                                .action(
                                    ContextMenuAction(
                                        title: lang("Install Card"),
                                        icon: .airBundle("MenuInstallCard26"),
                                        handler: {
                                            accountSettings.setBackgroundNft(nft)
                                            accountSettings.setAccentColorNft(nft)
                                        }
                                    )
                                )
                            )
                        }
                        let isCurrentAccent = mtwCardId == accountSettings.accentColorNft?.metadata?.mtwCardId
                        if isCurrentAccent {
                            items.append(
                                .action(
                                    ContextMenuAction(
                                        title: lang("Reset Palette"),
                                        icon: .airBundle("custom.paintbrush.badge.xmark"),
                                        handler: {
                                            accountSettings.setAccentColorNft(nil)
                                        }
                                    )
                                )
                            )
                        } else {
                            items.append(
                                .action(
                                    ContextMenuAction(
                                        title: lang("Apply Palette"),
                                        icon: .airBundle("MenuBrush26"),
                                        handler: {
                                            accountSettings.setAccentColorNft(nft)
                                        }
                                    )
                                )
                            )
                        }
                    }
                    return ContextMenuConfiguration(
                        rootPage: ContextMenuPage(items: items),
                        backdrop: .defaultBlurred(),
                        style: ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)
                    )
                }
            )
        case .send:
            guard !nft.isOnSale else { return nil }
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
                    guard let self else {
                        return ContextMenuConfiguration(
                            rootPage: ContextMenuPage(items: []),
                            backdrop: .defaultBlurred(),
                            style: ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)
                        )
                    }
                    
                    let accountContext = AccountContext(accountId: accountId)
                    let accountType = accountContext.account.type
                    let accountId = self.accountId
                    var items: [ContextMenuItem] = []
                    if nft.isTonDns && !nft.isOnSale && accountType == .mnemonic {
                        let linkedAddress = accountContext.domains.linkedAddressByAddress[nft.address]?.nilIfEmpty
                        let title = linkedAddress == nil ? lang("Link to Wallet") : lang("Change Linked Wallet")
                        items.append(
                            .action(
                                ContextMenuAction(
                                    title: title,
                                    icon: .system("link"),
                                    handler: {
                                        AppActions.showLinkDomain(accountSource: .accountId(accountId), nftAddress: nft.address)
                                    }
                                )
                            )
                        )
                    }
                    items.append(
                        .action(
                            ContextMenuAction(
                                title: lang("Hide"),
                                icon: .airBundle("MenuHide26"),
                                handler: {
                                    NftStore.setHiddenByUser(accountId: accountId, nftId: nft.id, isHidden: true)
                                }
                            )
                        )
                    )
                    if !nft.isOnSale {
                        items.append(
                            .action(
                                ContextMenuAction(
                                    title: lang("Burn"),
                                    icon: .airBundle("MenuBurn26"),
                                    role: .destructive,
                                    handler: {
                                        AppActions.showSend(accountContext: AccountContext(accountId: self.accountId), prefilledValues: .init(mode: .burnNft, nfts: [nft]))
                                    }
                                )
                            )
                        )
                    }
                    items.append(.separator)
                    if nft.chain == .ton, !ConfigStore.shared.shouldRestrictBuyNfts {
                        items.append(
                                .action(
                                    ContextMenuAction(
                                        title: "Getgems",
                                        icon: .airBundle("MenuGetgems26", renderingMode: .original),
                                        handler: {
                                            let url = ExplorerHelper.nftUrl(nft)
                                            AppActions.openInBrowser(url)
                                        }
                                    )
                            )
                        )
                    }
                    items.append(
                        .action(
                            ContextMenuAction(
                                title: ExplorerHelper.selectedExplorerName(for: nft.chain),
                                icon: .airBundle(
                                    ExplorerHelper.selectedExplorerMenuIconName(for: nft.chain),
                                    renderingMode: .original
                                ),
                                handler: {
                                    let url = ExplorerHelper.explorerNftUrl(nft)
                                    AppActions.openInBrowser(url)
                                }
                            )
                        )
                    )
                    return ContextMenuConfiguration(
                        rootPage: ContextMenuPage(items: items),
                        backdrop: .defaultBlurred(),
                        style: ContextMenuStyle(minWidth: 180.0, maxWidth: 280.0)
                    )
                }
            )
            
        case .showCollection:
            return .init(
                onTap: { [weak self] in
                    guard let self else { return }
                    guard let collection = nft.collection else {
                        assertionFailure()
                        return
                    }
                    AppActions.showAssets(accountSource: .accountId(accountId), selectedTab: 1, collectionsFilter: .collection(collection))
                }
            )
            
        case .renewDomain:
            return .init(
                onTap: { [weak self] in
                    guard let self else { return }
                    AppActions.showRenewDomain(accountSource: .accountId(accountId), nftsToRenew: [nft.address])
                }
            )
        }
    }
}
