import Foundation
import Testing
import UIComponents
import WalletCore
import WalletContext
@testable import UIToken

@Suite @MainActor
struct PerpsOrderStateTests {
    private func fixture() -> PerpsOrderDisplayData {
        var data = PerpsOrderDisplayData(token: .TONCOIN, direction: .short, paymentToken: .TON_USDT,
                                        input: .init(amount: "100.2", leverage: 10))
        data.status = .ready
        data.conversion = "25 TON"
        data.positionSize = "$1 002"
        data.paymentAmount = "100.2"
        data.tradingFee = "$3.61"
        data.fundingPayments = "0.0012%"
        data.leverageOptions = [.init(value: 2), .init(value: 10, liquidationPrice: "$4.50")]
        data.canUseFractions = true
        data.availableCollateral = .init(text: "400")
        return data
    }

    @Test func `editing immediately invalidates estimates and rejects older responses`() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: fixture()) { requests.append($0) }
        state.editAmount(.init(text: "1"))
        #expect(!state.canReview)
        #expect(state.data.status == .loading)
        #expect(state.data.conversion == "25 TON")
        #expect(state.data.positionSize == nil)
        #expect(state.data.paymentAmount == "100.2")
        #expect(state.data.tradingFee == nil)
        #expect(state.data.fundingPayments == "0.0012%")
        #expect(state.data.leverageOptions.last?.liquidationPrice == nil)
        state.editAmount(.init(text: "12"))
        let first = try #require(requests.first)
        let latest = try #require(requests.last)
        var response = fixture()
        response.input = latest.input
        #expect(!state.update(data: fixture(), for: first))
        #expect(state.data.input.amount.text == "12")
        #expect(state.update(data: response, for: latest))
        #expect(state.canReview)
        #expect(state.data.input.amount.text == "12")
    }

    @Test func `initial loading can resolve but cannot overwrite an edited draft`() {
        var loading = fixture()
        loading.status = .loading
        let state = PerpsOrderState(data: loading) { _ in }
        #expect(state.update(data: fixture()))
        #expect(state.canReview)
        state.editAmount(.init(text: "12"))
        #expect(!state.update(data: fixture()))
        #expect(state.data.input.amount.text == "12")
        #expect(!state.canReview)
    }

    @Test func `review can only be sent once until the adapter responds`() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: fixture()) { requests.append($0) }
        state.request(.review)
        state.request(.review)
        #expect(requests.count == 1)
        #expect(requests.first?.action == .review)
        #expect(requests.first?.input == fixture().input)
        #expect(state.data.direction == .short)
        #expect(!state.canReview)
        #expect(state.update(data: fixture(), for: try #require(requests.first)))
        #expect(state.canReview)
    }

    @Test(arguments: [25, 50, 100])
    func `opening fractions fill an empty dollar input through the normal edit path`(_ percentage: Int) {
        var data = fixture()
        data.input.amount = .init()
        data.status = .idle
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        state.request(.fraction(percentage))
        #expect(requests.count == 1)
        #expect(requests.last?.action == .amountChanged)
        #expect(requests.last?.input.amount.text == "\(percentage * 4).00")
        #expect(state.data.input == requests.last?.input)
        #expect(state.data.status == .loading)
        #expect(!state.canReview)
    }

    @Test func `fractions round down to input precision and supersede older estimates`() throws {
        var data = fixture()
        data.currencyDecimals = 6
        data.availableCollateral = .init(text: "200.123459")
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        state.editAmount(.init(text: "10"))
        let earlier = try #require(requests.last)
        state.request(.fraction(25))
        let fraction = try #require(requests.last)
        #expect(fraction.action == .amountChanged)
        #expect(fraction.input.amount.text == "50.030864")
        #expect(!state.update(data: fixture(), for: earlier))
        state.editAmount(.init(text: "51"))
        #expect(!state.update(data: fixture(), for: fraction))
        #expect(state.data.input.amount.text == "51")
    }

    @Test func `fractions wait for a known maximum and retain small fixed point amounts`() {
        var data = fixture()
        data.input.amount = .init()
        data.currencyDecimals = 6
        data.availableCollateral = nil
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        state.request(.fraction(100))
        #expect(requests.isEmpty)
        #expect(state.data.input.amount.text.isEmpty)
        data.availableCollateral = .init(text: "0.000007")
        #expect(state.update(data: data))
        state.request(.fraction(25))
        #expect(requests.last?.input.amount.text == "0.000001")
    }

    @Test func `opening controls require an SDK supplied collateral maximum`() throws {
        let asset = try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"eth","name":"ETH","symbol":"ETH","chain":"hyperliquid","provider":"hyperliquid",
         "dex":"","szDecimals":4,"maxLeverage":40,"context":{"markPx":"2000","prevDayPx":"1950"}}
        """.utf8))
        let account = MAccount(id: "wallet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x1234")])
        var requirements = try JSONDecoder().decode(ApiPerpsFundingRequirements.self, from: Data("""
        {"requiredUsdc":"10.2","requiredEth":"0.0001","requiredEthUsd":"0.25",
         "usdcBalance":"400.2","ethBalance":"1","needsUsdc":false,"needsEth":false}
        """.utf8))
        let unavailable = PerpsSDKAdapter.order(asset: asset, account: account, side: .long, input: .init(), fundingRequirements: requirements)
        #expect(!unavailable.canUseFractions)
        #expect(unavailable.availableCollateral == nil)
        requirements.availableCollateral = "400"
        let ready = PerpsSDKAdapter.order(asset: asset, account: account, side: .long, input: .init(), fundingRequirements: requirements)
        #expect(ready.canUseFractions)
        #expect(ready.availableCollateral?.text == "400")
    }

    @Test func `only supported leverage values trigger a request`() {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: fixture()) { requests.append($0) }
        state.selectLeverage(40)
        state.selectLeverage(10)
        #expect(requests.isEmpty)
        state.selectLeverage(2)
        #expect(requests.last?.action == .leverageChanged)
        #expect(requests.last?.input.leverage == 2)
        #expect(!state.canReview)
    }

    @Test(arguments: ["", "0", "0.", "0.00"])
    func `zero drafts cannot be reviewed even if the adapter marks them ready`(_ amount: String) {
        var data = fixture()
        data.input.amount = .init(text: amount)
        let state = PerpsOrderState(data: data) { _ in Issue.record("Unexpected review request") }
        #expect(!state.canReview)
        state.request(.review)
    }

    @Test(arguments: ["", "0", "0.", "0.00"])
    func `clearing an order immediately restores idle controls and invalidates an old quote`(_ amount: String) throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: fixture()) { requests.append($0) }
        state.editAmount(.init(text: "123"))
        let previous = try #require(requests.last)
        state.editAmount(.init(text: amount))
        #expect(state.data.status == .idle)
        #expect(state.data.conversion == nil)
        #expect(state.data.paymentAmount == nil)
        #expect(state.fractionPresets == [25, 50, 100])
        #expect(!state.canReview)
        #expect(!state.update(data: fixture(), for: previous))
        state.selectLeverage(2)
        #expect(state.data.status == .idle)
    }

    @Test func `selection supersedes an in flight amount response and cancellation can restore the draft`() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: fixture()) { requests.append($0) }
        state.editAmount(.init(text: "123"))
        let amountRequest = try #require(requests.last)
        state.request(.selectPayment)
        let selectionRequest = try #require(requests.last)
        var response = fixture()
        response.input = selectionRequest.input
        #expect(!state.update(data: response, for: amountRequest))
        #expect(state.update(data: response, for: selectionRequest))
        #expect(state.data.input.amount.text == "123")
        #expect(state.canReview)
    }

    @Test func `funding requirements prevent review and leverage changes while allowing amount edits`() {
        var data = fixture()
        data.fundingRequirement = fundingRequirement()
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        #expect(!state.canReview)
        state.request(.review)
        state.selectLeverage(2)
        state.request(.leverageChanged)
        state.request(.fraction(100))
        #expect(requests.isEmpty)
        state.editAmount(.init(text: "25"))
        #expect(requests.last?.action == .amountChanged)
        #expect(requests.last?.input.amount.text == "25")
        #expect(state.data.fundingRequirement == data.fundingRequirement)
    }

    @Test(arguments: [PerpsOrderDisplayData.FundingAction.buyUsdc, .buyEth])
    func `buy actions preserve the draft and do not supersede its current response`(_ action: PerpsOrderDisplayData.FundingAction) {
        var data = fixture()
        data.fundingRequirement = fundingRequirement(action: action)
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        let expected: PerpsOrderRequest.Action = action == .buyUsdc ? .buyUsdc : .buyEth
        state.request(action == .buyUsdc ? .buyEth : .buyUsdc)
        #expect(requests.isEmpty)
        state.request(expected)
        #expect(requests.last?.action == expected)
        #expect(state.latestRequestID == nil)
        #expect(state.data.status == .ready)
        #expect(state.data.input == data.input)
        #expect(state.data.conversion == data.conversion)
        #expect(state.update(data: data))
    }

    @Test func `refreshing funding retains the draft and ignores an earlier quote response`() throws {
        var data = fixture()
        data.fundingRequirement = fundingRequirement()
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        state.editAmount(.init(text: "125"))
        let edit = try #require(requests.last)
        state.request(.refreshFunding)
        let refresh = try #require(requests.last)
        #expect(refresh.action == .refreshFunding)
        #expect(refresh.input.amount.text == "125")
        #expect(state.data.fundingRequirement == data.fundingRequirement)
        #expect(!state.canReview)
        var funded = fixture()
        funded.input = refresh.input
        #expect(!state.update(data: funded, for: edit))
        #expect(state.update(data: funded, for: refresh))
        #expect(state.data.fundingRequirement == nil)
        #expect(state.data.input.amount.text == "125")
        #expect(state.canReview)
    }

    @Test func `failed funding refresh can retry the same wallet and draft then remain insufficient`() throws {
        var data = fixture()
        data.account = MAccount(id: "funding-wallet", title: "Wallet", type: .mnemonic,
            byChain: [.arbitrum: AccountChain(address: "0x1234")])
        data.fundingRequirement = fundingRequirement()
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        state.request(.buyUsdc)
        state.request(.refreshFunding)
        let failedRequest = try #require(requests.last)
        var failed = data
        failed.fundingRequirement = nil
        failed.status = .unavailable("Unable to refresh balances")
        #expect(state.update(data: failed, for: failedRequest))
        #expect(state.canRetryFunding)
        #expect(!state.canReview)

        state.request(.refreshFunding)
        let retry = try #require(requests.last)
        #expect(retry.id != failedRequest.id)
        #expect(retry.input == data.input)
        #expect(state.data.account?.id == "funding-wallet")
        #expect(!state.canRetryFunding)
        #expect(!state.update(data: data, for: failedRequest))

        data.fundingRequirement = fundingRequirement(action: .buyEth)
        #expect(state.update(data: data, for: retry))
        #expect(state.data.fundingRequirement?.action == .buyEth)
        #expect(!state.canReview)
        #expect(!state.canRetryFunding)
        state.request(.buyUsdc)
        #expect(requests.last?.id == retry.id)
        state.request(.buyEth)
        #expect(requests.last?.action == .buyEth)
        #expect(requests.last?.input == data.input)
    }

    @Test func `amount validation errors do not offer funding retry`() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: fixture()) { requests.append($0) }
        state.editAmount(.init(text: "1"))
        let request = try #require(requests.last)
        var failed = state.data
        failed.status = .unavailable("Increase the amount")
        #expect(state.update(data: failed, for: request))
        #expect(!state.canRetryFunding)
    }

    private func fundingRequirement(action: PerpsOrderDisplayData.FundingAction = .buyUsdc) -> PerpsOrderDisplayData.FundingRequirement {
        .init(title: "Not enough funds", message: "Fund this wallet on Arbitrum.", buttonTitle: "Not Enough Funds",
            actionTitle: action == .buyUsdc ? "Buy USDC" : "Buy ETH", action: action)
    }
}
