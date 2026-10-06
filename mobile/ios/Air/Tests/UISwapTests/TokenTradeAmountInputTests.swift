import Foundation
import Testing
import UIKit
import WalletContext
import WalletResources
@testable import UISwap

@Suite("Token trade amount input")
struct TokenTradeAmountInputTests {
    private func input(_ text: String, decimals: Int = 2) throws -> TokenTradeAmountInput {
        try #require(TokenTradeAmountInput().replacing(NSRange(location: 0, length: 0), with: text, decimals: decimals)).input
    }

    @Test func `selection replacement and deletion preserve cents and caret`() throws {
        let original = try input("1234.56")
        let replacement = try #require(original.replacing(NSRange(location: 1, length: 2), with: "9", decimals: 2))
        #expect(replacement.input.text == "194.56")
        #expect(replacement.input.amount(decimals: 2) == 19_456)
        #expect(replacement.caret == 2)
        let deletion = try #require(replacement.input.replacing(NSRange(location: 1, length: 1), with: "", decimals: 2))
        #expect(deletion.input.text == "14.56")
        #expect(deletion.caret == 1)
    }

    @Test func `paste normalizes localized digits and grouping with exact precision`() throws {
        let input = try input("١٢ ٣٤٥,٦٧")
        #expect(input.text == "12345.67")
        #expect(input.amount(decimals: 2) == 1_234_567)
        let grouped = try self.input("1,234.56")
        #expect(grouped.text == "1234.56")
    }

    @Test func `fraction first and leading zero input are normalized`() throws {
        let decimal = try #require(TokenTradeAmountInput().replacing(NSRange(location: 0, length: 0), with: ".", decimals: 9))
        #expect(decimal.input.text == "0.")
        #expect(decimal.caret == 2)
        #expect(try input("0005.10").text == "5.10")
        let empty = try #require(decimal.input.replacing(NSRange(location: 0, length: 2), with: "", decimals: 9))
        #expect(empty.input.text.isEmpty)
        #expect(empty.caret == 0)
    }

    @Test func `invalid and overprecise edits leave the amount unchanged`() throws {
        let original = try input("4.02")
        for replacement in ["9", ".", ",", "-", "e", "🙂"] {
            #expect(original.replacing(NSRange(location: 4, length: 0), with: replacement, decimals: 2) == nil)
        }
        #expect(try input("999999999999", decimals: 0).replacing(NSRange(location: 12, length: 0), with: "9", decimals: 0) == nil)
        #expect(TokenTradeAmountInput().replacing(NSRange(location: 0, length: 0), with: "1.1", decimals: 0) == nil)
        #expect(original.replacing(NSRange(location: 5, length: 0), with: "1", decimals: 2) == nil)
    }

    @Test func `selected decimal separator can be replaced`() throws {
        let original = try input("4.02")
        let edit = try #require(original.replacing(NSRange(location: 1, length: 1), with: ",", decimals: 2))
        #expect(edit.input == original)
        #expect(edit.caret == 2)
    }

    @Test func `token precision is preserved without floating point`() throws {
        var original = TokenTradeAmountInput()
        let amount = BigInt("123456789012123456789")
        original.set(amount, decimals: 9)
        #expect(original.amount(decimals: 9) == amount)
        #expect(original.replacing(NSRange(location: original.text.count, length: 0), with: "1", decimals: 9) == nil)
    }

    @MainActor @Test func `native field edits selections and preserves them during quote updates`() throws {
        _ = WalletResourcesBundle.bundle.load()
        let field = TokenTradeTextField()
        field.frame = CGRect(x: 0, y: 0, width: 354, height: 86)
        field.configure(input: try input("1234.56"), decimals: 2, prefix: "$", suffix: "", hasAmount: true)
        let start = try #require(field.position(from: field.beginningOfDocument, offset: 1))
        let end = try #require(field.position(from: field.beginningOfDocument, offset: 3))
        field.selectedTextRange = field.textRange(from: start, to: end)
        field.insertText("9")
        #expect(field.amountInput.text == "194.56")
        let selection = try #require(field.selectedTextRange)
        #expect(field.offset(from: field.beginningOfDocument, to: selection.start) == 2)
        field.configure(input: field.amountInput, decimals: 2, prefix: "$", suffix: "", hasAmount: true)
        #expect(field.offset(from: field.beginningOfDocument, to: try #require(field.selectedTextRange).start) == 2)
        field.deleteBackward()
        #expect(field.amountInput.text == "14.56")
        let all = try #require(field.textRange(from: field.beginningOfDocument, to: field.endOfDocument))
        field.replace(all, withText: "١ ٢٣٤,٥٦")
        #expect(field.amountInput.text == "1234.56")
        #expect(field.text == "1234" + (Locale.forNumberFormatters.decimalSeparator ?? ".") + "56")
    }

    @MainActor @Test func `currency number and fraction scale by the same factor`() throws {
        _ = WalletResourcesBundle.bundle.load()
        let field = TokenTradeTextField()
        field.frame = CGRect(x: 0, y: 0, width: 354, height: 86)
        field.configure(input: try input("555555566666.88"), decimals: 2, prefix: "$", suffix: "", hasAmount: true)
        field.layoutIfNeeded()
        let prefix = try #require(field.leftView as? UILabel)
        let attributes = try #require(field.attributedText)
        let integer = try #require(attributes.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let fraction = try #require(attributes.attribute(.font, at: 13, effectiveRange: nil) as? UIFont)
        #expect(integer.pointSize < 72)
        #expect(abs(prefix.font.pointSize / 64 - integer.pointSize / 72) < 0.001)
        #expect(abs(fraction.pointSize / 56 - integer.pointSize / 72) < 0.001)

        field.maximumHeight = 86
        let fittedHeight = field.fittingHeight(forWidth: 354)
        #expect(fittedHeight < 86)
        field.frame.size.height = fittedHeight
        field.configure(input: try input("5"), decimals: 2, prefix: "$", suffix: "", hasAmount: true)
        #expect(field.fittingHeight(forWidth: 354) > fittedHeight)
        #expect(field.font?.pointSize == 72)
    }

    @MainActor @Test(arguments: ["5.12", "123456789012.12", "5."])
    func `fractional caret follows the smaller font and shares the number baseline`(_ amount: String) throws {
        _ = WalletResourcesBundle.bundle.load()
        let field = TokenTradeTextField()
        field.frame = CGRect(x: 0, y: 0, width: 354, height: 86)
        field.configure(input: try input(amount), decimals: 2, prefix: "$", suffix: "", hasAmount: true)
        field.layoutIfNeeded()
        let attributedText = try #require(field.attributedText)
        let decimalRange = (attributedText.string as NSString).range(of: Locale.forNumberFormatters.decimalSeparator ?? ".")
        let font = try #require(field.font)
        let fractionFont = try #require(attributedText.attribute(.font, at: decimalRange.location, effectiveRange: nil) as? UIFont)
        let integerPosition = try #require(field.position(from: field.beginningOfDocument, offset: decimalRange.location))
        let integerCaret = field.caretRect(for: integerPosition)

        for offset in NSMaxRange(decimalRange)...attributedText.length {
            let position = try #require(field.position(from: field.beginningOfDocument, offset: offset))
            field.selectedTextRange = field.textRange(from: position, to: position)
            let caret = field.caretRect(for: position)
            #expect(caret.height < integerCaret.height)
            #expect(abs(caret.height - fractionFont.lineHeight) < 0.001)
            #expect(abs(caret.minY + fractionFont.ascender - font.ascender) < 0.001)
            #expect(caret.width == integerCaret.width)
        }

        field.selectedTextRange = field.textRange(from: integerPosition, to: integerPosition)
        #expect(field.caretRect(for: integerPosition) == integerCaret)
        field.configure(input: try input("5"), decimals: 2, prefix: "$", suffix: "", hasAmount: true)
        #expect(field.caretRect(for: field.endOfDocument).height > fractionFont.lineHeight)
    }

    @MainActor @Test func `full precision token amount and suffix fit together`() throws {
        _ = WalletResourcesBundle.bundle.load()
        let field = TokenTradeTextField()
        field.frame = CGRect(x: 0, y: 0, width: 354, height: 86)
        field.configure(input: try input("123456789012.123456789012345678", decimals: 18),
                        decimals: 18, prefix: "", suffix: " ETH", hasAmount: true)
        field.layoutIfNeeded()
        let suffix = try #require(field.rightView as? UILabel)
        let font = try #require(field.font)
        #expect(abs(suffix.font.pointSize / 32 - font.pointSize / 72) < 0.001)
        #expect(field.rightViewRect(forBounds: field.bounds).maxX <= field.bounds.maxX)
    }

}
