import Foundation
import MyAgent
import WalletCore
import WalletContext
import FoundationModels

private let log = Log("AgentStore")

@MainActor
public final class AgentStore {

    public static let shared = AgentStore()

    private let historyStore = AgentHistoryStore()
    private var isStarted = false
    private var isHistoryReady = false
    var isLocalBackendAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
    }

    private var lastKnowledgeBaseVersion: String?

    private init() {}

    public func start() {
        if !isStarted {
            WalletCoreData.add(eventObserver: self)
            isStarted = true
        }
        syncKnowledgeBase()
    }

    public func clean() {
        if isStarted {
            WalletCoreData.remove(observer: self)
            isStarted = false
        }
        isHistoryReady = false
        lastKnowledgeBaseVersion = nil
        historyStore.clean()
    }

    public func resetConversation() {
        connectHistoryIfNeeded()
        historyStore.save(messages: [])
    }

    func persistedTimelineItems() -> [AgentTimelineItem] {
        connectHistoryIfNeeded()
        return historyStore.loadMessages().map(AgentTimelineItem.message)
    }

    func saveHistory(messages: [AgentMessage]) {
        connectHistoryIfNeeded()
        historyStore.save(messages: messages)
    }

    private func connectHistoryIfNeeded() {
        guard !isHistoryReady, let db = WalletCore.db else { return }
        historyStore.connect(db: db)
        isHistoryReady = true
    }

    private func syncKnowledgeBase() {
        guard let version = ConfigStore.shared.knowledgeBaseVersion,
              version != lastKnowledgeBaseVersion else { return }
        lastKnowledgeBaseVersion = version
        Task { await KnowledgeBase.shared.load(version: version) }
    }
}

extension AgentStore: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .configChanged:
            syncKnowledgeBase()
        default:
            break
        }
    }
}
