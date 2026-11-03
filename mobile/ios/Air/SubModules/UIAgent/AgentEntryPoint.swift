import UIKit
import WalletCore

public enum AgentEntryPoint {
    @MainActor
    public static func makeRootViewController(thread: ApiAgentV2ThreadSummary) -> UIViewController {
        makeRootViewController(thread: thread, preloader: .shared)
    }

    @MainActor
    static func makeRootViewController(
        thread: ApiAgentV2ThreadSummary,
        preloader: AgentPreloader
    ) -> UIViewController {
        if let model = preloader.model(threadId: thread.id) {
            model.refreshThreadIfNeeded(thread)
            if model.isReadyForPresentation {
                preloader.keepRecent(model)
                return AgentVC(model: model)
            }
        }
        return AgentRootVC(thread: thread, preloader: preloader)
    }

    @MainActor
    public static func makeNewChatViewController(
        query: String? = nil,
        entryPoint: ApiAgentV2EntryPoint? = nil
    ) -> UIViewController {
        makeNewChatViewController(query: query, entryPoint: entryPoint, preloader: .shared)
    }

    @MainActor
    static func makeNewChatViewController(
        query: String? = nil,
        entryPoint: ApiAgentV2EntryPoint? = nil,
        preloader: AgentPreloader
    ) -> UIViewController {
        if let query = BaseAgentModel.normalizedText(from: query) {
            return AgentVC(model: preloader.acquireQuestionModel(query: query, entryPoint: entryPoint))
        }
        return AgentRootVC(client: preloader.client, preloader: preloader)
    }

    @MainActor
    static func makeNewsChatViewController(
        item: ApiAgentV2NewsFeedItem,
        locale: String,
        preloader: AgentPreloader = .shared,
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void
    ) -> UIViewController {
        AgentVC(
            model: preloader.acquireNewsModel(item: item, locale: locale, onThreadCreated: onThreadCreated)
        )
    }

    @MainActor
    public static func setWalletReady(_ isReady: Bool) {
        AgentPreloader.shared.setWalletReady(isReady)
    }

    /// Removes the chat of a deleted thread from its stack; `animated` pops it as the user leaves a chat they deleted
    @MainActor
    static func removeDeletedChat(_ controller: UIViewController, animated: Bool = false, completion: (() -> Void)? = nil) {
        // Root replacement can register observers after WalletCoreData finishes delivering its current event
        DispatchQueue.main.async { [weak controller] in
            guard let controller,
                  let navigationController = controller.navigationController,
                  let index = navigationController.viewControllers.firstIndex(of: controller) else {
                completion?()
                return
            }
            if index > 0, index == navigationController.viewControllers.count - 1 {
                // Wait for the confirmation to leave before starting the pop, so the root's toolbar participates.
                if let presented = navigationController.presentedViewController,
                   presented.isBeingDismissed,
                   let transition = presented.transitionCoordinator,
                   transition.animate(alongsideTransition: nil, completion: { _ in
                       removeDeletedChat(controller, animated: animated, completion: completion)
                   }) {
                    return
                }
                navigationController.popViewController(animated: animated)
                finishAfterTransition()
                return
            }
            var viewControllers = navigationController.viewControllers
            viewControllers.remove(at: index)
            if index == 0 {
                viewControllers.insert(AgentThreadListVC(userDefaults: .standard), at: 0)
            }
            navigationController.setViewControllers(viewControllers, animated: animated)
            finishAfterTransition()

            func finishAfterTransition() {
                if animated, let transition = navigationController.transitionCoordinator,
                   transition.animate(alongsideTransition: nil, completion: { _ in completion?() }) {
                    return
                }
                completion?()
            }
        }
    }
}
