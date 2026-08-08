import Testing
@testable import WalletCore
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
    static let missingLocalizedNames: [String?] = [nil, ""]

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

    @Test
    func `uses localized name when enabled`() {
        let token = makeToken(
            name: "Tether USD",
            localizedName: "Тезер",
            label: "TON",
            isRwaStock: false
        )

        #expect(token.displayName(strippingLabelWhenShown: false, useLocalizedName: true) == "Тезер")
    }

    @Test
    func `uses original name when localized names are disabled`() {
        let token = makeToken(
            name: "Tether USD",
            localizedName: "Тезер",
            label: "TON",
            isRwaStock: false
        )

        #expect(token.displayName(strippingLabelWhenShown: false, useLocalizedName: false) == "Tether USD")
    }

    @Test(arguments: Self.missingLocalizedNames)
    func `falls back to original name when localized name is unavailable`(localizedName: String?) {
        let token = makeToken(
            name: "Tether USD",
            localizedName: localizedName,
            label: "TON",
            isRwaStock: false
        )

        #expect(token.displayName(strippingLabelWhenShown: false, useLocalizedName: true) == "Tether USD")
    }

    @Test
    func `strips RWA label from localized name`() {
        let token = makeToken(
            name: "Tesla xStock",
            localizedName: "Tesla xStocks",
            label: "xStocks",
            isRwaStock: true
        )

        #expect(token.displayName(strippingLabelWhenShown: true, useLocalizedName: true) == "Tesla")
    }

    private func makeToken(name: String, localizedName: String? = nil, label: String, isRwaStock: Bool) -> ApiToken {
        ApiToken(
            slug: "display-name-\(name)-\(label)",
            name: name,
            localizedName: localizedName,
            symbol: "TEST",
            decimals: 9,
            chain: .ton,
            keywords: isRwaStock ? ["rwa"] : nil,
            label: label
        )
    }
}
