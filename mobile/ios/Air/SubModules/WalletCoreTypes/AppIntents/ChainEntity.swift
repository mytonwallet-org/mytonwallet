import AppIntents
import Foundation

@available(iOS 18.4, *)
public struct ChainEntity: AppEntity, Identifiable, Sendable, Hashable, Codable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Network"))
    public static let defaultQuery = ChainEntityQuery()

    public let id: String
    fileprivate let title: String

    public var chain: ApiChain? {
        ApiChain(rawValue: id)
    }

    public var displayRepresentation: DisplayRepresentation {
        .init(title: "\(title)")
    }

    public init(chain: ApiChain) {
        self.id = chain.rawValue
        self.title = chain.title
    }
}

@available(iOS 18.4, *)
public struct ChainEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [ChainEntity.ID]) async throws -> [ChainEntity] {
        identifiers.compactMap { identifier in
            guard let chain = ApiChain(rawValue: identifier), chain.isSupported else {
                return nil
            }
            return ChainEntity(chain: chain)
        }
    }

    public func suggestedEntities() async throws -> IntentItemCollection<ChainEntity> {
        IntentItemCollection(items: Self.allEntities())
    }

    public func entities(matching string: String) async throws -> IntentItemCollection<ChainEntity> {
        let string = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let entities = Self.allEntities().filter {
            $0.title.localizedCaseInsensitiveContains(string)
                || $0.id.localizedCaseInsensitiveContains(string)
        }

        return IntentItemCollection(items: entities)
    }

    private static func allEntities() -> [ChainEntity] {
        ApiChain.allCases.map(ChainEntity.init(chain:))
    }
}
