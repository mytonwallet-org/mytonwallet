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
    func `cross chain executor marks missing estimate as not submitted`() async throws {
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
            Issue.record("Expected missing estimate to throw")
        } catch let error as NotSubmittedError {
            let underlying = try #require(error.underlying as? SdkError)
            #expect(underlying.backendMessage == "Missing swap estimate")
            #expect(actionSubmissionErrorDisposition(for: error) == .notCommitted)
        } catch {
            Issue.record("Expected NotSubmittedError, got \(error)")
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

    @Test(arguments: [
        ("No swap quote available", SwapIssue.quoteUnavailable),
        ("Swap routers are unavailable", SwapIssue.serviceUnavailable),
        ("Insufficient liquidity", SwapIssue.insufficientLiquidity),
        ("Something broke", SwapIssue.unexpectedEstimateError),
    ])
    func `quote failures have helpful messages in returned and thrown responses`(message: String, issue: SwapIssue) throws {
        let thrown = SdkError.apiReturnedError(error: message, data: "")
        #expect(swapEstimateIssue(from: thrown) == issue)

        let data = try JSONSerialization.data(withJSONObject: ["error": message])
        let response = try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: data)
        let result = SwapEstimateResult(changedFrom: .selling, response: response)
        #expect(result.estimateIssue == issue)
        #expect(result.dexEstimate == nil)
        #expect(result.cexEstimate == nil)
        #expect(!result.isRateLimited)
    }

    @Test
    @MainActor
    func `cross chain non native token fee shortage highlights the fee`() {
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

        #expect(issue == .insufficientFee)
    }

    @Test(arguments: [false, true])
    @MainActor
    func `cross chain separates amount shortages from fee shortages`(hasInsufficientAmount: Bool) {
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
            balances: [TRX_SLUG: hasInsufficientAmount ? 5 : 100]
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

        #expect(issue == (hasInsufficientAmount ? .insufficientBalance : .insufficientFee))
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
    func `internal cross chain native max uses a fee reserved CEX quote`() async throws {
        let trx = token(slug: TRX_SLUG, symbol: "TRX", chain: .tron, decimals: 6)
        let ton = ApiChain.ton.nativeToken
        let account = tronAccount(balances: [TRX_SLUG: 105_240_099])
        let input = SwapEstimateInput(
            accountId: account.id,
            selling: TokenAmount(105_240_099, trx),
            buying: TokenAmount(0, ton),
            inputSource: .selling,
            isMaxAmount: true,
            maxAmount: nil,
            slippage: 5
        )
        let flow = CrosschainSwapFlow(
            validator: CrosschainSwapValidator(),
            estimateEngine: CrosschainSwapEstimateEngine(fetchEstimate: { _, request in
                let amount = request.fromAmount?.value
                var quote: ApiSwapCexEstimateResponse
                switch amount {
                case 105.240099:
                    quote = makeCexEstimate(fromAmount: 105.240099, toAmount: 200)
                case 104.140099:
                    quote = makeCexEstimate(fromAmount: 104.140099, toAmount: 198)
                default:
                    Issue.record("CEX was quoted for an unexpected amount: \(String(describing: amount))")
                    quote = makeCexEstimate(fromAmount: 105.240099, toAmount: 200)
                }
                quote.networkFee = MDouble("1.1")
                return .cex(quote)
            })
        )

        let update = try await flow.estimate(input, changedFrom: .selling, swapType: .crosschainInsideWallet, account: account)
        let quote = try #require(update.stateUpdate?.cexEstimate)
        #expect(quote.fromAmount.value == 104.140099)
        #expect(quote.toAmount.value == 198)
        #expect(quote.isEnoughNative == true)
        #expect(update.estimatedAmounts?.fromAmount.value == 104.140099)
        #expect(CrosschainSwapValidator().validationIssue(
            input: SwapValidationInput(
                sellingToken: trx,
                buyingToken: ton,
                sellingAmount: 104_140_099,
                maxAmount: nil,
                swapType: .crosschainInsideWallet
            ),
            swapEstimate: quote,
            account: account
        ) == nil)
    }

    @Test
    func `native max returning from CEX can receive a full balance DEX quote`() async throws {
        let eth = ApiChain.ethereum.nativeToken
        let baseEth = ApiChain.base.nativeToken
        let account = SwapAccountSnapshot(
            account: MAccount(id: "test-mainnet", title: nil, type: .mnemonic, byChain: [
                .ethereum: AccountChain(address: "0xsender"), .base: AccountChain(address: "0xrecipient")
            ]),
            balances: [eth.slug: 1_000_000_000_000_000_000]
        )
        let input = SwapEstimateInput(
            accountId: account.id,
            selling: TokenAmount(990_000_000_000_000_000, eth),
            buying: TokenAmount(0, baseEth),
            inputSource: .selling, isMaxAmount: true, maxAmount: nil, slippage: 1
        )
        let quote = try JSONDecoder().decode(ApiSwapDexEstimateResponse.self, from: Data("""
        {
          "route":"dex", "from":"\(eth.swapIdentifier)", "to":"\(baseEth.swapIdentifier)",
          "fromAmount":"0.98", "toAmount":"0.97", "toMinAmount":"0.96",
          "impact":0.1, "dieselStatus":"not-available", "networkFee":"0.01",
          "swapFee":"0", "swapFeePercent":0, "ourFee":"0", "ourFeePercent":0
        }
        """.utf8))
        let flow = OnchainSwapFlow(
            validator: OnchainSwapValidator(),
            estimateEngine: OnchainSwapEstimateEngine(fetchEstimate: { _, request in
                #expect(request.fromAmount?.value == 1)
                #expect(request.isFromAmountMax == true)
                return .dex(quote)
            })
        )

        let update = try await flow.estimate(input, changedFrom: .selling, swapType: .crosschainInsideWallet, account: account)
        #expect(update.backendMaxAmount == 980_000_000_000_000_000)
        #expect(update.stateUpdate?.dexEstimate?.toAmount.value == 0.97)
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
