import Testing
import UIKit
import UIComponents
import WalletContext
import WalletResources
@testable import UIToken

@Suite(.serialized) @MainActor
struct PerpsLeverageSheetTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func closePushedReviewDismissesTheEntireFlow() {
        let root = UIViewController()
        let review = PerpsOrderReviewVC(data: .init(token: .ETH, direction: .long, leverage: 5,
            margin: .fromDouble(100, .USD), positionSize: "$500", price: "$2 000",
            liquidationPrice: "$1 600", paymentAmount: "100 USDC", fee: "$0.05", paymentToken: .ETH), onConfirm: { _ in })
        let navigation = ReviewNavigationController(rootViewController: root)
        navigation.pushViewController(review, animated: false)
        review.closeReview()
        #expect(navigation.didDismiss)
        #expect(navigation.viewControllers.count == 2)
        #expect(navigation.topViewController === review)
    }

    @Test func maximumLeverageCommitsFromTheSlider() throws {
        var committed: Int?
        let controller = PerpsLeverageVC(data: order(leverage: 1, maxLeverage: 40)) { committed = $0 }
        controller.loadViewIfNeeded()
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        slider.setValue(40, animated: false)
        dispatch(.valueChanged, from: slider)
        #expect(slider.accessibilityValue == "40x")
        dispatch(.touchUpInside, from: try done(in: controller))
        #expect(committed == 40)
    }

    @Test func preparedEstimateIsShownAndOnlyChangedLeverageIsFetched() async throws {
        var data = order(leverage: 2, maxLeverage: 5)
        data.leverageEstimate = .init(leverage: 2, liquidationPrice: "$1 000")
        let controller = PerpsLeverageVC(data: data) { _ in }
        var requested: [Int] = []
        controller.loadEstimate = { leverage in
            requested.append(leverage)
            return .init(leverage: leverage, liquidationPrice: "$1 600")
        }
        controller.loadViewIfNeeded()
        #expect(controller.metrics.liquidationPrice == "$1 000")
        #expect(!controller.metrics.isLoading)
        #expect(controller.estimateTask == nil)
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        #expect(controller.metrics.liquidationPrice == "$1 000")
        #expect(controller.metrics.isLoading)
        await controller.estimateTask?.value
        #expect(requested == [5])
        #expect(controller.metrics.liquidationPrice == "$1 600")
        #expect(!controller.metrics.isLoading)
        slider.setValue(2, animated: false)
        dispatch(.valueChanged, from: slider)
        #expect(controller.metrics.liquidationPrice == "$1 000")
        #expect(!controller.metrics.isLoading)
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        await controller.estimateTask?.value
        #expect(requested == [5])
    }

    @Test func finishLoadingWhenTheFirstEstimateIsUnavailable() async {
        let controller = PerpsLeverageVC(data: order(leverage: 1, maxLeverage: 5)) { _ in }
        var requestCount = 0
        controller.loadEstimate = { leverage in
            requestCount += 1
            return .init(leverage: leverage, liquidationPrice: nil)
        }
        controller.loadViewIfNeeded()
        #expect(controller.metrics.isLoading)
        #expect(controller.metrics.liquidationPrice == nil)
        await controller.estimateTask?.value
        #expect(!controller.metrics.isLoading)
        #expect(controller.metrics.liquidationPrice == nil)
        controller.draftDidChange()
        await controller.estimateTask?.value
        #expect(!controller.metrics.isLoading)
        #expect(requestCount == 1)
    }

    @Test func clearPreviousValueAndAllowRetryAfterFailure() async throws {
        var data = order(leverage: 2, maxLeverage: 5)
        data.leverageEstimate = .init(leverage: 2, liquidationPrice: "$1 000")
        let controller = PerpsLeverageVC(data: data) { _ in }
        var requestCount = 0
        controller.loadEstimate = { leverage in
            requestCount += 1
            if requestCount == 1 { throw URLError(.notConnectedToInternet) }
            return .init(leverage: leverage, liquidationPrice: "$1 600")
        }
        controller.loadViewIfNeeded()
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        await controller.estimateTask?.value
        #expect(!controller.metrics.isLoading)
        #expect(controller.metrics.liquidationPrice == nil)
        controller.draftDidChange()
        #expect(controller.metrics.isLoading)
        await controller.estimateTask?.value
        #expect(requestCount == 2)
        #expect(!controller.metrics.isLoading)
        #expect(controller.metrics.liquidationPrice == "$1 600")
    }

    @Test(arguments: [false, true])
    func ignoreLateResponsesWhileLoadingANewerEstimate(shouldFail: Bool) async throws {
        var data = order(leverage: 2, maxLeverage: 5)
        data.leverageEstimate = .init(leverage: 2, liquidationPrice: "$1 000")
        let controller = PerpsLeverageVC(data: data) { _ in }
        let (requests, started) = AsyncStream<Int>.makeStream()
        var responses: [Int: CheckedContinuation<PerpsOrderDisplayData.LeverageEstimate, Error>] = [:]
        defer {
            for response in responses.values { response.resume(throwing: CancellationError()) }
            started.finish()
        }
        controller.loadEstimate = { leverage in
            try await withCheckedThrowingContinuation { response in
                responses[leverage] = response
                started.yield(leverage)
            }
        }
        controller.loadViewIfNeeded()
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        var events = requests.makeAsyncIterator()
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        let cancelled = try #require(controller.estimateTask)
        #expect(await events.next() == 5)
        slider.setValue(3, animated: false)
        dispatch(.valueChanged, from: slider)
        let latest = try #require(controller.estimateTask)
        #expect(await events.next() == 3)
        let oldResponse = responses.removeValue(forKey: 5)
        let old = try #require(oldResponse)
        if shouldFail { old.resume(throwing: URLError(.notConnectedToInternet)) }
        else { old.resume(returning: .init(leverage: 5, liquidationPrice: "$1 600")) }
        await cancelled.value
        #expect(controller.metrics.isLoading)
        #expect(controller.metrics.liquidationPrice == "$1 000")
        let latestResponse = responses.removeValue(forKey: 3)
        try #require(latestResponse).resume(returning: .init(leverage: 3, liquidationPrice: "$1 200"))
        await latest.value
        #expect(!controller.metrics.isLoading)
        #expect(controller.metrics.liquidationPrice == "$1 200")
    }

    @Test(arguments: [false, true])
    func cancelLoadingOnInvalidInputOrDisappearance(shouldDismiss: Bool) async throws {
        var data = order(leverage: 2, maxLeverage: 5)
        data.leverageEstimate = .init(leverage: 2, liquidationPrice: "$1 000")
        let controller = PerpsLeverageVC(data: data) { _ in }
        var requested: [Int] = []
        controller.loadEstimate = { leverage in
            requested.append(leverage)
            return .init(leverage: leverage, liquidationPrice: "$1 600")
        }
        controller.loadViewIfNeeded()
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        let cancelled = try #require(controller.estimateTask)
        if shouldDismiss {
            controller.viewDidDisappear(false)
        } else {
            let field = try #require(descendants(controller.view).compactMap { $0 as? WAmountInput }.first)
            field.text = "0"
            dispatch(.editingChanged, from: field)
        }
        await cancelled.value
        #expect(requested.isEmpty)
        #expect(!controller.metrics.isLoading)
        if shouldDismiss {
            controller.viewWillAppear(false)
            #expect(controller.metrics.isLoading)
            await controller.estimateTask?.value
            #expect(requested == [5])
            #expect(!controller.metrics.isLoading)
        } else {
            #expect(controller.metrics.liquidationPrice == nil)
        }
    }

    @Test func returningToACancelledPreviewStartsANewRequest() async throws {
        var data = order(leverage: 2, maxLeverage: 5)
        data.leverageEstimate = .init(leverage: 2, liquidationPrice: "$1 000")
        let controller = PerpsLeverageVC(data: data) { _ in }
        var requested: [Int] = []
        controller.loadEstimate = { leverage in
            requested.append(leverage)
            return .init(leverage: leverage, liquidationPrice: "$1 600")
        }
        controller.loadViewIfNeeded()
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        let cancelled = try #require(controller.estimateTask)
        slider.setValue(2, animated: false)
        dispatch(.valueChanged, from: slider)
        slider.setValue(5, animated: false)
        dispatch(.valueChanged, from: slider)
        await cancelled.value
        await controller.estimateTask?.value
        #expect(requested == [5])
        #expect(controller.metrics.liquidationPrice == "$1 600")
    }

    @Test(arguments: ["", "0", "41", "99999999999999999999999999999999999999999999999999"])
    func unsupportedManualLeverageCannotCommit(_ text: String) throws {
        let controller = PerpsLeverageVC(data: order(leverage: 2, maxLeverage: 40)) { _ in Issue.record("Invalid leverage committed") }
        controller.loadViewIfNeeded()
        let field = try #require(descendants(controller.view).compactMap { $0 as? WAmountInput }.first)
        let done = try done(in: controller)
        field.text = text
        dispatch(.editingChanged, from: field)
        #expect(!done.isEnabled)
        dispatch(.touchUpInside, from: done)
    }

    @Test func manualLeverageRemainsDraftAndSliderRestoresInvalidInput() throws {
        var committed: [Int] = []
        let controller = PerpsLeverageVC(data: order(leverage: 2, maxLeverage: 10)) { committed.append($0) }
        controller.loadViewIfNeeded()
        let field = try #require(descendants(controller.view).compactMap { $0 as? WAmountInput }.first)
        let slider = try #require(descendants(controller.view).compactMap { $0 as? TradePresetSlider }.first)
        let done = try done(in: controller)
        field.text = "5"
        dispatch(.editingChanged, from: field)
        #expect(committed.isEmpty)
        #expect(slider.selectedValue == 5)
        field.text = "0"
        dispatch(.editingChanged, from: field)
        #expect(!done.isEnabled)
        dispatch(.editingDidBegin, from: slider)
        #expect(field.amountValueOrNil == 5)
        #expect(done.isEnabled)
        dispatch(.touchUpInside, from: done)
        #expect(committed == [5])
    }

    private func order(leverage: Int, maxLeverage: Int) -> PerpsOrderDisplayData {
        PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH, input: .init(leverage: leverage), maxLeverage: maxLeverage)
    }

    private func done(in controller: UIViewController) throws -> WButton {
        try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.done" } as? WButton)
    }

    // AirTests is hostless, so UIApplication cannot dispatch UIControl target actions.
    private func dispatch(_ event: UIControl.Event, from control: UIControl) {
        for target in control.allTargets {
            for action in control.actions(forTarget: target, forControlEvent: event) ?? [] {
                (target as? NSObject)?.perform(NSSelectorFromString(action), with: control)
            }
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private final class ReviewNavigationController: UINavigationController {
        private(set) var didDismiss = false

        override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
            didDismiss = true
            completion?()
        }
    }
}
