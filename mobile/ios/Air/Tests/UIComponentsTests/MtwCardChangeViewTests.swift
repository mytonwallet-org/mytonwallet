import Testing
import UIKit
import WalletContext
import WalletCore
@testable import UIComponents

@Suite @MainActor
struct MtwCardChangeViewTests {
    @Test func customPillFitsLongValuesAndHidesChevronWithoutChangingHomeDefaults() throws {
        let view = MtwCardChangeView()
        view.frame = CGRect(x: 0, y: 0, width: 288, height: 28)
        view.configure(text: "−$123 456 789 012.34 · 12345.67%", color: .systemRed, height: 28, isHidden: false, animates: false)
        view.layoutIfNeeded()
        let visibility = try #require(view.subviews.first)
        #expect(visibility.frame.minX >= -0.5)
        #expect(visibility.frame.maxX <= view.bounds.width + 0.5)
        let pill = try #require(visibility.subviews.first)
        let chevron = try #require(pill.subviews.compactMap { $0 as? UIImageView }.first)
        let label = try #require(pill.subviews.compactMap { $0 as? UILabel }.first)
        #expect(chevron.isHidden)
        #expect(label.font == WTypography.uiFont(.bodyEmphasized))
        #expect(label.textColor.resolvedColor(with: view.traitCollection) == UIColor.systemRed.resolvedColor(with: view.traitCollection))
        #expect(view.accessibilityTraits == .staticText)
        view.configure(balance: .fromDouble(130, .USD), previous: .fromDouble(100, .USD), percent: 0.3,
                       nft: nil, style: .plainBackground, isHidden: false, animates: false)
        view.layoutIfNeeded()
        #expect(!chevron.isHidden)
        #expect(pill.bounds.height == 26)
        #expect(view.accessibilityTraits == .button)
        #expect(label.textColor == UIColor(hex: "34C759"))
    }
}
