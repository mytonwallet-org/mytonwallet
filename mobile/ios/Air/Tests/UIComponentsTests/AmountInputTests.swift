import Testing
import UIKit
import WalletContext
@testable import UIComponents

@MainActor
@Suite("Amount Input")
struct AmountInputTests {
    @Test(arguments: [9, 6, 0])
    func `reducing token precision truncates without rounding`(decimals: Int) throws {
        var changeCount = 0
        let input = makeInput(maximumFractionDigits: 18, onChange: { _ in changeCount += 1 })
        input.text = "1.123456789987654321"
        try select(input, start: 20, end: 20)

        input.maximumFractionDigits = decimals

        let expected = decimals == 0 ? "1" : "1." + String("123456789987654321".prefix(decimals))
        #expect(input.text == expected)
        #expect(input.amountValueOrNil == amountValue(expected, digits: decimals))
        #expect(selection(input) == NSRange(location: expected.count, length: 0))
        // A token/model update must not be reported as a new user edit.
        #expect(changeCount == 0)
    }

    @Test
    func `precision changes preserve valid text and selection`() throws {
        let input = makeInput(maximumFractionDigits: 18, onChange: { _ in })
        input.text = "12.3400"
        try select(input, start: 1, end: 4)
        input.maximumFractionDigits = 9
        #expect(input.text == "12.3400")
        #expect(selection(input) == NSRange(location: 1, length: 3))

        input.maximumFractionDigits = 18
        #expect(input.text == "12.3400")
        #expect(selection(input) == NSRange(location: 1, length: 3))
    }

    @Test
    func `truncation clamps a selection without moving its start`() throws {
        let input = makeInput(maximumFractionDigits: 18, onChange: { _ in })
        input.text = "12.123456789987654321"
        try select(input, start: 3, end: 21)
        input.maximumFractionDigits = 6
        #expect(input.text == "12.123456")
        #expect(selection(input) == NSRange(location: 3, length: 6))
    }

    @Test
    func `backspace removes one digit even while input remains over precision`() throws {
        var changes: [BigInt?] = []
        let input = makeInput(maximumFractionDigits: 6, onChange: { changes.append($0) })
        input.text = "0.123456789"
        try edit(input, range: NSRange(location: 10, length: 1), replacement: "")
        #expect(input.text == "0.12345678")
        #expect(selection(input) == NSRange(location: 10, length: 0))
        #expect(changes == [123456])

        try edit(input, range: NSRange(location: 9, length: 1), replacement: "")
        #expect(input.text == "0.1234567")
        try edit(input, range: NSRange(location: 0, length: 9), replacement: "")
        #expect(input.text == "")
        #expect(changes.last == .some(nil))
    }

    @Test
    func `deleting selected digits from over precision input keeps the caret`() throws {
        let input = makeInput(maximumFractionDigits: 6, onChange: { _ in })
        input.text = "12.123456789"
        try edit(input, range: NSRange(location: 5, length: 2), replacement: "")
        #expect(input.text == "12.1256789")
        #expect(selection(input) == NSRange(location: 5, length: 0))
    }

    @Test(arguments: ["1,123456789987654321", "۱.۱۲۳۴۵۶۷۸۹۹۸۷۶۵۴۳۲۱", "1.123456789987654321"])
    func `pasted precision is truncated on token change and stays editable`(pasted: String) throws {
        let input = makeInput(maximumFractionDigits: 18, onChange: { _ in })
        try edit(input, range: NSRange(location: 0, length: 0), replacement: pasted)
        #expect(input.text == "1.123456789987654321")
        input.maximumFractionDigits = 9
        #expect(input.text == "1.123456789")
        try edit(input, range: NSRange(location: 10, length: 1), replacement: "")
        #expect(input.text == "1.12345678")
        #expect(input.amountValueOrNil == 1_123_456_780)
    }

    @Test(arguments: ["9", "987", "x", ","])
    func `invalid insertions still leave a full precision amount unchanged`(replacement: String) throws {
        let input = makeInput(maximumFractionDigits: 6, onChange: { _ in })
        input.text = "1.123456"
        try edit(input, range: NSRange(location: 8, length: 0), replacement: replacement)
        #expect(input.text == "1.123456")
        #expect(selection(input) == NSRange(location: 8, length: 0))
    }

    @Test
    func `valid middle editing and trailing decimal separator are preserved`() throws {
        let input = makeInput(maximumFractionDigits: 9, onChange: { _ in })
        input.text = "12.345"
        try edit(input, range: NSRange(location: 4, length: 1), replacement: "9")
        #expect(input.text == "12.395")
        #expect(selection(input) == NSRange(location: 5, length: 0))
        try edit(input, range: NSRange(location: 3, length: 3), replacement: "")
        #expect(input.text == "12.")
        input.maximumFractionDigits = 6
        #expect(input.text == "12.")
    }

    @Test
    func `pasting into the middle leaves the caret after the pasted digits`() throws {
        let input = makeInput(maximumFractionDigits: 9, onChange: { _ in })
        input.text = "12.345"
        try edit(input, range: NSRange(location: 4, length: 0), replacement: "67")
        #expect(input.text == "12.36745")
        #expect(selection(input) == NSRange(location: 6, length: 0))
    }

    private func makeInput(maximumFractionDigits: Int, onChange: @escaping (BigInt?) -> Void) -> WAmountInput {
        let input = WAmountInput(maximumFractionDigits: maximumFractionDigits, onChange: onChange)
        input.integerFont = .systemFont(ofSize: 28)
        input.fractionFont = .systemFont(ofSize: 22)
        return input
    }

    private func edit(_ input: WAmountInput, range: NSRange, replacement: String) throws {
        try select(input, start: range.location, end: NSMaxRange(range))
        #expect(!input.textField(input, shouldChangeCharactersIn: range, replacementString: replacement))
    }

    private func select(_ input: WAmountInput, start: Int, end: Int) throws {
        let from = try #require(input.position(from: input.beginningOfDocument, offset: start))
        let to = try #require(input.position(from: input.beginningOfDocument, offset: end))
        input.selectedTextRange = input.textRange(from: from, to: to)
    }

    private func selection(_ input: WAmountInput) -> NSRange? {
        guard let range = input.selectedTextRange else { return nil }
        return NSRange(
            location: input.offset(from: input.beginningOfDocument, to: range.start),
            length: input.offset(from: range.start, to: range.end)
        )
    }
}
