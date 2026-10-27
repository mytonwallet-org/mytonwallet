import Testing
import UIKit
import WalletResources
@testable import UISwap

@Suite(.serialized) @MainActor
struct TokenTradeKeypadTests {
    @MainActor private struct Fixture {
        let editor: TokenTradeEditor
        let field: TokenTradeTextField
        let keypad: TokenTradeKeypad

        func button(_ identifier: String) throws -> UIButton {
            try #require(descendants(keypad).first { $0.accessibilityIdentifier == identifier } as? UIButton)
        }
    }

    private func fixture(_ amount: String = "123456789012") -> Fixture {
        _ = WalletResourcesBundle.bundle.load()
        let field = TokenTradeTextField()
        field.configure(input: TokenTradeAmountInput(text: amount), decimals: 9, prefix: "", suffix: "TON", hasAmount: true)
        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        let editor = TokenTradeEditor()
        editor.field = field
        let keypad = TokenTradeKeypad(editor: editor)
        keypad.frame = CGRect(x: 0, y: 0, width: 390, height: 256)
        keypad.updateDelete(isEnabled: !amount.isEmpty)
        field.onChange = { [weak keypad] input in keypad?.updateDelete(isEnabled: !input.text.isEmpty) }
        keypad.layoutIfNeeded()
        return Fixture(editor: editor, field: field, keypad: keypad)
    }

    @Test func `key content stays centered and visible through pressed layouts`() throws {
        let fixture = fixture()
        for identifier in ["tokenTrade.key.1", "tokenTrade.delete"] {
            let button = try fixture.button(identifier)
            let content = try #require(descendants(button).first {
                ($0 as? UILabel)?.text == "1" || ($0 as? UIImageView)?.image != nil
            })
            for highlighted in [true, false, true, false] {
                UIView.performWithoutAnimation {
                    button.isHighlighted = highlighted
                    button.setNeedsLayout()
                    button.layoutIfNeeded()
                }
                let center = content.convert(CGPoint(x: content.bounds.midX, y: content.bounds.midY), to: button)
                #expect(abs(center.x - button.bounds.midX) < 0.01)
                #expect(content.bounds.width > 0 && content.bounds.height > 0)
                #expect(!content.isHidden && content.alpha == 1)
                #expect(button.alpha == 1)
            }
        }
    }

    @Test func `backspace tap deletes once and remains available with text`() throws {
        let fixture = fixture("123")
        let button = try fixture.button("tokenTrade.delete")
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        #expect(fixture.field.amountInput.text == "12")
        #expect(button.isEnabled && button.alpha == 1 && !button.accessibilityElementsHidden)
        #expect(button.accessibilityActivate())
        #expect(fixture.field.amountInput.text == "1")
    }

    @Test func `holding backspace repeats and releasing does not add another deletion`() async throws {
        let fixture = fixture()
        let button = try fixture.button("tokenTrade.delete")
        button.sendActions(for: .touchDown)
        try await Task.sleep(for: .milliseconds(750))
        let heldText = fixture.field.amountInput.text
        #expect(heldText.count < 11 && !heldText.isEmpty)
        button.sendActions(for: .touchUpInside)
        #expect(fixture.field.amountInput.text == heldText)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.field.amountInput.text == heldText)
    }

    @Test(arguments: ["cancel", "dragOutside", "disable", "remove"])
    func `repeat stops when the press or control is interrupted`(_ interruption: String) async throws {
        let fixture = fixture()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(fixture.keypad)
        let button = try fixture.button("tokenTrade.delete")
        button.sendActions(for: .touchDown)
        try await Task.sleep(for: .milliseconds(650))
        #expect(fixture.field.amountInput.text.count < 12)
        switch interruption {
        case "cancel": button.sendActions(for: .touchCancel)
        case "dragOutside": button.sendActions(for: .touchDragExit)
        case "disable": fixture.keypad.updateDelete(isEnabled: false)
        default: fixture.keypad.removeFromSuperview()
        }
        let stoppedText = fixture.field.amountInput.text
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.field.amountInput.text == stoppedText)
    }

    @Test func `holding backspace stops at empty input`() async throws {
        let fixture = fixture("12")
        let button = try fixture.button("tokenTrade.delete")
        button.sendActions(for: .touchDown)
        try await Task.sleep(for: .milliseconds(750))
        #expect(fixture.field.amountInput.text.isEmpty)
        #expect(!button.isEnabled && button.accessibilityElementsHidden)
        fixture.field.insertText("3")
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.field.amountInput.text == "3")
    }
}

@MainActor private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}
