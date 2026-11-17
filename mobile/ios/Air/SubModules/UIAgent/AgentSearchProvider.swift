import BigInt
@preconcurrency import Combine
import Foundation
import WalletContext
import WalletCore

public struct AgentSuggestion: Hashable, Sendable {
    public let id: String
    public let catalogVersion: String
    public let title: String
    public let prompt: String

    public init(id: String, catalogVersion: String, title: String, prompt: String) {
        self.id = id
        self.catalogVersion = catalogVersion
        self.title = title
        self.prompt = prompt
    }
}

@MainActor
public final class AgentSearchProvider {
    public static let shared = AgentSearchProvider()

    private let conversationChangedSubject = PassthroughSubject<Void, Never>()

    public var conversationChanged: AnyPublisher<Void, Never> {
        conversationChangedSubject.eraseToAnyPublisher()
    }

    private init() {}

    /// A new pick of starter hints for the account on every call
    public func loadSuggestions(accountId: String?) async throws -> [AgentSuggestion] {
        let account = accountId.flatMap { AccountStore.accountsById[$0] }
        return try await loadSuggestions(client: AgentPreloader.shared.client, activeAccount: account)
    }

    /// The wallet state the active account's suggestions are picked for
    public func getActiveWalletState() -> ApiAgentV2HintWalletState? {
        AccountStore.account.flatMap { AgentPreloader.shared.client.hintWalletState(of: $0) }
    }

    func loadSuggestions(client: AgentV2Client, activeAccount: MAccount?) async throws -> [AgentSuggestion] {
        let response = try await client.loadStarterHints(for: activeAccount)
        return response.items.map { item in
            let prompt = AgentV2Copy.hint(item.id)
            return AgentSuggestion(
                id: item.id.rawValue,
                catalogVersion: response.catalogVersion,
                title: prompt.title,
                prompt: prompt.prompt
            )
        }
    }

    func notifyConversationChanged() {
        conversationChangedSubject.send()
    }
}

extension ApiAgentV2HintWalletState {
    /// The state of a known total balance. A positive total is funded even while some chains are still loading, as
    /// loading more cannot empty it; a zero total is empty only once every chain has loaded, and unknown until then.
    init?(balance: BigInt?, hasLoadedBalances: Bool) {
        guard let balance else { return nil }
        if balance > 0 {
            self = .funded
            return
        }
        guard hasLoadedBalances else { return nil }
        self = .empty
    }
}
