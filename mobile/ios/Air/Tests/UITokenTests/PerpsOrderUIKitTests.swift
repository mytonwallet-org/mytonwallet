import Testing
import UIKit
import WalletCore
import UIComponents
import WalletContext
import WalletResources
@testable import UIToken

@MainActor @Suite(.serialized)
struct PerpsOrderUIKitTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test(arguments: [false, true])
    func tokenEquivalentIsReadOnlyAndDoesNotReserveSpaceForAnArrow(_ isEditing: Bool) throws {
        var data = order(amount: "5")
        data.conversion = "0.025 ETH"
        if isEditing {
            data.editingPosition = .init(id: "position", currentInput: .init(text: "10"), currentCollateral: "10", currentAmount: "$10",
                currentLeverage: 5, change: .reduce)
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
        var data = order(amount: "5")
        data.availableCollateral = .init(text: "100")
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
        #expect(content.method.frame.maxY <= scroll.bounds.maxY)
        #expect(!scroll.delaysContentTouches)
        #expect(!scroll.showsVerticalScrollIndicator)
    }

    @Test(arguments: [-25, -5, 5, 25, 0])
    func animateAmountLayoutWhenCurrentAmountAppearsAndDisappears(_ percentage: Int) async throws {
        var data = order(amount: "100")
        data.editingPosition = .init(id: "position", currentInput: .init(text: "100"), currentCollateral: "100",
            currentAmount: "$100", currentLeverage: 5, liquidationPrice: "$1 500")
        data.positionSize = "$500"
        let state = PerpsOrderState(data: data, onRequest: { _ in })
        let content = PerpsOrderView(state: state, selectLeverage: {})
        let controller = UIViewController()
        controller.view = content
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 740))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { content.endEditing(true); window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        try #require(TradeMotion.enabled)
        let amount = content.amountField
        let initialAmountPosition = amount.layer.position
        let initialConversionPosition = content.conversion.layer.position
        let current = try #require(descendants(content).first { $0.accessibilityIdentifier == "perps.order.current" } as? UIControl)
        if percentage == 0 {
            amount.selectedTextRange = amount.textRange(from: amount.endOfDocument, to: amount.endOfDocument)
            amount.insertText("0")
        } else {
            let fraction = try #require(descendants(content).first {
                $0.accessibilityIdentifier == "perps.order.fraction.\(percentage)"
            } as? UIControl)
            fraction.sendActions(for: .touchUpInside)
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(state.hasPositionChanges)
        #expect(amount.layer.position.y < initialAmountPosition.y)
        #expect(content.conversion.layer.position.y < initialConversionPosition.y)
        #expect(amount.layer.animation(forKey: "position") != nil)
        #expect(content.conversion.layer.animation(forKey: "position") != nil)
        try await Task.sleep(for: .milliseconds(400))
        current.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!state.hasPositionChanges)
        #expect(amount.layer.position == initialAmountPosition)
        #expect(content.conversion.layer.position == initialConversionPosition)
        #expect(amount.layer.animation(forKey: "position") != nil)
        #expect(content.conversion.layer.animation(forKey: "position") != nil)
    }

    @Test(arguments: [false, true], ["funds", "unavailable"])
    func animateWarningsAlongsideAmountChanges(_ isDelayed: Bool, _ kind: String) async throws {
        var data = order(amount: "100")
        data.editingPosition = .init(id: "position", currentInput: .init(text: "100"), currentCollateral: "100",
            currentAmount: "$100", currentLeverage: 5, liquidationPrice: "$1 500")
        data.positionSize = "$500"
        var request: PerpsOrderRequest?
        let state = PerpsOrderState(data: data, onRequest: { request = $0 })
        let content = PerpsOrderView(state: state, selectLeverage: {})
        let controller = UIViewController()
        controller.view = content
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 640))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { content.endEditing(true); window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        try #require(TradeMotion.enabled)
        let initialCardHeight = content.amountCard.bounds.height
        let initialPaymentPosition = content.method.layer.position
        let views = descendants(content)
        let current = try #require(views.first { $0.accessibilityIdentifier == "perps.order.current" } as? UIControl)
        let notice = try #require(views.first { $0.accessibilityIdentifier == "perps.order.unavailable" } as? NativeTradeNoticeView)
        let presence = try #require(notice.superview?.superview as? TradePresenceView)
        state.editAmount(.init(text: "125"))
        if isDelayed { try await Task.sleep(for: .milliseconds(100)) }
        var response = state.data
        response.status = .unavailable("The minimum position amount is $150.")
        if kind == "funds" { response.fundingRequirement = fundingRequirement(kind) }
        #expect(state.update(data: response, for: try #require(request)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(state.hasPositionChanges)
        #expect(presence.showsContent)
        #expect(presence.content.layer.animation(forKey: "opacity") != nil)
        #expect(content.amountField.layer.animation(forKey: "position") != nil)
        #expect(content.conversion.layer.animation(forKey: "position") != nil)
        #expect(content.amountCard.bounds.height > initialCardHeight)
        #expect(content.amountCard.layer.animation(forKey: "bounds.size") != nil,
                "Card animations: \(content.amountCard.layer.animationKeys() ?? [])")
        #expect(content.method.layer.position.y > initialPaymentPosition.y)
        #expect(content.method.layer.animation(forKey: "position") != nil)
        let currentFrame = current.convert(current.bounds, to: content.amountCard)
        #expect(currentFrame.maxY <= presence.frame.minY)
        #expect(presence.frame.maxY <= content.amountCard.bounds.height)
        try await Task.sleep(for: .milliseconds(400))
        current.sendActions(for: .touchUpInside)
        #expect(state.update(data: data, for: try #require(request)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(!state.hasPositionChanges)
        #expect(!presence.showsContent)
        #expect(presence.content.layer.animation(forKey: "opacity") != nil)
        #expect(content.amountCard.bounds.height == initialCardHeight)
        #expect(content.amountCard.layer.animation(forKey: "bounds.size") != nil,
                "Card animations: \(content.amountCard.layer.animationKeys() ?? [])")
        #expect(content.method.layer.position == initialPaymentPosition)
        #expect(content.method.layer.animation(forKey: "position") != nil)
    }

    @Test func positionEditingUsesTheSharedUIKitControlsWithoutHostingTheForm() throws {
        var data = order(amount: "5")
        data.direction = .short
        data.editingPosition = .init(id: "position", currentInput: .init(text: "10"), currentCollateral: "10", currentAmount: "$10",
            currentLeverage: 5, change: .reduce)
        data.status = .ready
        let controller = PerpsOrderVC(data: data, onRequest: { _ in })
        controller.loadViewIfNeeded()
        #expect(controller.children.isEmpty)
        let views = descendants(controller.view)
        #expect(views.contains { $0 is NativeTradeEntryView })
        let field = try #require(views.compactMap { $0 as? TradeTextField }.first)
        #expect(!field.showsClearButton)
        #expect(views.contains { $0 is NativeTradeInputControls })
        #expect(views.contains { $0 is TradePaymentControl })
        #expect(views.contains { $0 is TradeKeypad })
    }

    @Test func unavailableReasonWrapsOutsideTheDisabledAction() throws {
        var data = order(amount: "10")
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

    @Test(arguments: [CGSize(width: 402, height: 844), CGSize(width: 375, height: 667)], [
        "Required: 3.01 USDC including fees. Available on Hyperliquid: 0.5 USDC.",
        "Нужно: 3,01 USDC с учётом комиссий. Доступно на Hyperliquid: 0,5 USDC.",
    ])
    func keepPaymentAccessibleWhenAnEditWarningAppears(size: CGSize, reason: String) throws {
        var data = order(amount: "14.95")
        data.editingPosition = .init(id: "position", currentInput: .init(text: "11.96"), currentCollateral: "11.96",
            currentAmount: "$11.96", currentLeverage: 5, change: .increase, liquidationPrice: "$335.00")
        data.positionSize = "$74.75"
        data.paymentAmount = "3.01"
        data.status = .unavailable(reason)
        let content = PerpsOrderView(state: .init(data: data, onRequest: { _ in }), selectLeverage: {})
        content.frame = CGRect(origin: .zero, size: size)
        content.layoutIfNeeded()
        if size.height < 800 {
            content.scrollView.contentOffset.y = max(0, content.scrollView.contentSize.height - content.scrollView.bounds.height)
            content.setNeedsLayout()
            content.layoutIfNeeded()
        }
        let payment = content.method.convert(content.method.bounds, to: content)
        let keypad = content.keypad.convert(content.keypad.bounds, to: content)
        #expect(payment.maxY <= keypad.minY - 88)
        #expect(payment.minY >= 0)
        let leverage = try #require(descendants(content).first { $0.accessibilityIdentifier == "perps.order.leverage" })
        #expect(leverage.isHidden)
    }

    @Test(arguments: [CGFloat(320), 402])
    func fundingUpdatesRetainTheAmountEditorAndReflowTheFooter(_ width: CGFloat) async throws {
        var data = order(amount: "15")
        data.fundingRequirement = fundingRequirement("funds")
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
        #expect(try #require(leverage.superview?.superview as? TradePresenceView).showsContent)
        let review = try #require(descendants(content).first { $0.accessibilityIdentifier == "perps.order.review" } as? WButton)
        #expect(review.isEnabled)
    }

    @Test(arguments: ["funds", "usdc", "eth"])
    func fundingNoticeReplacesMetricsAndOffersTheMissingAsset(_ kind: String) throws {
        let requirement = fundingRequirement(kind)
        var data = order()
        data.fundingRequirement = requirement
        data.positionSize = "$20"
        data.availableCollateral = .init(text: "100")
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
            #expect(try #require(metric.superview?.superview as? TradePresenceView).showsContent == false)
        }
        let review = try #require(views.first { $0.accessibilityIdentifier == "perps.order.review" } as? WButton)
        #expect(!review.isEnabled)
        #expect(review.accessibilityLabel == requirement.buttonTitle)
        let action = try #require(descendants(notice).first { $0.accessibilityLabel == requirement.actionTitle } as? UIButton)
        action.sendActions(for: .touchUpInside)
        #expect(requests.last?.action == (kind == "eth" ? .buyEth : .buyUsdc))
        #expect(requests.last?.input.amount.text == "")
    }

    @Test func returningToTheOrderRefreshesFundingWithTheUnchangedDraft() throws {
        var data = order(amount: "15")
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
        var data = order(amount: amount)
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
        var data = order(amount: "15")
        data.status = .ready
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

    @Test func balanceUpdatesRefreshAFundedEmptyOpeningForm() throws {
        var data = order()
        data.availableCollateral = .init(text: "100")
        var requests: [PerpsOrderRequest] = []
        let controller = PerpsOrderVC(data: data, onRequest: { requests.append($0) })
        controller.loadViewIfNeeded()

        controller.refreshBlockedFunding()
        let refresh = try #require(requests.last)
        #expect(refresh.action == .refreshFunding)
        #expect(refresh.input == data.input)
        controller.refreshBlockedFunding()
        #expect(requests.count == 1)

        #expect(controller.update(data: data, for: refresh))
        let maximum = try #require(descendants(controller.view).first {
            $0.accessibilityIdentifier == "perps.order.fraction.100"
        } as? UIControl)
        maximum.sendActions(for: .touchUpInside)
        #expect(requests.last?.input.fraction == 100)
        #expect(requests.last?.input.amount.text == "100")
        controller.refreshBlockedFunding()
        #expect(requests.count == 2)
    }

    @Test(arguments: [false, true])
    func balanceUpdatesRecheckBlockedFundingWithTheSameDraft(_ hasRefreshError: Bool) throws {
        var data = order(amount: "15")
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

    @Test func editingAPositionHasNoAccountSwitcherAndCannotSelectAnotherAccount() async {
        var data = order(amount: "100")
        data.account = MAccount(id: "1-mainnet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: .init(address: "0x1234")])
        data.editingPosition = .init(id: "position", currentInput: .init(text: "100"), currentCollateral: "100",
                                    currentAmount: "$100", currentLeverage: 5)
        var selectedAccounts: [String] = []
        let controller = PerpsOrderVC(data: data, onSelectAccount: { selectedAccounts.append($0) }, onRequest: { _ in })
        controller.loadViewIfNeeded()
        await controller.selectAccount("2-mainnet")
        #expect(controller.navigationItem.leftBarButtonItem == nil)
        #expect(selectedAccounts.isEmpty)
    }

    private func order(amount: String = "") -> PerpsOrderDisplayData {
        PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(amount: amount, leverage: 5), maxLeverage: 40)
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
