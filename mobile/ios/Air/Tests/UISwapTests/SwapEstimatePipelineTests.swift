import Foundation
import Testing
@testable import UISwap
import WalletCore
import WalletContext

@Suite("Swap Estimate Pipeline")
struct SwapEstimatePipelineTests {
    @Test
    func `estimate accepts output amount changes from applied sell estimate`() {
        let requested = makeInput(sellingAmount: 100, buyingAmount: 0, inputSource: .selling)
        let current = makeInput(sellingAmount: 100, buyingAmount: 250, inputSource: .selling)

        #expect(requested.matchesCurrent(current))
    }

    @Test
    func `estimate accepts output amount changes from applied buy estimate`() {
        let requested = makeInput(sellingAmount: 0, buyingAmount: 250, inputSource: .buying)
        let current = makeInput(sellingAmount: 100, buyingAmount: 250, inputSource: .buying)

        #expect(requested.matchesCurrent(current))
    }

    @Test
    func `max amount backend adjustment does not stale estimate`() {
        let requested = makeInput(sellingAmount: 1_000, buyingAmount: 0, inputSource: .selling, isMaxAmount: true, maxAmount: 1_000)
        let current = makeInput(sellingAmount: 900, buyingAmount: 250, inputSource: .selling, isMaxAmount: true, maxAmount: 1_000)

        #expect(requested.matchesCurrent(current))
    }

    @Test
    func `max amount balance change stales estimate`() {
        let requested = makeInput(sellingAmount: 1_000, buyingAmount: 0, inputSource: .selling, isMaxAmount: true, maxAmount: 1_000)
        let current = makeInput(sellingAmount: 900, buyingAmount: 250, inputSource: .selling, isMaxAmount: true, maxAmount: 900)

        #expect(!requested.matchesCurrent(current))
    }

    @Test
    func `non max input amount change stales estimate`() {
        let requested = makeInput(sellingAmount: 1_000, buyingAmount: 0, inputSource: .selling)
        let current = makeInput(sellingAmount: 900, buyingAmount: 250, inputSource: .selling)

        #expect(!requested.matchesCurrent(current))
    }

    @Test
    func `token pair change stales estimate`() {
        let requested = makeInput(sellingAmount: 100, buyingAmount: 0, inputSource: .selling)
        let current = makeInput(
            sellingToken: token(slug: "toncoin", symbol: "TON", chain: .ton),
            buyingToken: token(slug: "eth", symbol: "ETH", chain: .ethereum),
            sellingAmount: 100,
            buyingAmount: 250,
            inputSource: .selling
        )

        #expect(!requested.matchesCurrent(current))
    }

    @Test
    func `estimate gate prevents overlap and requests one follow up`() throws {
        var gate = SwapEstimateGate()
        let first = makeInput(sellingAmount: 100, buyingAmount: 0, inputSource: .selling)
        let second = makeInput(sellingAmount: 200, buyingAmount: 0, inputSource: .selling)

        let firstSlot = gate.start(first)
        let secondSlot = gate.start(second)
        #expect(firstSlot != nil)
        #expect(secondSlot == nil)
        #expect(gate.isInFlight)

        let didRequestFollowUp = gate.finish(try #require(firstSlot))
        #expect(didRequestFollowUp)
        #expect(!gate.isInFlight)

        let followUpSlot = gate.start(second)
        let didRequestSecondFollowUp = gate.finish(try #require(followUpSlot))
        #expect(followUpSlot != nil)
        #expect(!didRequestSecondFollowUp)
    }

    @Test
    func `estimate gate can cancel pending follow up`() throws {
        var gate = SwapEstimateGate()
        let first = makeInput(sellingAmount: 100, buyingAmount: 0, inputSource: .selling)
        let second = makeInput(sellingAmount: 0, buyingAmount: 200, inputSource: .buying)

        let firstSlot = gate.start(first)
        let secondSlot = gate.start(second)
        #expect(firstSlot != nil)
        #expect(secondSlot == nil)
        gate.cancelFollowUp()

        let didRequestFollowUp = gate.finish(try #require(firstSlot))
        #expect(!didRequestFollowUp)
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
            account: account
        )

        #expect(draftAmount == balance)
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
