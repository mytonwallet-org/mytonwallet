import Foundation
import WalletCore

@MainActor
final class AgentPreloader: WalletCoreData.EventsObserver {
    /// The feed's post a discussion that waits for its thread is about, which opening the post again returns to
    private enum DiscussionKey: Hashable {
        case news(eventId: Int)
        case digest(id: String)
    }

    private final class WeakModel {
        weak var value: AgentV2Model?

        init(_ value: AgentV2Model) {
            self.value = value
        }
    }

    static let shared = AgentPreloader(client: LiveAgentV2Client())

    let client: AgentV2Client
    private(set) var sessionGeneration = 0
    private var models: [String: WeakModel] = [:]
    private var discussionModels: [DiscussionKey: WeakModel] = [:]
    private var openingModels: [WeakModel] = []
    private var deletedThreadIds: Set<String> = []
    /// Recently opened chats stay loaded, so reopening one shows its messages at once
    private var recentModels: [AgentV2Model] = []
    private static let recentModelLimit = 8
    private let cachedHistories: AgentCachedHistories
    /// The wallet is ready, and the SDK's cached histories belong to it
    private var isWalletReady = false

    init(client: AgentV2Client) {
        self.client = client
        cachedHistories = AgentCachedHistories(client: client)
    }

    /// Reads ahead the SDK's cached histories of the list's top threads, so their chats open with them
    func prefetchCachedHistories(of threads: [ApiAgentV2ThreadSummary]) {
        guard isWalletReady else { return }
        cachedHistories.prefetch(threads)
    }

    func getCachedHistory(threadId: String) -> AgentCachedHistory? {
        cachedHistories.getHistory(threadId: threadId)
    }

    func setWalletReady(_ isReady: Bool) {
        isWalletReady = isReady
        WalletCoreData.remove(observer: self)
        if isReady {
            WalletCoreData.addImmediately(eventObserver: self)
        } else {
            sessionGeneration += 1
            let recent = recentModels
            recentModels.removeAll()
            recent.forEach { $0.releasePresentation() }
            let activeModels = models.values.compactMap(\.value) + discussionModels.values.compactMap(\.value) + openingModels.compactMap(\.value)
            models.removeAll()
            discussionModels.removeAll()
            openingModels.removeAll()
            deletedThreadIds.removeAll()
            cachedHistories.removeAll()
            activeModels.forEach { $0.stop() }
        }
    }

    /// With `isSummaryCached`, a new chat shows no cached history: the summary is the SDK's copy, whose unread state is
    /// unknown
    func acquireModel(
        thread: ApiAgentV2ThreadSummary,
        news: (item: ApiAgentV2NewsFeedItem, locale: String)? = nil,
        digest: ApiAgentV2ThreadDigestCard? = nil,
        isSummaryCached: Bool = false
    ) -> AgentV2Model? {
        guard !isThreadDeleted(thread.id) else { return nil }
        models = models.filter { $0.value.value != nil }
        if let model = model(threadId: thread.id) {
            if let news {
                model.updateNewsPreview(news.item)
                model.updateNewsLocale(news.locale)
            }
            if let digest { model.updateDigestPreview(digest) }
            return model
        }
        let model: AgentV2Model
        if let news {
            model = AgentV2Model(client: client, thread: thread, news: news.item, locale: news.locale) { _ in }
        } else {
            model = AgentV2Model(
                client: client,
                thread: thread,
                digest: digest,
                cachedHistory: isSummaryCached ? nil : cachedHistories.getHistory(threadId: thread.id),
                isSummaryCached: isSummaryCached
            )
        }
        observeCachedHistory(of: model)
        models[thread.id] = WeakModel(model)
        model.onStop = { [weak self, weak model] in
            guard let self, let model, self.models[thread.id]?.value === model else { return }
            self.models.removeValue(forKey: thread.id)
        }
        return model
    }

    /// Keeps recent chats loaded after their screens close; queued questions and running answers outlive the limit
    func keepRecent(_ model: AgentV2Model) {
        guard model.threadId != nil || model.hasPendingDiscussionMessage else { return }
        if let index = recentModels.firstIndex(where: { $0 === model }) {
            recentModels.remove(at: index)
        } else {
            model.retainPresentation()
        }
        recentModels.append(model)
        var index = 0
        while index < recentModels.count - Self.recentModelLimit {
            if recentModels[index].hasQueuedQuestions || recentModels[index].hasActiveRun
                || recentModels[index].hasPendingDiscussionMessage {
                index += 1
            } else {
                recentModels.remove(at: index).releasePresentation()
            }
        }
    }

    /// The thread chats loaded now: on screen, opening or kept from a recent visit
    func getLoadedModels() -> [AgentV2Model] {
        models.values.compactMap(\.value)
    }

    func model(threadId: String) -> AgentV2Model? {
        guard let model = models[threadId]?.value else { return nil }
        guard !model.hasFailedInitialLoad else {
            model.stop()
            return nil
        }
        return model
    }

    func acquireQuestionModel(query: String, entryPoint: ApiAgentV2EntryPoint?) -> AgentV2Model {
        acquireOpeningModel { onThreadCreated in
            AgentV2Model(client: client, question: query, entryPoint: entryPoint, onThreadCreated: onThreadCreated)
        }
    }

    func acquireNewsModel(
        item: ApiAgentV2NewsFeedItem,
        locale: String,
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void
    ) -> AgentV2Model {
        discussionModels = discussionModels.filter { $0.value.value != nil }
        if let model = newsModel(eventId: item.eventId) {
            model.updateNewsPreview(item)
            model.updateNewsLocale(locale)
            return model
        }
        return acquireOpeningModel(discussionKey: .news(eventId: item.eventId), onThreadCreated: onThreadCreated) { onCreated in
            AgentV2Model(client: client, news: item, locale: locale, onThreadCreated: onCreated)
        }
    }

    func acquireNewsModel(request: ApiAgentV2ThreadNewsRequest) -> AgentV2Model {
        if let model = newsModel(eventId: request.eventId) {
            model.updateNewsLocale(request.locale)
            return model
        }
        return acquireOpeningModel(discussionKey: .news(eventId: request.eventId)) { onCreated in
            AgentV2Model(client: client, newsRequest: request, onThreadCreated: onCreated)
        }
    }

    /// A digest's discussion opened without the feed's copy of the digest
    func acquireDigestModel(id: String) -> AgentV2Model {
        acquireOpeningModel { onCreated in
            AgentV2Model(client: client, digestRequest: .init(id: id), onThreadCreated: onCreated)
        }
    }

    /// A digest's discussion opened from the feed's copy of the digest, which its post shows while its thread comes
    func acquireDigestModel(
        digest: ApiAgentV2NewsFeedDigest,
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void
    ) -> AgentV2Model {
        discussionModels = discussionModels.filter { $0.value.value != nil }
        if let model = digestModel(id: digest.id) {
            model.updateDigestPreview(digest)
            return model
        }
        return acquireOpeningModel(discussionKey: .digest(id: digest.id), onThreadCreated: onThreadCreated) { onCreated in
            AgentV2Model(client: client, digest: digest, onThreadCreated: onCreated)
        }
    }

    private func acquireOpeningModel(
        discussionKey: DiscussionKey? = nil,
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void = { _ in },
        makeModel: (@escaping (ApiAgentV2ThreadSummary) -> Void) -> AgentV2Model
    ) -> AgentV2Model {
        openingModels = openingModels.filter { $0.value != nil }
        let generation = sessionGeneration
        weak var openingModel: AgentV2Model?
        let model = makeModel { [weak self] thread in
            guard let self, let model = openingModel else { return }
            self.models[thread.id] = WeakModel(model)
            self.openingModels.removeAll { $0.value == nil || $0.value === model }
            if let discussionKey { self.discussionModels.removeValue(forKey: discussionKey) }
            self.keepRecent(model)
            onThreadCreated(thread)
        }
        openingModel = model
        model.onDiscussionMessageQueued = { [weak self, weak model] in
            guard let self, let model else { return }
            self.keepRecent(model)
        }
        model.resolveOpeningThreadModel = { [weak self, weak model] thread in
            guard let self, let model else { return nil }
            guard self.sessionGeneration == generation else {
                model.stop()
                return nil
            }
            guard !self.isThreadDeleted(thread.id) else {
                model.rejectDeletedThread(id: thread.id)
                return nil
            }
            if let existing = self.model(threadId: thread.id), existing !== model {
                existing.refreshThreadIfNeeded(thread)
                if model.hasPendingDiscussionMessage { self.keepRecent(existing) }
                if let discussionKey { self.discussionModels.removeValue(forKey: discussionKey) }
                onThreadCreated(thread)
                return existing
            }
            return nil
        }
        observeCachedHistory(of: model)
        openingModels.append(WeakModel(model))
        if let discussionKey { discussionModels[discussionKey] = WeakModel(model) }
        model.onStop = { [weak self, weak model] in
            guard let self, let model else { return }
            self.openingModels.removeAll { $0.value == nil || $0.value === model }
            if let discussionKey, self.discussionModels[discussionKey]?.value === model {
                self.discussionModels.removeValue(forKey: discussionKey)
            }
            if let threadId = model.threadId, self.models[threadId]?.value === model {
                self.models.removeValue(forKey: threadId)
            }
            if model.threadId == nil, let index = self.recentModels.firstIndex(where: { $0 === model }) {
                self.recentModels.remove(at: index).releasePresentation()
            }
        }
        return model
    }

    /// A history the chat loads takes the place of its thread's cached history
    private func observeCachedHistory(of model: AgentV2Model) {
        let generation = sessionGeneration
        model.onCachedHistoryChange = { [weak self] threadId, history in
            guard let self, self.isWalletReady, self.sessionGeneration == generation,
                  !self.isThreadDeleted(threadId) else { return }
            if let history {
                self.cachedHistories.store(history)
            } else {
                self.cachedHistories.remove(threadId: threadId)
            }
        }
    }

    func newsModel(eventId: Int) -> AgentV2Model? {
        discussionModels[.news(eventId: eventId)]?.value
    }

    func digestModel(id: String) -> AgentV2Model? {
        discussionModels[.digest(id: id)]?.value
    }

    func isThreadDeleted(_ threadId: String) -> Bool {
        deletedThreadIds.contains(threadId)
    }

    func deleteThread(id: String) {
        invalidateDeletedThread(id)
        WalletCoreData.notify(event: .agentThreadDeleted(threadId: id))
    }

    private func invalidateDeletedThread(_ threadId: String) {
        deletedThreadIds.insert(threadId)
        cachedHistories.remove(threadId: threadId)
        let deleted = recentModels.filter { $0.threadId == threadId }
        recentModels.removeAll { $0.threadId == threadId }
        deleted.forEach { $0.releasePresentation() }
        models.removeValue(forKey: threadId)?.value?.stop()
    }

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountsReset:
            client.forgetKnownConsent()
            setWalletReady(false)
        case .agentThreadDeleted(let threadId):
            invalidateDeletedThread(threadId)
        default:
            break
        }
    }
}
