import Foundation
import Testing
@testable import WalletContext

struct ToolbarSettingsTests {
    @Test(arguments: [false, true]) func `switches from before the toolbar could be rearranged carry over`(showsScan: Bool) throws {
        let defaults = try makeDefaults()
        #expect(HomeToolbarConfiguration().visibleItems == [.search, .scan, .actions])
        #expect(ToolbarSettings.configuration(in: defaults) == HomeToolbarConfiguration())
        defaults.set(true, forKey: ToolbarSettings.accountsKey)
        defaults.set(showsScan, forKey: ToolbarSettings.scanKey)
        defaults.set(false, forKey: ToolbarSettings.sharedBackgroundKey)
        #expect(ToolbarSettings.configuration(in: defaults) == .init(showsAccounts: true, showsScan: showsScan, sharesBackground: false))
    }

    @Test func `a stored arrangement survives and replaces the old switches`() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: ToolbarSettings.accountsKey)
        var configuration = HomeToolbarConfiguration()
        configuration.order = [.send, .search, .actions, .scan, .accounts, .buy, .fund, .trade, .sell, .earn]
        configuration.setShown(true, .send)
        configuration.actionsOrder = [.scan, .buy, .fund, .trade, .sell, .send, .earn]
        configuration.isAccountsAtStart = true
        ToolbarSettings.setConfiguration(configuration, in: defaults)
        let stored = ToolbarSettings.configuration(in: defaults)
        #expect(stored == configuration)
        #expect(stored.visibleItems == [.send, .search, .actions, .scan])
        #expect(!stored.showsAccounts)
    }

    @Test func `items missing from a stored arrangement join it with their default visibility`() throws {
        let defaults = try makeDefaults()
        defaults.set([
            "order": ["scan", "search", "actions", "scan", "unknown"],
            "hidden": ["search", "actions"],
            "actionsOrder": ["send", "search"],
        ] as [String: Any], forKey: ToolbarSettings.configurationKey)
        let stored = ToolbarSettings.configuration(in: defaults)
        #expect(stored.order == [.scan, .search, .actions, .accounts, .buy, .fund, .trade, .sell, .send, .earn])
        #expect(stored.visibleItems == [.scan, .search, .actions])
        #expect(stored.actionsOrder == [.send, .buy, .fund, .trade, .sell, .earn, .scan])
        #expect(stored.sharesBackground)
    }

    @Test func `the search field and the actions button cannot be hidden`() {
        var configuration = HomeToolbarConfiguration()
        configuration.setShown(false, .search)
        configuration.setShown(false, .actions)
        #expect(configuration.hiding([.search, .actions, .scan]).visibleItems == [.search, .actions])
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "ToolbarSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

struct HomeToolbarLayoutTests {
    @Test(arguments: [false, true]) func `buttons stand on both sides of the field`(sharesBackground: Bool) throws {
        let layout = HomeToolbarLayout(items: [.accounts, .send, .search, .scan, .actions], sharesBackground: sharesBackground)
        let stride: CGFloat = sharesBackground ? 48 : 56
        let groupSpan = stride + 48 + 12
        #expect(layout.fieldLeadingInset == groupSpan)
        #expect(layout.fieldTrailingInset == groupSpan)
        let starts = try [HomeToolbarItem.accounts, .send, .scan, .actions].map {
            layout.getStart(of: try #require(layout.slot(for: $0)), length: 400)
        }
        #expect(starts == [0, stride, 400 - stride - 48, 400 - 48])
    }

    @Test func `a field with no buttons beside it takes the whole toolbar`() {
        let layout = HomeToolbarLayout(items: [.search], sharesBackground: true)
        #expect(layout.buttonsSpan == 0)
        #expect(layout.slots.isEmpty)
    }

    @Test func `the toolbar refuses a button that would squeeze the field`() {
        var configuration = HomeToolbarConfiguration()
        for item in [HomeToolbarItem.accounts, .buy, .fund] { configuration.setShown(true, item) }
        // Five buttons after the field take 252 points with their gap
        #expect(HomeToolbarLayout.canHold(.send, in: configuration, length: 348 + 48))
        #expect(!HomeToolbarLayout.canHold(.send, in: configuration, length: 347 + 48))
        #expect(HomeToolbarLayout.canHold(.fund, in: configuration, length: 100))
    }

    @Test(arguments: [false, true]) func `a narrow toolbar leaves out the buttons last in order`(sharesBackground: Bool) {
        let items: [HomeToolbarItem] = [.accounts, .fund, .search, .trade, .scan, .actions]
        func getFittingItems(length: CGFloat) -> [HomeToolbarItem] {
            HomeToolbarLayout.getFittingItems(items, sharesBackground: sharesBackground, length: length)
        }
        let span = HomeToolbarLayout(items: items, sharesBackground: sharesBackground).buttonsSpan
        #expect(getFittingItems(length: span + 64) == items)
        #expect(getFittingItems(length: span + 63) == [.accounts, .fund, .search, .trade, .actions])
        // The actions button stays when nothing else does
        #expect(getFittingItems(length: 100) == [.search, .actions])
    }

    @Test func `a dragged button takes the place nearest to the finger`() {
        let order = HomeToolbarConfiguration().order
        let shownItems: Set<HomeToolbarItem> = [.search, .scan, .actions]
        func getVisibleOrder(toward position: CGFloat) -> [HomeToolbarItem] {
            HomeToolbarLayout.getOrder(
                moving: .scan,
                in: order,
                shownItems: shownItems,
                sharesBackground: true,
                toward: position,
                length: 334
            ).filter(shownItems.contains)
        }
        #expect(getVisibleOrder(toward: 20) == [.scan, .search, .actions])
        #expect(getVisibleOrder(toward: 262) == [.search, .scan, .actions])
        #expect(getVisibleOrder(toward: 320) == [.search, .actions, .scan])
        // Staying over its own place keeps the stored order, hidden items included
        #expect(HomeToolbarLayout.getOrder(
            moving: .scan, in: order, shownItems: shownItems, sharesBackground: true, toward: 262, length: 334
        ) == order)
    }
}
