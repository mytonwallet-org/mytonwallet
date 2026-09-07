import Testing
@testable import WalletCore

@Suite("Home Activity Visible Items Limit")
struct HomeActivityVisibleItemsLimitTests {
    @Test
    func `unsupported stored limit falls back to top five`() {
        #expect(HomeActivityVisibleItemsLimit(storedValue: 7) == .top5)
    }
}
