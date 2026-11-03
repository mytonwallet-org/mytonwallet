import Testing
import UIKit
import UIComponents
import WalletContext
import WalletResources
@testable import UIToken

@MainActor @Suite(.serialized)
struct PerpsOrderUIKitTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test(arguments: [false, true])
    func tokenEquivalentIsReadOnlyAndDoesNotReserveSpaceForAnArrow(_ isEditing: Bool) throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH,
            input: .init(amount: "5", leverage: 2))
        data.conversion = "0.025 ETH"
        if isEditing {
            data.editingPosition = .init(id: "position", currentInput: .init(text: "10"), currentAmount: "$10", change: .reduce)
        }
        var requests: [PerpsOrderRequest] = []
        let content = PerpsOrderView(state: .init(data: data, onRequest: { requests.append($0) }), selectLeverage: {})
        content.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        content.layoutIfNeeded()
        let conversion = try #require(descendants(content).first { $0.accessibilityIdentifier == "perps.order.conversion" } as? TradeConversionControl)
        #expect(!conversion.isUserInteractionEnabled)
        #expect(conversion.accessibilityTraits == .staticText)
        #expect(conversion.accessibilityValue == "0.025 ETH")
        #expect(conversion.content.alpha == 1)
        let images = descendants(conversion).compactMap { $0 as? UIImageView }
        #expect(images.allSatisfy { $0.isHidden })
        conversion.sendActions(for: .touchUpInside)
        #expect(requests.isEmpty)
        #expect(content.amountField.accessibilityLabel?.hasSuffix("USD") == true)

        let selectable = TradeConversionControl(frame: .zero)
        selectable.update(text: "0.025 ETH", isTokenAmount: false, isStale: false, isEnabled: true, animated: false)
        #expect(selectable.isUserInteractionEnabled)
        #expect(selectable.intrinsicContentSize.width == conversion.intrinsicContentSize.width + 16)
    }

    @Test(arguments: [CGFloat(320), 390, 600])
    func quoteUpdatesRetainEditingAndKeepThePaymentRowReachable(_ width: CGFloat) async throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH,
            input: .init(amount: "5", leverage: 2))
        data.canUseFractions = true
        data.leverageOptions = [.init(value: 2)]
        data.status = .ready
        var request: PerpsOrderRequest?
        let state = PerpsOrderState(data: data) { request = $0 }
        let content = PerpsOrderView(state: state, selectLeverage: {})
        let controller = UIViewController()
        controller.view = content
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 480))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { content.endEditing(true); window.isHidden = true }
        window.layoutIfNeeded()
        let field = content.amountField
        field.becomeFirstResponder()
        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        field.insertText("0")
        let edit = try #require(request)
        #expect(edit.input.amount.text == "50")
        var response = state.data
        response.status = .ready
        response.conversion = "0.025 ETH"
        response.paymentAmount = "50.20"
        response.positionSize = "$100"
        #expect(state.update(data: response, for: edit))
        try await Task.sleep(for: .milliseconds(100))
        content.layoutIfNeeded()
        #expect(content.amountField === field)
        #expect(field.isFirstResponder)
        let selection = try #require(field.selectedTextRange)
        #expect(field.offset(from: field.beginningOfDocument, to: selection.start) == 2)
        let scroll = content.scrollView
        let bottom = max(0, scroll.contentSize.height - scroll.bounds.height)
        scroll.contentOffset.y = bottom
        content.setNeedsLayout()
        content.layoutIfNeeded()
        #expect(scroll.contentOffset.y == bottom)
        #expect(content.payment.frame.maxY <= scroll.bounds.maxY)
        #expect(!scroll.delaysContentTouches)
        #expect(!scroll.showsVerticalScrollIndicator)
    }

    @Test func positionEditingUsesTheSharedUIKitControlsWithoutHostingTheForm() throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .short, paymentToken: .ETH, input: .init(amount: "5", leverage: 2))
        data.editingPosition = .init(id: "position", currentInput: .init(text: "10"), currentAmount: "$10", change: .reduce)
        data.status = .ready
        let controller = PerpsOrderVC(data: data, onRequest: { _ in })
        controller.loadViewIfNeeded()
        #expect(controller.children.isEmpty)
        let views = descendants(controller.view)
        let field = try #require(views.compactMap { $0 as? TradeTextField }.first)
        #expect(!field.showsClearButton)
        #expect(views.contains { $0 is NativeTradeInputControls })
        #expect(views.contains { $0 is TradePaymentControl })
        #expect(views.contains { $0 is TradeKeypad })
    }

    @Test func unavailableReasonWrapsOutsideTheDisabledAction() throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(amount: "10"))
        let reason = "You already have a position in this market. Edit that position instead."
        data.status = .unavailable(reason)
        let content = PerpsOrderView(state: .init(data: data, onRequest: { _ in }), selectLeverage: {})
        content.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        content.layoutIfNeeded()
        let notice = try #require(descendants(content).first { $0.accessibilityIdentifier == "perps.order.unavailable" } as? NativeTradeNoticeView)
        notice.superview?.layoutIfNeeded()
        #expect(notice.bounds.height >= notice.sizeThatFits(CGSize(width: notice.bounds.width, height: .greatestFiniteMagnitude)).height)
        #expect(descendants(notice).contains { $0.accessibilityLabel?.contains(reason) == true })
        let button = try #require(descendants(content).first { $0.accessibilityIdentifier == "perps.order.review" } as? WButton)
        #expect(!button.isEnabled)
        #expect(button.accessibilityLabel != reason)
    }

    @Test(arguments: ["funds", "usdc", "eth", "unsupported"])
    func fundingNoticeReplacesMetricsBeforeAnAmountAndOffersTheCorrectBuyAction(_ kind: String) throws {
        let requirement = fundingRequirement(kind)
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH)
        data.fundingRequirement = requirement
        data.leverageOptions = [.init(value: 2)]
        data.positionSize = "$20"
        data.canUseFractions = true
        var requests: [PerpsOrderRequest] = []
        let content = PerpsOrderView(state: .init(data: data, onRequest: { requests.append($0) }), selectLeverage: {})
        content.frame = CGRect(x: 0, y: 0, width: 402, height: 844)
        content.layoutIfNeeded()
        let views = descendants(content)
        let notice = try #require(views.first { $0.accessibilityIdentifier == "perps.order.unavailable" } as? NativeTradeNoticeView)
        let presence = try #require(notice.superview?.superview as? TradePresenceView)
        presence.layoutIfNeeded()
        let card = try #require(presence.superview)
        #expect(presence.frame.minX == 16)
        #expect(card.bounds.width - presence.frame.maxX == 16)
        #expect(card.bounds.height - presence.frame.maxY == 16)
        #expect(notice.bounds.height >= 78)
        #expect(notice.configuration?.title == requirement.title)
        #expect(notice.configuration?.message == requirement.message)
        for id in ["perps.order.leverage", "perps.order.liquidationPrice", "perps.order.positionSize"] {
            let metric = try #require(views.first { $0.accessibilityIdentifier == id })
            #expect(metric.isHidden)
        }
        let review = try #require(views.first { $0.accessibilityIdentifier == "perps.order.review" } as? WButton)
        #expect(!review.isEnabled)
        #expect(review.accessibilityLabel == requirement.buttonTitle)
        let action = try #require(descendants(notice).first { $0.accessibilityLabel == requirement.actionTitle } as? UIButton)
        action.sendActions(for: .touchUpInside)
        #expect(requests.last?.action == (kind == "eth" ? .buyEth : .buyUsdc))
        #expect(requests.last?.input.amount.text == "")
    }

    @Test(arguments: [CGFloat(320), 402])
    func fundingUpdatesRetainTheAmountEditorAndReflowTheFooter(_ width: CGFloat) async throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(amount: "15"))
        data.fundingRequirement = fundingRequirement("funds")
        data.leverageOptions = [.init(value: 2)]
        let state = PerpsOrderState(data: data, onRequest: { _ in })
        let content = PerpsOrderView(state: state, selectLeverage: {})
        let controller = UIViewController()
        controller.view = content
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 600))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { content.endEditing(true); window.isHidden = true }
        window.layoutIfNeeded()
        let field = content.amountField
        field.becomeFirstResponder()
        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        let notice = try #require(descendants(content).first { $0.accessibilityIdentifier == "perps.order.unavailable" } as? NativeTradeNoticeView)

        data.fundingRequirement = fundingRequirement("eth")
        #expect(state.update(data: data))
        try await Task.sleep(for: .milliseconds(100))
        content.layoutIfNeeded()
        #expect(notice.configuration?.title == data.fundingRequirement?.title)
        #expect(notice.bounds.height >= notice.sizeThatFits(CGSize(width: notice.bounds.width, height: .greatestFiniteMagnitude)).height)
        #expect(content.amountField === field)
        #expect(field.isFirstResponder)

        data.fundingRequirement = nil
        data.status = .ready
        data.positionSize = "$30"
        #expect(state.update(data: data))
        try await Task.sleep(for: .milliseconds(100))
        content.layoutIfNeeded()
        #expect(field.isFirstResponder)
        #expect(state.data.input.amount.text == "15")
        let selection = try #require(field.selectedTextRange)
        #expect(field.offset(from: field.beginningOfDocument, to: selection.start) == 2)
        let leverage = try #require(descendants(content).first { $0.accessibilityIdentifier == "perps.order.leverage" })
        #expect(!leverage.isHidden)
        let review = try #require(descendants(content).first { $0.accessibilityIdentifier == "perps.order.review" } as? WButton)
        #expect(review.isEnabled)
    }

    @Test func returningToTheOrderRefreshesFundingWithTheUnchangedDraft() throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(amount: "15"))
        data.fundingRequirement = fundingRequirement("usdc")
        var requests: [PerpsOrderRequest] = []
        let controller = PerpsOrderVC(data: data, onRequest: { requests.append($0) })
        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        let initial = try #require(requests.last)
        #expect(initial.action == .refreshFunding)
        controller.viewDidAppear(false)
        #expect(requests.count == 1)
        controller.refreshFunding()
        let returning = try #require(requests.last)
        #expect(returning.action == .refreshFunding)
        #expect(returning.input.amount.text == "15")
        #expect(!controller.update(data: data, for: initial))
        data.fundingRequirement = nil
        #expect(controller.update(data: data, for: returning))
    }

    @Test(arguments: ["", "15"])
    func failedFundingRefreshOffersRetryWithoutChangingTheDraft(_ amount: String) async throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH,
            input: .init(amount: amount, leverage: 5))
        var requests: [PerpsOrderRequest] = []
        let controller = PerpsOrderVC(data: data, onRequest: { requests.append($0) })
        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        let initial = try #require(requests.last)
        data.status = .unavailable("Unable to refresh balances")
        #expect(controller.update(data: data, for: initial))
        try await Task.sleep(for: .milliseconds(100))
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        let notice = try #require(descendants(controller.view).first {
            $0.accessibilityIdentifier == "perps.order.unavailable"
        } as? NativeTradeNoticeView)
        #expect(notice.configuration?.actionTitle == lang("Retry"))
        let retry = try #require(descendants(notice).first {
            $0.accessibilityLabel == lang("Retry")
        } as? UIButton)
        retry.sendActions(for: .touchUpInside)
        let request = try #require(requests.last)
        #expect(request.id != initial.id)
        #expect(request.action == .refreshFunding)
        #expect(request.input == data.input)
        retry.sendActions(for: .touchUpInside)
        #expect(requests.count == 2)
        #expect(!controller.update(data: data, for: initial))
    }

    @Test(arguments: [false, true])
    func balanceUpdatesDoNotSupersedeFundedEditingOrReview(_ isReview: Bool) throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH,
            input: .init(amount: "15", leverage: 5))
        data.status = .ready
        data.leverageOptions = [.init(value: 5)]
        var requests: [PerpsOrderRequest] = []
        let controller = PerpsOrderVC(data: data, onRequest: { requests.append($0) })
        controller.loadViewIfNeeded()
        controller.refreshBlockedFunding()
        #expect(requests.isEmpty)
        let views = descendants(controller.view)
        if isReview {
            let review = try #require(views.first { $0.accessibilityIdentifier == "perps.order.review" } as? WButton)
            review.sendActions(for: .touchUpInside)
        } else {
            let field = try #require(views.compactMap { $0 as? TradeTextField }.first)
            field.onChange?(.init(text: "20"))
        }
        let request = try #require(requests.last)
        #expect(request.action == (isReview ? .review : .amountChanged))
        controller.refreshBlockedFunding()
        #expect(requests.count == 1)
        data.input = request.input
        #expect(controller.update(data: data, for: request))
    }

    @Test(arguments: ["50", "150"])
    func balanceUpdatesRefreshTheMaximumOfFundedEmptyOpeningForms(_ availableCollateral: String) throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH)
        data.availableCollateral = .init(text: "100")
        data.canUseFractions = true
        var requests: [PerpsOrderRequest] = []
        let controller = PerpsOrderVC(data: data, onRequest: { requests.append($0) })
        controller.loadViewIfNeeded()

        controller.refreshBlockedFunding()
        let refresh = try #require(requests.last)
        #expect(refresh.action == .refreshFunding)
        #expect(refresh.input == data.input)
        controller.refreshBlockedFunding()
        #expect(requests.count == 1)

        data.availableCollateral = .init(text: availableCollateral)
        #expect(controller.update(data: data, for: refresh))
        let maximum = try #require(descendants(controller.view).first {
            $0.accessibilityIdentifier == "perps.order.fraction.100"
        } as? UIControl)
        maximum.sendActions(for: .touchUpInside)
        #expect(requests.last?.action == .amountChanged)
        #expect(requests.last?.input.amount.text == availableCollateral + ".00")
        controller.refreshBlockedFunding()
        #expect(requests.count == 2)
    }

    @Test(arguments: [false, true])
    func balanceUpdatesRecheckBlockedFundingWithTheSameDraft(_ hasRefreshError: Bool) throws {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .short, paymentToken: .ETH,
            input: .init(amount: "15", leverage: 5))
        data.fundingRequirement = fundingRequirement("eth")
        var requests: [PerpsOrderRequest] = []
        let controller = PerpsOrderVC(data: data, onRequest: { requests.append($0) })
        controller.refreshFunding()
        let initial = try #require(requests.last)
        if hasRefreshError {
            data.fundingRequirement = nil
            data.status = .unavailable("Unable to refresh balances")
        }
        #expect(controller.update(data: data, for: initial))
        controller.refreshBlockedFunding()
        let refresh = try #require(requests.last)
        #expect(requests.count == 2)
        #expect(refresh.id != initial.id)
        #expect(refresh.action == .refreshFunding)
        #expect(refresh.input == data.input)
        #expect(!controller.update(data: data, for: initial))
    }

    private func fundingRequirement(_ kind: String) -> PerpsOrderDisplayData.FundingRequirement {
        let title: String
        let message: String
        let button: String
        switch kind {
        case "eth":
            title = "Not enough ETH for the fee"
            message = "Fees on Arbitrum are paid in ETH. Buy 0.0001 ETH."
            button = "Not Enough ETH"
        case "usdc":
            title = "Not enough USDC"
            message = "You need at least 10.2 USDC on Arbitrum to open a position."
            button = "Not Enough USDC"
        case "unsupported":
            title = "Pay with USDC on Arbitrum"
            message = "Other tokens aren't supported yet. Buy USDC to continue."
            button = "Unsupported Token"
        default:
            title = "No USDC or ETH on Arbitrum"
            message = "Buy at least 10.2 USDC and 0.0001 ETH for fees."
            button = "Not Enough Funds"
        }
        return .init(title: title, message: message, buttonTitle: button,
            actionTitle: kind == "eth" ? "Buy ETH" : "Buy USDC", action: kind == "eth" ? .buyEth : .buyUsdc)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
