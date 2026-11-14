import UIKit
import UIComponents

extension AgentVC {
    /// Flies a news or digest card from the feed into this chat's post. The card's picture takes its place in `window` at once,
    /// at `frame` in the window's coordinates, under the feed's header, which ends at `contentTop` in the window, so the
    /// feed hides the card itself. Returns whether the card flies, which it does not with Reduce Motion.
    @discardableResult
    func prepareNewsPostArrival(
        snapshot: UIView, from frame: CGRect, contentTop: CGFloat, in window: UIWindow,
        navigationHost: UINavigationController? = nil, sourceHeaderBackground: UIView? = nil
    ) -> Bool {
        newsPostArrival?.cancel()
        guard !UIAccessibility.isReduceMotionEnabled else { return false }
        let arrival = AgentNewsPostArrival(card: snapshot, frame: frame, contentTop: contentTop) { [weak self] in
            self?.makeNewsPostArrivalDestination()
        }
        arrival.onFinish = { [weak self, weak arrival] in
            guard let self, self.newsPostArrival === arrival else { return }
            self.newsPostArrival = nil
        }
        newsPostArrival = arrival
        arrival.start(in: window, navigationHost: navigationHost, sourceHeaderBackground: sourceHeaderBackground)
        return true
    }

    private func makeNewsPostArrivalDestination() -> AgentNewsPostArrival.Destination? {
        guard let view = viewIfLoaded, let window = view.window, parent != nil,
              let model = model as? AgentV2Model else { return nil }
        let cell = model.newsPostItemID
            .flatMap { messageIndexPath(for: $0) }
            .flatMap { collectionView.cellForItem(at: $0) as? AgentNewsPostCell }
        return AgentNewsPostArrival.Destination(
            hostView: view,
            cell: cell,
            post: model.newsPostContent,
            contentTop: collectionView.getContentTopInWindow(),
            contentBottom: view.convertAsShown(composerView.convert(composerView.inputBackgroundFrame, to: view), to: window).minY,
            headerBackground: navigationBarBackground
        )
    }
}

extension UIScrollView {
    /// Where the bar over the list ends, in the window's coordinates: the top of the list's content area
    func getContentTopInWindow() -> CGFloat {
        convert(CGPoint(x: 0, y: bounds.minY + adjustedContentInset.top), to: nil).y
    }
}
