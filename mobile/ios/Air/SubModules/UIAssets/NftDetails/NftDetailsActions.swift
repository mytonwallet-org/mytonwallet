import UIComponents

struct NftDetailsToolbarButtonConfig {
    var onTap: (() -> Void)?
    var onMenuConfiguration: (() -> MenuConfig)?
}

protocol NftDetailsActionsDelegate: AnyObject {
    func nftDetailsOnShowCollection(forModel model: NftDetailsItemModel)
    func nftDetailsOnRenewDomain(forModel model: NftDetailsItemModel)
    func ntfDetailsOnConfigureToolbarButton(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsToolbarButtonConfig?
}
