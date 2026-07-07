import ContextMenuKit
import ObjectiveC
import UIKit

@MainActor private var accountCellContextMenuInteractionKey: UInt8 = 0

public extension UICollectionViewCell {
    @MainActor
    func setAccountContextMenuInteraction(_ interaction: ContextMenuInteraction?) {
        if let currentInteraction = objc_getAssociatedObject(self, &accountCellContextMenuInteractionKey) as? ContextMenuInteraction {
            currentInteraction.detach()
        }
        objc_setAssociatedObject(self, &accountCellContextMenuInteractionKey, interaction, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        interaction?.attach(to: self)
    }
}
