import UIKit
import XCTest
import GRDB
@testable import WalletCore
import WalletContext
import UIComponents
@testable import UIAssets

@MainActor
final class HomePreparedContentTests: XCTestCase {
    func testAccountRefreshResetsLocalRevealAndPrivacyTogglesStillApply() throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        defer { SettingsStore.liveValue.clean() }
        AppStorageHelper.isSensitiveDataHidden = true
        let mask = WSensitiveData<UILabel>(cols: 12, rows: 2, cellSize: 9,
                                          cornerRadius: 5, theme: .adaptive, alignment: .trailing)
        var visibility: [Bool] = []
        mask.onMaskStateChanged = { visibility.append($0) }
        mask.performTap()
        XCTAssertEqual(visibility, [true, false])
        NotificationCenter.default.post(name: .updateSensitiveData, object: nil)
        XCTAssertEqual(visibility, [true, false, true])
        NotificationCenter.default.post(name: .updateSensitiveData, object: nil)
        XCTAssertEqual(visibility, [true, false, true])
        AppStorageHelper.isSensitiveDataHidden = false
        NotificationCenter.default.post(name: .updateSensitiveData, object: nil)
        XCTAssertEqual(visibility.last, false)
        AppStorageHelper.isSensitiveDataHidden = true
        NotificationCenter.default.post(name: .updateSensitiveData, object: nil)
        XCTAssertEqual(visibility.last, true)
    }

    func testPreparedTokenContentCanMoveBetweenReusableCells() {
        let content = WalletTokenContentView(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        let balance = MTokenBalance(tokenSlug: "prepared-test-token", balance: 7, isStaking: false)
        content.configure(with: balance, animated: false, badgeContent: nil,
                          stakingAccessoryContent: nil, isMultichain: false, isPinned: false)
        let outgoing = WalletTokenCell(frame: content.frame)
        let incoming = WalletTokenCell(frame: content.frame)
        outgoing.host(content)
        incoming.host(content)
        outgoing.prepareForReuse()
        outgoing.host(WalletTokenContentView(frame: content.frame))
        XCTAssertTrue(content.superview === incoming.contentView)
        XCTAssertEqual(incoming.walletToken, balance)
        XCTAssertEqual(incoming.preferredLayoutAttributesFitting(
            UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        ).size.height, 60)
    }

    func testNftPresentationDetectsContentChangesWithStableIdentity() {
        let original = ApiNft.sample
        let presentation = NftCellPresentation(nft: original, domainExpirationText: nil)
        let changes: [(inout ApiNft) -> Void] = [
            { $0.image = "updated-image" },
            { $0.thumbnail = "updated-thumbnail" },
            { $0.name = "Updated name" },
            { $0.isOnSale.toggle() },
            { $0.metadata?.lottie = "updated-animation" },
        ]
        for change in changes {
            var updated = original
            change(&updated)
            XCTAssertEqual(original, updated, "ApiNft equality only compares identity")
            XCTAssertNotEqual(presentation, NftCellPresentation(nft: updated, domainExpirationText: nil))
        }
        XCTAssertNotEqual(presentation, NftCellPresentation(nft: original, domainExpirationText: "Expires tomorrow"))
        XCTAssertEqual(presentation, NftCellPresentation(nft: original, domainExpirationText: nil))
    }

    func testReuseReleasesPreparedContentButKeepsOrdinaryCellContent() throws {
        let prepared = WalletTokenContentView(frame: .zero)
        let cell = WalletTokenCell(frame: .zero)
        cell.host(prepared)
        cell.prepareForReuse()
        XCTAssertNil(prepared.superview)

        cell.configure(with: MTokenBalance(tokenSlug: "reuse-test-token", balance: 1, isStaking: false),
                       animated: false, badgeContent: nil, stakingAccessoryContent: nil,
                       isMultichain: false, isPinned: false)
        let ordinary = try XCTUnwrap(cell.contentView.subviews.first { $0 is WalletTokenContentView })
        cell.prepareForReuse()
        XCTAssertTrue(ordinary.superview === cell.contentView)
    }
}
