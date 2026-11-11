import Dependencies
import UIComponents
import UIKit
import WalletContext
import WalletCore
import WalletResources
import XCTest
@testable import UIActivityList

@MainActor
final class ActivityTimestampUpdateTests: XCTestCase, ActivityCell.Delegate {
    func testHomeTimestampChangesAfterTwelveHoursWithoutReconfiguringTheCell() throws {
        _ = WalletResourcesBundle.bundle.load()
        let calendar = LocalizationSupport.shared.calendar
        let day = calendar.startOfDay(for: .now)
        let timestamp = try XCTUnwrap(calendar.date(byAdding: .hour, value: 22, to: day))
        let transition = timestamp.addingTimeInterval(12 * 60 * 60 + 1)
        let address = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"
        let account = MAccount(id: "date-update-mainnet", title: "Dates", type: .view, byChain: [.ton: .init(address: address)])
        let activity = ApiActivity.transaction(ApiTransactionActivity(
            id: "date-update", kind: "transaction", externalMsgHashNorm: nil,
            timestamp: Int64(timestamp.timeIntervalSince1970 * 1000), amount: 0, fromAddress: address, toAddress: address,
            comment: nil, encryptedComment: nil, fee: 0, slug: "toncoin", isIncoming: true,
            normalizedAddress: address, type: nil, metadata: nil, nft: nil, status: .confirmed
        ))
        let cell = ActivityCell(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        withDependencies { $0.context = .live } operation: {
            cell.configure(with: activity, accountContext: AccountContext(source: .constant(account)),
                           delegate: self, timestampDisplayMode: .dateWhenOlderThanTwelveHours)
        }
        let title = cell.titleLabel.text
        let before = transition.addingTimeInterval(-1)
        XCTAssertEqual(cell.updateDate(relativeTo: before), transition)
        let timeText = ActivityDateFormatting.timestampText(for: timestamp, mode: .timeOnly, relativeTo: before)
        XCTAssertTrue(cell.detailsLabel.attributedText?.string.hasSuffix(timeText) == true)
        XCTAssertNil(cell.updateDate(relativeTo: transition))
        let dateText = ActivityDateFormatting.shortDateText(for: timestamp, relativeTo: transition)
        XCTAssertTrue(cell.detailsLabel.attributedText?.string.hasSuffix(dateText) == true)
        XCTAssertEqual(cell.titleLabel.text, title)

        cell.configureSkeleton()
        XCTAssertNil(cell.updateDate(relativeTo: before))
        cell.prepareForReuse()
        cell.detailsLabel.text = "Reused"
        cell.updateDate(relativeTo: .distantFuture)
        XCTAssertEqual(cell.detailsLabel.text, "Reused")
    }

    func onSelect(transaction: ApiActivity) {}
}
