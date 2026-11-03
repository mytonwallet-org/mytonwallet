import UIKit
import UIComponents
@testable import UIAgent

/// A key window as large as the test phone's screen that shows `rootViewController`
@MainActor
func makeKeyWindow(showing rootViewController: UIViewController) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    return window
}

/// Makes the chat of `threadId` count as one this device never showed, which opens at its latest message: a chat shown
/// before with fewer messages than it has now opens at the "New" divider over the rest
@MainActor
func forgetChatReadState(threadId: String) {
    AgentThreadReadState.shared.remove(threadId: threadId)
}

/// Every view under `view`, each one before its own subviews
@MainActor
func findDescendants(of view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + findDescendants(of: $0) }
}

/// A chat of `messages` in a key window, over a backend that answers nothing
@MainActor
final class AgentTestChat {
    final class Backend: AgentBackend {
        var context: AgentBackendContext?
        var isLoadingOlderMessages = false

        func attach(to context: AgentBackendContext) { self.context = context }
        func detach() { context = nil }
        func loadHints(animated: Bool) {}
        func prepareForEditing(_ editContext: AgentBackendEditContext) {}
        func didSendUserMessage(
            _ text: String,
            userMessageID: AgentItemID,
            source: AgentBackendSendSource,
            editContext: AgentBackendEditContext?
        ) {}
        func clearConversation() {}
    }

    let backend = Backend()
    let model: AgentModel
    let controller: AgentVC
    let window: UIWindow

    var collectionView: AgentCollectionView { controller.collectionView }

    init(messages: [AgentMessage], size: CGSize = CGSize(width: 402, height: 874)) {
        model = AgentModel(backend: backend)
        backend.context?.replaceTimeline(with: messages.map(AgentTimelineItem.message), animated: false)
        controller = AgentVC(model: model)
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
    }

    func close() {
        window.rootViewController = nil
        window.isHidden = true
    }

    func layout() {
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
    }

    /// The offset at which the last row's bottom stands just above the composer
    var latestOffsetY: CGFloat? {
        guard let indexPath = controller.lastItemIndexPath,
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return nil }
        return controller.clampedContentOffsetY(frame.maxY - collectionView.bounds.height + controller.occlusionBottomInset)
    }

    /// The tallest stretch of the visible rows' range that no displayed row covers, in the list's coordinates
    func getLargestUncoveredGap() -> CGFloat {
        let visibleRect = controller.visibleContentRect()
        let frames = collectionView.visibleCells
            .filter { !$0.isHidden && $0.bounds.height > 0 && !($0 is AgentSpacerCell) }
            .map(\.frame)
            .sorted { $0.minY < $1.minY }
        guard let firstRowY = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame.minY,
              let lastIndexPath = controller.lastItemIndexPath,
              let lastRowY = collectionView.layoutAttributesForItem(at: lastIndexPath)?.frame.maxY else { return 0 }
        let top = max(visibleRect.minY, firstRowY)
        let bottom = min(visibleRect.maxY, lastRowY)
        var covered = top
        var gap: CGFloat = 0
        for frame in frames where frame.maxY > top && frame.minY < bottom {
            gap = max(gap, frame.minY - covered)
            covered = max(covered, frame.maxY)
        }
        return max(gap, bottom - covered)
    }

    /// Waits until the list's offset, insets and rows stay put for 20 frames
    func waitForStableLayout(timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now + timeout
        var state = layoutState
        var stableSamples = 0
        while stableSamples < 20 {
            guard ContinuousClock.now < deadline else { throw AgentTestTimeout() }
            try await Task.sleep(for: .milliseconds(16))
            layout()
            let nextState = layoutState
            stableSamples = nextState == state ? stableSamples + 1 : 0
            state = nextState
        }
    }

    private var layoutState: [CGFloat] {
        [
            collectionView.contentOffset.y,
            collectionView.contentInset.bottom,
            collectionView.collectionViewLayout.collectionViewContentSize.height,
            controller.composerView.frame.minY,
        ]
    }
}

struct AgentTestTimeout: Error {}

/// The text field of an `AgentTextInputAlert`, once the alert's content is on screen
@MainActor
func waitForTextInputField(in alert: WAlertController) async throws -> AgentAlertTextFieldView {
    for _ in 0..<100 {
        alert.view.layoutIfNeeded()
        if let field = findDescendants(of: alert.view).compactMap({ $0 as? AgentAlertTextFieldView }).first {
            return field
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw AgentTestTimeout()
}
