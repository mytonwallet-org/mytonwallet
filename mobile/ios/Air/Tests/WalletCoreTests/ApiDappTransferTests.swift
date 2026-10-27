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

    @Test
    func `request is flagged when any message carries a state init`() {
        let info = makeRequest([makeTransfer(), makeTransfer(stateInit: "te6cckEBAQEAAgAAAEysuc0=")]).combinedInfo

        #expect(info.hasStateInit)
        #expect(!info.isDangerous)
    }

    @Test
    func `request without a state init is not flagged`() {
        #expect(!makeRequest([makeTransfer(), makeTransfer(stateInit: "")]).combinedInfo.hasStateInit)
    }

    private func makeRequest(_ transactions: [ApiDappTransfer]) -> ApiUpdate.DappSendTransactions {
        .init(promiseId: "test", accountId: "test", dapp: .sample, operationChain: .ton, transactions: transactions, emulation: nil, shouldHideTransfers: false)
    }

    private func makeTransfer(payload: ApiParsedPayload? = nil, stateInit: String? = nil) -> ApiDappTransfer {
        ApiDappTransfer(
            toAddress: "message-address",
            amount: 0,
            payload: payload,
            stateInit: stateInit,
            isDangerous: false,
            normalizedAddress: "message-address",
            displayedToAddress: "message-address",
            networkFee: 0
        )
    }
}
