import Foundation
import Testing
import Dependencies
@testable import UISwap
import WalletCore
import WalletContext

@Suite("Swap Estimate Pipeline")
@MainActor
struct SwapEstimatePipelineTests {
    @Test
    func `applied estimate output cannot move the request`() {
        // The opposite-side amount is an output: it is not part of the
        // request, so writing an estimate back cannot start another one.
        let requested = deriveRequest(inputSource: .selling, sellingAmount: 100, buyingAmount: nil)
        let applied = deriveRequest(inputSource: .selling, sellingAmount: 100, buyingAmount: 250)

        #expect(requested == applied)

        let requestedBuy = deriveRequest(inputSource: .buying, sellingAmount: nil, buyingAmount: 250)
        let appliedBuy = deriveRequest(inputSource: .buying, sellingAmount: 100, buyingAmount: 250)

        #expect(requestedBuy == appliedBuy)
    }

    @Test
    func `backend max adjustment cannot move the request`() {
        // In max mode the request keys on the balance, not the amount the
        // backend computes from it.
        let requested = deriveRequest(inputSource: .selling, sellingAmount: 1_000, buyingAmount: nil, isUsingMax: true, tokenBalance: 1_000)
        let applied = deriveRequest(inputSource: .selling, sellingAmount: 900, buyingAmount: 250, isUsingMax: true, tokenBalance: 1_000)

        #expect(requested == applied)
    }

    @Test
    func `balance change moves a max request`() {
        let before = deriveRequest(inputSource: .selling, sellingAmount: 1_000, buyingAmount: nil, isUsingMax: true, tokenBalance: 1_000)
        let after = deriveRequest(inputSource: .selling, sellingAmount: 900, buyingAmount: 250, isUsingMax: true, tokenBalance: 900)

        #expect(before != after)
    }

    @Test
    func `typed amount change moves the request`() {
        let before = deriveRequest(inputSource: .selling, sellingAmount: 1_000, buyingAmount: nil)
        let after = deriveRequest(inputSource: .selling, sellingAmount: 900, buyingAmount: 250)

        #expect(before != after)
    }

    @Test
    func `token pair change moves the request`() {
        let before = deriveRequest(inputSource: .selling, sellingAmount: 100, buyingAmount: nil)
        let after = deriveRequest(buyingSlug: "eth", inputSource: .selling, sellingAmount: 100, buyingAmount: 250)

        #expect(before != after)
    }

    @Test
    func `disabled buy side coerces the request to the sell side`() {
        let request = deriveRequest(
            inputSource: .buying,
            isBuyAmountInputDisabled: true,
            sellingAmount: 100,
            buyingAmount: 250
        )

        #expect(request?.side == .selling)
        #expect(request?.amount == .exact(100))
    }

    @Test
    func `invalid pair produces no request`() {
        let request = deriveRequest(inputSource: .selling, sellingAmount: 100, buyingAmount: nil, isValidPair: false)

        #expect(request == nil)
    }

    @Test
    @MainActor
    func `TON on chain swaps allow buy amount input when pair allows reverse`() {
        let mode = resolveBuyAmountInputMode(
            swapType: .onChain,
            sellingChain: .ton,
            isReverseProhibited: false
        )

        #expect(mode == .enabled)
    }

    @Test
    @MainActor
    func `TON on chain swaps do not map unknown pair state to disabled UI`() {
        let mode = resolveBuyAmountInputMode(
            swapType: .onChain,
            sellingChain: .ton,
            isReverseProhibited: nil
        )

        #expect(mode == .enabled)
    }

    @Test
    @MainActor
    func `TON on chain swaps disable buy amount when pair prohibits reverse`() {
        let mode = resolveBuyAmountInputMode(
            swapType: .onChain,
            sellingChain: .ton,
            isReverseProhibited: true
        )

        #expect(mode == .disabled)
    }

    @Test
    @MainActor
    func `Solana on chain swaps disable buy amount input even when pair allows reverse`() {
        let mode = resolveBuyAmountInputMode(
            swapType: .onChain,
            sellingChain: .solana,
            isReverseProhibited: false
        )

        #expect(mode == .disabled)
    }

    @Test
    func `external to external pairs are outside account scope`() {
        let isScoped = isSwapPairInAccountScope(
            selling: token(slug: "ethereum-eth", symbol: "ETH", chain: .ethereum),
            buying: token(slug: "solana-sol", symbol: "SOL", chain: .solana),
            accountChains: [.ton]
        )

        #expect(!isScoped)
    }

    @Test
    func `external to wallet pairs remain inside account scope`() {
        let isScoped = isSwapPairInAccountScope(
            selling: token(slug: "ethereum-eth", symbol: "ETH", chain: .ethereum),
            buying: token(slug: "toncoin", symbol: "TON", chain: .ton),
            accountChains: [.ton]
        )

        #expect(isScoped)
    }

    @Test
    @MainActor
    func `pair resolver rejects external to external without loading pairs`() async throws {
        let resolver = SwapPairResolver()
        let resolution = try await resolver.resolve(
            selling: token(slug: "ethereum-eth", symbol: "ETH", chain: .ethereum),
            buying: token(slug: "solana-sol", symbol: "SOL", chain: .solana),
            accountChains: [.ton]
        )

        #expect(resolution.swapType == .crosschainToWallet)
        #expect(!resolution.isValidPair)
        #expect(resolution.buyAmountInputMode == .disabled)
    }

    @Test
    @MainActor
    func `cross chain executor throws when estimate is missing`() async {
        let executor = CrosschainSwapExecutor()
        let account = SwapAccountSnapshot(
            account: MAccount(
                id: "test-mainnet",
                title: nil,
                type: .mnemonic,
                byChain: [.ton: AccountChain(address: "ton-address")]
            ),
            balances: [:]
        )

        do {
            _ = try await executor.performSwap(
                swapType: .crosschainToWallet,
                swapEstimate: nil,
                sellingToken: token(slug: "ethereum-eth", symbol: "ETH", chain: .ethereum),
                buyingToken: token(slug: "toncoin", symbol: "TON", chain: .ton),
                account: account,
                enclaveToken: "test-token"
            )
            #expect(Bool(false), "Expected missing estimate to throw")
        } catch is SdkError {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Expected SdkError")
        }
    }

    @Test
    @MainActor
    func `cross chain estimate engine rejects buy side estimates`() async {
        let engine = CrosschainSwapEstimateEngine()
        let input = makeInput(
            sellingToken: token(slug: "ethereum-eth", symbol: "ETH", chain: .ethereum),
            buyingToken: token(slug: "toncoin", symbol: "TON", chain: .ton),
            sellingAmount: 0,
            buyingAmount: 200,
            inputSource: .buying
        )
        let account = SwapAccountSnapshot(
            account: MAccount(
                id: "test-mainnet",
                title: nil,
                type: .mnemonic,
                byChain: [.ton: AccountChain(address: "ton-address")]
            ),
            balances: [:]
        )

        do {
            _ = try await engine.estimate(
                input,
                changedFrom: .buying,
                swapType: .crosschainToWallet,
                account: account
            )
            #expect(Bool(false), "Expected buy-side CEX estimate to throw")
        } catch is SdkError {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Expected SdkError")
        }
    }

    @Test
    func `rate limit backend message is detected`() {
        let error = SdkError.apiReturnedError(error: "Requests limit exceeded", data: "")

        #expect(isSwapEstimateRateLimited(error))
    }

    @Test
    func `swap estimate errors share one mapping`() {
        let error = SdkError.apiReturnedError(error: "Insufficient liquidity", data: "")

        #expect(swapEstimateIssue(from: error) == .insufficientLiquidity)
    }

    @Test
    @MainActor
    func `cross chain non native token fee issue names native token`() {
        let validator = CrosschainSwapValidator()
        var estimate = makeCexEstimate(fromAmount: 10, toAmount: 20)
        estimate.isEnoughNative = false
        let account = SwapAccountSnapshot(
            account: MAccount(
                id: "test-mainnet",
                title: nil,
                type: .mnemonic,
                byChain: [.tron: AccountChain(address: "tron-address")]
            ),
            balances: [
                TRON_USDT_SLUG: 100,
                TRX_SLUG: 0,
            ]
        )
        let issue = validator.validationIssue(
            input: SwapValidationInput(
                sellingToken: token(slug: TRON_USDT_SLUG, symbol: "USDT", chain: .tron),
                buyingToken: token(slug: "toncoin", symbol: "TON", chain: .ton),
                sellingAmount: 10,
                maxAmount: nil,
                swapType: .crosschainInsideWallet
            ),
            swapEstimate: estimate,
            account: account
        )

        guard case .notEnoughToken(let token) = issue else {
            #expect(Bool(false), "Expected not enough native token issue")
            return
        }
        #expect(token.slug == TRX_SLUG)
        #expect(token.symbol == "TRX")
    }

    @Test
    @MainActor
    func `cross chain native token fee issue remains insufficient balance`() {
        let validator = CrosschainSwapValidator()
        var estimate = makeCexEstimate(fromAmount: 10, toAmount: 20)
        estimate.isEnoughNative = false
        let account = SwapAccountSnapshot(
            account: MAccount(
                id: "test-mainnet",
                title: nil,
                type: .mnemonic,
                byChain: [.tron: AccountChain(address: "tron-address")]
            ),
            balances: [TRX_SLUG: 100]
        )
        let issue = validator.validationIssue(
            input: SwapValidationInput(
                sellingToken: token(slug: TRX_SLUG, symbol: "TRX", chain: .tron),
                buyingToken: token(slug: "toncoin", symbol: "TON", chain: .ton),
                sellingAmount: 10,
                maxAmount: nil,
                swapType: .crosschainInsideWallet
            ),
            swapEstimate: estimate,
            account: account
        )

        #expect(issue == .insufficientBalance)
    }

    @Test
    @MainActor
    func `cross chain unknown fee blocks with an unexpected estimate error`() {
        let validator = CrosschainSwapValidator()
        var estimate = makeCexEstimate(fromAmount: 10, toAmount: 20)
        estimate.isEnoughNative = nil
        let account = tronAccount(balances: [TRON_USDT_SLUG: 100, TRX_SLUG: 100])

        let issue = validator.validationIssue(
            input: usdtToTonInput(sellingAmount: 10),
            swapEstimate: estimate,
            account: account
        )

        #expect(issue == .unexpectedEstimateError)
    }

    @Test
    @MainActor
    func `cross chain unknown fee keeps the insufficient balance issue`() {
        let validator = CrosschainSwapValidator()
        var estimate = makeCexEstimate(fromAmount: 10, toAmount: 20)
        estimate.isEnoughNative = nil
        let account = tronAccount(balances: [TRON_USDT_SLUG: 5, TRX_SLUG: 100])

        let issue = validator.validationIssue(
            input: usdtToTonInput(sellingAmount: 10),
            swapEstimate: estimate,
            account: account
        )

        #expect(issue == .insufficientBalance)
    }

    @Test
    @MainActor
    func `cross chain fee gate is unknown only when the fee is unknown`() {
        let selling = TokenAmount(10, token(slug: TRON_USDT_SLUG, symbol: "USDT", chain: .tron))
        let account = tronAccount(balances: [:])

        #expect(isEnoughNativeForCrosschain(selling: selling, swapType: .crosschainInsideWallet, fee: nil, account: account) == nil)
        #expect(isEnoughNativeForCrosschain(selling: selling, swapType: .crosschainInsideWallet, fee: 1, account: account) == false)
    }

    @Test
    @MainActor
    func `cross chain fee gate needs the token for the swap and the native token for the fee`() {
        let selling = TokenAmount(10, token(slug: TRON_USDT_SLUG, symbol: "USDT", chain: .tron))
        let account = tronAccount(balances: [TRON_USDT_SLUG: 10, TRX_SLUG: 1])

        #expect(isEnoughNativeForCrosschain(selling: selling, swapType: .crosschainInsideWallet, fee: 1, account: account) == true)
        #expect(isEnoughNativeForCrosschain(selling: selling, swapType: .crosschainInsideWallet, fee: 2, account: account) == false)
        #expect(isEnoughNativeForCrosschain(selling: TokenAmount(11, selling.token), swapType: .crosschainInsideWallet, fee: 1, account: account) == false)
    }

    @Test
    @MainActor
    func `cross chain fee gate passes without a fee when the wallet does not send the transfer`() {
        let selling = TokenAmount(10, token(slug: TRON_USDT_SLUG, symbol: "USDT", chain: .tron))
        let foreignAccount = SwapAccountSnapshot(
            account: MAccount(id: "test-mainnet", title: nil, type: .mnemonic, byChain: [:]),
            balances: [:]
        )

        #expect(isEnoughNativeForCrosschain(selling: selling, swapType: .crosschainInsideWallet, fee: nil, account: foreignAccount) == true)
        #expect(isEnoughNativeForCrosschain(selling: selling, swapType: .crosschainToWallet, fee: nil, account: tronAccount(balances: [:])) == true)
    }

    @Test
    @MainActor
    func `cross chain TRX balance is not reduced by magic reserve`() {
        let validator = CrosschainSwapValidator()
        var estimate = makeCexEstimate(fromAmount: 100, toAmount: 20)
        estimate.isEnoughNative = true
        let account = SwapAccountSnapshot(
            account: MAccount(
                id: "test-mainnet",
                title: nil,
                type: .mnemonic,
                byChain: [.tron: AccountChain(address: "tron-address")]
            ),
            balances: [TRX_SLUG: 100]
        )
        let issue = validator.validationIssue(
            input: SwapValidationInput(
                sellingToken: token(slug: TRX_SLUG, symbol: "TRX", chain: .tron),
                buyingToken: token(slug: "toncoin", symbol: "TON", chain: .ton),
                sellingAmount: 100,
                maxAmount: nil,
                swapType: .crosschainInsideWallet
            ),
            swapEstimate: estimate,
            account: account
        )

        #expect(issue == nil)
    }

    @Test
    func `cross chain native max subtracts source transfer fee before cex estimate`() {
        let trx = token(slug: TRX_SLUG, symbol: "TRX", chain: .tron, decimals: 6)
        let account = SwapAccountSnapshot(
            account: MAccount(
                id: "test-mainnet",
                title: nil,
                type: .mnemonic,
                byChain: [.tron: AccountChain(address: "tron-address")]
            ),
            balances: [TRX_SLUG: 105_240_099]
        )

        let maxAmount = crosschainAdjustedNativeMaxAmount(
            sellingToken: trx,
            swapType: .crosschainInsideWallet,
            isMaxAmount: true,
            account: account,
            networkFee: MDouble("1.1")
        )

        #expect(maxAmount == 104_140_099)
    }

    @Test
    func `cross chain evm native max drafts transfer fee with full balance`() {
        let eth = token(slug: ETH_SLUG, symbol: "ETH", chain: .ethereum, decimals: 18)
        let balance: BigInt = 123_000_000_000_000_000
        let account = SwapAccountSnapshot(
            account: MAccount(
                id: "test-mainnet",
                title: nil,
                type: .mnemonic,
                byChain: [.ethereum: AccountChain(address: "ethereum-address")]
            ),
            balances: [ETH_SLUG: balance]
        )

        let draftAmount = crosschainNetworkFeeDraftAmount(
            sellingToken: eth,
            isMaxAmount: true,
            account: account,
            amount: 1
        )

        #expect(draftAmount == balance)
    }

    @Test(arguments: [ApiChain.dogecoin, .bitcoin, .litecoin, .bitcoincash, .ethereum, .ton, .solana, .tron])
    func `native fee draft uses full balance for max and requested amount otherwise`(chain: ApiChain) {
        let native = chain.nativeToken
        let account = SwapAccountSnapshot(
            account: MAccount(id: "test-mainnet", title: nil, type: .mnemonic, byChain: [:]),
            balances: [native.slug: 300_000_000]
        )
        #expect(crosschainNetworkFeeDraftAmount(
            sellingToken: native, isMaxAmount: true, account: account, amount: 299_774_000
        ) == 300_000_000)
        #expect(crosschainNetworkFeeDraftAmount(
            sellingToken: native, isMaxAmount: false, account: account, amount: 100_000_000
        ) == 100_000_000)
    }

    @Test
    func `cross chain wait payment hides qr when memo is required`() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let payment = makeCrosschainPayment(
            createdAt: createdAt,
            payinExtraId: "memo-123",
            cexStatus: .waiting
        )

        #expect(payment.showsPaymentInstructions(at: createdAt))
        #expect(!payment.shouldShowQRCode(at: createdAt))
    }

    @Test
    func `cross chain wait payment expires after deadline`() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let payment = makeCrosschainPayment(
            createdAt: createdAt,
            cexStatus: .waiting
        )

        #expect(payment.isExpired(at: createdAt.addingTimeInterval(3 * 60 * 60 + 1)))
    }

    @Test
    func `internal cross chain swap suppresses payment instructions`() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let payment = makeCrosschainPayment(
            createdAt: createdAt,
            cexStatus: .waiting,
            isInternalSwap: true
        )

        #expect(!payment.showsPaymentInstructions(at: createdAt))
    }

    @Test
    func `amount limit issues use token amount formatting`() {
        let token = token(slug: "usdt", symbol: "USDT", chain: .ton, decimals: 9)

        #expect(SwapIssue.minimumAmount(1.23456789, token).buttonTitle == L10n.minimumAmount(value: "1.23 USDT"))
        #expect(SwapIssue.maximumAmount(123.456789, token).buttonTitle == L10n.maximumAmount(value: "123.46 USDT"))
    }

}

private func makeInput(
    sellingToken: ApiToken = token(slug: "toncoin", symbol: "TON", chain: .ton),
    buyingToken: ApiToken = token(slug: "usdt", symbol: "USDT", chain: .ton),
    sellingAmount: BigInt,
    buyingAmount: BigInt,
    inputSource: SwapSide,
    isMaxAmount: Bool = false,
    maxAmount: BigInt? = nil,
    slippage: Double = 5
) -> SwapEstimateInput {
    SwapEstimateInput(
        accountId: "test-mainnet",
        selling: TokenAmount(sellingAmount, sellingToken),
        buying: TokenAmount(buyingAmount, buyingToken),
        inputSource: inputSource,
        isMaxAmount: isMaxAmount,
        maxAmount: maxAmount,
        slippage: slippage
    )
}

@MainActor private func deriveRequest(
    sellingSlug: String = "toncoin",
    buyingSlug: String = "usdt",
    inputSource: SwapSide,
    isBuyAmountInputDisabled: Bool = false,
    sellingAmount: BigInt?,
    buyingAmount: BigInt?,
    isUsingMax: Bool = false,
    tokenBalance: BigInt? = nil,
    isValidPair: Bool = true,
    slippage: Double = 5
) -> SwapEstimateRequest? {
    return withDependencies {
        $0[_TokenStore.self] = TokenStore
    } operation: {
        let input = SwapInputModel(
            sellingTokenSlug: nil,
            buyingTokenSlug: nil,
            tokenBalance: tokenBalance,
            accountContext: AccountContext(source: .constant(MAccount(
                id: "test-mainnet", title: nil, type: .mnemonic, byChain: [:]
            )))
        )
        input.sellingToken = token(slug: sellingSlug, symbol: "SELL", chain: .ton)
        input.buyingToken = token(slug: buyingSlug, symbol: "BUY", chain: .ton)
        input.inputSource = inputSource
        input.buyingAmountInputDisabled = isBuyAmountInputDisabled
        input.isUsingMax = isUsingMax
        input.sellingAmount = sellingAmount
        input.buyingAmount = buyingAmount
        return SwapEstimateRequest.derive(
            accountId: "test-mainnet",
            input: input,
            isValidPair: isValidPair,
            slippage: slippage
        )
    }
}

private func makeCrosschainPayment(
    createdAt: Date,
    payinExtraId: String? = nil,
    cexStatus: ApiSwapCexTransactionStatus? = nil,
    isInternalSwap: Bool = false
) -> CrosschainToWalletPayment {
    CrosschainToWalletPayment(
        sellingAmount: TokenAmount(100, token(slug: "ethereum-eth", symbol: "ETH", chain: .ethereum)),
        buyingAmount: TokenAmount(200, token(slug: "toncoin", symbol: "TON", chain: .ton)),
        payinAddress: "payin-address",
        payoutAddress: "payout-address",
        payinExtraId: payinExtraId,
        exchangerTxId: "cex-id",
        cexLabel: nil,
        providerName: nil,
        supportUrl: nil,
        supportEmail: nil,
        createdAt: createdAt,
        cexStatus: cexStatus,
        isInternalSwap: isInternalSwap
    )
}

private func makeCexEstimate(fromAmount: Double, toAmount: Double) -> ApiSwapCexEstimateResponse {
    let data = """
    {
      "route": "cex",
      "cexLabel": "changelly",
      "from": "from-token",
      "fromAmount": "\(fromAmount)",
      "to": "to-token",
      "toAmount": "\(toAmount)",
      "swapFee": "0",
      "fromMin": "1",
      "fromMax": "1000"
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(ApiSwapCexEstimateResponse.self, from: data)
}

private func tronAccount(balances: [String: BigInt]) -> SwapAccountSnapshot {
    SwapAccountSnapshot(
        account: MAccount(
            id: "test-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: [.tron: AccountChain(address: "tron-address")]
        ),
        balances: balances
    )
}

private func usdtToTonInput(sellingAmount: BigInt) -> SwapValidationInput {
    SwapValidationInput(
        sellingToken: token(slug: TRON_USDT_SLUG, symbol: "USDT", chain: .tron),
        buyingToken: token(slug: "toncoin", symbol: "TON", chain: .ton),
        sellingAmount: sellingAmount,
        maxAmount: nil,
        swapType: .crosschainInsideWallet
    )
}

private func token(slug: String, symbol: String, chain: ApiChain, decimals: Int = 9) -> ApiToken {
    ApiToken(
        slug: slug,
        name: symbol,
        symbol: symbol,
        decimals: decimals,
        chain: chain
    )
}
