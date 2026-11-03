import UIKit
import UIComponents

extension AgentVC: AgentChatNavigationHandoff {
    public var navigationHandoffLeadingView: UIView? {
        AgentChatNavigation.findCircle(in: navigationItem.leftBarButtonItem)
    }

    public var navigationHandoffTrailingView: UIView? {
        AgentChatNavigation.findCircle(in: navigationItem.rightBarButtonItem)
    }

    public func setNavigationHandoffHidden(_ isHidden: Bool) {
        AgentChatNavigation.setButtonsHidden(isHidden, in: navigationItem)
    }
}

extension AgentVC: WBackSwipeControlling {
    public func shouldAllowBackSwipe(at point: CGPoint) -> Bool {
        AgentChatBackSwipe.shouldAllowBackSwipe(in: view, at: point)
    }
}

extension AgentVC: AgentComposerHandoffTarget {
    public func setComposerHandoffHidden(_ isHidden: Bool) {
        composerView.alpha = isHidden ? 0 : 1
    }

    /// Shows `overlay` under the messages, and so under the header's backdrop and the composer
    func insertUnderMessages(_ overlay: UIView) {
        view.insertSubview(overlay, belowSubview: collectionView)
    }

    /// Brings the messages on screen in as they replace a skeleton, as the News feed brings its cards in
    func revealMessagesFromSkeleton(placeholders: [AgentMessagesSkeletonView.Placeholder] = []) {
        AgentSkeletonReveal.revealRows(
            in: collectionView,
            isRightToLeft: view.effectiveUserInterfaceLayoutDirection == .rightToLeft,
            placeholders: placeholders
        ) { [weak self] _, indexPath in
            guard let self, let listItemID = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
            switch listItemID {
            case .bottomSpacer:
                return nil
            case .unreadDivider:
                return .line
            case .message(let itemID):
                guard case .message(let message)? = self.model.item(for: itemID) else { return .bubble(isOutgoing: false) }
                if message.role == .system || message.isFailureCaption {
                    return .line
                }
                return .bubble(isOutgoing: message.role == .user)
            }
        }
    }

    public func getComposerHandoffFrame(in window: UIWindow) -> CGRect? {
        guard composerView.window === window else { return nil }
        return composerView.convert(composerView.inputBackgroundFrame, to: window)
    }
}
