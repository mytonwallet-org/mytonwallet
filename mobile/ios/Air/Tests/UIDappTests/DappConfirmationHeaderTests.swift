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

    private func makeHeader(transactions: [ApiDappTransfer], hidden: Bool = false) -> DappConfirmationHeaderView {
        DappConfirmationHeaderView(
            dapp: .sample,
            action: .send(.init(promiseId: "test", accountId: "test", dapp: .sample, operationChain: .ton, transactions: transactions, emulation: nil, shouldHideTransfers: hidden))
        )
    }

    private func transfer(payload: ApiParsedPayload? = nil) -> ApiDappTransfer {
        .init(toAddress: "contract", amount: 50_000_000, payload: payload, isDangerous: false, normalizedAddress: "contract", displayedToAddress: "recipient", networkFee: 10_000_000)
    }
}
