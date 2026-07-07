import ContextMenuKit
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception
import SwiftNavigation
import Dependencies
import OrderedCollections

private let log = Log("NftDetailsVC")

public enum NftDetailsDataSource {
    /// Any visibility state. Shown as a part of whole unhidden account Nft collection (if belongs to the account), single otherwise
    case singleNft(ApiNft)
    
    /// All unhidden nfts for given account and filter, selected at `selection`
    case collectionNfts(selection: ApiNft, filter: NftCollectionFilter)
    
    /// Any visibility state, always single - called from Hidden NFTs screen for further management
    case hiddenManagement(ApiNft)
}

public class NftDetailsVC: NftDetailsBaseVC {
    private var nfts: [ApiNft]
    private let accountId: String
    private let account: MAccount
    private var didAppearOnce = false
    private var pendingSelectionNftId: String?
    private let sourceContext: SourceContext

    public init(accountId: String, source: NftDetailsDataSource, isExpanded: Bool = false) {
        
        sourceContext = .init(accountId: accountId, source: source)
        let (nfts, selectedNft) = sourceContext.getInitialData()
        let selectedIndex = nfts.firstIndex(where: { $0.id == selectedNft.id }) ?? 0

        self.nfts = nfts
        self.accountId = accountId
        self.account = AccountContext(accountId: accountId).account
        let items = Self.makeItems(accountId: accountId, nfts: nfts)
        
        super.init(nfts: items, selectedIndex: selectedIndex, initiallyExpanded: isExpanded)
        
        manager.setDisplayStateProvider(self)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if didAppearOnce {
            reconcileFromSource()
        } else {
            didAppearOnce = true
        }
    }

    public func removeNft(id: String, animated: Bool = true) {
        nfts.removeAll { $0.id == id }
        removeItem(id: id, animated: animated)
    }

    private func reconcileFromSource() {
        nfts = sourceContext.getNextData()

        let preferredSelectedId = pendingSelectionNftId
        pendingSelectionNftId = nil

        reconcileItems(Self.makeItems(accountId: accountId, nfts: nfts), preferredSelectedId: preferredSelectedId)
    }

    private static func makeItems(accountId: String, nfts: [ApiNft]) -> [NftDetailsItem] {
        let accountContext = AccountContext(accountId: accountId)
        let accountType = accountContext.account.type
        let domains = accountContext.domains

        return nfts.map { nft in
            let attributes: [NftDetailsItem.Attribute]? = nft.metadata?.attributes?.map { .init(traitType: $0.trait_type, value: $0.value) }

            let tonDomain = domains.expirationDays(for: nft).map {
                NftDetailsItem.TonDomain(
                    expirationDays: $0,
                    canRenew: accountType != .view && !nft.isOnSale
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
                collection: nft.collection.map { NftDetailsItem.Collection(name: $0.name) },
                tonDomain: tonDomain,
            )
        }
    }

    private func resolveNft(for model: NftDetailsItemModel) -> ApiNft? {
        guard let result = nfts.first(where: { $0.id == model.id}) else {
            assertionFailure("Unable to find nft '\(model.name)'")
            return nil
        }
        return result
    }

    private func isOwnedByAccount(_ nft: ApiNft, displayNft: DisplayNft? = nil) -> Bool {
        if let displayNft = displayNft ?? NftStore.getNft(accountId: accountId, nftId: nft.id) {
            if let ownerAddress = displayNft.nft.ownerAddress?.nilIfEmpty,
               let accountAddress = account.getAddress(chain: displayNft.nft.chain)?.nilIfEmpty {
                return addressesMatch(ownerAddress, accountAddress, chain: displayNft.nft.chain)
            }
            return true
        }
        if NftStore.getAccountNfts(accountId: accountId) != nil {
            return false
        }
        if let ownerAddress = nft.ownerAddress?.nilIfEmpty,
           let accountAddress = account.getAddress(chain: nft.chain)?.nilIfEmpty {
            return addressesMatch(ownerAddress, accountAddress, chain: nft.chain)
        }
        return false
    }

    private func addressesMatch(_ lhs: String, _ rhs: String, chain: ApiChain) -> Bool {
        if chain.isEvm {
            return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        }
        return lhs == rhs
    }

    override func nftDetailsDidSetActiveModel(_ model: NftDetailsItemModel) {
        guard let nft = resolveNft(for: model), nft.isMtwCard, isOwnedByAccount(nft) else {
            return
        }
        MtwCardImagePreloader.preload(nft)
    }
        
    override func ntfDetailsOnConfigureAction(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsActionConfig? {
        guard let nft = resolveNft(for: model) else { return nil }
        
        switch action {
        case .wear:
            guard nft.isMtwCard, isOwnedByAccount(nft) else { return nil }
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
                    let accountId = self.accountId
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
                                            log.info("cardBackground.uiReset source=nftDetails accountId=\(accountId, .public) nftAddress=\(nft.address, .public) nftChain=\(nft.chain.rawValue, .public) nftMtwId=\(mtwCardId)")
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
                                            log.info("cardBackground.uiInstall source=nftDetails accountId=\(accountId, .public) nftAddress=\(nft.address, .public) nftChain=\(nft.chain.rawValue, .public) nftMtwId=\(mtwCardId)")
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
            guard account.supportsSend, isOwnedByAccount(nft), !nft.isOnSale else { return nil }
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
                    let network = AccountContext(accountId: self.accountId).account.network
                    AppActions.shareUrl(ExplorerHelper.viewNftUrl(network: network, nftAddress: nft.address))
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
                    let displayNft = NftStore.getNft(accountId: accountId, nftId: nft.id)
                    let isOwned = self.isOwnedByAccount(nft, displayNft: displayNft)
                    var items: [ContextMenuItem] = []
                    
                    if isOwned, nft.isLinkableDns, !nft.isOnSale, accountType != .view {
                        let linkedAddress = accountContext.domains.linkedAddressByAddress[nft.address]?.nilIfEmpty
                        let title = linkedAddress == nil ? lang("Link to Wallet") : lang("Change Linked Wallet")
                        items.append(
                            .action(
                                ContextMenuAction(
                                    title: title,
                                    icon: .system("link"),
                                    handler: {
                                        AppActions.showLinkDomain(accountSource: .accountId(accountId), nftAddress: nft.address, nft: nft)
                                    }
                                )
                            )
                        )
                    }
                    
                    if isOwned {
                        if displayNft?.isHiddenByUser == true {
                            items.append(.action(hideMenuAction(nft, title: lang("Unhide"), icon: .system("eye"), hide: false)))
                        } else if nft.isScam == true, displayNft?.isUnhiddenByUser != true {
                            items.append(.action(hideMenuAction(nft, title: lang("Not Scam"), icon: .system("checkmark.shield"), hide: false)))
                        } else {
                            items.append(.action(hideMenuAction(nft, title: lang("Hide"), icon: .airBundle("MenuHide26"), hide: true)))
                        }
                    }
                    
                    if account.supportsBurn, isOwned, nft.chain.isNftBurnSupported, !nft.isOnSale {
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
                    if !items.isEmpty {
                        items.append(.separator)
                    }
                    if let url = nft.fragmentUrl {
                        items.append(
                            .action(
                                ContextMenuAction(
                                    title: "Fragment",
                                    icon: .airBundle("MenuFragment26", renderingMode: .original),
                                    handler: {
                                        AppActions.openInBrowser(url)
                                    }
                                )
                            )
                        )
                    }
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
                    } else if let marketplace = ExplorerHelper.marketplaceNftWebsite(nft) {
                        items.append(
                            .action(
                                ContextMenuAction(
                                    title: marketplace.title,
                                    icon: .airBundle("SendGlobe"),
                                    handler: {
                                        AppActions.openInBrowser(marketplace.address)
                                    }
                                )
                            )
                        )
                    }
                    if let url = ExplorerHelper.tonDnsManagementUrl(nft) {
                        items.append(
                            .action(
                                ContextMenuAction(
                                    title: "TON Domains",
                                    icon: .airBundle("MenuTonDomains26", renderingMode: .original),
                                    handler: {
                                        AppActions.openInBrowser(url)
                                    }
                                )
                            )
                        )
                    }
                    let explorerIconRenderingMode: ContextMenuIconRenderingMode =
                        ExplorerHelper.selectedExplorerHasMenuIconAsset(for: nft.chain) ? .original : .template
                    items.append(
                        .action(
                            ContextMenuAction(
                                title: ExplorerHelper.selectedExplorerName(for: nft.chain),
                                icon: .airBundle(
                                    ExplorerHelper.selectedExplorerMenuIconName(for: nft.chain),
                                    renderingMode: explorerIconRenderingMode
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
                    guard let nc = navigationController else {
                        assertionFailure()
                        return
                    }
                    let vc = NftsFullScreenVC(accountSource: .accountId(accountId), filter: .collection(collection))
                    nc.pushViewController(vc, animated: true)
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
    
    private func hideMenuAction(_ nft: ApiNft, title: String, icon: ContextMenuIcon?, hide: Bool) -> ContextMenuAction {
        return ContextMenuAction(
            title: title,
            icon: icon,
            handler: { [weak self] in self?.hideNft(nft, hide: hide) }
        )
    }
    
    private func showHideToast(_ nft: ApiNft, hide: Bool, delayToParentScreen: Bool = false) {
        let accountId = self.accountId
        let delayEnoughToHideThisScreen: TimeInterval = 1.0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + (delayToParentScreen ? delayEnoughToHideThisScreen : 0)) {
            if hide {
                AppActions.showToast(style: .large,
                                     message: lang("The NFT has been hidden"),
                                     transition: .floatUp,
                                     actionTitle: lang("Change")) { [weak self] in
                    
                    if !delayToParentScreen, let nc = self?.navigationController {
                        let vc = HiddenNftsVC(onUnhideNft: { [weak self] nftId in
                            self?.pendingSelectionNftId = nftId
                        })
                        nc.pushViewController(vc, animated: true)
                    } else {
                        AppActions.showHiddenNfts(accountSource: .accountId(accountId))
                    }

                }
            } else {
                AppActions.showToast(style: .large,
                                     message: lang("The NFT is no longer hidden"),
                                     transition: .floatUp
                )
            }
        }
    }

    private func hideNft(_ nft: ApiNft, hide: Bool) {
        switch sourceContext.source {
        case .collectionNfts, .singleNft:
            if hide {
                removeNft(id: nft.id)
                NftStore.setHiddenByUser(accountId: accountId, nftId: nft.id, isHidden: true)
                showHideToast(nft, hide: hide, delayToParentScreen: nfts.isEmpty)
            } else {
                NftStore.setHiddenByUser(accountId: accountId, nftId: nft.id, isHidden: false)
                showHideToast(nft, hide: hide, delayToParentScreen: false)
            }
        case .hiddenManagement:
            NftStore.setHiddenByUser(accountId: accountId, nftId: nft.id, isHidden: hide)
            dismissSelf()
        }
    }
}

extension NftDetailsVC: NftDetailsDisplayStateProviding {
    func isOnSale(for model: NftDetailsItemModel) -> Bool {
        NftStore.getNft(accountId: accountId, nftId: model.id)?.nft.isOnSale
            ?? resolveNft(for: model)?.isOnSale
            ?? false
    }

    func isHiddenByUser(for model: NftDetailsItemModel) -> Bool {
        NftStore.getNft(accountId: accountId, nftId: model.id)?.isHiddenByUser ?? false
    }
}

private class SourceContext {
    let accountId: String
    let source: NftDetailsDataSource
    private var singleNftInitiallyHidden = false
    
    init(accountId: String, source: NftDetailsDataSource) {
        self.accountId = accountId
        self.source = source
    }

    func getInitialData() -> (nfts: [ApiNft], selectedNft: ApiNft) {
        var nfts: [ApiNft]
        let selectedNft: ApiNft
        
        switch source {
        case .collectionNfts(selection: let selection, filter: let filter):
            let shownNfts = getShownNfts()
            nfts = filter.apply(to: shownNfts).values.map(\.nft)
            if !nfts.contains(where: { $0.id == selection.id }) {
                nfts.append(selection)
            }
            selectedNft = selection
            
        case .singleNft(let nft):
            if nftBelongsToAccount(nft) {
                let shownNfts = getShownNfts()
                if shownNfts[nft.id] == nil {
                    singleNftInitiallyHidden = true
                    nfts = [nft]
                } else {
                    nfts = shownNfts.values.map(\.nft)
                }
            } else {
                nfts = [nft]
            }
            selectedNft = nft
            
        case .hiddenManagement(let nft):
            nfts = [nft]
            selectedNft = nft
        }
        
        return (nfts, selectedNft)
    }
  
    func getNextData() -> [ApiNft] {
        switch source {
        case .collectionNfts(_, let filter):
            let shownNfts = getShownNfts()
            return filter.apply(to: shownNfts).values.map(\.nft)
            
        case .singleNft(let nft):
            if singleNftInitiallyHidden {
                return NftStore.getNft(accountId: accountId, nftId: nft.id) != nil ? [nft] : []
            }
            if nftBelongsToAccount(nft) {
                return getShownNfts().values.map(\.nft)
            }
            return [nft]
            
        case .hiddenManagement(let nft):
            return NftStore.getNft(accountId: accountId, nftId: nft.id) != nil ? [nft] : []
        }
    }

    private func getShownNfts() -> OrderedDictionary<String, DisplayNft> {
        NftStore.getAccountShownNfts(accountId: accountId) ?? [:]
    }
            
    private func nftBelongsToAccount(_ nft: ApiNft) -> Bool {
        let accountNfts = NftStore.getAccountNfts(accountId: accountId) ?? [:]
        return accountNfts.values.contains { displayNft in displayNft.nft.id == nft.id }
    }
}
