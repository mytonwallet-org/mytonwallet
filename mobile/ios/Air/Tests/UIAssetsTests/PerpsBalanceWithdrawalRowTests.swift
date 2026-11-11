import Dependencies
import Testing
import UIKit
import UIComponents
import WalletContext
import WalletCore
import WalletResources
@testable import UIAssets

@Suite(.serialized) @MainActor
struct PerpsBalanceWithdrawalRowTests {
    private let row = PerpsBalanceWithdrawalRowDisplayData(token: .TONCOIN, balance: "$1.50")

    private func home(positions: Int, showsOnboarding: Bool = false, row: PerpsBalanceWithdrawalRowDisplayData?) -> PerpsHomeDisplayData {
        .init(positions: .init(accountID: "wallet", totalValue: .fromDouble(0, .USD), profitLoss: .init("$0"),
                               positions: (0..<positions).map {
                                   .init(id: "\($0)", token: .TONCOIN, directionAndLeverage: "Long 2x", value: "$20", profitLoss: .init("+$1"))
                               }),
              balanceWithdrawal: row, showsOnboarding: showsOnboarding)
    }

    private func layOut(_ data: PerpsHomeDisplayData, onAction: @escaping (PerpsHomeAction) -> Void = { _ in }) throws -> (PerpsHomeVC, UICollectionView) {
        _ = WalletResourcesBundle.bundle.load()
        let controller = PerpsHomeVC(data: data, onAction: onAction)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        controller.view.layoutIfNeeded()
        let collection = try #require(controller.view.subviews.first { $0 is UICollectionView } as? UICollectionView)
        return (controller, collection)
    }

    private func balanceCell(in collection: UICollectionView) throws -> (PerpsBalanceWithdrawalCell, IndexPath) {
        for section in 0..<collection.numberOfSections {
            let index = IndexPath(item: 0, section: section)
            if let cell = collection.cellForItem(at: index) as? PerpsBalanceWithdrawalCell { return (cell, index) }
        }
        throw PerpsBalanceRowMissing()
    }

    private struct PerpsBalanceRowMissing: Error {}

    @Test func rowFollowsOpenPositionsInACardOfItsOwn() throws {
        try withDependencies { $0.context = .live } operation: {
            let (controller, collection) = try layOut(home(positions: 2, row: row))
            _ = controller
            let (cell, index) = try balanceCell(in: collection)
            let lastPosition = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: index.section - 1)))
            let frame = try #require(collection.layoutAttributesForItem(at: index)?.frame)
            #expect(frame.minX == lastPosition.frame.minX && frame.width == lastPosition.frame.width)
            #expect(frame.height == PerpsPositionCell.height)
            #expect(collection.numberOfItems(inSection: index.section) == 1)
            #expect(cell.accessibilityIdentifier == "perps.balance")
        }
    }

    @Test(arguments: [false, true])
    func rowIsReachableWithoutPositions(showsOnboarding: Bool) throws {
        try withDependencies { $0.context = .live } operation: {
            let (controller, collection) = try layOut(home(positions: 0, showsOnboarding: showsOnboarding, row: row))
            _ = controller
            let (_, index) = try balanceCell(in: collection)
            #expect(index.section == (showsOnboarding ? 1 : 0))
            if !showsOnboarding {
                let frame = try #require(collection.layoutAttributesForItem(at: index)?.frame)
                #expect(frame.minY == 16)
            }
        }
    }

    @Test func noOfferMeansNoRow() throws {
        try withDependencies { $0.context = .live } operation: {
            let (controller, collection) = try layOut(home(positions: 2, row: nil))
            _ = controller
            #expect(throws: PerpsBalanceRowMissing.self) { try balanceCell(in: collection) }
        }
    }

    @Test func tappingRequestsTheWithdrawalUnlessOneIsBeingPrepared() throws {
        try withDependencies { $0.context = .live } operation: {
            var actions: [PerpsHomeAction] = []
            let (controller, collection) = try layOut(home(positions: 1, row: row)) { actions.append($0) }
            var (_, index) = try balanceCell(in: collection)
            let delegate = try #require(collection.delegate)
            #expect(delegate.collectionView?(collection, shouldSelectItemAt: index) == true)
            delegate.collectionView?(collection, didSelectItemAt: index)
            #expect(actions == [.withdrawBalance])

            var preparing = row
            preparing.isPreparing = true
            controller.update(data: home(positions: 1, row: preparing))
            controller.view.layoutIfNeeded()
            (_, index) = try balanceCell(in: collection)
            #expect(delegate.collectionView?(collection, shouldSelectItemAt: index) == false)
            delegate.collectionView?(collection, didSelectItemAt: index)
            #expect(actions == [.withdrawBalance])
        }
    }

    @Test func anAccountThatCannotWithdrawSeesTheRowAndCannotTapIt() throws {
        try withDependencies { $0.context = .live } operation: {
            var viewOnly = row
            viewOnly.canWithdraw = false
            var actions: [PerpsHomeAction] = []
            let (controller, collection) = try layOut(home(positions: 1, row: viewOnly)) { actions.append($0) }
            _ = controller
            let (cell, index) = try balanceCell(in: collection)
            let delegate = try #require(collection.delegate)
            #expect(delegate.collectionView?(collection, shouldSelectItemAt: index) == false)
            delegate.collectionView?(collection, didSelectItemAt: index)
            #expect(actions.isEmpty)
            let withdraw = try #require(descendants(cell).compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "perps.balance.withdraw" })
            #expect(withdraw.accessibilityTraits.contains(.notEnabled))
            #expect(withdraw.superview?.alpha == 0.5)
        }
    }

    /// The notice replaces the balance summary, the positions and the balance row.
    @Test func anAccountNoticeReplacesTheAccountsOwnSections() throws {
        try withDependencies { $0.context = .live } operation: {
            var data = home(positions: 2, row: row)
            data.accountNotice = "Futures require a multichain wallet."
            let (controller, collection) = try layOut(data)
            _ = controller
            let cells = collection.visibleCells
            #expect(cells.contains { $0.accessibilityIdentifier == "perps.accountNotice" })
            #expect(!cells.contains { $0 is PerpsPositionsSummaryCell })
            #expect(!cells.contains { $0 is PerpsPositionCell })
            #expect(!cells.contains { $0 is PerpsBalanceWithdrawalCell })
        }
    }

    private func cell(_ data: PerpsBalanceWithdrawalRowDisplayData) -> (PerpsBalanceWithdrawalCell, (String) throws -> UILabel) {
        let cell = PerpsBalanceWithdrawalCell(frame: CGRect(x: 0, y: 0, width: 370, height: PerpsPositionCell.height))
        cell.configure(data)
        cell.layoutIfNeeded()
        let labels = descendants(cell).compactMap { $0 as? UILabel }
        return (cell, { identifier in try #require(labels.first { $0.accessibilityIdentifier == identifier }) })
    }

    /// Hidden amounts hide the balance and keep the row's label and action readable.
    @Test func onlyTheAmountIsSensitive() throws {
        let (_, label) = cell(row)
        func isMasked(_ identifier: String) throws -> Bool {
            var view: UIView? = try label(identifier)
            while let current = view {
                if current is WSensitiveData<TradeShineView> { return true }
                view = current.superview
            }
            return false
        }
        #expect(try isMasked("perps.balance.amount"))
        #expect(try !isMasked("perps.balance.detail"))
        #expect(try !isMasked("perps.balance.withdraw"))
    }

    /// Figma `19664:139231`: the amount over "Available · USDC", then a 30pt capsule 12pt from the edge.
    @Test func theAmountLeadsAndTheActionIsACapsule() throws {
        let (cell, label) = cell(row)
        let content = cell.contentView
        let amount = try label("perps.balance.amount")
        let detail = try label("perps.balance.detail")
        #expect(amount.text == "$1.50")
        #expect(detail.text == lang("PerpsAvailable") + " · " + row.token.symbol)
        let amountFrame = amount.convert(amount.bounds, to: content)
        let detailFrame = detail.convert(detail.bounds, to: content)
        #expect(abs(amountFrame.minX - 62) < 0.01)
        #expect(abs(detailFrame.minX - 62) < 0.01)
        #expect(amountFrame.minY == 10)
        #expect(detailFrame.maxY == 50)

        let pill = try #require(try label("perps.balance.withdraw").superview)
        let frame = pill.convert(pill.bounds, to: content)
        #expect(frame.height == 30)
        #expect(frame.maxX == content.bounds.width - 12)
        #expect(frame.midY == content.bounds.midY)
        #expect(pill.layer.cornerRadius == frame.height / 2)
    }

    @Test func preparingKeepsTheCapsuleAndReplacesItsTitle() throws {
        let (ready, readyLabel) = cell(row)
        var preparing = row
        preparing.isPreparing = true
        let (busy, busyLabel) = cell(preparing)
        let withdraw = try busyLabel("perps.balance.withdraw")
        let spinner = try #require(descendants(busy).compactMap { $0 as? UIActivityIndicatorView }.first)
        #expect(withdraw.isHidden)
        #expect(spinner.isAnimating)
        #expect(try #require(withdraw.superview).bounds.width == (try #require(try readyLabel("perps.balance.withdraw").superview)).bounds.width)
        #expect(descendants(ready).compactMap { $0 as? UIActivityIndicatorView }.first?.isAnimating == false)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
