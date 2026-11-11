import UIKit
import XCTest
@testable import AirAsFramework
import ProtectedAction
@testable import UIAgent
import UIComponents
import WalletContext
import WalletCore
import WalletResources

/// The Agent chat's toasts as the app shows them: `AppActions.showToast` finds the screen on top of the app's key
/// window, the chat pushed onto the main navigation, and shows the toast there
@MainActor
final class AgentChatToastPlacementTests: XCTestCase {
    private final class Backend: AgentBackend {
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

    /// What `configureAppActions()` replaces, given back once the test is done
    private var previousActions: (any AppActionsProtocol.Type)?
    private var previousExecutor: (any ProtectedActionExecuting.Type)?

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            previousActions = AppActions
            previousExecutor = ProtectedActionExecutor
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            if let previousActions {
                AppActions = previousActions
            }
            if let previousExecutor {
                ProtectedActionExecutor = previousExecutor
            }
        }
        super.tearDown()
    }

    /// A reaction's toast stands above the chat's composer, as Telegram's chat keeps its overlays above its input
    /// panel, and the composer keeps its height under it. With a host app the toast takes the app's own way, from
    /// `AppActions.showToast` through the key window; without one there is no scene for a key window, and the toast
    /// takes the same way from the window's root that `topWViewController()` takes from the key window's.
    func testAppToastStandsAboveTheChatsComposer() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window: UIWindow = scene.map { WWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        if let scene {
            window.frame = scene.coordinateSpace.bounds
        }

        let backend = Backend()
        let model = AgentModel(backend: backend)
        var answer = AgentMessage(role: .assistant, text: "Here is the answer.", isStreaming: false)
        answer.canRate = true
        let messages = [AgentMessage(role: .user, text: "Rate this", isStreaming: false), answer]
        backend.context?.replaceTimeline(with: messages.map(AgentTimelineItem.message), animated: false)
        let chat = AgentVC(model: model)
        let navigation = WNavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.rootViewController = nil
            window.isHidden = true
        }
        navigation.pushViewController(chat, animated: false)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(20))
            window.layoutIfNeeded()
        }

        let toast = AgentReactionToasts.makeToast(for: .like)
        if scene != nil {
            configureAppActions()
            XCTAssertTrue(topWViewController() === chat, "The app's toasts go to the chat on top")
            AppActions.showToast(toast)
        } else {
            let top = try XCTUnwrap(window.rootViewController?.visibleContentViewController as? WViewController)
            XCTAssertTrue(top === chat, "The app's toasts go to the chat on top")
            top.showToast(toast)
        }
        let toastView = try XCTUnwrap(chat.view.subviews.compactMap { $0 as? ToastView }.first)
        defer { toastView.removeFromSuperview() }
        chat.view.layoutIfNeeded()
        let composer = chat.composerView
        XCTAssertEqual(composer.bounds.height, composer.intrinsicContentSize.height, accuracy: 0.5, "The toast squeezes nothing")
        let fieldTop = composer.convert(composer.inputBackgroundFrame, to: chat.view).minY
        XCTAssertEqual(toastView.frame.maxY, fieldTop - AgentVCLayout.toastSpacingToComposer, accuracy: 0.5)
        XCTAssertEqual(AgentVCLayout.toastSpacingToComposer, 23, "Telegram's 12 pt over the messages' inset, 11 pt above the field")
    }
}
