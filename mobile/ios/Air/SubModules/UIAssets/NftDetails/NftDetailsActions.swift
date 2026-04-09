import ContextMenuKit
import UIComponents

struct NftDetailsActionConfig {
    var onTap: (() -> Void)?
    var onMenuConfiguration: (() -> ContextMenuConfiguration)?
}

protocol NftDetailsActionsDelegate: AnyObject {
    func ntfDetailsOnConfigureAction(forModel model: NftDetailsItemModel, action: NftDetailsItemModel.Action) -> NftDetailsActionConfig?
}
