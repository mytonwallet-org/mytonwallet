import UIKit
import WalletContext
import XCTest
@testable import UIComponents

@MainActor
final class ActivityDateRefreshTests: XCTestCase {
    func testMidnightUpdatesRetainedHeaderWithoutReconfiguringOrMovingRows() async throws {
        let calendar = LocalizationSupport.shared.calendar
        let day = calendar.startOfDay(for: .now)
        var now = day.addingTimeInterval(12 * 60 * 60)
        let fixture = DateRefreshFixture(day: day)
        defer { fixture.window.isHidden = true }
        fixture.collection.contentOffset.y = 60
        fixture.collection.layoutIfNeeded()
        let controller = ActivityDateRefreshController(collectionView: fixture.collection, getCurrentDate: { now })
        controller.start()
        try await Task.sleep(for: .milliseconds(20))
        let header = try XCTUnwrap(fixture.collection.visibleSupplementaryViews(
            ofKind: UICollectionView.elementKindSectionHeader
        ).first as? ActivityDateCell)
        let label = try XCTUnwrap(header.contentView.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(label.text, lang("Today"))
        let configurationCount = fixture.configurationCount
        let cells = Set(fixture.collection.visibleCells.map(ObjectIdentifier.init))
        let offset = fixture.collection.contentOffset

        now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(label.text, ActivityDateFormatting.dateText(for: day, relativeTo: now))
        XCTAssertEqual(fixture.configurationCount, configurationCount)
        XCTAssertEqual(Set(fixture.collection.visibleCells.map(ObjectIdentifier.init)), cells)
        XCTAssertEqual(fixture.collection.contentOffset, offset)
        XCTAssertNil(controller.timer)
    }

    func testOneShotTimerCoalescesUpdatesAndStopsWithVisibilityAndApplicationState() async throws {
        var now = Date()
        let fixture = DateRefreshFixture(day: now)
        defer { fixture.window.isHidden = true }
        let cells = fixture.collection.visibleCells.compactMap { $0 as? DateRefreshCell }
        XCTAssertGreaterThan(cells.count, 1)
        cells[0].transition = now.addingTimeInterval(60)
        cells[1].transition = now.addingTimeInterval(120)
        var controller: ActivityDateRefreshController? = ActivityDateRefreshController(
            collectionView: fixture.collection, getCurrentDate: { now }
        )
        weak var weakController = controller
        controller?.start()
        for _ in 0..<10 { controller?.setNeedsUpdate() }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(cells[0].updateCount, 1)
        XCTAssertEqual(controller?.nextUpdateDate, cells[0].transition)
        let timer = try XCTUnwrap(controller?.timer)
        controller?.setNeedsUpdate()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(controller?.timer === timer)

        now = now.addingTimeInterval(10)
        NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(20))
        let adjustedTimer = try XCTUnwrap(controller?.timer)
        XCTAssertFalse(timer.isValid)
        XCTAssertFalse(adjustedTimer === timer)
        XCTAssertEqual(controller?.nextUpdateDate, cells[0].transition)

        now = try XCTUnwrap(cells[0].transition)
        adjustedTimer.fire()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller?.nextUpdateDate, cells[1].transition)
        XCTAssertNotNil(controller?.timer)

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        let updateCount = cells[0].updateCount
        controller?.setNeedsUpdate()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(controller?.timer)
        XCTAssertEqual(cells[0].updateCount, updateCount)
        now = try XCTUnwrap(cells[1].transition)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertGreaterThan(cells[0].updateCount, updateCount)
        XCTAssertNil(controller?.timer)

        cells[0].transition = now.addingTimeInterval(60)
        controller?.setNeedsUpdate()
        try await Task.sleep(for: .milliseconds(20))
        let pendingTimer = try XCTUnwrap(controller?.timer)
        controller?.stop()
        controller?.setNeedsUpdate()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(pendingTimer.isValid)
        XCTAssertNil(controller?.timer)
        controller?.start()
        try await Task.sleep(for: .milliseconds(20))
        let finalTimer = try XCTUnwrap(controller?.timer)
        controller = nil
        XCTAssertNil(weakController)
        XCTAssertFalse(finalTimer.isValid)
    }

    func testDateHeaderReusePreservesCustomTitlesAndSkeletons() {
        let header = ActivityDateCell(frame: .zero)
        header.configure(with: .now)
        header.configure(title: "Activity")
        header.updateDate(relativeTo: .distantFuture)
        let label = header.contentView.subviews.compactMap { $0 as? UILabel }.first
        XCTAssertEqual(label?.text, "Activity")
        header.configure(with: .now)
        header.configureSkeleton()
        header.updateDate(relativeTo: .distantFuture)
        XCTAssertEqual(label?.alpha, 0)
        XCTAssertEqual(label?.text, "AAAA")
    }
}

@MainActor
private final class DateRefreshFixture {
    let window: UIWindow
    let collection: UICollectionView
    private var source: UICollectionViewDiffableDataSource<Int, Int>!
    private(set) var configurationCount = 0

    init(day: Date) {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 60)
        layout.headerReferenceSize = CGSize(width: 300, height: 40)
        layout.sectionHeadersPinToVisibleBounds = true
        collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 400), collectionViewLayout: layout)
        window = UIWindow(frame: collection.frame)
        let host = UIViewController()
        host.view = collection
        window.rootViewController = host
        let registration = UICollectionView.CellRegistration<DateRefreshCell, Int> { [weak self] _, _, _ in
            self?.configurationCount += 1
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<ActivityDateCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, _ in header.configure(with: day) }
        source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collection) { collection, indexPath, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
        source.supplementaryViewProvider = { collection, _, indexPath in
            collection.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(0..<15))
        source.apply(snapshot, animatingDifferences: false)
        window.makeKeyAndVisible()
        collection.layoutIfNeeded()
    }
}

@MainActor
private final class DateRefreshCell: UICollectionViewCell, ActivityDateDisplaying {
    var transition: Date?
    private(set) var updateCount = 0

    func updateDate(relativeTo now: Date) -> Date? {
        updateCount += 1
        return transition.flatMap { $0 > now ? $0 : nil }
    }
}
