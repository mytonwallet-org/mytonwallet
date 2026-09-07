import Foundation
import Testing
import Dependencies
@testable import UISwap
@testable import WalletCore
import WalletContext

@Suite("Backend swap hints")
@MainActor
struct SwapBackendHintTests {
    @Test
    func `an error-only estimate decodes and displays an intermediate suggestion`() throws {
        let response = try decodeHintResponse([
            "error": "Pair not found",
            "hint": ["type": "intermediate", "token": SOLANA_SLUG]
        ])
        #expect(!response.isQuote)
        #expect(SwapHint.fromBackend(response.hint, sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken)
            == .intermediate(token: ApiChain.solana.nativeToken, buyingToken: ApiChain.ethereum.nativeToken))
    }

    @Test
    func `external suggestions preserve the complete prefilled URL`() throws {
        let url = "https://example.com/swap?chain=ethereum&from=eth&to=usdc&amount=0.1#swap"
        let response = try decodeHintResponse([
            "error": "Pair not found",
            "hint": ["type": "external", "providerName": "1inch", "url": url]
        ])
        #expect(SwapHint.fromBackend(response.hint, sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken)
            == .external(providerName: "1inch", url: URL(string: url)!))
    }

    @Test(arguments: [
        #"{"type":"future","payload":{"new":true}}"#,
        #"{"type":"intermediate"}"#,
        #"{"type":"intermediate","token":"unknown-token"}"#,
        #"{"type":"intermediate","token":"toncoin"}"#,
        #"{"type":"external","providerName":"1inch","url":"javascript:alert(1)"}"#,
        #"{"type":"external","providerName":"1inch","url":"https:///"}"#,
        #"{"type":"external","providerName":" ","url":"https://example.com"}"#,
        #"{"type":"external","providerName":42,"url":{}}"#,
        "42",
        "null"
    ])
    func `unknown or unusable hints retain the ordinary error`(_ hint: String) throws {
        let json = "{\"error\":\"Pair not found\",\"hint\":\(hint)}"
        let response = try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: Data(json.utf8))
        let result = SwapEstimateResult(changedFrom: .selling, response: response)
        #expect(result.estimateIssue == .invalidPair)
        #expect(SwapHint.fromBackend(response.hint, sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken) == nil)
    }

    @Test(arguments: ["dex", "cex"])
    func `quotes retain optional hints and still count as quotes`(_ route: String) throws {
        var payload: [String: Any] = [
            "route": route, "from": TONCOIN_SLUG, "to": TON_USDT_SLUG,
            "fromAmount": "1", "toAmount": "5", "swapFee": "0",
            "hint": ["type": "external", "providerName": "Service", "url": "https://example.com"]
        ]
        if route == "dex" {
            payload.merge([
                "toMinAmount": "4.9", "impact": 0, "dieselStatus": DieselStatus.notAvailable.rawValue,
                "networkFee": "0.01", "realNetworkFee": "0.01", "swapFeePercent": 0,
                "ourFee": "0", "ourFeePercent": 0
            ]) { _, new in new }
        } else {
            payload.merge(["cexLabel": "changelly", "fromMin": "1", "fromMax": "1000"]) { _, new in new }
        }
        let response = try decodeHintResponse(payload)
        #expect(response.isQuote)
        #expect(response.hint?.providerName == "Service")

        payload.removeValue(forKey: "hint")
        let withoutHint = try decodeHintResponse(payload)
        #expect(withoutHint.isQuote)
        #expect(withoutHint.hint == nil)
        #expect(response != withoutHint)
    }

    @Test(arguments: [false, true])
    func `both estimate flows preserve backend hints without producing executable quotes`(crosschain: Bool) async throws {
        let response = try decodeHintResponse([
            "error": "Pair not found",
            "hint": ["type": "intermediate", "token": SOLANA_SLUG]
        ])
        let input = hintInput()
        let account = SwapAccountSnapshot(account: MAccount(
            id: input.accountId, title: nil, type: .mnemonic,
            byChain: [.ton: AccountChain(address: "ton-address"), .ethereum: AccountChain(address: "eth-address")]
        ), balances: [:])
        let fetch: (String, ApiSwapEstimateRequest) async throws -> ApiSwapEstimateResponse = { accountId, request in
            #expect(accountId == input.accountId)
            #expect(request.from == input.selling.token.swapIdentifier)
            #expect(request.to == input.buying.token.swapIdentifier)
            #expect(request.fromAmount?.value == 1)
            return response
        }
        let flow: any SwapFlow = crosschain
            ? CrosschainSwapFlow(validator: CrosschainSwapValidator(), estimateEngine: CrosschainSwapEstimateEngine(fetchEstimate: fetch))
            : OnchainSwapFlow(validator: OnchainSwapValidator(), estimateEngine: OnchainSwapEstimateEngine(fetchEstimate: fetch))
        let update = try await flow.estimate(
            input, changedFrom: .selling,
            swapType: crosschain ? .crosschainInsideWallet : .onChain,
            account: account
        )
        #expect(!update.hasQuote)
        #expect(update.estimatedAmounts == nil)
        let result = try #require(update.stateUpdate)
        #expect(result.estimateIssue == .invalidPair)
        var state = SwapEstimateModel()
        state.apply(result, input: input)
        #expect(state.response(for: input)?.hint == response.hint)
        #expect(state.swapMode == nil)
        #expect(state.dexEstimate == nil)
        #expect(state.cexEstimate == nil)
    }

    @Test
    func `a hint preserves the user entered buy amount when the route switches estimate direction`() async throws {
        let response = try decodeHintResponse([
            "error": "Pair not found",
            "hint": ["type": "intermediate", "token": SOLANA_SLUG]
        ])
        let selling = ApiChain.ethereum.nativeToken
        let buying = ApiChain.ton.nativeToken
        let account = MAccount(id: "hint-mainnet", title: nil, type: .mnemonic, byChain: [
            .ethereum: AccountChain(address: "eth-address"), .ton: AccountChain(address: "ton-address")
        ])
        let input = SwapEstimateInput(
            accountId: account.id, selling: TokenAmount(0, selling), buying: TokenAmount(1_000_000_000, buying),
            inputSource: .buying, isMaxAmount: false, maxAmount: nil, slippage: 5
        )
        let flow = CrosschainSwapFlow(
            validator: CrosschainSwapValidator(),
            estimateEngine: CrosschainSwapEstimateEngine(fetchEstimate: { _, _ in response })
        )
        let update = try await flow.estimate(input, changedFrom: .selling, swapType: .crosschainInsideWallet,
                                             account: SwapAccountSnapshot(account: account, balances: [:]))
        let model = withDependencies {
            $0[_TokenStore.self] = TokenStore
            $0[_BalancesStore.self] = _BalancesStore.liveValue
        } operation: {
            SwapInputModel(sellingTokenSlug: selling.slug, buyingTokenSlug: buying.slug, tokenBalance: nil,
                           accountContext: AccountContext(source: .constant(account)))
        }
        model.buyingAmount = input.buying.amount
        model.inputSource = .buying
        update.apply(to: model)
        let selectedSelling: ApiToken? = model.sellingToken
        let selectedBuying: ApiToken? = model.buyingToken
        #expect(selectedSelling?.slug == selling.slug)
        #expect(selectedBuying?.slug == buying.slug)
        #expect(model.buyingAmount == input.buying.amount)
        #expect(model.inputSource == .buying)
    }

    @Test
    func `hints disappear when any request input changes or a replacement has no hint`() throws {
        let response = try decodeHintResponse([
            "error": "Pair not found",
            "hint": ["type": "intermediate", "token": SOLANA_SLUG]
        ])
        var state = SwapEstimateModel()
        state.apply(SwapEstimateResult(changedFrom: .selling, response: response), input: hintInput())
        #expect(state.response(for: hintInput()) != nil)
        #expect(state.response(for: nil) == nil)
        #expect(state.response(for: hintInput(amount: 2_000_000_000)) == nil)
        #expect(state.response(for: hintInput(buying: ApiChain.solana.nativeToken)) == nil)
        #expect(state.response(for: hintInput(accountId: "other-mainnet")) == nil)
        #expect(state.response(for: hintInput(slippage: 10)) == nil)

        state.apply(SwapEstimateResult(changedFrom: .selling, response: try decodeHintResponse(["error": "Pair not found"])), input: hintInput())
        #expect(state.response(for: hintInput())?.hint == nil)
        state.clear()
        #expect(state.response == nil)
    }

    @Test
    func `legacy minimum and rate limit responses retain their existing behavior`() throws {
        let minimum = SwapEstimateResult(changedFrom: .selling, response: try decodeHintResponse(["error": "Too small amount"]))
        #expect(minimum.estimateIssue == .tooSmallAmount)
        #expect(minimum.response?.hint == nil)
        let limited = SwapEstimateResult(changedFrom: .selling, response: try decodeHintResponse(["error": "requests limit exceeded"]))
        #expect(limited.isRateLimited)
        #expect(limited.estimateIssue == nil)
    }

    @Test
    func `a pair absent from the catalog remains eligible for a backend estimate`() async throws {
        let selling = ApiChain.ethereum.nativeToken
        let buying = ApiChain.solana.nativeToken
        let previous = TokenStore.swapPairs[selling.swapIdentifier]
        TokenStore.swapPairs[selling.swapIdentifier] = []
        defer { TokenStore.swapPairs[selling.swapIdentifier] = previous }
        let resolution = try await SwapPairResolver().resolve(selling: selling, buying: buying, accountChains: [.ethereum, .solana])
        #expect(!resolution.isValidPair)
        #expect(isSwapPairInAccountScope(selling: selling, buying: buying, accountChains: [.ethereum, .solana]))
    }
}

private func decodeHintResponse(_ payload: [String: Any]) throws -> ApiSwapEstimateResponse {
    try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: JSONSerialization.data(withJSONObject: payload))
}

private func hintInput(
    amount: BigInt = 1_000_000_000,
    buying: ApiToken = ApiChain.ethereum.nativeToken,
    accountId: String = "hint-mainnet",
    slippage: Double = 5
) -> SwapEstimateInput {
    SwapEstimateInput(
        accountId: accountId,
        selling: TokenAmount(amount, .TONCOIN), buying: TokenAmount(0, buying),
        inputSource: .selling, isMaxAmount: false, maxAmount: nil, slippage: slippage
    )
}
