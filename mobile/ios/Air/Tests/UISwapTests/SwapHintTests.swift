import Foundation
import Testing
import Dependencies
@testable import UISwap
@testable import WalletCore
import WalletContext

@Suite("Swap funding hints")
@MainActor
struct SwapHintTests {
    @Test
    func `an empty wallet shows Fund for the buying chain`() {
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: makeHintContext(),
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        ) == .receive(chain: .ethereum, hasAlternativeToken: false))
    }

    @Test
    func `an empty buying side does not show Fund`() {
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: makeHintContext(), sellingToken: .TONCOIN, buyingToken: nil
        ) == nil)
    }

    @Test
    func `missing balances are treated as zero and show Fund`() {
        let context = makeHintContext(hasLoadedBalances: false)
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: context,
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        ) == .receive(chain: .ethereum, hasAlternativeToken: false))
    }

    @Test
    func `any positive selected selling balance suppresses Fund without a price or minimum`() {
        let context = makeHintContext(balances: [ApiChain.solana.nativeToken.slug: 1])
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: context,
            sellingToken: ApiChain.solana.nativeToken, buyingToken: ApiChain.ethereum.nativeToken
        ) == nil)
    }

    @Test
    func `the buying token alone cannot fund its own purchase`() {
        let context = makeHintContext(balances: [ApiChain.ethereum.nativeToken.slug: 1])
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: context,
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        ) == .receive(chain: .ethereum, hasAlternativeToken: false))
    }

    @Test(arguments: [false, true])
    func `a zero or missing sell balance suggests another funded token`(hasSellBalanceEntry: Bool) {
        var balances: [String: BigInt] = [SOLANA_SLUG: 1]
        if hasSellBalanceEntry { balances[TONCOIN_SLUG] = 0 }
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: makeHintContext(balances: balances),
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        ) == .receive(chain: .ethereum, hasAlternativeToken: true))
    }

    @Test
    func `an empty sell side can suggest another funded token`() {
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: makeHintContext(balances: [SOLANA_SLUG: 1]),
            sellingToken: nil, buyingToken: ApiChain.ethereum.nativeToken
        ) == .receive(chain: .ethereum, hasAlternativeToken: true))
    }

    @Test
    func `the funding hint follows balance updates and the selected sell token`() {
        let context = makeHintContext()
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: context,
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        ) == .receive(chain: .ethereum, hasAlternativeToken: false))

        _BalancesStore.liveValue.for(accountId: context.accountId).replaceAll(byChain: [.solana: [SOLANA_SLUG: 1]])
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: context,
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        ) == .receive(chain: .ethereum, hasAlternativeToken: true))
        #expect(SwapHint.resolve(
            estimate: nil, accountContext: context,
            sellingToken: ApiChain.solana.nativeToken, buyingToken: ApiChain.ethereum.nativeToken
        ) == nil)
    }

    @Test(arguments: [false, true])
    func `a backend hint takes precedence over either local funding message`(hasAlternativeToken: Bool) throws {
        let hint = try JSONDecoder().decode(ApiSwapHint.self, from: Data(
            #"{"type":"external","providerName":"1inch","url":"https://example.com/swap"}"#.utf8
        ))
        let context = makeHintContext(balances: hasAlternativeToken ? [SOLANA_SLUG: 1] : [:])
        #expect(SwapHint.resolve(
            estimate: .error(ApiSwapEstimateErrorResponse(error: "Pair not found", hint: hint)), accountContext: context,
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        ) == .external(providerName: "1inch", url: URL(string: "https://example.com/swap")!))
    }

    @Test
    func `an unusable backend hint does not hide the local funding hint`() throws {
        let hint = try JSONDecoder().decode(ApiSwapHint.self, from: Data(#"{"type":"future"}"#.utf8))
        #expect(SwapHint.resolve(
            estimate: .error(ApiSwapEstimateErrorResponse(error: "Pair not found", hint: hint)), accountContext: makeHintContext(),
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        ) == .receive(chain: .ethereum, hasAlternativeToken: false))
    }

    @Test(arguments: [0, 500_000_000, 1_000_000_000, 2_000_000_000], ["0.1", "2"])
    func `minimum funding compares the wallet balance regardless of the entered amount`(balance: Int, enteredAmount: String) throws {
        let context = makeHintContext(balances: [TONCOIN_SLUG: BigInt(balance)])
        let estimate = try makeMinimumEstimate(enteredAmount: enteredAmount)
        let hint = SwapHint.resolve(
            estimate: estimate, accountContext: context,
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        )
        #expect(hint == (balance < 1_000_000_000 ? .belowMinimum(chain: .ethereum) : nil))
    }

    @Test
    func `externally funded swaps do not treat an unknown source balance as below minimum`() throws {
        let selling = ApiChain.tron.nativeToken
        let context = makeHintContext()
        #expect(SwapPairResolver().swapType(
            selling: selling, buying: ApiChain.ethereum.nativeToken, accountChains: context.account.supportedChains
        ) == .crosschainToWallet)
        #expect(SwapHint.resolve(
            estimate: try makeMinimumEstimate(selling: selling), accountContext: context,
            sellingToken: selling, buyingToken: ApiChain.ethereum.nativeToken
        ) == .receive(chain: .ethereum, hasAlternativeToken: false))
    }

    @Test
    func `minimum comparison preserves the selling token precision`() throws {
        let selling = ApiChain.ethereum.nativeToken
        let minimum = try #require(BigInt("1000000000000000001"))
        let estimate = try makeMinimumEstimate(selling: selling, buying: .TONCOIN, minimum: "1.000000000000000001")
        #expect(SwapHint.resolve(
            estimate: estimate, accountContext: makeHintContext(balances: [selling.slug: minimum - 1]),
            sellingToken: selling, buyingToken: .TONCOIN
        ) == .belowMinimum(chain: .ton))
        #expect(SwapHint.resolve(
            estimate: estimate, accountContext: makeHintContext(balances: [selling.slug: minimum]),
            sellingToken: selling, buyingToken: .TONCOIN
        ) == nil)
    }

    @Test
    func `a stale minimum or an error without a minimum does not show the small balance hint`() throws {
        let context = makeHintContext(balances: [TONCOIN_SLUG: 1])
        let input = SwapEstimateInput(
            accountId: context.accountId, selling: TokenAmount(100_000_000, .TONCOIN),
            buying: TokenAmount(0, ApiChain.ethereum.nativeToken), inputSource: .selling,
            isMaxAmount: false, maxAmount: nil, slippage: 5
        )
        let changedInput = SwapEstimateInput(
            accountId: input.accountId, selling: input.selling, buying: TokenAmount(0, ApiChain.solana.nativeToken),
            inputSource: .selling, isMaxAmount: false, maxAmount: nil, slippage: 5
        )
        var state = SwapEstimateModel()
        state.apply(SwapEstimateResult(changedFrom: .selling, response: try makeMinimumEstimate()), input: input)
        #expect(SwapHint.resolve(
            estimate: state.response(for: input), accountContext: context,
            sellingToken: .TONCOIN, buyingToken: input.buying.token
        ) == .belowMinimum(chain: .ethereum))
        #expect(SwapHint.resolve(
            estimate: state.response(for: changedInput), accountContext: context,
            sellingToken: .TONCOIN, buyingToken: changedInput.buying.token
        ) == nil)

        state.apply(SwapEstimateResult(changedFrom: .selling, response: .error(
            ApiSwapEstimateErrorResponse(error: "Too small amount", hint: nil)
        )), input: input)
        #expect(SwapHint.resolve(
            estimate: state.response(for: input), accountContext: context,
            sellingToken: .TONCOIN, buyingToken: input.buying.token
        ) == nil)
    }

    @Test
    func `a backend hint takes precedence over the small balance hint`() throws {
        let estimate = try makeMinimumEstimate(hint: [
            "type": "external", "providerName": "1inch", "url": "https://example.com/swap"
        ])
        #expect(SwapHint.resolve(
            estimate: estimate, accountContext: makeHintContext(balances: [TONCOIN_SLUG: 1]),
            sellingToken: .TONCOIN, buyingToken: ApiChain.ethereum.nativeToken
        ) == .external(providerName: "1inch", url: URL(string: "https://example.com/swap")!))
    }
}

private func makeMinimumEstimate(
    selling: ApiToken = .TONCOIN,
    buying: ApiToken = ApiChain.ethereum.nativeToken,
    minimum: String = "1",
    enteredAmount: String = "0.1",
    hint: [String: String]? = nil
) throws -> ApiSwapEstimateResponse {
    var payload: [String: Any] = [
        "route": "cex", "cexLabel": "changelly", "from": selling.swapIdentifier, "to": buying.swapIdentifier,
        "fromAmount": enteredAmount, "toAmount": "1", "swapFee": "0", "fromMin": minimum, "fromMax": "1000"
    ]
    if let hint { payload["hint"] = hint }
    return try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: JSONSerialization.data(withJSONObject: payload))
}

@MainActor
private func makeHintContext(balances: [String: BigInt] = [:], hasLoadedBalances: Bool = true) -> AccountContext {
    let accountId = "swaphints\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))-mainnet"
    let store = _BalancesStore.liveValue
    if hasLoadedBalances {
        var byChain: [ApiChain: [String: BigInt]] = [.ton: [:], .solana: [:], .ethereum: [:]]
        for (slug, balance) in balances {
            if let chain = getChainBySlug(slug) {
                byChain[chain, default: [:]][slug] = balance
            }
        }
        store.for(accountId: accountId).replaceAll(byChain: byChain)
    }
    return withDependencies {
        $0[_BalancesStore.self] = store
    } operation: {
        let account = MAccount(id: accountId, title: nil, type: .mnemonic, byChain: [
            .ton: AccountChain(address: "ton-address"),
            .solana: AccountChain(address: "solana-address"),
            .ethereum: AccountChain(address: "ethereum-address")
        ])
        return AccountContext(source: .constant(account))
    }
}
