import Foundation
import Testing
import UIKit
import WalletCore
import WalletContext
@testable import UIAssets

@Suite @MainActor
struct PerpsCashFlowActivityTests {
    private func transfer() throws -> ApiPerpsCashFlow {
        try JSONDecoder().decode(ApiPerpsCashFlow.self, from: Data("""
        {"id":"transfer/1","kind":"transfer","direction":"incoming","time":1793113200016,
         "amount":"0.001004","token":"USDC","fees":[]}
        """.utf8))
    }

    @Test func transferKeepsSmallAmountsAndDoesNotInventFeesOrTransactionID() throws {
        let flow = try transfer()
        let row = PerpsHomeAdapter.cashFlow(flow, asset: nil)
        #expect(row.kind == .received)
        #expect(row.title == lang("Transfer"))
        #expect(row.badge.isEmpty)
        #expect(row.amount.text == "+" + PerpsFormatting.quantity("0.001004", symbol: "USDC"))
        #expect(row.amount.tone == .positive)
        let details = PerpsHomeAdapter.cashFlowDetails(flow, asset: nil)
        #expect(details.rows.map(\.title) == [lang("Amount")])
        #expect(details.rows.allSatisfy { $0.copyValue == nil })
    }

    @Test func transferHasNoPositionBadgeOrFundingFieldsAndInternalMovesStayNeutral() throws {
        var flow = try transfer()
        flow.kind = .transfer
        flow.direction = .internal
        flow.amount = "10"
        flow.coin = nil
        flow.positionSide = nil
        flow.positionSize = nil
        flow.fundingRate = nil
        flow.sourceDex = ""
        flow.destinationDex = "xyz"
        flow.hash = "0x1234567890123456789012345678901234567890"
        let row = PerpsHomeAdapter.cashFlow(flow, asset: nil)
        #expect(row.badge.isEmpty)
        #expect(row.amount.tone == .neutral)
        #expect(row.amount.text == PerpsFormatting.quantity("10", symbol: "USDC"))
        let details = PerpsHomeAdapter.cashFlowDetails(flow, asset: nil)
        #expect(details.rows.map(\.title) == [lang("Amount"), lang("From"), lang("To"), lang("Transfer ID")])
        #expect(details.rows[1].value == lang("Futures"))
        #expect(details.rows[2].value == "xyz")
        #expect(details.rows.last?.copyValue == flow.hash)
    }

    @Test func combinedHistoryOmitsFundingKeepsTransfersAndUsesUIKitDetails() async throws {
        let flow = try transfer()
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"coin":"BTC","tid":1,"oid":1,"time":1793113100000,"px":"80000","sz":"0.001","side":"B",
         "dir":"Open Long","startPosition":"0","closedPnl":"0","fee":"0.1","feeToken":"USDC",
         "eventKind":"opened","positionSide":"long","notional":"80"}
        """.utf8))
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"btc","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
         "dex":"","szDecimals":5,"maxLeverage":40,"context":{"markPx":"80000","prevDayPx":"80000"}}
        """.utf8))
        var client = PerpsClient()
        client.snapshot = { _ in
            var snapshot = try JSONDecoder().decode(ApiPerpsSnapshot.self, from: Data("""
            {"assets":[],"positions":[],"totalEquity":"0","totalPnl":"0","timestamp":1,"unavailableDexs":[]}
            """.utf8))
            snapshot.assets = [asset]
            return snapshot
        }
        var funding = flow
        funding.id = "funding/BTC/1"
        funding.kind = .funding
        funding.coin = "BTC"
        client.history = { _ in .init(fills: [fill], cashFlows: [funding, flow]) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "a")
        #expect(PerpsHomeAdapter.home(store: store, accountId: "a").activities.map(\.id) == [flow.id, fill.id])
        let controller = PerpsCashFlowDetailsVC(data: PerpsHomeAdapter.cashFlowDetails(flow, asset: asset))
        controller.loadViewIfNeeded()
        let collection = try #require(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(!collection.delaysContentTouches)
        #expect(!collection.showsVerticalScrollIndicator)
        #expect(collection.numberOfSections == 2)
        #expect(collection.numberOfItems(inSection: 1) == 1)
    }
}
