import Dependencies
import GRDB
import Testing
import UIComponents
import UIKit
import WalletContext
@testable import WalletCore
@testable import UIAssets

@Suite(.serialized) @MainActor
struct PerpsPositionsSummaryTests {
    init() throws {
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        SettingsStore.liveValue.use(db: database)
    }

    private func data(_ amount: Double) -> PerpsPositionsDisplayData {
        .init(accountID: "header-test", totalValue: .fromDouble(amount, .USD),
              profitLoss: .init("−$110 · 36.7%", tone: .negative), positions: [])
    }

    @Test func zeroAndUnavailableBalancesOmitTheChangeLine() {
        #expect(PerpsPositionsSummaryCell.height(for: data(0)) == 132)
        #expect(PerpsPositionsSummaryCell.height(for: data(190.26)) == 172)
        var loading = data(190.26)
        loading.status = .loading
        #expect(!PerpsPositionsSummaryCell.showsChange(for: loading))
        loading.status = .unavailable("Offline")
        #expect(!PerpsPositionsSummaryCell.showsChange(for: loading))
    }

    @Test func privacyDoesNotMoveEitherLineForSmallOrLargeBalances() async throws {
        try await withDependencies { $0.context = .live } operation: {
            @Dependency(\.sensitiveData) var sensitiveData
            let wasHidden = sensitiveData.isHidden
            defer { sensitiveData.isHidden = wasHidden }
            for width: CGFloat in [320, 402] {
                for amount in [0.0, 190.26, 1_234_567_890_123.45] {
                    sensitiveData.isHidden = false
                    let cell = PerpsPositionsSummaryCell(frame: CGRect(x: 0, y: 0, width: width, height: 172))
                    var snapshot = data(amount)
                    snapshot.isStale = true
                    cell.configure(snapshot)
                    cell.layoutIfNeeded()
                    let balanceFrame = cell.balance.convert(cell.balance.bounds, to: cell.contentView)
                    let changeFrame = cell.change.convert(cell.change.bounds, to: cell.contentView)
                    #expect(balanceFrame.midY == 83)
                    #expect(changeFrame.midY == 130 || amount == 0)
                    let labelFrame = cell.balance.alignmentFrame(for: cell.balance.displayedBalance,
                        style: .homeNavigationBarCollapsed, isHidden: false)
                    #expect(labelFrame.width <= cell.balance.bounds.width + 1)
                    sensitiveData.isHidden = true
                    try await Task.sleep(for: .milliseconds(20))
                    cell.layoutIfNeeded()
                    #expect(cell.balance.convert(cell.balance.bounds, to: cell.contentView) == balanceFrame)
                    #expect(cell.change.convert(cell.change.bounds, to: cell.contentView) == changeFrame)
                    #expect(cell.balance.displayedBalance != nil)
                    #expect(cell.balance.alpha == 1)
                    #expect(cell.balance.accessibilityLabel == lang("Tap to reveal"))
                    #expect(cell.change.accessibilityElementsHidden == (amount == 0))
                    if amount != 0 { #expect(cell.change.accessibilityLabel == lang("Tap to reveal")) }
                }
            }
        }
    }

    @Test func collectionResizesWhenChangeAppearsAndDisappears() async throws {
        try await withDependencies { $0.context = .live } operation: {
            let controller = PerpsHomeVC(data: .init(positions: data(0)), onAction: { _ in })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            defer { window.isHidden = true; window.rootViewController = nil }
            for amount in [0.0, 190.26, 0.0, 190.26] {
                controller.update(data: .init(positions: data(amount)))
                try await Task.sleep(for: .milliseconds(400))
                controller.view.layoutIfNeeded()
                let collection = try #require(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
                let cell = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? PerpsPositionsSummaryCell)
                #expect(cell.bounds.height == PerpsPositionsSummaryCell.height(for: data(amount)))
                #expect(cell.change.superview?.alpha == (amount == 0 ? 0 : 1))
                #expect(cell.change.accessibilityElementsHidden == (amount == 0))
                #expect(cell.balance.convert(cell.balance.bounds, to: cell.contentView).midY == 83)
            }
        }
    }
}
