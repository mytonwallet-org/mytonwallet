import AppIntents
import Foundation
import WalletContext
import WalletCore
import WalletCoreTypes

@available(iOS 18.4, *)
public struct RecipientEntity: AppEntity, Identifiable, Sendable, Hashable, Codable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Recipient"))
    public static let defaultQuery = RecipientEntityQuery()

    public let id: String
    public var kind: AirSendTokenRecipientKind
    public var displayTitle: String
    public var addressOrDomain: String?
    public var chainRawValue: String?
    public var accountId: String?

    public var displayRepresentation: DisplayRepresentation {
        if let subtitle = self.subtitle?.nilIfEmpty {
            .init(title: "\(displayTitle)", subtitle: "\(subtitle)")
        } else {
            .init(title: "\(displayTitle)")
        }
    }

    public init(
        kind: AirSendTokenRecipientKind,
        displayTitle: String,
        addressOrDomain: String?,
        chainRawValue: String?,
        accountId: String?
    ) {
        self.kind = kind
        self.displayTitle = displayTitle
        self.addressOrDomain = addressOrDomain
        self.chainRawValue = chainRawValue
        self.accountId = accountId
        self.id = Self.id(
            kind: kind,
            accountId: accountId,
            chainRawValue: chainRawValue,
            addressOrDomain: addressOrDomain
        )
    }

    public var systemRecipient: AirSendTokenRecipient {
        AirSendTokenRecipient(
            kind: kind,
            addressOrDomain: addressOrDomain,
            chain: chainRawValue,
            accountId: accountId
        )
    }

    private var subtitle: String? {
        switch kind {
        case .account:
            return addressOrDomain.map { formatStartEndAddress($0) }
        case .savedAddress:
            return [chainRawValue?.uppercased(), addressOrDomain.map { formatStartEndAddress($0) }]
                .compactMap { $0 }
                .joined(separator: " - ")
        case .rawAddressOrDomain:
            return nil
        }
    }

    private static func id(
        kind: AirSendTokenRecipientKind,
        accountId: String?,
        chainRawValue: String?,
        addressOrDomain: String?
    ) -> String {
        switch kind {
        case .account:
            return "recipient:v1:account:\(Self.encode(accountId ?? ""))"
        case .savedAddress:
            return "recipient:v1:saved:\(Self.encode(chainRawValue ?? "")):\(Self.encode(addressOrDomain ?? ""))"
        case .rawAddressOrDomain:
            return "recipient:v1:raw:\(Self.encode(addressOrDomain ?? ""))"
        }
    }

    @MainActor
    fileprivate static func parse(id: String) -> RecipientEntity? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, parts[0] == "recipient", parts[1] == "v1" else {
            return nil
        }

        switch parts[2] {
        case "account":
            guard parts.count == 4, let accountId = decode(parts[3]) else { return nil }
            return accountEntity(accountId: accountId)
        case "saved":
            guard
                parts.count == 5,
                let chainRawValue = decode(parts[3]),
                let chain = ApiChain(rawValue: chainRawValue),
                let address = decode(parts[4])
            else {
                return nil
            }
            let saved = AccountStore.orderedAccounts
                .lazy
                .compactMap { AccountContext(source: .accountId($0.id)).savedAddresses.get(chain: chain, address: address) }
                .first
            return savedAddressEntity(saved ?? SavedAddress(name: formatStartEndAddress(address), address: address, chain: chain))
        case "raw":
            guard parts.count == 4, let value = decode(parts[3]) else { return nil }
            return rawEntity(value)
        default:
            return nil
        }
    }

    private static func accountEntity(accountId: String) -> RecipientEntity? {
        guard let account = AccountStore.accountsById[accountId] else { return nil }
        let address = account.getAddress(chain: .ton) ?? account.supportedChains.first.flatMap { account.getAddress(chain: $0) }
        return RecipientEntity(
            kind: .account,
            displayTitle: AccountEntityTitle.displayTitle(for: account, index: accountIndex(accountId: accountId)),
            addressOrDomain: address,
            chainRawValue: nil,
            accountId: accountId
        )
    }

    fileprivate static func savedAddressEntity(_ savedAddress: SavedAddress) -> RecipientEntity {
        RecipientEntity(
            kind: .savedAddress,
            displayTitle: savedAddress.name,
            addressOrDomain: savedAddress.address,
            chainRawValue: savedAddress.chain.rawValue,
            accountId: nil
        )
    }

    fileprivate static func rawEntity(_ value: String) -> RecipientEntity {
        RecipientEntity(
            kind: .rawAddressOrDomain,
            displayTitle: value,
            addressOrDomain: value,
            chainRawValue: nil,
            accountId: nil
        )
    }

    private static func accountIndex(accountId: String) -> Int {
        AccountStore.orderedAccounts.firstIndex(where: { $0.id == accountId }) ?? 0
    }

    private static func encode(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ value: String) -> String? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@available(iOS 18.4, *)
public struct RecipientEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [RecipientEntity.ID]) async throws -> [RecipientEntity] {
        await MainActor.run {
            identifiers.compactMap(RecipientEntity.parse(id:))
        }
    }

    public func suggestedEntities() async throws -> IntentItemCollection<RecipientEntity> {
        let accounts = await Self.accountEntities(senderId: nil, token: nil, excludesSender: false)
        let savedAddresses = await Self.savedAddressEntities(senderId: nil, token: nil)
        return Self.collection(accounts: accounts, savedAddresses: savedAddresses, raw: [])
    }

    public func entities(matching string: String) async throws -> IntentItemCollection<RecipientEntity> {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.lowercased()
        let accounts = await Self.accountEntities(senderId: nil, token: nil, excludesSender: false).filter {
            $0.displayTitle.lowercased().contains(normalizedQuery)
                || $0.addressOrDomain?.lowercased().contains(normalizedQuery) == true
        }
        let savedAddresses = await Self.savedAddressEntities(senderId: nil, token: nil).filter {
            $0.displayTitle.lowercased().contains(normalizedQuery)
                || $0.addressOrDomain?.lowercased().contains(normalizedQuery) == true
                || $0.chainRawValue?.lowercased().contains(normalizedQuery) == true
        }
        let raw = query.isEmpty ? [] : [RecipientEntity.rawEntity(query)]

        return Self.collection(accounts: accounts, savedAddresses: savedAddresses, raw: raw)
    }

    fileprivate static func collection(
        accounts: [RecipientEntity],
        savedAddresses: [RecipientEntity],
        raw: [RecipientEntity]
    ) -> IntentItemCollection<RecipientEntity> {
        var sections: [IntentItemSection<RecipientEntity>] = []
        if !accounts.isEmpty {
            sections.append(IntentItemSection(LocalizedStringResource("My Accounts"), items: accounts))
        }
        if !savedAddresses.isEmpty {
            sections.append(IntentItemSection(LocalizedStringResource("Saved Addresses"), items: savedAddresses))
        }
        if !raw.isEmpty {
            sections.append(IntentItemSection(LocalizedStringResource("Address or Domain"), items: raw))
        }
        return IntentItemCollection(sections: sections)
    }

    @MainActor
    fileprivate static func accountEntities(senderId: String?, token: TokenEntity?, excludesSender: Bool) -> [RecipientEntity] {
        let sender = senderId.flatMap { AccountStore.accountsById[$0] }
        let chain = token.flatMap { ApiChain(rawValue: $0.chainRawValue) }
        return AccountStore.orderedAccounts.enumerated().compactMap { index, account -> RecipientEntity? in
            if excludesSender, account.id == senderId {
                return nil
            }
            if let sender, account.network != sender.network {
                return nil
            }
            if let chain, !account.supports(chain: chain) {
                return nil
            }
            let address = account.getAddress(chain: .ton) ?? account.supportedChains.first.flatMap { account.getAddress(chain: $0) }
            return RecipientEntity(
                kind: .account,
                displayTitle: AccountEntityTitle.displayTitle(for: account, index: index),
                addressOrDomain: address,
                chainRawValue: nil,
                accountId: account.id
            )
        }
    }

    @MainActor
    fileprivate static func savedAddressEntities(senderId: String?, token: TokenEntity?) -> [RecipientEntity] {
        let chain = token.flatMap { ApiChain(rawValue: $0.chainRawValue) }
        let accounts = senderId.flatMap { AccountStore.accountsById[$0].map { [$0] } } ?? AccountStore.orderedAccounts
        var entities: [RecipientEntity] = []
        var seen = Set<String>()
        for account in accounts {
            for savedAddress in AccountContext(source: .accountId(account.id)).savedAddresses.values {
                if let chain, savedAddress.chain != chain {
                    continue
                }
                let entity = RecipientEntity.savedAddressEntity(savedAddress)
                if seen.insert(entity.id).inserted {
                    entities.append(entity)
                }
            }
        }
        return entities
    }
}

@available(iOS 18.4, *)
public struct SendTokenRecipientEntityQuery: EntityStringQuery {
    @IntentParameterDependency<SendTokenIntent>(\.$sender, \.$token)
    public var intent

    public init() {}

    public func entities(for identifiers: [RecipientEntity.ID]) async throws -> [RecipientEntity] {
        try await RecipientEntityQuery().entities(for: identifiers)
    }

    public func suggestedEntities() async throws -> IntentItemCollection<RecipientEntity> {
        let senderId = intent?.sender.id ?? AccountStore.accountId
        let token = intent?.token
        let accounts = await RecipientEntityQuery.accountEntities(senderId: senderId, token: token, excludesSender: true)
        let savedAddresses = await RecipientEntityQuery.savedAddressEntities(senderId: senderId, token: token)
        return RecipientEntityQuery.collection(accounts: accounts, savedAddresses: savedAddresses, raw: [])
    }

    public func entities(matching string: String) async throws -> IntentItemCollection<RecipientEntity> {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.lowercased()
        let senderId = intent?.sender.id ?? AccountStore.accountId
        let token = intent?.token
        let accounts = await RecipientEntityQuery.accountEntities(senderId: senderId, token: token, excludesSender: true).filter {
            $0.displayTitle.lowercased().contains(normalizedQuery)
                || $0.addressOrDomain?.lowercased().contains(normalizedQuery) == true
        }
        let savedAddresses = await RecipientEntityQuery.savedAddressEntities(senderId: senderId, token: token).filter {
            $0.displayTitle.lowercased().contains(normalizedQuery)
                || $0.addressOrDomain?.lowercased().contains(normalizedQuery) == true
                || $0.chainRawValue?.lowercased().contains(normalizedQuery) == true
        }
        let raw = query.isEmpty ? [] : [RecipientEntity.rawEntity(query)]
        return RecipientEntityQuery.collection(accounts: accounts, savedAddresses: savedAddresses, raw: raw)
    }
}
