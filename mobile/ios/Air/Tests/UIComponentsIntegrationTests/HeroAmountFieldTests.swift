import CoreText
import Testing
import UIKit
import WalletResources
@testable import UIComponents

@MainActor @Suite("Hero amount editor")
struct HeroAmountFieldTests {
    private func field() -> HeroAmountField {
        _ = WalletResourcesBundle.bundle.load()
        let field = HeroAmountField()
        field.focusesOnAppearance = false
        field.caretColor = .systemPink
        field.maximumHeight = 86
        field.frame = CGRect(x: 20, y: 100, width: 300, height: 86)
        field.edit = { text, range, replacement in
            guard let rangeInText = Range(range, in: text) else { return nil }
            return .init(text: text.replacingCharacters(in: rangeInText, with: replacement),
                         caret: range.location + replacement.utf16.count)
        }
        return field
    }

    private func expectCaret(_ field: HeroAmountField, at position: UITextPosition) {
        let actual = field.amountPresentation.caretFrame
        let expected = field.amountCaretRect(for: position)
        #expect(abs(actual.minX - expected.minX) < 0.001)
        #expect(abs(actual.minY - expected.minY) < 0.001)
        #expect(abs(actual.width - expected.width) < 0.001)
        #expect(abs(actual.height - expected.height) < 0.001)
    }

    @Test func `only the custom insertion caret survives focus edits selection and animation changes`() throws {
        let field = field()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(field)
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        field.configure(text: "", prefix: "$", suffix: "", hasAmount: false)
        field.configureAnimation(active: true, animated: true)
        field.becomeFirstResponder()
        field.layoutIfNeeded()
        #expect(field.caretRect(for: field.endOfDocument) == .zero)
        #expect(field.tintColor == .clear)
        #expect(field.amountPresentation.showsCaret)

        for digit in "123456789" { field.insertText(String(digit)) }
        #expect(field.caretRect(for: field.endOfDocument) == .zero)
        #expect(field.tintColor == .clear)
        #expect(field.amountPresentation.showsCaret)

        let start = try #require(field.position(from: field.beginningOfDocument, offset: 2))
        let end = try #require(field.position(from: field.beginningOfDocument, offset: 5))
        field.selectedTextRange = field.textRange(from: start, to: end)
        field.textFieldDidChangeSelection(field)
        #expect(field.tintColor == field.caretColor)
        #expect(!field.amountPresentation.showsCaret)
        #expect(!field.amountPresentation.isAnimating)

        field.selectedTextRange = field.textRange(from: start, to: start)
        field.textFieldDidChangeSelection(field)
        #expect(field.tintColor == .clear)
        #expect(field.amountPresentation.showsCaret)
        expectCaret(field, at: start)
        field.insertText("0")
        #expect(field.inputText == "1203456789")
        field.configureAnimation(active: true, animated: false)
        field.layoutIfNeeded()
        #expect(field.caretRect(for: field.endOfDocument) == .zero)
        #expect(field.amountPresentation.showsCaret)
        #expect(!field.amountPresentation.isAnimating)
        field.configureAnimation(active: false, animated: false)
        #expect(!field.amountPresentation.showsCaret)
    }

    @Test func `unit changes animate while quote refreshes preserve the selection`() throws {
        let field = field()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(field)
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        field.configureAnimation(active: true, animated: true)
        field.configure(text: "123.45", prefix: "$", suffix: "", hasAmount: true)
        field.becomeFirstResponder()
        field.layoutIfNeeded()
        field.configure(text: "41.15", prefix: "", suffix: "TON", hasAmount: true)
        field.layoutIfNeeded()
        #expect(field.amountPresentation.isAnimating)
        #expect(field.caretRect(for: field.endOfDocument) == .zero)
        let start = try #require(field.position(from: field.beginningOfDocument, offset: 1))
        field.selectedTextRange = field.textRange(from: start, to: start)
        field.textFieldDidChangeSelection(field)
        field.configure(text: "41.15", prefix: "", suffix: "TON", hasAmount: true)
        #expect(field.selectedTextRange?.start == start)
        #expect(!field.amountPresentation.isAnimating)
    }

    @Test func `parent layout animations do not animate the Metal canvas geometry`() throws {
        let field = field()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(field)
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        field.configureAnimation(active: true, animated: true)
        field.configure(text: "", prefix: "$", suffix: "", hasAmount: false)
        field.layoutIfNeeded()

        UIView.animate(withDuration: 0.32) {
            field.configure(text: "27.01", prefix: "$", suffix: "", hasAmount: true)
            field.layoutIfNeeded()
        }
        let canvas = try #require(field.amountPresentation.subviews.compactMap { $0 as? TelegramAmountCanvas }.first)
        #expect(field.amountPresentation.isAnimating)
        #expect(canvas.layer.animation(forKey: "bounds") == nil)
        #expect(canvas.layer.animation(forKey: "position") == nil)
    }

    @Test(arguments: ["", "0", "123.45"])
    func `unit switches hide native text in the first animation frame`(_ amount: String) throws {
        let field = field()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(field)
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        field.configureAnimation(active: true, animated: true)
        field.configure(text: amount, prefix: "$", suffix: "", hasAmount: amount == "123.45")
        field.becomeFirstResponder()
        field.layoutIfNeeded()

        // Include reversing an in-flight transition before a GPU completion can arrive.
        for tokenMode in [true, false, true] {
            field.configure(text: amount, prefix: tokenMode ? "" : "$", suffix: tokenMode ? "GRAM" : "",
                            hasAmount: amount == "123.45")
            field.layoutIfNeeded()
            #expect(field.amountPresentation.isAnimating)
            #expect(field.amountPresentation.isPresentingText)
            #expect(field.leftView?.alpha == 0)
            #expect(field.rightView?.alpha == 0)
            let text = try #require(amount.isEmpty ? field.attributedPlaceholder : field.attributedText)
            text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { color, _, _ in
                #expect((color as? UIColor) == .clear)
            }
        }

        field.configureAnimation(active: true, animated: false)
        field.layoutIfNeeded()
        #expect(!field.amountPresentation.isAnimating)
        #expect(!field.amountPresentation.isPresentingText)
        #expect(field.leftView?.alpha == 1)
        #expect(field.rightView?.alpha == 1)
        let text = try #require(amount.isEmpty ? field.attributedPlaceholder : field.attributedText)
        #expect((text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor) != .clear)
    }

    @Test func `render failures restore native text without cancelling newer frames`() async throws {
        let field = field()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(field)
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        field.configureAnimation(active: true, animated: true)
        field.configure(text: "123.45", prefix: "$", suffix: "", hasAmount: true)
        field.becomeFirstResponder()
        field.layoutIfNeeded()
        field.configure(text: "41.15", prefix: "", suffix: "TON", hasAmount: true)
        field.layoutIfNeeded()
        let canvas = try #require(field.amountPresentation.subviews.compactMap { $0 as? TelegramAmountCanvas }.first)
        #expect(field.amountPresentation.isPresentingText)
        let failedGeneration = canvas.frameGeneration

        canvas.renderingFailed(for: failedGeneration)
        #expect(!canvas.hasFrame)
        #expect(canvas.isHidden)
        #expect(!field.amountPresentation.isPresentingText)
        #expect(!field.amountPresentation.isAnimating)
        #expect(field.leftView?.alpha == 1)
        #expect(field.rightView?.alpha == 1)
        let text = try #require(field.attributedText)
        #expect((text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor) != .clear)

        // Allow the real command to finish before starting the next transition.
        try await Task.sleep(for: .milliseconds(20))
        field.configure(text: "123.45", prefix: "$", suffix: "", hasAmount: true)
        field.layoutIfNeeded()
        #expect(canvas.frameGeneration != failedGeneration)
        #expect(field.amountPresentation.isPresentingText)
        canvas.renderingFailed(for: failedGeneration)
        #expect(canvas.hasFrame)
        #expect(field.amountPresentation.isPresentingText)
        #expect(field.amountPresentation.isAnimating)

        let cancelledGeneration = canvas.frameGeneration
        field.configureAnimation(active: true, animated: false)
        canvas.renderingFailed(for: cancelledGeneration)
        #expect(!field.amountPresentation.isPresentingText)
        #expect(!field.amountPresentation.isAnimating)
        #expect(field.leftView?.alpha == 1)
        #expect(field.rightView?.alpha == 1)
    }

    @Test(arguments: [CGFloat(240), 300, 354])
    func `full precision fits without scrolling away from the prefix`(_ width: CGFloat) throws {
        let field = field()
        field.frame.size.width = width
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(field)
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        field.configure(text: "123456789012.123456789012345678", prefix: "$", suffix: "ETH", hasAmount: true)
        field.becomeFirstResponder()
        field.layoutIfNeeded()
        #expect(abs(field.amountTextOrigin - field.textRect(forBounds: field.bounds).minX) < 1)
        #expect(field.rightViewRect(forBounds: field.bounds).maxX <= width - 52)
        let text = try #require(field.attributedText)
        let advance = CTLineGetOffsetForStringIndex(CTLineCreateWithAttributedString(text), text.length, nil)
        let scale = try #require(field.font).pointSize / 72
        #expect(abs(field.amountCaretRect(for: field.endOfDocument).minX - field.amountTextOrigin - advance - 2.5 * scale) < 0.001)
    }

    @Test(arguments: ["", "4", "4.02"])
    func `caret gap and design dimensions scale with the amount`(_ amount: String) throws {
        let field = field()
        field.configure(text: amount, prefix: "$", suffix: "", hasAmount: !amount.isEmpty)
        for size in [CGSize(width: 354, height: 86), CGSize(width: 150, height: 86), CGSize(width: 150, height: 43)] {
            field.maximumHeight = size.height
            field.frame.size = size
            field.layoutIfNeeded()
            let text = try #require(amount.isEmpty ? field.attributedPlaceholder : field.attributedText)
            let font = try #require(field.font)
            let scale = font.pointSize / 72
            let caret = field.amountCaretRect(for: field.endOfDocument)
            let advance = CTLineGetOffsetForStringIndex(CTLineCreateWithAttributedString(text), text.length, nil)
            let gap = caret.minX - field.amountTextOrigin - advance
            #expect(abs(gap / scale - 2.5) < 0.001)
            #expect(abs(caret.width / scale - 2.5) < 0.001)
            #expect(abs(caret.height / scale - (amount.contains(".") ? 48 : 58)) < 0.001)
            #expect(abs(caret.maxY - field.textRect(forBounds: field.bounds).midY - 31 * scale) < 0.001)
        }
    }

    @Test func `RTL input direction cannot move the placeholder or amount away from its prefix`() throws {
        let field = field()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController!.view.semanticContentAttribute = .forceRightToLeft
        window.rootViewController!.view.addSubview(field)
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        field.configureAnimation(active: true, animated: false)
        field.configure(text: "", prefix: "$", suffix: "", hasAmount: false)
        field.becomeFirstResponder()
        for amount in ["", "4.02", ""] {
            field.configure(text: amount, prefix: "$", suffix: "", hasAmount: !amount.isEmpty)
            let range = try #require(field.textRange(from: field.beginningOfDocument, to: field.endOfDocument))
            // An RTL keyboard asks the text input to change paragraph direction.
            field.setBaseWritingDirection(.rightToLeft, for: range)
            field.layoutIfNeeded()
            let text = try #require(amount.isEmpty ? field.attributedPlaceholder : field.attributedText)
            let style = try #require(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            #expect(style.baseWritingDirection == .leftToRight)
            #expect(style.alignment == .left)
            #expect(field.baseWritingDirection(for: field.beginningOfDocument, in: .forward) == .leftToRight)
            #expect(field.baseWritingDirection(for: field.endOfDocument, in: .backward) == .leftToRight)
            #expect(abs(field.amountTextOrigin - field.leftViewRect(forBounds: field.bounds).maxX) < 1)
            expectCaret(field, at: field.endOfDocument)
            #expect(field.caretRect(for: field.endOfDocument) == .zero)
        }
    }
}
