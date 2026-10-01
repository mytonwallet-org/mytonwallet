import Testing
@testable import WalletCore

@Suite("Dapp Transfer")
struct ApiDappTransferTests {
    @Test
    func `token payload exposes its recipient separately from the message address`() {
        let payload = ApiTokensTransferPayload(
            queryId: 1,
            amount: 2,
            destination: "payload-recipient",
            responseDestination: "response-destination",
            customPayload: nil,
            forwardAmount: 0,
            forwardPayload: nil,
            forwardPayloadOpCode: nil,
            slug: "ton-token",
            tokenAddress: "token-address"
        )
        let transfer = makeTransfer(payload: .tokensTransfer(payload))

        #expect(transfer.toAddress == "message-address")
        #expect(transfer.payloadRecipientAddress == "payload-recipient")
    }

    @Test
    func `NFT payload exposes its new owner separately from the message address`() {
        let payload = ApiNftTransferPayload(
            queryId: 1,
            newOwner: "payload-recipient",
            responseDestination: "response-destination",
            customPayload: nil,
            forwardAmount: 0,
            forwardPayload: nil,
            nftAddress: "nft-address",
            nftName: nil,
            nft: nil,
            comment: nil
        )
        let transfer = makeTransfer(payload: .nftTransfer(payload))

        #expect(transfer.toAddress == "message-address")
        #expect(transfer.payloadRecipientAddress == "payload-recipient")
    }

    @Test
    func `payload recipient matching the message address is omitted`() {
        let payload = ApiTokensTransferPayload(
            queryId: 1,
            amount: 2,
            destination: "message-address",
            responseDestination: "response-destination",
            customPayload: nil,
            forwardAmount: 0,
            forwardPayload: nil,
            forwardPayloadOpCode: nil,
            slug: "ton-token",
            tokenAddress: "token-address"
        )
        let transfer = makeTransfer(payload: .tokensTransfer(payload))

        #expect(transfer.payloadRecipientAddress == nil)
    }

    private func makeTransfer(payload: ApiParsedPayload) -> ApiDappTransfer {
        ApiDappTransfer(
            toAddress: "message-address",
            amount: 0,
            payload: payload,
            isDangerous: false,
            normalizedAddress: "message-address",
            displayedToAddress: "message-address",
            networkFee: 0
        )
    }
}
