import Testing
@testable import WalletContext

@Suite("Log message privacy")
struct LogTests {
    @Test
    func `always redacts private fault values for remote reporting`() {
        let secret = "alpha beta gamma"
        let accountId = "0-mainnet"
        let message: LogMessage = "secret=\(secret) account=\(accountId, .public) retry=\(2) explicit=\(7, .redacted)"

        #expect(
            message.composedForRemoteReporting == "secret=<redacted> account=0-mainnet retry=2 explicit=<redacted>"
        )
    }
}
