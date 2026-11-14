import UIKit
import WalletCore
import WalletContext

public enum AgentEntryPoint {
    /// With `isSummaryCached`, the summary is the SDK's copy from a past session, whose unread state is unknown until
    /// the history loads: the chat loads under the skeleton rather than opening on its cached history
    @MainActor
    public static func makeRootViewController(
        thread: ApiAgentV2ThreadSummary,
        isSummaryCached: Bool = false
    ) -> UIViewController {
        makeRootViewController(thread: thread, preloader: .shared, isSummaryCached: isSummaryCached)
    }

    @MainActor
    static func makeRootViewController(
        thread: ApiAgentV2ThreadSummary,
        preloader: AgentPreloader,
        isSummaryCached: Bool = false
    ) -> UIViewController {
        if let model = preloader.model(threadId: thread.id) {
            model.refreshThreadIfNeeded(thread)
            // A chat that got an answer since it took its cached history waits for its history, as an unread chat does
            if model.isReadyForPresentation
                || model.isShowingCachedMessages && !isSummaryCached && !AgentThreadReadState.shared.isUnread(thread) {
                preloader.keepRecent(model)
                return AgentVC(model: model)
            }
        } else if !isSummaryCached,
                  preloader.getCachedHistory(threadId: thread.id) != nil,
                  let model = preloader.acquireModel(thread: thread) {
            // A chat that may show its cached history opens with it; one that may not loads under the skeleton
            preloader.keepRecent(model)
            if model.isShowingCachedMessages {
                return AgentVC(model: model)
            }
        }
        return AgentRootVC(thread: thread, preloader: preloader, isSummaryCached: isSummaryCached)
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

    /// A new chat that asks for a support operator once it has loaded, as Contact Support among the starter hints does
    @MainActor
    static func makeSupportChatViewController(preloader: AgentPreloader = .shared) -> UIViewController {
        AgentRootVC(client: preloader.client, preloader: preloader, shouldRequestSupport: true)
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
    public static func makeNewsChatViewController(eventId: Int) async throws -> UIViewController {
        try await makeNewsChatViewController(eventId: eventId, client: LiveAgentNewsFeedClient(), preloader: .shared)
    }

    @MainActor
    static func makeNewsChatViewController(eventId: Int, client: AgentNewsFeedClient, preloader: AgentPreloader) async throws -> UIViewController {
        let generation = preloader.sessionGeneration
        let page = try await client.getNewsFeed(
            lang: LocalizationSupport.shared.langCode, cursor: nil, schedule: .current, view: .all
        )
        guard preloader.sessionGeneration == generation else { throw CancellationError() }
        if let item = page.items.first(where: { $0.eventId == eventId }) {
            return makeNewsChatViewController(item: item, locale: page.locale, preloader: preloader, onThreadCreated: { _ in })
        }
        return AgentVC(model: preloader.acquireNewsModel(request: .init(eventId: eventId, locale: page.locale)))
    }

    @MainActor
    public static func makeDigestChatViewController(digestId: String) -> UIViewController {
        AgentVC(model: AgentPreloader.shared.acquireDigestModel(id: digestId))
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
            // The consent sheet an opening waits on goes with the chat
            let presentation = AgentConsentSheetPresentation.current
            if let presented = presentation.presentedViewController(of: controller), !presented.isBeingDismissed,
               (presented as? UINavigationController)?.viewControllers.first is AgentConsentSheetVC {
                if presentation.whenPresented(presented, {
                    removeDeletedChat(controller, animated: animated, completion: completion)
                }) {
                    return
                }
                presentation.dismiss(presented, animated: animated) {
                    removeDeletedChat(controller, animated: animated, completion: completion)
                }
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
