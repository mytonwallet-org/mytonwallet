import XCTest
import UIKit
import WalletCore
import WalletResources
@testable import UIComponents

@MainActor
final class CardMaterialDepthTests: XCTestCase {
    func testAccountLineRendersAndAnnouncesOnlyOneAddress() {
        _ = WalletResourcesBundle.bundle.load()
        let chains: [(ApiChain, AccountChain)] = [
            (.ton, AccountChain(address: "ton-address", domain: "wallet.ton")),
            (.ethereum, AccountChain(address: "0x1234", domain: "wallet.eth")),
            (.tron, AccountChain(address: "tron-address")),
        ]
        let account = MAccount(id: "card-address-mainnet", title: "Wallet", type: .mnemonic,
                               byChain: Dictionary(uniqueKeysWithValues: chains))
        let view = MtwCardAccountLineView()
        view.configure(address: account.addressLine(orderedChains: chains), name: account.displayName,
                       showsName: false, isTemporary: false, nft: nil)

        func labels(in view: UIView) -> [String] {
            if let text = (view as? UILabel)?.text { return [text] }
            let children = view.subviews + (view.mask.map { [$0] } ?? [])
            return children.flatMap { labels(in: $0) }
        }
        XCTAssertTrue(labels(in: view).contains("wallet.ton"))
        XCTAssertFalse(labels(in: view).contains { $0.contains("wallet.eth") || $0.contains("tron-address") })
        XCTAssertEqual(view.addressesButton.accessibilityLabel, "wallet.ton")
    }

    func testViewAccountLightingDoesNotDuplicateGlyphsAndSurvivesReconfiguration() throws {
        _ = WalletResourcesBundle.bundle.load()
        let chain = AccountChain(address: "UQDQ7EXuEywyezyEWzfNkHZTSbe8qbPKETFYHr_KTZnnJ-xL")
        let account = MAccount(id: "badge-mainnet", title: "View wallet", type: .view, byChain: [.ton: chain])
        let line = account.addressLine(orderedChains: [(.ton, chain)])
        var withoutMaterials = CardMotionPreset.black
        withoutMaterials.materialEnabled = false
        for preset in [CardMotionPreset.myDefault, .gramDefault, .standard, .black, withoutMaterials] {
            let view = MtwCardAccountLineView()
            view.frame = CGRect(x: 0, y: 0, width: 360, height: 30)
            var nft = ApiNft.sampleMtwCard
            nft.metadata?.mtwCardType = .black
            for showsName in [true, false] {
                view.configure(address: line, name: "View wallet", showsName: showsName, isTemporary: false, nft: nft)
                view.layoutIfNeeded()
                let badge = try XCTUnwrap(view.addressesButton.subviews.compactMap { $0 as? CardBadgeBackground }.first)
                for tilt in [CGPoint.zero, CGPoint(x: -1, y: 1), CGPoint(x: 1, y: -1)] {
                    preset.applyContentLight(CardSurfaceLight(borderTilt: tilt), balance: UIView(), change: MtwCardChangeView(),
                                             accountLine: view, decoration: UIView())
                    XCTAssertEqual(view.layer.shadowOpacity, 0, "An offset white shadow creates a second address and badge")
                    XCTAssertEqual(view.transform.tx, tilt.x * CGFloat(preset.materialEnabled ? preset.materialDepth : 0) * 0.8, accuracy: 0.001)
                    XCTAssertEqual(badge.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.filter { !$0.isHidden }.count, 2,
                                   "The badge keeps its fill and rim at every light direction")
                    XCTAssertFalse(try XCTUnwrap(badge.subviews.first as? UIVisualEffectView).isHidden,
                                   "Live blur stays underneath the directional light")
                }
            }
            view.prepareForReuse()
            let badge = try XCTUnwrap(view.addressesButton.subviews.compactMap { $0 as? CardBadgeBackground }.first)
            XCTAssertTrue(badge.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.allSatisfy(\.isHidden) == true)
            XCTAssertFalse(try XCTUnwrap(badge.subviews.first as? UIVisualEffectView).isHidden)
        }
    }

    func testLayerDepthMovesTheSameGeometryWithoutRelayingOutEveryGlyph() {
        final class CountingView: UIView {
            var layouts = 0
            override func layoutSubviews() { super.layoutSubviews(); layouts += 1 }
        }
        let host = UIView(frame: CGRect(x: 0,y: 0,width: 400,height: 232))
        let balance = CountingView(frame: CGRect(x: 20,y: 30,width: 200,height: 50))
        let change = MtwCardChangeView(), line = MtwCardAccountLineView(), decoration = UIView()
        for view in [balance,change,line,decoration] { host.addSubview(view); view.layoutIfNeeded() }
        let initial = balance.layouts
        for index in 0..<120 {
            let value = CGFloat(index)/120
            CardMotionPreset.myDefault.applyContentLight(.init(borderTilt: CGPoint(x: value,y: -value)),
                balance: balance,change: change,accountLine: line,decoration: decoration)
            balance.layoutIfNeeded()
            XCTAssertEqual(balance.frame.minX,20 + value*3.5*1.1,accuracy: 0.001)
        }
        XCTAssertEqual(balance.layouts,initial,"Lighting must not relayout labels at the display-link rate")
    }

    func testSelectedDepthSurvivesContentRelayout() throws {
        _ = WalletResourcesBundle.bundle.load()
        let chain = AccountChain(address: "UQDQ7EXuEywyezyEWzfNkHZTSbe8qbPKETFYHr_KTZnnJ-xL")
        let account = MAccount(id: "depth-mainnet", title: "Depth test", type: .view, byChain: [.ton: chain])
        let data = MtwCardContentData(account: account, addressLine: account.addressLine(orderedChains: [(.ton, chain)]),
                                    balance: .fromDouble(1234.56, .USD), previousBalance: .fromDouble(1100.23, .USD),
                                    balanceChange: 12.2, nft: nil)
        for preset in [CardMotionPreset.myDefault, .gramDefault] {
            XCTAssertEqual(Double(preset.materialDepth), 3.5, accuracy: 0.03)
            let content = MtwCardContentView(mode: .expanded)
            content.frame = CGRect(x: 0, y: 0, width: 386, height: 232)
            content.configure(data, cardWidth: 386, animatesBalance: false)
            content.layoutIfNeeded()
            let planes: [UIView] = [content.balance, content.change, content.accountLine, content.seasonal]
            let resting = planes.map { $0.frame }
            let light = CardSurfaceLight(borderTilt: CGPoint(x: 1, y: -1))
            preset.applyContentLight(light, balance: content.balance, change: content.change,
                                     accountLine: content.accountLine, decoration: content.seasonal)
            let shifted = planes.map { $0.frame }
            func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
            let backgrounds = descendants(content).compactMap { $0 as? CardBadgeBackground }
            XCTAssertEqual(backgrounds.count, 2, "Portfolio change and View share the glass surface")
            for background in backgrounds {
                XCTAssertFalse(try XCTUnwrap(background.subviews.first as? UIVisualEffectView).isHidden)
                let gradients = try XCTUnwrap(background.layer.sublayers?.compactMap { $0 as? CAGradientLayer })
                XCTAssertEqual(gradients.filter { !$0.isHidden }.count, 2)
                let fill = try XCTUnwrap(gradients.first)
                let dx = (fill.endPoint.x - fill.startPoint.x) * background.bounds.width
                let dy = (fill.endPoint.y - fill.startPoint.y) * background.bounds.height
                XCTAssertEqual(dx / dy, 0.65 / 0.35, accuracy: 0.001)
                XCTAssertEqual(fill.locations?.count, 13, "Broad lighting stays smooth on both badge shapes")
            }
            for (index, factor) in [1.1, 1.1, 0.8, 0.4].enumerated() {
                XCTAssertEqual(shifted[index].minX - resting[index].minX, CGFloat(preset.materialDepth) * factor, accuracy: 0.001)
                XCTAssertEqual(shifted[index].minY - resting[index].minY, -CGFloat(preset.materialDepth) * factor, accuracy: 0.001)
            }
            for _ in 0..<3 {
                content.configure(data, cardWidth: 386, animatesBalance: false)
                content.layoutIfNeeded()
                for (plane, expected) in zip(planes, shifted) {
                    XCTAssertEqual(plane.frame.minX, expected.minX, accuracy: 0.001)
                    XCTAssertEqual(plane.frame.minY, expected.minY, accuracy: 0.001)
                }
            }
        }
    }
}
