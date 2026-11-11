import Testing
import UIKit
import WalletCore
@testable import UIAssets

@Suite @MainActor
struct PerpsPositionsSectionTests {
    private func data(account: String = "a", count: Int = 7) -> PerpsPositionsDisplayData {
        .init(accountID: account, totalValue: .fromDouble(130, .USD), profitLoss: .init("+$30 · 30%"),
              positions: (0..<count).map { .init(id: "position-\($0)", token: .TONCOIN,
                directionAndLeverage: "Long 5x", value: "$130", profitLoss: .init("+$30 (30%)")) })
    }

    @Test func previewHasSharedShowAllAndNoSeparatorAboveIt() {
        let provider = PerpsPositionsSectionDataProvider(id: "test")
        provider.data = data()
        #expect(provider.itemIdentifiers.count == 6)
        let separator = UIListSeparatorConfiguration(listAppearance: .insetGrouped)
        #expect(provider.separatorConfiguration(at: 3, default: separator).bottomSeparatorVisibility == separator.bottomSeparatorVisibility)
        #expect(provider.separatorConfiguration(at: 4, default: separator).bottomSeparatorVisibility == .hidden)
        #expect(provider.separatorConfiguration(at: 5, default: separator).topSeparatorVisibility == .hidden)
        #expect(provider.separatorConfiguration(at: 5, default: separator).bottomSeparatorVisibility == .hidden)
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        provider.prepareForUse()
        let cell = provider.dequeueCell(collection, IndexPath(item: 5, section: 0), itemIdentifier: provider.itemIdentifiers[5])
        #expect(cell is WalletSeeAllCell)
    }

    @Test func emptyPreviewIsHiddenAndAccountSwitchRejectsOldActions() {
        let provider = PerpsPositionsSectionDataProvider(id: "test")
        var actions: [PerpsHomeAction] = []
        provider.onAction = { actions.append($0) }
        provider.data = data()
        let oldRows = provider.itemIdentifiers
        provider.didSelect(itemIdentifier: oldRows[0])
        provider.data = data(account: "b")
        oldRows.forEach { provider.didSelect(itemIdentifier: $0) }
        #expect(actions == [.position("position-0")])
        provider.data = data(count: 0)
        #expect(provider.itemIdentifiers.isEmpty)
        provider.data = data()
        provider.data?.status = .unavailable("Offline")
        provider.didSelect(itemIdentifier: provider.itemIdentifiers[0])
        #expect(actions.last == .refresh)
    }

    @Test(arguments: [1, 4, 5, 6, 7])
    func showAllAppearsOnlyWhenPositionsAreHidden(count: Int) {
        let provider = PerpsPositionsSectionDataProvider(id: "test")
        provider.data = data(count: count)
        let positions = (0..<min(count, 5)).map { "test:position:a:position-\($0)" }
        #expect(provider.itemIdentifiers == positions + (count > 5 ? ["test:all:a"] : []))
    }

    @Test func fullListDoesNotTruncateOrAddShowAllAndScrollDoesNotDelayTouches() {
        let provider = PerpsPositionsSectionDataProvider(id: "test", showsHeader: false, previewLimit: nil)
        provider.data = data()
        #expect(provider.itemIdentifiers.count == 7)
        let collection = PerpsCollectionView()
        #expect(!collection.delaysContentTouches)
        #expect(!collection.showsVerticalScrollIndicator)
    }

    @Test func pnlIncludesSignedFiatAndUnsignedPercentage() {
        let gain = PerpsFormatting.profitLoss("30", returnOnEquity: "0.3")
        #expect(gain.text == "+$30 (30.0%)")
        #expect(gain.tone == .positive)
        let loss = PerpsFormatting.profitLoss("-80", returnOnEquity: "-0.8")
        #expect(loss.text.contains("80 (80.0%)"))
        #expect(loss.tone == .negative)
        #expect(PerpsFormatting.profitLoss("-110", returnOnEquity: "-0.367", summary: true)
            .text.contains(" · 36.7%"))
        #expect(PerpsFormatting.profitLoss("0", returnOnEquity: "0").tone == .neutral)
        #expect(!PerpsFormatting.profitLoss("1", returnOnEquity: nil).text.contains("%"))
        #expect(PerpsFormatting.profitLoss(nil, returnOnEquity: nil).text == "—")
    }

    @Test(arguments: [("0.12345", "12.35%"), ("-0.12345", "12.35%"), ("0.3", "30.0%"), ("0", "0.0%")])
    func rowAndSummaryPercentagesUseTheSameDecimalPointAndPrecision(ratio: String, expected: String) {
        let row = PerpsFormatting.profitLoss("1", returnOnEquity: ratio)
        let summary = PerpsFormatting.profitLoss("1", returnOnEquity: ratio, summary: true)
        #expect(row.text.hasSuffix("(" + expected + ")"))
        #expect(summary.text.hasSuffix(" · " + expected))
    }

    @Test func positionsAnimateAfterAnExistingRenderForTheSameWallet() {
        let empty = data(count: 0)
        let populated = data(count: 1)
        #expect(populated.shouldAnimatePositionsChange(from: empty))
        #expect(empty.shouldAnimatePositionsChange(from: populated))
        #expect(!populated.shouldAnimatePositionsChange(from: nil))
        #expect(!populated.shouldAnimatePositionsChange(from: data(account: "another-wallet", count: 0)))
        #expect(!populated.shouldAnimatePositionsChange(from: populated))
        var loading = empty
        loading.status = .loading
        #expect(populated.shouldAnimatePositionsChange(from: loading))
        #expect(!empty.shouldAnimatePositionsChange(from: loading))
        var unavailable = populated
        unavailable.status = .unavailable("Offline")
        #expect(populated.shouldAnimatePositionsChange(from: unavailable))
        #expect(unavailable.shouldAnimatePositionsChange(from: populated))
        var fresh = populated
        fresh.isStale = false
        var cached = populated
        cached.isStale = true
        #expect(!fresh.shouldAnimatePositionsChange(from: cached))
    }
}
