import Foundation
import WalletContext

final class JSBridgeStorage: Sendable {
    enum Method: String, Sendable {
        case get = "airStorageGetItem"
        case set = "airStorageSetItem"
        case remove = "airStorageRemoveItem"
        case clear = "airStorageClear"
        case keys = "airStorageKeys"
    }

    enum Response: Sendable, Equatable {
        case value(String?)
        case keys([String])
        case void
    }

    private let provider: any IKeychainStorageProvider
    private let queue = DispatchQueue(label: "JSBridgeStorage", qos: .userInitiated)

    init(provider: any IKeychainStorageProvider = KeychainStorageProvider) {
        self.provider = provider
    }

    // Submit directly from the bridge's serial update queue to preserve storage ordering.
    // Keychain IPC can block, so it needs its own queue rather than the main actor or update queue.
    func enqueue(
        _ method: Method,
        key: String? = nil,
        value: String? = nil,
        completion: @escaping @Sendable (Result<Response, any Error>) -> Void
    ) {
        queue.async {
            completion(Result { try self.perform(method, key: key, value: value) })
        }
    }

    private func perform(_ method: Method, key: String?, value: String?) throws -> Response {
        switch method {
        case .get:
            guard let key else { throw KeychainStorageProviderError.invalidValue }
            return .value(try provider.load(key: key))
        case .set:
            guard let key, let value else { throw KeychainStorageProviderError.invalidValue }
            try provider.store(key: key, value: value)
            return .void
        case .remove:
            guard let key else { throw KeychainStorageProviderError.invalidValue }
            try provider.removeOrThrow(key: key)
            return .void
        case .clear:
            for key in provider.keys() {
                _ = provider.remove(key: key)
            }
            return .void
        case .keys:
            return .keys(provider.keys())
        }
    }
}
