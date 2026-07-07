import Foundation
import Testing
@testable import UISwap
import WalletCore
import WalletContext
import Dependencies

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
    func `estimate gate prevents overlap and requests one follow up`() {
        var gate = SwapEstimateGate()
        let first = makeInput(sellingAmount: 100, buyingAmount: 0, inputSource: .selling)
        let second = makeInput(sellingAmount: 200, buyingAmount: 0, inputSource: .selling)

        let didStartFirst = gate.start(first)
        let didStartSecond = gate.start(second)
        #expect(didStartFirst)
        #expect(!didStartSecond)
        #expect(gate.isInFlight)
        let didRequestFollowUp = gate.finish()
        #expect(didRequestFollowUp)
        #expect(!gate.isInFlight)
        let didStartFollowUp = gate.start(second)
        let didRequestSecondFollowUp = gate.finish()
        #expect(didStartFollowUp)
        #expect(!didRequestSecondFollowUp)
    }

    @Test
    func `estimate gate can cancel pending follow up`() {
        var gate = SwapEstimateGate()
        let first = makeInput(sellingAmount: 100, buyingAmount: 0, inputSource: .selling)
        let second = makeInput(sellingAmount: 0, buyingAmount: 200, inputSource: .buying)

        let didStartFirst = gate.start(first)
        let didStartSecond = gate.start(second)
        #expect(didStartFirst)
        #expect(!didStartSecond)
        gate.cancelFollowUp()

        let didRequestFollowUp = gate.finish()
        #expect(!didRequestFollowUp)
    }

    @Test
    @MainActor
    func `cross chain swaps disable buy amount input`() {
        let context = SwapContextModel()
        let isDisabled = context.currentBuyAmountInputDisabled(
            selling: token(slug: "eth", symbol: "ETH", chain: .ethereum),
            buying: token(slug: "toncoin", symbol: "TON", chain: .ton),
            accountChains: [.ton]
        )

        #expect(isDisabled)
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
                passcode: "0000"
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
    @MainActor
    func `rate limited estimates preserve current state`() {
        let update = SwapEstimateUpdate.rateLimited(changedFrom: .selling)

        #expect(update.keepsCurrentState)
    }

    @Test
    @MainActor
    func `leaving editing stage clears estimating state`() {
        let model = makeSwapModel()
        model.input.startEstimating(changedFrom: .selling)

        model.setStage(.confirming)

        #expect(!model.input.isEstimating)
    }

    @Test
    @MainActor
    func `buy token selection preserves previous estimate while refresh loads`() {
        let oldBuyingToken = token(slug: "old-usdt", symbol: "USDT", chain: .ton, decimals: 9)
        let newBuyingToken = token(slug: "new-usdt", symbol: "USDT", chain: .ton, decimals: 6)
        let model = makeInputModel()
        model.sellingAmount = 1_000_000_000
        model.buyingToken = oldBuyingToken
        model.buyingAmount = 1_250_000_000

        model.userSelectedToken(newBuyingToken, side: .buying)

        #expect(model.buyingToken == newBuyingToken)
        #expect(model.buyingAmount == 1_250_000)
    }

    @Test
    @MainActor
    func `failed sell estimate clears stale buy amount`() {
        let model = makeInputModel()
        model.sellingAmount = 1_000_000_000
        model.buyingAmount = 2_000_000_000
        let update = SwapEstimateUpdate(
            changedFrom: .selling,
            estimatedAmounts: nil,
            backendMaxAmount: nil,
            stateUpdate: nil
        )

        update.apply(to: model)

        #expect(model.buyingAmount == nil)
    }

    @Test
    func `rate limit backend message is detected`() {
        let error = SdkError.apiReturnedError(error: "Requests limit exceeded", data: "")

        #expect(isSwapEstimateRateLimited(error))
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
    func `on chain swap local history starts pending trusted`() {
        let request = ApiSwapBuildRequest(
            from: "TON",
            to: "GRAM",
            fromAddress: "sender-address",
            dexLabel: .dedust,
            fromAmount: 1,
            toAmount: 2,
            toMinAmount: 2,
            slippage: 0.5,
            shouldTryDiesel: false,
            swapVersion: nil,
            walletVersion: nil,
            routes: nil,
            networkFee: 0.1,
            swapFee: 0,
            ourFee: 0,
            dieselFee: nil
        )

        let item = ApiSwapHistoryItem.makeFrom(swapBuildRequest: request, swapId: "swap-id")

        #expect(item.status == .pendingTrusted)
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
    @MainActor
    func `button model surfaces typed issue`() {
        let model = SwapButtonModel()
        let config = model.configuration(
            for: .blocked(.tooSmallAmount),
            sellingToken: token(slug: "toncoin", symbol: "TON", chain: .ton),
            buyingToken: token(slug: "usdt", symbol: "USDT", chain: .ton)
        )

        #expect(config.isEnabled == false)
        #expect(issue(from: config) == .tooSmallAmount)
    }

    @Test
    @MainActor
    func `button model suppresses issue while estimating`() {
        let model = SwapButtonModel()
        let config = model.configuration(
            for: .estimating(showContinue: false),
            sellingToken: token(slug: "toncoin", symbol: "TON", chain: .ton),
            buyingToken: token(slug: "usdt", symbol: "USDT", chain: .ton)
        )

        #expect(config.isEnabled == false)
        #expect(config.showLoading == true)
        #expect(issue(from: config) == nil)
    }

    @Test
    func `amount limit issues use token amount formatting`() {
        let token = token(slug: "usdt", symbol: "USDT", chain: .ton, decimals: 9)

        #expect(SwapIssue.minimumAmount(1.23456789, token).buttonTitle == lang("Minimum amount", arg1: "1.23 USDT"))
        #expect(SwapIssue.maximumAmount(123.456789, token).buttonTitle == lang("Maximum amount", arg1: "123.46 USDT"))
    }

}

private func issue(from config: SwapButtonConfiguration) -> SwapIssue? {
    if case .issue(let issue) = config.title {
        return issue
    }
    return nil
}

@MainActor
private func makeSwapModel() -> SwapModel {
    withDependencies {
        $0[_TokenStore.self] = TokenStore
        $0[_BalancesStore.self] = _BalancesStore.liveValue
    } operation: {
        let delegate = SwapModelDelegateSpy()
        let account = MAccount(
            id: "test-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: [.ton: AccountChain(address: "ton-address")]
        )
        return SwapModel(
            delegate: delegate,
            defaultSellingToken: TONCOIN_SLUG,
            defaultBuyingToken: TON_USDT_SLUG,
            defaultSellingAmount: nil,
            accountContext: AccountContext(source: .constant(account))
        )
    }
}

@MainActor
private final class SwapModelDelegateSpy: SwapModelDelegate {
    func applyButtonConfiguration(_ config: SwapButtonConfiguration) {
    }

    func executeSwapCommand(_ command: SwapCommand) {
    }
}

@MainActor
private func makeInputModel() -> SwapInputModel {
    withDependencies {
        $0[_TokenStore.self] = TokenStore
    } operation: {
        let account = MAccount(
            id: "test-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: [.ton: AccountChain(address: "ton-address")]
        )
        let model = SwapInputModel(
            sellingTokenSlug: "toncoin",
            buyingTokenSlug: "old-usdt",
            tokenBalance: 10_000_000_000,
            accountContext: AccountContext(source: .constant(account))
        )
        model.sellingToken = token(slug: "toncoin", symbol: "TON", chain: .ton)
        model.buyingToken = token(slug: "old-usdt", symbol: "USDT", chain: .ton)
        return model
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
      "from": "from-token",
      "fromAmount": "\(fromAmount)",
      "to": "to-token",
      "toAmount": "\(toAmount)",
      "swapFee": "0"
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(ApiSwapCexEstimateResponse.self, from: data)
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
