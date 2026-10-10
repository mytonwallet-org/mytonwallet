import Foundation
import WalletContext
import WalletCore

/// Keeps one fully prepared conversation in memory until navigation takes ownership.
@MainActor
final class AgentPreloader: WalletCoreData.EventsObserver {
    static let shared = AgentPreloader(client: LiveAgentV2Client())

    let client: AgentV2Client
    private let now: () -> Date
    private let language: () -> String
    private let cacheLifetime: TimeInterval = 5 * 60
    private var isWalletReady = false
    private var preparation: Task<Void, Never>?
    private var generation = 0
    private var sessionGeneration = 0
    private var cachedModel: AgentV2Model?
    private var preparedAt: Date?
    private var preparedLanguage: String?
    private weak var activeModel: AgentV2Model?

    init(
        client: AgentV2Client,
        now: @escaping () -> Date = Date.init,
        language: @escaping () -> String = { LocalizationSupport.shared.langCode }
    ) {
        self.client = client
        self.now = now
        self.language = language
    }

    func setWalletReady(_ isReady: Bool) {
        isWalletReady = isReady
        WalletCoreData.remove(observer: self)
        if isReady {
            WalletCoreData.addImmediately(eventObserver: self)
            prepare()
        } else {
            sessionGeneration += 1
            discardPreparation()
            activeModel?.stop()
            activeModel = nil
        }
    }

    func prepare() {
        guard isWalletReady, activeModel == nil else { return }
        if preparedAt != nil, !isCacheFresh {
            discardPreparation()
        }
        guard preparation == nil, cachedModel == nil else { return }
        let generation = generation
        preparedLanguage = language()
        preparation = Task { [weak self] in
            guard let self else { return }
            let hasConsent = (try? await client.consent()) == true
            guard !Task.isCancelled, self.generation == generation else { return }
            guard hasConsent else {
                preparation = nil
                return
            }
            let model = AgentV2Model(client: client)
            cachedModel = model
            await model.waitForInitialLoad()
            guard !Task.isCancelled, self.generation == generation else { return }
            preparation = nil
            if model.isReadyForPresentation {
                preparedAt = now()
            } else {
                discardPreparation()
            }
        }
    }

    func takeReadyModel() -> AgentV2Model? {
        guard isCacheFresh, let model = cachedModel else {
            prepare()
            return nil
        }
        return takeOwnership(of: model)
    }

    /// Navigation joins a preload already in flight instead of starting a second coordinator.
    func acquireModel() async -> AgentV2Model? {
        let sessionGeneration = sessionGeneration
        if let model = takeReadyModel() { return model }
        await waitForPreparation()
        guard !Task.isCancelled, self.sessionGeneration == sessionGeneration else { return nil }
        if let model = takeReadyModel() { return model }
        // A failed speculative load should use the normal foreground error/retry path.
        discardPreparation()
        return takeOwnership(of: AgentV2Model(client: client))
    }

    func waitForPreparation() async {
        await preparation?.value
    }

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountsReset:
            setWalletReady(false)
        case .applicationWillEnterForeground, .accountChanged, .accountDeleted,
             .agentV2(.runtimeReady), .agentV2(.threadChanged):
            discardPreparation()
            prepare()
        default:
            break
        }
    }

    private var isCacheFresh: Bool {
        guard let preparedAt else { return false }
        return now().timeIntervalSince(preparedAt) < cacheLifetime
            && preparedLanguage == language()
    }

    private func takeOwnership(of model: AgentV2Model) -> AgentV2Model {
        cachedModel = nil
        preparedAt = nil
        activeModel = model
        model.onStop = { [weak self, weak model] in
            guard let self, let model, activeModel === model else { return }
            activeModel = nil
            prepare()
        }
        return model
    }

    private func discardPreparation() {
        generation += 1
        preparation?.cancel()
        preparation = nil
        cachedModel?.stop()
        cachedModel = nil
        preparedAt = nil
        preparedLanguage = nil
    }
}
