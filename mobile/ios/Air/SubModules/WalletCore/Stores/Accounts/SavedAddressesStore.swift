import Foundation
import Dependencies
import Perception
import WalletContext

@Perceptible
public final class SavedAddressesStore {
    
    private var _byAccountId: UnfairLock<[String: SavedAddresses]> = .init(initialState: [:])
    
    public func `for`(accountId: String) -> SavedAddresses {
        access(keyPath: \.__byAccountId)
        return _byAccountId.withLock { _byAccountId in
            if let settings = _byAccountId[accountId] {
                return settings
            }
            let savedAddresses = SavedAddresses(accountId: accountId)
            _byAccountId[accountId] = savedAddresses
            return savedAddresses
        }
    }
}

extension SavedAddressesStore: DependencyKey {
    public static let liveValue: SavedAddressesStore = SavedAddressesStore()
}

extension DependencyValues {
    public var savedAddresses: SavedAddressesStore {
        self[SavedAddressesStore.self]
    }
}

@Perceptible
public final class SavedAddresses {
    
    public let accountId: String
    
    init(accountId: String) {
        self.accountId = accountId
    }
    
    private var key: String { "byAccountId.\(accountId).savedAddresses" }
    
    public var values: [SavedAddress] {
        access(keyPath: \.values)
        if let value = GlobalStorage[key], let addresses = try? JSONSerialization.decode([SavedAddress].self, from: value) {
            return addresses
        }
        return []
    }

    public func save(_ newValue: SavedAddress, addOnly: Bool = false) {
        withMutation(keyPath: \.values) {
            var values = self.values.filter { !$0.matches(newValue) }
            guard !addOnly || values.count == self.values.count else { return }
            values.append(newValue)
            if let object = try? JSONSerialization.encode(values) {
                GlobalStorage.update { $0[key] = object }
                Task { try? await GlobalStorage.syncronize() }
            }
        }
    }

    public func delete(_ valueToDelete: SavedAddress) {
        withMutation(keyPath: \.values) {
            let values = self.values.filter { !$0.matches(valueToDelete) }
            if let object = try? JSONSerialization.encode(values) {
                GlobalStorage.update { $0[key] = object }
                Task { try? await GlobalStorage.syncronize() }
            }
        }
    }
    
    public func getMatching(_ searchString: String) -> [SavedAddress] {
        return searchString.isEmpty ? values : values
            .filter { $0.name.lowercased().contains(searchString) || $0.address.lowercased().contains(searchString) }
    }
    
    public func get(chain: ApiChain, address: String) -> SavedAddress? {
        values.first(where: { $0.matches(chain: chain, address: address )})
    }
}
