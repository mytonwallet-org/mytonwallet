import UIKit
import XCTest
@testable import UIComponents

@MainActor
final class ButtonsToolbarTests: XCTestCase {
    func testActionsHaveEqualWidthsAcrossPhoneSizes() throws {
        let (window, toolbar, buttons) = makeToolbar()
        defer { window.isHidden = true }

        for width: CGFloat in [338, 350, 362, 380, 381] {
            toolbar.frame.size.width = width
            toolbar.setNeedsLayout()
            toolbar.layoutIfNeeded()
            assertEqualWidthsAndSpacing(buttons, in: toolbar)
        }
    }

    func testHiddenActionsDoNotAffectEqualWidths() throws {
        let (window, toolbar, buttons) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.frame.size.width = 289

        for hidden in [true, false] {
            buttons[1].isHidden = hidden
            toolbar.update()
            toolbar.layoutIfNeeded()
            assertEqualWidthsAndSpacing(buttons.filter { !$0.isHidden }, in: toolbar)
        }
    }

    func testWideToolbarKeepsButtonsCappedAndCentered() throws {
        let (window, toolbar, buttons) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.frame.size.width = 600
        toolbar.setNeedsLayout()
        toolbar.layoutIfNeeded()

        assertEqualWidthsAndSpacing(buttons, in: toolbar)
        XCTAssertEqual(buttons[0].bounds.width, ButtonsToolbar.preferredItemWidth, accuracy: 0.01)
    }

    private func makeToolbar() -> (UIWindow, ButtonsToolbar, [WScalableButton]) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 900))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let toolbar = ButtonsToolbar(frame: CGRect(x: 20, y: 100, width: 380, height: WScalableButton.preferredHeight))
        toolbar.spacing = 10
        controller.view.addSubview(toolbar)
        let buttons = ["Пополнить", "Отправить", "Торговля", "Стейкинг"].map {
            WScalableButton(title: $0, image: nil, style: .plain)
        }
        buttons.forEach(toolbar.addArrangedSubview)
        toolbar.layoutIfNeeded()
        return (window, toolbar, buttons)
    }

    private func assertEqualWidthsAndSpacing(
        _ buttons: [WScalableButton],
        in toolbar: ButtonsToolbar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frames = buttons.map { $0.convert($0.bounds, to: toolbar) }
        guard let first = frames.first, let last = frames.last else {
            return XCTFail("Expected visible actions", file: file, line: line)
        }
        for frame in frames {
            XCTAssertEqual(frame.width, first.width, accuracy: 0.01, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minX, -0.01, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, toolbar.bounds.width + 0.01, file: file, line: line)
        }
        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(right.minX - left.maxX, toolbar.spacing, accuracy: 0.01, file: file, line: line)
        }
        // UIKit may place an odd leftover pixel on either side of the centered row.
        let pixel = 1 / max(1, toolbar.traitCollection.displayScale)
        XCTAssertEqual(first.minX, toolbar.bounds.width - last.maxX, accuracy: pixel + 0.01, file: file, line: line)
    }
}
