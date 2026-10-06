#if DEBUG
import Foundation
import WalletContext

private let log = Log("E2EWalletSession")

/// End-to-end tests start the app with the same synthetic wallet session as the web app's tests:
/// `E2E_WALLET_SESSION` holds the web app's persisted global state and SDK storage records. They are
/// written where the Capacitor app kept them, so the first launch migrates them as it migrates the
/// wallet of a user upgrading from it.
@MainActor
enum E2EWalletSession {
    static func seedIfRequested() async {
        guard AirLauncher.isFirstLaunch,
              let value = ProcessInfo.processInfo.environment["E2E_WALLET_SESSION"], !value.isEmpty else {
            return
        }
        do {
            guard let session = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  let globalState = session["globalState"] as? [String: Any],
                  let storage = session["storage"] as? [String: Any] else {
                throw KeychainStorageProviderError.invalidValue
            }
            // The simulator keeps keychain items across reinstalls; a test must not inherit another's wallet.
            KeychainHelper.deleteAllWallets()
            for (key, record) in storage {
                let data = try JSONSerialization.data(withJSONObject: record, options: .fragmentsAllowed)
                try KeychainStorageProvider.store(key: key, value: String(decoding: data, as: UTF8.self))
            }
            let global = GlobalStorage()
            global.update { $0[""] = globalState }
            try await global.syncronize()
            log.info("seeded \(storage.count) storage records")
        } catch {
            // A test that runs without its wallet would check the wrong state.
            fatalError("E2E_WALLET_SESSION could not be seeded: \(error)")
        }
    }
}
#endif
