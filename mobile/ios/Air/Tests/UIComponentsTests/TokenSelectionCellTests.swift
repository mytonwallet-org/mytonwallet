import Testing
import UIKit
import WalletCore
import WalletContext
@testable import UIComponents

@MainActor
struct TokenSelectionCellTests {
    @Test(arguments: [320.0, 402.0, 580.0])
    func `trade and fiat rows keep their height across reuse`(width: Double) {
        let cell = TokenCell(frame: CGRect(x: 0, y: 0, width: width, height: 180))
        for balance: BigInt in [0, 2_000_000_000] {
            cell.configure(with: token(), balance: balance, isAvailable: true, secondaryAmountMode: .balanceValueOrPrice) {}
            expectHeight(cell, width: width)
            for currency in [MBaseCurrency.USD, .EUR, .RUB] {
                cell.configure(currency: currency) {}
                expectHeight(cell, width: width)
            }
        }
    }

    @Test
    func `trade amounts switch between balance value and price across reuse`() {
        let cell = TokenCell(frame: CGRect(x: 0, y: 0, width: 402, height: 60))
        let token = token()
        for balance: BigInt in [0, 2_000_000_000, 0] {
            cell.configure(currency: .USD) {}
            cell.configure(with: token, balance: balance, isAvailable: true, secondaryAmountMode: .balanceValueOrPrice) {}
            cell.layoutIfNeeded()
            let labels = visibleLabels(in: cell)
            let amount = TokenAmount(balance, token).formatted(.defaultAdaptive, roundHalfUp: false)
            let value = BaseCurrencyAmount.fromDouble(balance == 0 ? token.price! : 2 * token.price!, TokenStore.baseCurrency)
                .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
            #expect(labels.contains { $0.text == amount })
            #expect(labels.contains { $0.text == (balance == 0 ? L10n.tokenPriceValue(value: value) : value) })
            #expect(!labels.contains { $0.text?.contains("%") == true })
            let containers = sensitiveContainers(in: cell)
            #expect(containers.count == 2)
            #expect(containers.filter(\.isDisabled).count == (balance == 0 ? 1 : 0))
        }
        cell.configure(with: self.token(price: nil), balance: 0, isAvailable: true, secondaryAmountMode: .balanceValueOrPrice) {}
        #expect(visibleLabels(in: cell).contains { $0.text == lang("No Price") })
    }

    private func expectHeight(_ cell: TokenCell, width: Double) {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.size = CGSize(width: width, height: 180)
        let fitted = cell.preferredLayoutAttributesFitting(attributes)
        #expect(abs(fitted.size.height - 60) < 1)
    }

    private func visibleLabels(in view: UIView) -> [UILabel] {
        guard !view.isHidden else { return [] }
        return (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { visibleLabels(in: $0) }
    }

    private func sensitiveContainers(in view: UIView) -> [WSensitiveData<UIView>] {
        (view as? WSensitiveData<UIView>).map { [$0] } ?? view.subviews.flatMap { sensitiveContainers(in: $0) }
    }

    private func token(price: Double? = 1.5) -> ApiToken {
        ApiToken(slug: "ton-token-cell-test", name: "Test Token", symbol: "TEST", decimals: 9,
                 chain: .ton, priceUsd: price, percentChange24h: 2.5)
    }
}
