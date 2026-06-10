import Testing
@testable import WalletCore

@Suite("Subwallet Title Naming")
struct SubwalletTitleNamingTests {
    struct BaseTitleCase: Sendable {
        let title: String
        let expected: String
    }

    struct NextTitleCase: Sendable {
        let baseTitle: String
        let existingTitles: [String]
        let expected: String
    }

    static let baseTitleCases: [BaseTitleCase] = [
        .init(title: "MyTonWallet", expected: "MyTonWallet"),
        .init(title: "MyTonWallet .2", expected: "MyTonWallet"),
        .init(title: "MyTonWallet.2", expected: "MyTonWallet"),
        .init(title: "MyTonWallet 2", expected: "MyTonWallet 2"),
        .init(title: "MyTonWallet 2.3", expected: "MyTonWallet 2"),
        .init(title: "Wallet.v4R2", expected: "Wallet.v4R2"),
    ]

    static let nextTitleCases: [NextTitleCase] = [
        .init(
            baseTitle: "MyTonWallet",
            existingTitles: ["MyTonWallet"],
            expected: "MyTonWallet .2"
        ),
        .init(
            baseTitle: "MyTonWallet",
            existingTitles: ["MyTonWallet", "MyTonWallet .2"],
            expected: "MyTonWallet .3"
        ),
        .init(
            baseTitle: "MyTonWallet",
            existingTitles: ["MyTonWallet", "MyTonWallet .2", "MyTonWallet.3"],
            expected: "MyTonWallet .4"
        ),
        .init(
            baseTitle: "MyTonWallet 2",
            existingTitles: ["MyTonWallet 2"],
            expected: "MyTonWallet 2.2"
        ),
        .init(
            baseTitle: "MyTonWallet 2",
            existingTitles: ["MyTonWallet 2", "MyTonWallet 2.2"],
            expected: "MyTonWallet 2.3"
        ),
        .init(
            baseTitle: "MyTonWallet 3",
            existingTitles: ["MyTonWallet 2", "MyTonWallet 2.2", "MyTonWallet 2.3"],
            expected: "MyTonWallet 3.2"
        ),
    ]

    @Test(arguments: Self.baseTitleCases)
    func `base title strips only subwallet suffixes`(testCase: BaseTitleCase) {
        #expect(SubwalletTitleNaming.baseTitle(from: testCase.title) == testCase.expected)
    }

    @Test(arguments: Self.nextTitleCases)
    func `next title follows subwallet numbering format`(testCase: NextTitleCase) {
        #expect(
            SubwalletTitleNaming.nextTitle(
                baseTitle: testCase.baseTitle,
                existingTitles: testCase.existingTitles
            ) == testCase.expected
        )
    }
}
