import UIKit

@MainActor
protocol ContextMenuPresentationSession: AnyObject {
    /// Called once before `onDidDismiss`: as the overlay starts its dismissal, or with `onDidDismiss` for a system
    /// popover or sheet, whose dismissal UIKit can still cancel until it ends
    var onWillDismiss: (() -> Void)? { get set }
    var onDidDismiss: (() -> Void)? { get set }

    func beginExternalSelection(at pointInWindow: CGPoint)
    func updateExternalSelection(at pointInWindow: CGPoint)
    func endExternalSelection(performAction: Bool)
}
