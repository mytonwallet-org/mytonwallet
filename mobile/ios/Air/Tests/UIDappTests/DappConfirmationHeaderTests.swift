import Foundation
import Testing
@testable import UIDapp
@testable import WalletCore

@Suite("Dapp confirmation summary")
@MainActor
struct DappConfirmationHeaderTests {
    @Test
    func tokenTransferUsesPayloadAmountInsteadOfAttachedNativeCurrency() throws {
        let payload = try JSONDecoder().decode(ApiParsedPayload.self, from: Data(
            #"{"type":"tokens:transfer-non-standard","queryId":"0","amount":"748210000","destination":"recipient","slug":"tether-usdt"}"#.utf8
        ))
        let header = makeHeader(transactions: [transfer(payload: payload)])
        guard case .token(let amount) = try #require(header.assets.first) else {
            Issue.record("Expected the transferred token")
            return
        }
        #expect(amount.amount == 748_210_000)
        #expect(amount.token.slug == "tether-usdt")
    }

    @Test
    func nftWithoutMetadataRetainsItsIdentity() throws {
        let payload = try JSONDecoder().decode(ApiParsedPayload.self, from: Data(
            #"{"type":"nft:transfer","queryId":"0","newOwner":"recipient","responseDestination":"sender","forwardAmount":"0","nftAddress":"nft","nftName":"Durov’s Cap #777"}"#.utf8
        ))
        let header = makeHeader(transactions: [transfer(payload: payload)])
        guard case .nft(let nft) = try #require(header.assets.first) else {
            Issue.record("Expected NFT rather than attached native currency")
            return
        }
        #expect(nft.nft == nil)
        #expect(nft.nftName == "Durov’s Cap #777")
        #expect(nft.nftAddress == "nft")
    }

    @Test(arguments: [false, true])
    func hiddenOrDangerousRequestsDoNotDisplayMisleadingAssets(dangerous: Bool) {
        var transaction = transfer()
        transaction.isDangerous = dangerous
        let header = makeHeader(transactions: [transaction], hidden: !dangerous)
        #expect(header.assets.isEmpty)
    }

    @Test
    func repeatedAssetsRetainTheFullTransferCount() {
        let header = makeHeader(transactions: Array(repeating: transfer(), count: 15))
        #expect(header.assets.count == 15)
    }

    @Test
    func validatedSwapAndGasRefundUseTheEstimatedExchange() throws {
        let header = makeHeader(transactions: [try swapTransfer()], activities: try swapActivities())
        let swap = try #require(header.swap)
        #expect(swap.fromAmount.value == 1)
        #expect(swap.toAmount.value == 2.61)
        #expect(swap.to == "ton-dust")
    }

    @Test
    func swapDoesNotHideOtherTransfersEvenWhenTheyAreHiddenFromPreview() throws {
        var activities = try swapActivities()
        activities.append(try JSONDecoder().decode(ApiActivity.self, from: Data(
            #"{"id":"extra","kind":"transaction","timestamp":0,"amount":"-1000000000","fee":"0","slug":"toncoin","isIncoming":false,"status":"completed","shouldHide":true}"#.utf8
        )))
        #expect(makeHeader(transactions: [try swapTransfer()], activities: activities).swap == nil)
        #expect(makeHeader(transactions: [try swapTransfer(), transfer()], activities: try swapActivities()).swap == nil)
    }

    @Test
    func failedOrDangerousSwapDoesNotBecomeAConfirmationSummary() throws {
        var transaction = try swapTransfer()
        transaction.isDangerous = true
        #expect(makeHeader(transactions: [transaction], activities: try swapActivities()).swap == nil)
        #expect(makeHeader(transactions: [try swapTransfer()], activities: try swapActivities(status: "failed")).swap == nil)
    }

    @Test
    func emulationDoesNotClassifyAnUnknownPayloadAsASwap() throws {
        let unknown = try JSONDecoder().decode(ApiParsedPayload.self, from: Data(
            #"{"type":"unknown","base64":"payload"}"#.utf8
        ))
        let header = makeHeader(transactions: [transfer(payload: unknown)], activities: try swapActivities())
        #expect(header.swapPayload == nil)
        #expect(header.swap == nil)
    }

    @Test
    func validatedSwapRetainsItsClassificationWithoutEmulation() throws {
        let header = makeHeader(transactions: [try swapTransfer()])
        #expect(header.swapPayload?.amount == 1_000_000_000)
        #expect(header.swapPayload?.minimumAmountOut == 2_580_000_000)
        #expect(header.swap == nil)
    }

    @Test
    func mismatchedEmulationCannotReplaceSignedSwapAmounts() throws {
        var transaction = try swapTransfer()
        guard case .dedustNativeSwap(var payload) = transaction.payload else { return }
        payload.amount = 2_000_000_000
        transaction.payload = .dedustNativeSwap(payload)
        #expect(makeHeader(transactions: [transaction], activities: try swapActivities()).swap == nil)
        payload.amount = 1_000_000_000
        payload.toSlug = "another-token"
        transaction.payload = .dedustNativeSwap(payload)
        #expect(makeHeader(transactions: [transaction], activities: try swapActivities()).swap == nil)
    }

    @Test
    func uncachedOutputUsesPayloadDecimalsForMinimumAndEstimate() throws {
        var transaction = try swapTransfer()
        guard case .dedustNativeSwap(var payload) = transaction.payload else { return }
        payload.toToken.decimals = 18
        payload.minimumAmountOut = 1_000_000_000_000_000_000
        transaction.payload = .dedustNativeSwap(payload)
        let header = makeHeader(transactions: [transaction], activities: try swapActivities())
        #expect(payload.minimumReceived.doubleValue == 1)
        let output = try #require(header.swapOutputAmount)
        #expect(output.token.decimals == 18)
        #expect(abs(output.doubleValue - 2.61) < 0.000000001)

        payload.minimumAmountOut = 3_000_000_000_000_000_000
        transaction.payload = .dedustNativeSwap(payload)
        #expect(makeHeader(transactions: [transaction], activities: try swapActivities()).swap == nil)
    }

    private func swapTransfer() throws -> ApiDappTransfer {
        let payload = try JSONDecoder().decode(ApiParsedPayload.self, from: Data(
            #"{"type":"dedust:native-swap","queryId":"0","amount":"1000000000","poolAddress":"pool","toSlug":"ton-dust","toToken":{"slug":"ton-dust","name":"Dust","symbol":"DUST","decimals":9,"chain":"ton"},"minimumAmountOut":"2580000000","recipientAddress":"sender","deadline":0}"#.utf8
        ))
        var result = transfer(payload: payload)
        result.amount = 1_250_000_000
        return result
    }

    private func swapActivities(status: String = "completed") throws -> [ApiActivity] {
        try JSONDecoder().decode([ApiActivity].self, from: Data("""
        [
          {"id":"swap","kind":"swap","timestamp":0,"from":"toncoin","fromAmount":"1","to":"ton-dust","toAmount":"2.61","status":"\(status)","transactionIds":{}},
          {"id":"refund","kind":"transaction","timestamp":0,"amount":"230000000","fee":"0","slug":"toncoin","isIncoming":true,"type":"excess","status":"completed"}
        ]
        """.utf8))
    }

    private func makeHeader(transactions: [ApiDappTransfer], hidden: Bool = false, activities: [ApiActivity]? = nil) -> DappConfirmationHeaderView {
        DappConfirmationHeaderView(
            dapp: .sample,
            action: .send(.init(promiseId: "test", accountId: "test", dapp: .sample, operationChain: .ton, transactions: transactions, emulation: activities.map { Emulation(activities: $0, realFee: 15_000_000) }, shouldHideTransfers: hidden))
        )
    }

    private func transfer(payload: ApiParsedPayload? = nil) -> ApiDappTransfer {
        .init(toAddress: "contract", amount: 50_000_000, payload: payload, isDangerous: false, normalizedAddress: "contract", displayedToAddress: "recipient", networkFee: 10_000_000)
    }
}
