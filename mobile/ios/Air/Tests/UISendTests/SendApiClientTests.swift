import Foundation
import ProtectedAction
import Testing
@testable import UISend
import WalletCore

@Suite("Send API Clients")
struct SendApiClientTests {
    @Test
    func `token draft validation uses the injected API client`() async throws {
        let recorder = TokenApiRecorder()
        let draft = try decodeDraft(
            #"{"resolvedAddress":"resolved","isMemoRequired":true}"#
        )
        let flow = TokenSendFlow(api: TokenSendApiClient(
            checkDraft: { chain, options in
                await recorder.recordDraft(chain: chain, options: options)
                return draft
            },
            submit: { _, _ in
                throw TestError.unexpectedCall
            }
        ))
        let token = makeToken(
            slug: "ethereum-usdt",
            chain: .ethereum,
            tokenAddress: "token-contract"
        )

        let result = try await flow.validateDraft(TokenSendDraftRequest(
            accountId: "account",
            address: "recipient",
            asset: TokenSendAsset(token),
            amount: 42,
            payload: .comment(text: "memo", shouldEncrypt: false),
            stateInit: "state-init"
        ))

        let calls = await recorder.draftCalls
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        expectTokenDraftResult(result, draft: draft)
        expectTokenDraftCall(call)
    }

    @Test
    func `token fee quote uses the chain fee check address`() async throws {
        let recorder = TokenApiRecorder()
        let flow = TokenSendFlow(api: TokenSendApiClient(
            checkDraft: { chain, options in
                await recorder.recordDraft(chain: chain, options: options)
                return try decodeDraft(#"{}"#)
            },
            submit: { _, _ in
                throw TestError.unexpectedCall
            }
        ))
        let token = makeToken(
            slug: "ethereum-usdt",
            chain: .ethereum,
            tokenAddress: "token-contract"
        )

        _ = try await flow.estimateFee(TokenSendFeeQuoteRequest(
            accountId: "account",
            asset: TokenSendAsset(token)
        ))

        let calls = await recorder.draftCalls
        let call = try #require(calls.first)
        #expect(call.chain == .ethereum)
        #expect(
            call.options.toAddress
                == getChainConfig(chain: .ethereum).feeCheckAddress
        )
        #expect(call.options.accountId == "account")
        #expect(call.options.amount == nil)
        #expect(call.options.payload == nil)
        #expect(call.options.stateInit == nil)
        #expect(call.options.tokenAddress == "token-contract")
        #expect(call.options.allowGasless == false)
    }

    @Test
    func `nonrecoverable token draft error is thrown`() async throws {
        let flow = TokenSendFlow(api: TokenSendApiClient(
            checkDraft: { _, _ in
                try decodeDraft(#"{"error":"InvalidStateInit"}"#)
            },
            submit: { _, _ in
                throw TestError.unexpectedCall
            }
        ))
        let token = makeToken(slug: "toncoin", chain: .ton)

        await #expect(throws: ApiAnyDisplayError.invalidStateInit) {
            try await flow.validateDraft(TokenSendDraftRequest(
                accountId: "account",
                address: "recipient",
                asset: TokenSendAsset(token),
                amount: 1,
                payload: nil,
                stateInit: "invalid"
            ))
        }
    }

    @Test
    func `insufficient balance keeps the token draft for inline state`() async throws {
        let flow = TokenSendFlow(api: TokenSendApiClient(
            checkDraft: { _, _ in
                try decodeDraft(
                    #"{"resolvedAddress":"resolved","error":"InsufficientBalance"}"#
                )
            },
            submit: { _, _ in
                throw TestError.unexpectedCall
            }
        ))
        let token = makeToken(slug: "toncoin", chain: .ton)

        let result = try await flow.validateDraft(TokenSendDraftRequest(
            accountId: "account",
            address: "recipient",
            asset: TokenSendAsset(token),
            amount: 1,
            payload: nil,
            stateInit: nil
        ))

        #expect(result.recipient.resolvedAddress == "resolved")
        #expect(result.recipient.error == .insufficientBalance)
    }

    @MainActor
    @Test
    func `Ledger token submission uses the accepted asset chain`() async throws {
        let recorder = TokenApiRecorder()
        let response = try decodeTokenSubmitResult(
            #"{"activityId":"activity"}"#
        )
        let flow = TokenSendFlow(api: TokenSendApiClient(
            checkDraft: { _, _ in
                throw TestError.unexpectedCall
            },
            submit: { chain, options in
                await recorder.recordSubmit(
                    chain: chain,
                    options: options
                )
                return response
            }
        ))
        let token = makeToken(
            slug: "solana-usdc",
            chain: .solana,
            tokenAddress: "mint"
        )
        let operation = try await flow.ledgerOperation(
            TokenSendSubmission(
                accountId: "account",
                asset: TokenSendAsset(token),
                amount: 99,
                payload: nil,
                stateInit: nil,
                resolvedAddress: "resolved",
                diesel: nil
            ),
            explainedFee: nil
        )

        let result = await operation.perform(
            context: HardwareOperationContext { _, _ in }
        )

        guard case .committed = result else {
            Issue.record("Expected committed Ledger submission")
            return
        }
        let call = try #require(await recorder.submitCalls.first)
        #expect(call.chain == .solana)
    }

    @Test
    func `NFT draft validation uses the injected API client`() async throws {
        let recorder = NftApiRecorder()
        let draft = try decodeDraft(#"{"resolvedAddress":"resolved"}"#)
        let flow = NftSendFlow(api: NftSendApiClient(
            checkDraft: { chain, options in
                await recorder.recordDraft(chain: chain, options: options)
                return draft
            },
            submit: { _ in
                throw TestError.unexpectedCall
            }
        ))
        let nft = makeNft(chain: .solana, address: "nft")

        let result = try await flow.validateDraft(NftSendDraftRequest(
            accountId: "account",
            address: "recipient",
            chain: .solana,
            nfts: [nft],
            comment: "memo",
            mode: .send
        ))

        #expect(result.recipient.resolvedAddress == "resolved")

        let calls = await recorder.draftCalls
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.chain == .solana)
        #expect(call.options.accountId == "account")
        #expect(call.options.nfts == [nft])
        #expect(call.options.toAddress == "recipient")
        #expect(call.options.comment == "memo")
        #expect(call.options.isNftBurn == false)
    }

    @Test
    func `NFT burn lets the SDK choose its destination`() async throws {
        let recorder = NftApiRecorder()
        let sdkResolvedAddress = "sdk-burn-destination"
        let draft = try decodeDraft(
            #"{"resolvedAddress":"\#(sdkResolvedAddress)"}"#
        )
        let flow = NftSendFlow(api: NftSendApiClient(
            checkDraft: { chain, options in
                await recorder.recordDraft(
                    chain: chain,
                    options: options
                )
                return draft
            },
            submit: { _ in
                throw TestError.unexpectedCall
            }
        ))
        let nft = makeNft(chain: .ton, address: "nft")

        let result = try await flow.validateDraft(
            NftSendDraftRequest(
                accountId: "account",
                address: "",
                chain: .ton,
                nfts: [nft],
                comment: nil,
                mode: .burn
            )
        )

        #expect(
            result.recipient.resolvedAddress
                == sdkResolvedAddress
        )

        let call = try #require(await recorder.draftCalls.first)
        #expect(call.options.toAddress.isEmpty)
        #expect(call.options.isNftBurn == true)
    }

    @MainActor
    @Test
    func `Ledger NFT success without activity IDs is indeterminate`() async throws {
        let recorder = NftApiRecorder()
        let response = try decodeNftSubmitResult(#"{}"#)
        let flow = NftSendFlow(api: NftSendApiClient(
            checkDraft: { _, _ in
                throw TestError.unexpectedCall
            },
            submit: { request in
                await recorder.recordSubmit(request)
                return response
            }
        ))
        let nft = makeNft(chain: .ton, address: "nft")
        let operation = try await flow.ledgerOperation(
            NftSendSubmission(
                accountId: "account",
                chain: .ton,
                nfts: [nft],
                comment: nil,
                mode: .send,
                resolvedAddress: "resolved",
                totalRealFee: nil
            )
        )

        let result = await operation.perform(
            context: HardwareOperationContext { _, _ in }
        )

        guard case .indeterminate(_, let receipt) = result else {
            Issue.record("Expected indeterminate Ledger submission")
            return
        }
        #expect(receipt == nil)
        let request = try #require(
            await recorder.submitRequests.first
        )
        #expect(request.totalRealFee == 0)
    }
}

private func expectTokenDraftResult(
    _ result: TokenSendValidatedDraft,
    draft: ApiCheckTransactionDraftResult
) {
    #expect(
        result.recipient.resolvedAddress
            == draft.resolvedAddress
    )
    #expect(result.requiresMemo)
}

private func expectTokenDraftCall(_ call: TokenApiRecorder.DraftCall) {
    #expect(call.chain == .ethereum)
    #expect(call.options.accountId == "account")
    #expect(call.options.toAddress == "recipient")
    #expect(call.options.amount == 42)
    #expect(call.options.payload == .comment(text: "memo", shouldEncrypt: false))
    #expect(call.options.stateInit == "state-init")
    #expect(call.options.tokenAddress == "token-contract")
    #expect(call.options.allowGasless == true)
}

private actor TokenApiRecorder {
    fileprivate struct DraftCall: Sendable {
        let chain: ApiChain
        let options: ApiCheckTransactionDraftOptions
    }

    struct SubmitCall: Sendable {
        let chain: ApiChain
        let options: ApiSubmitTransferOptions
    }

    private(set) var draftCalls: [DraftCall] = []
    private(set) var submitCalls: [SubmitCall] = []

    func recordDraft(chain: ApiChain, options: ApiCheckTransactionDraftOptions) {
        draftCalls.append(DraftCall(chain: chain, options: options))
    }

    func recordSubmit(chain: ApiChain, options: ApiSubmitTransferOptions) {
        submitCalls.append(SubmitCall(chain: chain, options: options))
    }
}

private actor NftApiRecorder {
    struct DraftCall: Sendable {
        let chain: ApiChain
        let options: ApiCheckNftTransferDraftOptions
    }

    private(set) var draftCalls: [DraftCall] = []
    private(set) var submitRequests: [NftSendSubmissionRequest] = []

    func recordDraft(chain: ApiChain, options: ApiCheckNftTransferDraftOptions) {
        draftCalls.append(DraftCall(chain: chain, options: options))
    }

    func recordSubmit(_ request: NftSendSubmissionRequest) {
        submitRequests.append(request)
    }
}

private enum TestError: Error {
    case unexpectedCall
}

private func makeToken(
    slug: String,
    chain: ApiChain,
    tokenAddress: String? = nil
) -> ApiToken {
    ApiToken(
        slug: slug,
        name: slug,
        symbol: slug,
        decimals: 9,
        chain: chain,
        tokenAddress: tokenAddress
    )
}

private func decodeDraft(_ json: String) throws -> ApiCheckTransactionDraftResult {
    try JSONDecoder().decode(
        ApiCheckTransactionDraftResult.self,
        from: Data(json.utf8)
    )
}

private func decodeTokenSubmitResult(_ json: String) throws -> ApiSubmitTransferResult {
    try JSONDecoder().decode(
        ApiSubmitTransferResult.self,
        from: Data(json.utf8)
    )
}

private func decodeNftSubmitResult(_ json: String) throws -> ApiSubmitNftTransfersResult {
    try JSONDecoder().decode(
        ApiSubmitNftTransfersResult.self,
        from: Data(json.utf8)
    )
}
