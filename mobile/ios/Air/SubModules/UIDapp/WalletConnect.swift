import WalletCore
import WalletContext

private let log = Log("WalletConnect")

public final class WalletConnect {
    public static let shared = WalletConnect()

    private init() {}

    public func handleDeeplink(_ url: String) {
        Task { @MainActor in
            do {
                try await Api.walletConnect_handleDeepLink(url)
            } catch {
                log.error("failed to handle deeplink: \(error, .public)")
                AppActions.showError(error: error)
            }
        }
    }
}
