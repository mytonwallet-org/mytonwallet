import Testing
import WalletCore
import WalletContext

@Suite("ApiToken Display Name")
struct ApiTokenDisplayNameTests {
    struct DisplayNameCase: Sendable {
        let name: String
        let label: String
        let expected: String
    }

    static let rwaStockLabelCases: [DisplayNameCase] = [
        .init(name: "Tesla xStock", label: "xStocks", expected: "Tesla"),
        .init(name: "Tesla xStocks", label: "xStocks", expected: "Tesla"),
        .init(name: "Shift Robotics", label: "Shift", expected: "Robotics"),
        .init(name: "Robotics Shift", label: "Shift", expected: "Robotics"),
    ]

    @Test(arguments: Self.rwaStockLabelCases)
    func `strips shown RWA stock label prefix or suffix`(testCase: DisplayNameCase) {
        let token = makeToken(name: testCase.name, label: testCase.label, isRwaStock: true)

        #expect(token.displayName(strippingLabelWhenShown: true) == testCase.expected)
    }

    @Test
    func `keeps RWA stock label when label is not shown`() {
        let token = makeToken(name: "Tesla xStock", label: "xStocks", isRwaStock: true)

        #expect(token.displayName(strippingLabelWhenShown: false) == "Tesla xStock")
    }

    @Test
    func `keeps non RWA token name even if label matches`() {
        let token = makeToken(name: "Shift Token", label: "Shift", isRwaStock: false)

        #expect(token.displayName(strippingLabelWhenShown: true) == "Shift Token")
    }

    @Test
    func `keeps name when stripping would remove the full title`() {
        let token = makeToken(name: "Shift", label: "Shift", isRwaStock: true)

        #expect(token.displayName(strippingLabelWhenShown: true) == "Shift")
    }

    private func makeToken(name: String, label: String, isRwaStock: Bool) -> ApiToken {
        ApiToken(
            slug: "display-name-\(name)-\(label)",
            name: name,
            symbol: "TEST",
            decimals: 9,
            chain: .ton,
            keywords: isRwaStock ? ["rwa"] : nil,
            label: label
        )
    }
}
