import Dependencies
import GRDB
import UIComponents
import UIKit
import WalletContext
import WalletResources
import XCTest
@testable import UIActivityList
@testable import UIAssets
@testable import WalletCore

@MainActor
final class HiddenBalanceLayoutTests: XCTestCase, ActivityCell.Delegate {
    override func setUp() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        SettingsStore.liveValue.use(db: database)
        setHidden(false)
    }

    override func tearDown() async throws {
        setHidden(false)
        SettingsStore.liveValue.clean()
    }

    func testWalletTokenSpoilersKeepNamesBadgesAndPricesClear() throws {
        let cell = WalletTokenCell(frame: CGRect(x: 0, y: 0, width: 300, height: 60))
        for hasBadge in [false, true] {
            cell.prepareForReuse()
            cell.configure(with: MTokenBalance(tokenSlug: "Ethena USDe Staking", balance: 0, isStaking: false),
                           animated: false,
                           badgeContent: hasBadge ? .tokenLabel(text: "4.76%", style: .regular) : nil,
                           stakingAccessoryContent: nil, isMultichain: false, isPinned: hasBadge)
            let content = try XCTUnwrap(cell.tokenContent)
            let price = try XCTUnwrap(content.subviews.flatMap(\.subviews).compactMap { $0 as? UILabel }.first)
            price.text = "$123,456,789.12 +999.99%"
            let masks = descendants(of: content).compactMap { $0 as? WSensitiveData<UILabel> }
            XCTAssertEqual(masks.count, 2)
            for hidden in [true, false, true] {
                setHidden(hidden)
                for cols in [4, 11, 6] {
                    masks.forEach { $0.setCols(cols) }
                    cell.setNeedsLayout()
                    cell.layoutIfNeeded()
                    content.setNeedsLayout()
                    content.layoutIfNeeded()
                    try assertSpoilersClear(in: content, masks: masks, hidden: hidden)
                    if !hidden {
                        for mask in masks {
                            let label = try XCTUnwrap(descendants(of: mask).compactMap { $0 as? UILabel }.first)
                            XCTAssertEqual(mask.bounds.width, ceil(label.intrinsicContentSize.width), accuracy: 0.5)
                        }
                    }
                }
            }
        }
    }

    func testActivitySpoilersKeepTitlesDetailsAndScamBadgesClear() throws {
        let cell = ActivityCell(frame: CGRect(x: 0, y: 0, width: 300, height: 60))
        let address = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"
        let account = MAccount(id: "spoiler-layout-mainnet", title: "Layout", type: .view, byChain: [.ton: .init(address: address)])
        for isScam in [true, false] {
            cell.prepareForReuse()
            let activity = ApiActivity.transaction(ApiTransactionActivity(
                id: "spoiler-layout", kind: "transaction", externalMsgHashNorm: nil,
                timestamp: 1_782_203_040_000, amount: 0, fromAddress: address, toAddress: address,
                comment: nil, encryptedComment: nil, fee: 0, slug: "toncoin", isIncoming: true,
                normalizedAddress: address, type: nil,
                metadata: .init(name: "A very long recipient name", isScam: isScam, isMemoRequired: nil),
                nft: nil, status: .confirmed
            ))
            withDependencies { $0.context = .live } operation: {
                cell.configure(with: activity, accountContext: AccountContext(source: .constant(account)),
                               delegate: self, showsRightChevron: isScam)
            }
            cell.detailsLabel.text = "Received · A very long date and time"
            let masks = descendants(of: cell).compactMap { $0 as? WSensitiveData<UILabel> }
            XCTAssertEqual(masks.count, 2)
            for hidden in [true, false, true] {
                setHidden(hidden)
                for cols in [4, 11, 6] {
                    masks.forEach { $0.setCols(cols) }
                    cell.setNeedsLayout()
                    cell.layoutIfNeeded()
                    try assertSpoilersClear(in: cell.firstTwoRows, masks: masks, hidden: hidden)
                }
            }
        }
    }

    func testMaskWidthIsReleasedOnRevealAndDisableAndRestoredOnReuse() throws {
        setHidden(true)
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        let mask = WSensitiveData<UILabel>(cols: 11, rows: 2, cellSize: 9, cornerRadius: 5,
                                          theme: .adaptive, alignment: .trailing, reservesMaskWidth: true)
        let label = UILabel()
        label.text = "0"
        label.translatesAutoresizingMaskIntoConstraints = false
        mask.addContent(label)
        parent.addSubview(mask)
        NSLayoutConstraint.activate([
            mask.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            mask.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
        ])
        parent.layoutIfNeeded()
        XCTAssertEqual(mask.bounds.width, 99, accuracy: 0.5)
        mask.performTap()
        parent.setNeedsLayout()
        parent.layoutIfNeeded()
        XCTAssertEqual(mask.bounds.width, label.intrinsicContentSize.width, accuracy: 0.5)
        mask.resetReveal()
        parent.setNeedsLayout()
        parent.layoutIfNeeded()
        XCTAssertEqual(mask.bounds.width, 99, accuracy: 0.5)
        mask.isDisabled = true
        parent.setNeedsLayout()
        parent.layoutIfNeeded()
        XCTAssertEqual(mask.bounds.width, label.intrinsicContentSize.width, accuracy: 0.5)
    }

    private func setHidden(_ hidden: Bool) {
        AppStorageHelper.isSensitiveDataHidden = hidden
        NotificationCenter.default.post(name: .updateSensitiveData, object: nil)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func assertSpoilersClear(in view: UIView, masks: [WSensitiveData<UILabel>], hidden: Bool,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        guard hidden else { return }
        for mask in masks {
            let spoiler = try XCTUnwrap(mask.shyMask, file: file, line: line)
            XCTAssertGreaterThanOrEqual(mask.bounds.width + 0.5, spoiler.bounds.width, file: file, line: line)
            let spoilerFrame = spoiler.convert(spoiler.bounds, to: view)
            for neighbor in descendants(of: view) where neighbor is UILabel || neighbor is BadgeView || neighbor is UIImageView {
                guard !neighbor.isHidden, neighbor.alpha > 0,
                      !masks.contains(where: { neighbor.isDescendant(of: $0) }) else { continue }
                var visibleFrame = neighbor.convert(neighbor.bounds, to: view)
                var ancestor = neighbor.superview
                while let current = ancestor, current !== view {
                    if current.clipsToBounds {
                        visibleFrame = visibleFrame.intersection(current.convert(current.bounds, to: view))
                    }
                    ancestor = current.superview
                }
                XCTAssertFalse(visibleFrame.intersects(spoilerFrame), "Spoiler overlaps \(type(of: neighbor))", file: file, line: line)
            }
        }
    }

    func onSelect(transaction: ApiActivity) {}
}
