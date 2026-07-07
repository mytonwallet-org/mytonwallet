import AppIntents
import Foundation
import WalletCore

@available(iOS 18.4, *)
public struct AccountEntity: AppEntity, Identifiable, Sendable, Hashable, Codable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Account"))
    public static let defaultQuery = AccountEntityQuery()

    public let id: String
    fileprivate let displayTitle: String

    public var displayRepresentation: DisplayRepresentation {
        .init(title: "\(displayTitle)")
    }

    public init(id: String, displayTitle: String) {
        self.id = id
        self.displayTitle = displayTitle
    }
}

@available(iOS 18.4, *)
public struct AccountEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [AccountEntity.ID]) async throws -> [AccountEntity] {
        let accounts = loadAccounts()
        let accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.account.id, $0.entity) })
        return identifiers.map {
            accountsById[$0] ?? AccountEntity(id: $0, displayTitle: AccountEntityTitle.fallbackTitle)
        }
    }

    public func suggestedEntities() async throws -> IntentItemCollection<AccountEntity> {
        let entities = loadAccounts().map(\.entity)
        return IntentItemCollection(items: entities)
    }

    public func entities(matching string: String) async throws -> IntentItemCollection<AccountEntity> {
        let string = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let entities = loadAccounts()
            .filter { account, entity in
                account.title?.localizedCaseInsensitiveContains(string) == true
                    || entity.displayTitle.localizedCaseInsensitiveContains(string)
            }
            .map(\.entity)

        return IntentItemCollection(items: entities)
    }

    private func loadAccounts() -> [(account: MAccount, entity: AccountEntity)] {
        AccountStore.orderedAccounts.enumerated().map { index, account in
            (
                account,
                AccountEntity(
                    id: account.id,
                    displayTitle: AccountEntityTitle.displayTitle(for: account, index: index)
                )
            )
        }
    }
}

@available(iOS 18.4, *)
enum AccountEntityTitle {
    static func displayTitle(for account: MAccount, index: Int) -> String {
        if let title = account.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        let walletTitle = Bundle.main.localizedString(forKey: "Wallet", value: "Wallet", table: nil)
        return "\(walletTitle) \(index + 1)"
    }

    static var fallbackTitle: String {
        Bundle.main.localizedString(forKey: "Wallet", value: "Wallet", table: nil)
    }
}
