import Foundation
import Testing
@testable import WalletContext

struct ToolbarSettingsTests {
    @Test(arguments: [false, true]) func defaultsAndExplicitSettings(showsScan: Bool) throws {
        let name = "ToolbarSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(HomeToolbarConfiguration() == .init(showsAccounts: false, showsScan: true, sharesBackground: true))
        #expect(ToolbarSettings.configuration(in: defaults) == HomeToolbarConfiguration())
        defaults.set(true, forKey: ToolbarSettings.accountsKey)
        defaults.set(showsScan, forKey: ToolbarSettings.scanKey)
        defaults.set(false, forKey: ToolbarSettings.sharedBackgroundKey)
        #expect(ToolbarSettings.configuration(in: defaults) == .init(showsAccounts: true, showsScan: showsScan, sharesBackground: false))
    }
}
