import Foundation
import WalletCore

@MainActor
final class AgentPreloader: WalletCoreData.EventsObserver {
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
    private var newsModels: [Int: WeakModel] = [:]
    private var openingModels: [WeakModel] = []
    private var deletedThreadIds: Set<String> = []
    /// Recently opened chats stay loaded, so reopening one shows its messages at once
    private var recentModels: [AgentV2Model] = []
    private static let recentModelLimit = 8

    init(client: AgentV2Client) {
        self.client = client
    }

    func setWalletReady(_ isReady: Bool) {
        WalletCoreData.remove(observer: self)
        if isReady {
            WalletCoreData.addImmediately(eventObserver: self)
        } else {
            sessionGeneration += 1
            let recent = recentModels
            recentModels.removeAll()
            recent.forEach { $0.releasePresentation() }
            let activeModels = models.values.compactMap(\.value) + newsModels.values.compactMap(\.value) + openingModels.compactMap(\.value)
            models.removeAll()
            newsModels.removeAll()
            openingModels.removeAll()
            deletedThreadIds.removeAll()
            activeModels.forEach { $0.stop() }
        }
    }

    func acquireModel(
        thread: ApiAgentV2ThreadSummary,
        news: (item: ApiAgentV2NewsFeedItem, locale: String)? = nil
    ) -> AgentV2Model? {
        guard !isThreadDeleted(thread.id) else { return nil }
        models = models.filter { $0.value.value != nil }
        if let model = model(threadId: thread.id) {
            if let news { model.updateNewsPreview(news.item) }
            return model
        }
        let model: AgentV2Model
        if let news {
            model = AgentV2Model(client: client, thread: thread, news: news.item, locale: news.locale) { _ in }
        } else {
            model = AgentV2Model(client: client, thread: thread)
        }
        models[thread.id] = WeakModel(model)
        model.onStop = { [weak self, weak model] in
            guard let self, let model, self.models[thread.id]?.value === model else { return }
            self.models.removeValue(forKey: thread.id)
        }
        return model
    }

    /// Keeps a presented chat's model loaded after its screen closes, up to a few recent chats
    func keepRecent(_ model: AgentV2Model) {
        guard model.threadId != nil else { return }
        if let index = recentModels.firstIndex(where: { $0 === model }) {
            recentModels.remove(at: index)
        } else {
            model.retainPresentation()
        }
        recentModels.append(model)
        while recentModels.count > Self.recentModelLimit {
            recentModels.removeFirst().releasePresentation()
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
        newsModels = newsModels.filter { $0.value.value != nil }
        if let model = newsModel(eventId: item.eventId) {
            return model
        }
        return acquireOpeningModel(newsEventId: item.eventId, onThreadCreated: onThreadCreated) { onCreated in
            AgentV2Model(client: client, news: item, locale: locale, onThreadCreated: onCreated)
        }
    }

    private func acquireOpeningModel(
        newsEventId: Int? = nil,
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
            if let newsEventId { self.newsModels.removeValue(forKey: newsEventId) }
            self.keepRecent(model)
            onThreadCreated(thread)
        }
        openingModel = model
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
                if let newsEventId { self.newsModels.removeValue(forKey: newsEventId) }
                onThreadCreated(thread)
                return existing
            }
            return nil
        }
        openingModels.append(WeakModel(model))
        if let newsEventId { newsModels[newsEventId] = WeakModel(model) }
        model.onStop = { [weak self, weak model] in
            guard let self, let model else { return }
            self.openingModels.removeAll { $0.value == nil || $0.value === model }
            if let newsEventId, self.newsModels[newsEventId]?.value === model {
                self.newsModels.removeValue(forKey: newsEventId)
            }
            if let threadId = model.threadId, self.models[threadId]?.value === model {
                self.models.removeValue(forKey: threadId)
            }
        }
        return model
    }

    func newsModel(eventId: Int) -> AgentV2Model? {
        newsModels[eventId]?.value
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
        let deleted = recentModels.filter { $0.threadId == threadId }
        recentModels.removeAll { $0.threadId == threadId }
        deleted.forEach { $0.releasePresentation() }
        models.removeValue(forKey: threadId)?.value?.stop()
    }

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountsReset:
            setWalletReady(false)
        case .agentThreadDeleted(let threadId):
            invalidateDeletedThread(threadId)
        default:
            break
        }
    }
}
