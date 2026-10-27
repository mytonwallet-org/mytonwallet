import UIKit
import XCTest
import WalletCore
import WalletResources
@testable import UISettings

@MainActor
final class ChainVisibilityCellTests: XCTestCase {
    func testNewAndReusedRowsDoNotInheritLayoutAnimations() throws {
        for isReused in [false, true] {
            let (window, cell, title) = try makeCell()
            defer { window.isHidden = true }
            if isReused {
                configure(cell, showsReorderControl: false)
                cell.isDisplaying = true
                cell.prepareForReuse()
            }

            UIView.animate(withDuration: 1) {
                self.configure(cell, showsReorderControl: true)
            }

            XCTAssertEqual(title.frame.minX, 92, accuracy: 0.5)
            XCTAssertTrue(title.layer.animationKeys()?.isEmpty ?? true,
                          "A row entering the list must start at its final position (reused: \(isReused))")
        }
    }

    func testPreparedOffscreenRowDoesNotAnimateADeferredSortModeChange() throws {
        let (window, cell, title) = try makeCell()
        defer { window.isHidden = true }
        configure(cell, showsReorderControl: false)

        configure(cell, showsReorderControl: true)

        XCTAssertEqual(title.frame.minX, 92, accuracy: 0.5)
        XCTAssertTrue(title.layer.animationKeys()?.isEmpty ?? true)
    }

    func testVisibleSortModeChangesStillAnimateInBothDirections() throws {
        for showsReorderControl in [false, true] {
            let (window, cell, title) = try makeCell()
            defer { window.isHidden = true }
            configure(cell, showsReorderControl: !showsReorderControl)
            cell.isDisplaying = true

            configure(cell, showsReorderControl: showsReorderControl)

            XCTAssertEqual(title.frame.minX, showsReorderControl ? 92 : 56, accuracy: 0.5)
            XCTAssertFalse(title.layer.animationKeys()?.isEmpty ?? true,
                           "Changing Sort by Value must animate the visible row")
        }
    }

    private func makeCell() throws -> (UIWindow, ChainVisibilityCell, UILabel) {
        _ = WalletResourcesBundle.bundle.load()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        let cell = ChainVisibilityCell(frame: CGRect(x: 16, y: 160, width: 358, height: 60))
        controller.view.addSubview(cell)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        cell.layoutIfNeeded()
        let title = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? UILabel }.first)
        return (window, cell, title)
    }

    private func configure(_ cell: ChainVisibilityCell, showsReorderControl: Bool) {
        cell.configure(
            chain: .polygon,
            isVisible: true,
            isSwitchEnabled: showsReorderControl,
            showsReorderControl: showsReorderControl,
            usesAutomaticAppearance: !showsReorderControl,
            onVisibilityChange: { _ in },
            onReorderGesture: { _ in }
        )
    }
}
