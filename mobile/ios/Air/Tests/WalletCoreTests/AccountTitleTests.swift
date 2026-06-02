import Testing
@testable import WalletCore

@Suite("Account Title")
struct AccountTitleTests {
    struct NormalizedTitleCase: Sendable {
        let title: String?
        let expected: String?
    }

    static let normalizedTitleCases: [NormalizedTitleCase] = [
        .init(title: "New Locked", expected: "New Locked"),
        .init(title: "  New Locked  ", expected: "New Locked"),
        .init(title: "\nNew   Locked\t", expected: "New   Locked"),
        .init(title: "   ", expected: nil),
        .init(title: nil, expected: nil),
    ]

    @Test(arguments: Self.normalizedTitleCases)
    func `normalizes saved wallet titles`(testCase: NormalizedTitleCase) {
        #expect(AccountTitle.normalized(testCase.title) == testCase.expected)
    }
}
