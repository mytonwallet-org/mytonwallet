import UIKit
import UIComponents
import XCTest
@testable import UIAgent

/// A key window as large as the test phone's screen that shows `rootViewController`
@MainActor
func makeKeyWindow(showing rootViewController: UIViewController) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    return window
}

/// Runs the handler of `alert`'s action titled `title`, as a tap on it does, without the alert's own dismissal
@MainActor
func performAlertAction(titled title: String, in alert: UIAlertController) {
    typealias Handler = @convention(block) (UIAlertAction) -> Void
    guard let action = alert.actions.first(where: { $0.title == title }),
          let block = action.value(forKey: "handler") else { return }
    unsafeBitCast(block as AnyObject, to: Handler.self)(action)
}

/// Makes the chat of `threadId` count as one this device never showed, which opens at its latest message: a chat shown
/// before with fewer messages than it has now opens at the "New" divider over the rest
@MainActor
func forgetChatReadState(threadId: String) {
    AgentThreadReadState.shared.remove(threadId: threadId)
}

/// The consent sheet that `controller` asks with: it shows `controller`'s navigation in a key window, which a sheet
/// needs, and waits for the sheet. The window goes when the test ends.
@MainActor
func waitForConsentSheet(
    over controller: UIViewController,
    in test: XCTestCase,
    scene: UIWindowScene? = nil
) async throws -> AgentConsentSheetVC {
    let host = controller.navigationController ?? controller
    if host.view.window == nil {
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        test.addTeardownBlock {
            MainActor.assumeIsolated {
                window.rootViewController?.presentedViewController?.dismiss(animated: false)
                window.isHidden = true
            }
        }
    }
    let presentation = AgentConsentSheetPresentation.current
    for _ in 0..<300 {
        if let presented = presentation.presentedViewController(of: controller) ?? presentation.presentedViewController(of: host),
           !presented.isBeingDismissed,
           let sheet = (presented as? UINavigationController)?.viewControllers.first as? AgentConsentSheetVC {
            sheet.loadViewIfNeeded()
            return sheet
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("The consent sheet did not show")
    throw CancellationError()
}

/// The consent sheet's presentation for a test, which runs without a window scene, where UIKit never finishes
/// bringing a sheet up or taking it away: a sheet comes up at once, or stays coming up until `finishPresenting` when
/// `isFinishingAtOnce` is false, and goes on the next turn of the run loop, as UIKit's would after its animation.
/// `install(in:)` puts it in place for the test and takes it away as the test ends.
@MainActor
final class AgentTestConsentSheetPresentation: AgentConsentSheetPresentation {
    private var sheets: [ObjectIdentifier: UIViewController] = [:]
    private var presenters: [ObjectIdentifier: UIViewController] = [:]
    private var comingUp: [ObjectIdentifier: [() -> Void]] = [:]
    /// Every sheet that came up, in order
    private(set) var presentedSheets: [UIViewController] = []
    private(set) var dismissalCount = 0
    var isFinishingAtOnce = true

    static func install(in test: XCTestCase) -> AgentTestConsentSheetPresentation {
        let presentation = AgentTestConsentSheetPresentation()
        let previous = AgentConsentSheetPresentation.current
        AgentConsentSheetPresentation.current = presentation
        test.addTeardownBlock {
            MainActor.assumeIsolated { AgentConsentSheetPresentation.current = previous }
        }
        return presentation
    }

    override func presentedViewController(of presenter: UIViewController) -> UIViewController? {
        sheets[ObjectIdentifier(presenter)] ?? presenter.presentedViewController
    }

    override func present(_ sheet: UIViewController, over presenter: UIViewController) {
        sheets[ObjectIdentifier(presenter)] = sheet
        presenters[ObjectIdentifier(sheet)] = presenter
        presentedSheets.append(sheet)
        sheet.loadViewIfNeeded()
        if !isFinishingAtOnce {
            comingUp[ObjectIdentifier(sheet)] = []
        }
    }

    override func isPresented(_ sheet: UIViewController) -> Bool {
        presenters[ObjectIdentifier(sheet)] != nil
    }

    /// `sheet` is still coming up
    func isComingUp(_ sheet: UIViewController) -> Bool {
        comingUp[ObjectIdentifier(sheet)] != nil
    }

    override func whenPresented(_ sheet: UIViewController, _ action: @escaping () -> Void) -> Bool {
        guard comingUp[ObjectIdentifier(sheet)] != nil else { return false }
        comingUp[ObjectIdentifier(sheet)]?.append(action)
        return true
    }

    /// Ends the coming up of every sheet still coming up, which runs what waited for it
    func finishPresenting() {
        let waiting = comingUp
        comingUp = [:]
        for actions in waiting.values {
            actions.forEach { $0() }
        }
    }

    override func dismiss(_ sheet: UIViewController, animated: Bool, completion: @escaping () -> Void) {
        guard let presenter = presenters.removeValue(forKey: ObjectIdentifier(sheet)) else {
            completion()
            return
        }
        dismissalCount += 1
        comingUp[ObjectIdentifier(sheet)] = nil
        DispatchQueue.main.async { [weak self] in
            self?.sheets[ObjectIdentifier(presenter)] = nil
            completion()
        }
    }
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
        /// A question goes at once, or with only `canAcceptMessages` waits for the answer being written
        var canSendMessages = true
        var canAcceptMessages = true
        /// The Agent thinks on each question that goes, its typing row coming once the chat has brought the question up
        var isThinkingOnSend = false

        func attach(to context: AgentBackendContext) { self.context = context }
        func detach() { context = nil }
        func loadHints(animated: Bool) {}
        func prepareForEditing(_ editContext: AgentBackendEditContext) {}
        func didSendUserMessage(
            _ text: String,
            userMessageID: AgentItemID,
            source: AgentBackendSendSource,
            editContext: AgentBackendEditContext?
        ) {
            guard isThinkingOnSend else { return }
            context?.append(.typingIndicator(AgentTypingIndicator()), animated: true)
        }
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
