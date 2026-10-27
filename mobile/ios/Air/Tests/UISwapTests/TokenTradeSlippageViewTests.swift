import Testing
import UIKit
import UIComponents
import WalletContext
@testable import UISwap

@Suite("Token trade slippage sheet") @MainActor
struct TokenTradeSlippageViewTests {
    @Test func `manual decimals remain draft until Done`() throws {
        var committed: [BigInt] = []
        let vc = TokenTradeSlippageVC(slippage: 50) { committed.append($0) }
        vc.loadViewIfNeeded()
        let input = try #require(find(WAmountInput.self, in: vc.view))
        let done = try #require(find(WButton.self, in: vc.view))
        input.text = "12.7"
        dispatch(.editingChanged, from: input)
        #expect(committed.isEmpty)
        #expect(done.isEnabled)
        dispatch(.touchUpInside, from: done)
        #expect(committed == [127])
    }

    @Test(arguments: ["", "0", "50.1", "99999999999999999999999999999999999999999999999999"])
    func `invalid input cannot be committed`(text: String) throws {
        var committed = false
        let vc = TokenTradeSlippageVC(slippage: 50) { _ in committed = true }
        vc.loadViewIfNeeded()
        let input = try #require(find(WAmountInput.self, in: vc.view))
        let done = try #require(find(WButton.self, in: vc.view))
        input.text = text
        dispatch(.editingChanged, from: input)
        #expect(!done.isEnabled)
        dispatch(.touchUpInside, from: done)
        #expect(!committed)
    }

    @Test func `changing the slider keeps the amount baseline and height fixed`() throws {
        let vc = TokenTradeSlippageVC(slippage: 50) { _ in }
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 400)
        vc.view.layoutIfNeeded()
        let input = try #require(find(WAmountInput.self, in: vc.view))
        let slider = try #require(find(TokenTradeSlippageSlider.self, in: vc.view))
        let initial = input.convert(input.bounds, to: vc.view)
        for value in [0.1, 0.2, 0.5, 1, 2, 5, 10, 49, 50] {
            slider.setValue(value, animated: false)
            dispatch(.valueChanged, from: slider)
            vc.view.layoutIfNeeded()
            #expect(input.amountValueOrNil == BigInt(Int((value * 10).rounded())))
            let frame = input.convert(input.bounds, to: vc.view)
            #expect(frame.minY == initial.minY)
            #expect(frame.height == initial.height)
        }
    }

    @Test(arguments: ["", "0", "50.1"])
    func `starting the slider restores invalid input without changing its value`(text: String) throws {
        var committed: [BigInt] = []
        let vc = TokenTradeSlippageVC(slippage: 50) { committed.append($0) }
        vc.loadViewIfNeeded()
        let input = try #require(find(WAmountInput.self, in: vc.view))
        let slider = try #require(find(TokenTradeSlippageSlider.self, in: vc.view))
        let done = try #require(find(WButton.self, in: vc.view))
        input.text = text
        dispatch(.editingChanged, from: input)
        #expect(!done.isEnabled)

        dispatch(.editingDidBegin, from: slider)

        #expect(input.amountValueOrNil == 50)
        #expect(slider.selectedValue == 5)
        #expect(done.isEnabled)
        #expect(committed.isEmpty)
        dispatch(.touchUpInside, from: done)
        #expect(committed == [50])
    }

    @Test(arguments: [320.0, 390.0, 420.0, 600.0])
    func `fitted presentation keeps the design spacing below Done after moving and resizing`(width: Double) throws {
        let vc = TokenTradeSlippageVC(slippage: 50) { _ in }
        let navigation = WNavigationController(rootViewController: vc)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
        let root = UIViewController()
        window.rootViewController = root
        root.addChild(navigation)
        root.view.addSubview(navigation.view)
        navigation.didMove(toParent: root)
        window.isHidden = false
        defer { window.isHidden = true }
        navigation.view.frame = CGRect(x: 0, y: 200, width: width, height: 500)
        window.layoutIfNeeded()
        navigation.view.layoutIfNeeded()
        vc.view.layoutIfNeeded()
        // Fit again after the first pass establishes the scroll content's width.
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let scroll = try #require(find(UIScrollView.self, in: vc.view))
        let done = try #require(find(WButton.self, in: vc.view))

        for y in [200.0, 260.0, 220.0, 200.0] {
            navigation.view.frame = CGRect(x: 0, y: y, width: width,
                                           height: vc.preferredContentSize.height + navigation.navigationBar.frame.maxY)
            navigation.view.layoutIfNeeded()
            vc.view.layoutIfNeeded()
            let frame = done.convert(done.bounds, to: scroll)
            #expect(frame.minY >= scroll.bounds.minY)
            #expect(frame.maxY <= scroll.bounds.maxY + 1)
            #expect(abs(scroll.frame.maxY - vc.view.bounds.maxY) < 1)
            #expect(abs(scroll.bounds.maxY - frame.maxY - 28) < 1)
        }
    }

    // AirTests is hostless, so UIApplication cannot dispatch UIControl target actions.
    private func dispatch(_ event: UIControl.Event, from control: UIControl) {
        for target in control.allTargets {
            for action in control.actions(forTarget: target, forControlEvent: event) ?? [] {
                (target as? NSObject)?.perform(NSSelectorFromString(action), with: control)
            }
        }
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
}
