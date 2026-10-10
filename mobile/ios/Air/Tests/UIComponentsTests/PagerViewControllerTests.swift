import SwiftUI
import UIKit
import XCTest
@testable import UIComponents

@MainActor
final class PagerViewControllerTests: XCTestCase {
    func testRenderedPagesMeetWithoutAGapThroughoutSwipe() async throws {
        for rtl in [false, true] {
            let pager = WPagerViewController(pages: [UIColor.red, .blue].enumerated().map { index, color in
                .init(id: String(index)) {
                    let controller = UIViewController()
                    controller.view.backgroundColor = color
                    return controller
                }
            })
            pager.view.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            pager.view.backgroundColor = .green
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = pager
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            let width = pager.view.bounds.width
            pager.beginAdditionalPaging()
            for progress in [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1] {
                pager.updateAdditionalPaging(translation: (rtl ? 1 : -1) * width * progress)
                try await Task.sleep(for: .milliseconds(50))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let layer = try XCTUnwrap(pager.view.layer.presentation())
                let image = UIGraphicsImageRenderer(bounds: pager.view.bounds, format: format).image { context in
                    layer.render(in: context.cgContext)
                }
                let bitmap = try XCTUnwrap(image.cgImage)
                var pixels = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
                try pixels.withUnsafeMutableBytes { storage in
                    let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: bitmap.width, height: bitmap.height,
                        bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                    context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
                }
                for fraction in [0.05, 0.2, 0.4, 0.6, 0.8, 0.95] {
                    let pixel = ((bitmap.height / 2) * bitmap.width + Int(CGFloat(bitmap.width) * fraction)) * 4
                    let isDestination = rtl ? fraction < progress : fraction > 1 - progress
                    XCTAssertEqual(pixels[pixel], isDestination ? 0 : 255, accuracy: 2, "Red at x=\(fraction), progress=\(progress), rtl=\(rtl)")
                    XCTAssertEqual(pixels[pixel + 1], 0, accuracy: 2, "Gap at x=\(fraction), progress=\(progress), rtl=\(rtl)")
                    XCTAssertEqual(pixels[pixel + 2], isDestination ? 255 : 0, accuracy: 2, "Blue at x=\(fraction), progress=\(progress), rtl=\(rtl)")
                }
            }
            pager.endAdditionalPaging(translation: 0, velocity: 0, cancelled: true)
        }
    }

    func testFactoriesAndViewsAreLazyAndNonAdjacentSelectionSkipsMiddle() async throws {
        let fixture = Fixture()
        XCTAssertTrue(fixture.created.isEmpty)
        let window = fixture.show()
        defer { window.isHidden = true }
        XCTAssertEqual(fixture.created, [0])
        XCTAssertEqual(fixture.pager.children.count, 1)

        fixture.pager.select(index: 2, animated: true)
        XCTAssertEqual(fixture.created, [0, 2])
        XCTAssertEqual(fixture.pager.children.count, 2)
        XCTAssertEqual(fixture.pager.selectedIndex, 2)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(fixture.pager.children, [fixture.controllers[2]!])
        XCTAssertNil(fixture.controllers[0]?.view.window)
        XCTAssertEqual(fixture.controllers[0]?.events, ["willAppear", "didAppear", "willDisappear", "didDisappear"])
        XCTAssertEqual(fixture.controllers[2]?.events, ["willAppear", "didAppear"])
    }

    func testPreparationIsStagedAndDoesNotPresentInactivePages() async throws {
        let fixture = Fixture(preloadsPages: true)
        fixture.pager.loadViewIfNeeded()
        fixture.pager.prepareNextPage()
        XCTAssertEqual(fixture.created, [0])
        let window = fixture.show()
        defer { window.isHidden = true }
        var callbacks = 0
        fixture.pager.onSelectionChanged = { _ in callbacks += 1 }
        fixture.pager.onProgressChanged = { _ in callbacks += 1 }

        fixture.pager.prepareNextPage()
        XCTAssertEqual(fixture.created, [0, 1])
        XCTAssertEqual(fixture.controllers[1]?.events, [])
        // The next page is prepared automatically on a later idle turn.
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(fixture.created, [0, 1, 2])
        XCTAssertEqual(fixture.controllers[2]?.events, [])
        XCTAssertEqual(callbacks, 0)
        for index in 0..<3 {
            let host = try XCTUnwrap(fixture.controllers[index]?.view.superview)
            XCTAssertEqual(host.isHidden, index != 0)
            XCTAssertEqual(host.isUserInteractionEnabled, index == 0)
            XCTAssertEqual(host.accessibilityElementsHidden, index != 0)
        }
    }

    func testPreparedDirectJumpSkipsMiddleAppearanceAndReusesHosts() async throws {
        for rtl in [false, true] {
            let fixture = Fixture(preloadsPages: true)
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            fixture.pager.prepareNextPage()
            fixture.pager.prepareNextPage()
            let first = try XCTUnwrap(fixture.controllers[0])
            let middle = try XCTUnwrap(fixture.controllers[1])
            let last = try XCTUnwrap(fixture.controllers[2])
            let firstHost = first.view.superview
            let lastHost = last.view.superview
            first.scrollView.contentOffset.y = 123
            var progress: [WPagerViewController.Progress] = []
            fixture.pager.onProgressChanged = { progress.append($0) }

            fixture.pager.select(index: 2, animated: true)
            XCTAssertEqual(fixture.pager.scrollView.contentSize.width, fixture.pager.view.bounds.width * 2)
            XCTAssertTrue(middle.view.superview!.isHidden)
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertEqual(fixture.pager.selectedIndex, 2)
            XCTAssertTrue(progress.allSatisfy { $0.source != 1 && $0.destination != 1 })
            XCTAssertTrue(progress.contains { $0.logicalOffset > 0 && $0.logicalOffset < 2 })
            XCTAssertEqual(middle.events, [])
            XCTAssertEqual(last.events, ["willAppear", "didAppear"])
            XCTAssertEqual(fixture.pager.children.count, 3)
            fixture.pager.select(index: 0, animated: false)
            XCTAssertTrue(first.view.superview === firstHost)
            XCTAssertTrue(last.view.superview === lastHost)
            XCTAssertEqual(first.scrollView.contentOffset.y, 123)
            XCTAssertEqual(fixture.created, [0, 1, 2])
            XCTAssertTrue(fixture.controllers.values.allSatisfy { $0.mountCount == 1 })
        }
    }

    func testPreparationPausesDuringNavigationAndDisappearance() async throws {
        let fixture = Fixture(preloadsPages: true)
        let window = fixture.show()
        defer { window.isHidden = true }
        fixture.pager.select(index: 2, animated: true)
        fixture.pager.prepareNextPage()
        XCTAssertEqual(fixture.created, [0, 2])
        try await Task.sleep(for: .milliseconds(350))
        fixture.pager.beginAppearanceTransition(false, animated: false)
        fixture.pager.endAppearanceTransition()
        try await Task.sleep(for: .milliseconds(200))
        fixture.pager.prepareNextPage()
        XCTAssertEqual(fixture.created, [0, 2])
        fixture.pager.beginAppearanceTransition(true, animated: false)
        fixture.pager.endAppearanceTransition()
        fixture.pager.isPagingEnabled = false
        fixture.pager.prepareNextPage()
        XCTAssertEqual(fixture.created, [0, 2])
        fixture.pager.isPagingEnabled = true
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(fixture.created, [0, 2, 1])
        XCTAssertEqual(fixture.controllers[1]?.events, [])
    }

    func testScrollingPreparedPagesDoesNotRelayoutTheirContent() async throws {
        for rtl in [false, true] {
            let fixture = Fixture(preloadsPages: true)
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            let pager = fixture.pager
            pager.prepareNextPage()
            pager.prepareNextPage()
            let scroll = pager.scrollView!
            let start = scroll.contentOffset.x
            let step = scroll.bounds.width * (rtl ? -1 : 1)
            pager.scrollViewWillBeginDragging(scroll)
            scroll.contentOffset.x = start + step * 0.1
            // Let destination appearance and its first layout finish before measuring
            // the steady swipe, including the prepared but invisible third page.
            try await Task.sleep(for: .milliseconds(100))
            window.layoutIfNeeded()
            fixture.controllers.values.forEach { $0.layoutCount = 0 }
            for fraction in stride(from: 0.15, through: 0.85, by: 0.05) {
                scroll.contentOffset.x = start + step * fraction
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(16))
            }
            for (index, controller) in fixture.controllers {
                XCTAssertEqual(controller.layoutCount, 0, "Page \(index), rtl=\(rtl)")
            }
            scroll.contentOffset.x = start + step
            pager.scrollViewDidEndDragging(scroll, willDecelerate: false)
        }
    }

    func testRetainedPagesBalanceCancelledAndReversedAppearance() {
        let fixture = Fixture(preloadsPages: true)
        let window = fixture.show()
        defer { window.isHidden = true }
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        fixture.pager.prepareNextPage()
        fixture.pager.prepareNextPage()
        fixture.pager.select(index: 1, animated: false)
        fixture.pager.beginAdditionalPaging()
        fixture.pager.updateAdditionalPaging(translation: -300)
        fixture.pager.updateAdditionalPaging(translation: 100)
        fixture.pager.endAdditionalPaging(translation: 100, velocity: 1000, cancelled: true)
        XCTAssertEqual(fixture.pager.selectedIndex, 1)
        XCTAssertEqual(fixture.pager.children.count, 3)
        XCTAssertEqual(fixture.controllers[1]?.events.last, "didAppear")
        for index in [0, 2] {
            XCTAssertEqual(fixture.controllers[index]?.events.last, "didDisappear")
            XCTAssertTrue(fixture.controllers[index]!.view.superview!.isHidden)
        }
    }

    func testMemoryPressureDetachesInactiveHostsWithoutLosingControllerState() async throws {
        let fixture = Fixture(preloadsPages: true)
        let window = fixture.show()
        defer { window.isHidden = true }
        fixture.pager.prepareNextPage()
        fixture.pager.prepareNextPage()
        let first = try XCTUnwrap(fixture.controllers[0])
        first.scrollView.contentOffset.y = 123
        fixture.pager.select(index: 2, animated: true)
        fixture.pager.didReceiveMemoryWarning()
        XCTAssertEqual(fixture.pager.children.count, 2)
        XCTAssertNil(fixture.controllers[1]?.parent)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(fixture.pager.children, [fixture.controllers[2]!])
        fixture.pager.prepareNextPage()
        XCTAssertEqual(fixture.pager.children.count, 1)
        fixture.pager.select(index: 0, animated: false)
        XCTAssertEqual(fixture.pager.children, [first])
        XCTAssertEqual(first.scrollView.contentOffset.y, 123)
        XCTAssertEqual(fixture.created, [0, 1, 2])
        XCTAssertEqual(fixture.controllers[1]?.events, [])
    }

    func testSelectionBeforeViewLoadingOnlyCreatesRequestedPage() {
        let fixture = Fixture()
        fixture.pager.select(index: 2, animated: true)
        XCTAssertFalse(fixture.pager.isViewLoaded)
        XCTAssertTrue(fixture.created.isEmpty)
        let window = fixture.show()
        defer { window.isHidden = true }
        XCTAssertEqual(fixture.created, [2])
        XCTAssertEqual(fixture.pager.children, [fixture.controllers[2]!])
    }

    func testIdleOffsetAndResizeDoNotStartNavigation() {
        for rtl in [false, true] {
            let fixture = Fixture()
            fixture.pager.select(index: 2, animated: false)
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            var progressCount = 0
            fixture.pager.onProgressChanged = { _ in progressCount += 1 }
            let events = fixture.controllers[2]!.events

            fixture.pager.scrollView.contentOffset.x += rtl ? 100 : -100
            fixture.root.view.frame.size.width = 700
            fixture.pager.view.frame = fixture.root.view.bounds
            fixture.pager.view.layoutIfNeeded()

            XCTAssertEqual(fixture.created, [2])
            XCTAssertEqual(fixture.pager.children, [fixture.controllers[2]!])
            XCTAssertEqual(fixture.controllers[2]!.events, events)
            XCTAssertEqual(progressCount, 0)
            XCTAssertEqual(fixture.pager.selectedIndex, 2)
        }
    }

    func testNativeDragKeepsReportingProgressThroughDeceleration() {
        for rtl in [false, true] {
            let fixture = Fixture()
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            let scrollView = fixture.pager.scrollView!
            let start = scrollView.contentOffset.x
            let distance = scrollView.bounds.width * (rtl ? -1 : 1)
            var progress: [WPagerViewController.Progress] = []
            fixture.pager.onProgressChanged = { progress.append($0) }

            fixture.pager.scrollViewWillBeginDragging(scrollView)
            scrollView.contentOffset.x = start + distance * 0.3
            fixture.pager.scrollViewDidEndDragging(scrollView, willDecelerate: true)
            scrollView.contentOffset.x = start + distance * 0.8
            XCTAssertEqual(progress.last?.destination, 1)
            XCTAssertEqual(progress.last?.fraction ?? 0, 0.8, accuracy: 0.01)
            scrollView.contentOffset.x = start + distance
            XCTAssertEqual(fixture.controllers[1]?.events.last, "willAppear")
            fixture.pager.scrollViewDidEndDecelerating(scrollView)

            XCTAssertEqual(fixture.pager.selectedIndex, 1)
            XCTAssertEqual(fixture.controllers[0]?.events.last, "didDisappear")
            XCTAssertEqual(fixture.controllers[1]?.events.last, "didAppear")
            let count = progress.count
            scrollView.contentOffset.x += distance * 0.2
            XCTAssertEqual(progress.count, count)
            XCTAssertEqual(fixture.created, [0, 1])
        }
    }

    func testRegrabbingNativeDecelerationPreservesPositionAndIgnoresItsOldCompletion() {
        for rtl in [false, true] {
            let fixture = Fixture(preloadsPages: true)
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            let pager = fixture.pager
            let scroll = pager.scrollView!
            let start = scroll.contentOffset.x
            let step = scroll.bounds.width * (rtl ? -1 : 1)
            var progress: CGFloat = 0
            var selections: [Int] = []
            pager.onProgressChanged = { progress = $0.logicalOffset }
            pager.onSelectionChanged = { selections.append($0) }
            pager.scrollViewWillBeginDragging(scroll)
            scroll.contentOffset.x = start + step * 0.35
            pager.scrollViewDidEndDragging(scroll, willDecelerate: true)
            scroll.contentOffset.x = start + step * 0.8
            let before = scroll.contentOffset
            pager.scrollViewWillBeginDragging(scroll)
            XCTAssertEqual(scroll.contentOffset, before)
            XCTAssertEqual(progress, 0.8, accuracy: 0.001)
            // A completion belonging to the retired deceleration cannot settle the new drag.
            pager.scrollViewDidEndDecelerating(scroll)
            XCTAssertEqual(scroll.contentOffset, before)
            XCTAssertTrue(selections.isEmpty)
            scroll.contentOffset.x = start
            pager.scrollViewDidEndDragging(scroll, willDecelerate: false)
            XCTAssertEqual(selections, [0])
            XCTAssertEqual(pager.selectedIndex, 0)
            XCTAssertEqual(progress, 0, accuracy: 0.001)
        }
    }

    func testFastNativeSwipeUsesTheVisiblePairAcrossMultipleBoundaries() throws {
        for rtl in [false, true] {
            let fixture = Fixture(preloadsPages: true)
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            let pager = fixture.pager
            let scroll = pager.scrollView!
            let start = scroll.contentOffset.x
            let step = scroll.bounds.width * (rtl ? -1 : 1)
            var progress: CGFloat = 0
            pager.onProgressChanged = { progress = $0.logicalOffset }
            pager.scrollViewWillBeginDragging(scroll)
            for position in [0.2, 0.9, 1.1, 1.8, 1.4, 0.8, 0.1, 1.6] {
                scroll.contentOffset.x = start + step * position
                XCTAssertEqual(progress, position, accuracy: 0.001)
                let visible = fixture.controllers.filter { $0.value.view.superview?.isHidden == false }.keys
                XCTAssertEqual(Set(visible), [Int(floor(position)), Int(ceil(position))])
            }
            pager.scrollViewDidEndDragging(scroll, willDecelerate: true)
            scroll.contentOffset.x = start + step * 2
            let before = scroll.contentOffset
            pager.scrollViewDidEndDecelerating(scroll)
            XCTAssertEqual(scroll.contentOffset, before, "Native page coordinates must not recenter at rest")
            XCTAssertEqual(pager.selectedIndex, 2)
            XCTAssertEqual(fixture.controllers[2]?.events.last, "didAppear")
            for index in [0, 1] {
                XCTAssertEqual(fixture.controllers[index]?.events.last, "didDisappear")
                XCTAssertTrue(try XCTUnwrap(fixture.controllers[index]?.view.superview).isHidden)
            }
        }
    }

    func testContentAndToolbarCanInterruptDirectJumpWithoutSnapping() async throws {
        for rtl in [false, true] {
            for toolbar in [false, true] {
                let fixture = Fixture(preloadsPages: true)
                let window = fixture.show(rtl: rtl)
                defer { window.isHidden = true }
                let pager = fixture.pager
                let scroll = pager.scrollView!
                var logical: CGFloat = 0
                pager.onProgressChanged = { logical = $0.logicalOffset }
                pager.select(index: 2, animated: true)
                try await Task.sleep(for: .milliseconds(80))
                let before = scroll.contentOffset
                let beforeLogical = logical
                if toolbar { pager.beginAdditionalPaging() }
                else { pager.scrollViewWillBeginDragging(scroll) }
                XCTAssertEqual(scroll.contentOffset, before)
                XCTAssertEqual(logical, beforeLogical, accuracy: 0.001)
                // The old display-link completion must not finish the interrupted jump.
                try await Task.sleep(for: .milliseconds(350))
                XCTAssertEqual(scroll.contentOffset, before)
                if toolbar {
                    let sourceOffset: CGFloat = rtl ? scroll.bounds.width : 0
                    let translation = before.x - sourceOffset
                    pager.updateAdditionalPaging(translation: translation)
                    pager.endAdditionalPaging(translation: translation, velocity: 0, cancelled: false)
                } else {
                    scroll.contentOffset.x = rtl ? scroll.bounds.width : 0
                    pager.scrollViewDidEndDragging(scroll, willDecelerate: false)
                }
                XCTAssertEqual(pager.selectedIndex, 0)
                XCTAssertEqual(fixture.controllers[0]?.events.last, "didAppear")
                XCTAssertFalse(fixture.created.contains(1))
            }
        }
    }

    func testResizeResolvesAnInterruptedGestureUsingItsPreviousViewportWidth() {
        for rtl in [false, true] {
            let fixture = Fixture(preloadsPages: true)
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            let pager = fixture.pager
            let scroll = pager.scrollView!
            let start = scroll.contentOffset.x
            let step = scroll.bounds.width * (rtl ? -1 : 1)
            pager.scrollViewWillBeginDragging(scroll)
            scroll.contentOffset.x = start + step * 0.8
            fixture.root.view.frame.size.width = 700
            pager.view.frame = fixture.root.view.bounds
            pager.view.layoutIfNeeded()
            XCTAssertEqual(pager.selectedIndex, 1)
            XCTAssertEqual(fixture.controllers[1]?.view.bounds.width, 700)
            XCTAssertEqual(fixture.controllers[1]?.events.last, "didAppear")
            // The cancelled gesture cannot commit its old destination after resizing.
            pager.scrollViewDidEndDragging(scroll, willDecelerate: true)
            pager.scrollViewDidEndDecelerating(scroll)
            XCTAssertEqual(pager.selectedIndex, 1)
        }
    }

    func testSettlingPreservesAsymmetricInsetsBeforeAndAfterAppearance() async throws {
        for rtl in [false, true] {
            let fixture = Fixture(preloadsPages: true)
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            fixture.root.additionalSafeAreaInsets = .init(top: 11, left: rtl ? 84 : 0, bottom: 24, right: rtl ? 0 : 84)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            fixture.pager.prepareNextPage()
            fixture.pager.prepareNextPage()
            let insets = fixture.pager.view.safeAreaInsets
            let margins = fixture.pager.view.layoutMargins
            func check(_ index: Int) {
                let page = fixture.controllers[index]!
                XCTAssertEqual(page.view.safeAreaInsets, insets)
                XCTAssertEqual(page.view.layoutMargins, margins)
                XCTAssertEqual(page.hosting.view.safeAreaInsets, insets)
                XCTAssertEqual(page.hosting.rootView.margins.left, max(0, margins.left - insets.left), accuracy: 0.5)
                XCTAssertEqual(page.hosting.rootView.margins.right, max(0, margins.right - insets.right), accuracy: 0.5)
            }
            for index in [1, 2, 0, 2, 1, 0] {
                fixture.controllers[index]!.onDidAppear = { check(index) }
                fixture.pager.select(index: index, animated: true)
                for _ in 0..<16 {
                    try await Task.sleep(for: .milliseconds(25))
                    window.layoutIfNeeded()
                    for (visibleIndex, page) in fixture.controllers where page.view.superview?.isHidden == false {
                        check(visibleIndex)
                    }
                }
                check(index)
                fixture.controllers[index]!.onDidAppear = nil
            }
        }
    }

    func testAnimatedToolbarFlickMountsDestinationAfterRelease() async throws {
        let fixture = Fixture()
        let window = fixture.show()
        defer { window.isHidden = true }
        fixture.pager.beginAdditionalPaging()
        // A fast flick can release before a scroll callback has mounted the destination.
        fixture.pager.endAdditionalPaging(translation: -10, velocity: -3000, cancelled: false)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(fixture.pager.selectedIndex, 1)
        XCTAssertEqual(fixture.created, [0, 1])
        XCTAssertEqual(fixture.controllers[1]?.events, ["willAppear", "didAppear"])
    }

    func testCancelledAndReversedDragBalancesAppearanceAndKeepsScrollState() {
        let fixture = Fixture()
        let window = fixture.show()
        defer { window.isHidden = true }
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        fixture.pager.select(index: 1, animated: false)
        let middle = fixture.controllers[1]!
        middle.scrollView.contentOffset.y = 123
        middle.events.removeAll()

        fixture.pager.beginAdditionalPaging()
        fixture.pager.updateAdditionalPaging(translation: -300)
        XCTAssertEqual(fixture.pager.selectedIndex, 1)
        XCTAssertEqual(fixture.pager.children.count, 2)
        fixture.pager.updateAdditionalPaging(translation: 100)
        XCTAssertNil(fixture.controllers[2]?.parent)
        XCTAssertEqual(fixture.pager.children.count, 2)
        fixture.pager.endAdditionalPaging(translation: 100, velocity: 1000, cancelled: true)
        XCTAssertEqual(fixture.pager.selectedIndex, 1)
        XCTAssertEqual(fixture.pager.children, [middle])
        XCTAssertEqual(middle.events.last, "didAppear")
        XCTAssertEqual(fixture.controllers[0]?.events.last, "didDisappear")
        XCTAssertEqual(fixture.controllers[2]?.events.last, "didDisappear")
        XCTAssertEqual(middle.scrollView.contentOffset.y, 123)
    }

    func testToolbarFlickAndCancellationInBothDirections() {
        for rtl in [false, true] {
            let fixture = Fixture()
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            UIView.setAnimationsEnabled(false)
            defer { UIView.setAnimationsEnabled(true) }
            var progress: [WPagerViewController.Progress] = []
            fixture.pager.onProgressChanged = { progress.append($0) }
            let sign: CGFloat = rtl ? 1 : -1
            fixture.pager.beginAdditionalPaging()
            fixture.pager.updateAdditionalPaging(translation: sign * 50)
            XCTAssertEqual(progress.last?.source, 0)
            XCTAssertEqual(progress.last?.destination, 1)
            fixture.pager.endAdditionalPaging(translation: sign * 50, velocity: sign * 5000, cancelled: false)
            XCTAssertEqual(fixture.pager.selectedIndex, 1)
            XCTAssertEqual(fixture.created, [0, 1])

            fixture.pager.beginAdditionalPaging()
            fixture.pager.updateAdditionalPaging(translation: sign * 300)
            fixture.pager.endAdditionalPaging(translation: sign * 300, velocity: sign * 5000, cancelled: true)
            XCTAssertEqual(fixture.pager.selectedIndex, 1)
            XCTAssertEqual(fixture.pager.children, [fixture.controllers[1]!])
        }
    }

    func testRapidSelectionAndResizeCannotCompleteAnObsoleteTransition() async throws {
        let fixture = Fixture()
        let window = fixture.show()
        defer { window.isHidden = true }
        var selections: [Int] = []
        fixture.pager.onSelectionChanged = { selections.append($0) }
        fixture.pager.select(index: 2, animated: true)
        try await Task.sleep(for: .milliseconds(40))
        fixture.pager.select(index: 0, animated: true)
        fixture.root.view.frame.size.width = 700
        fixture.pager.view.frame = fixture.root.view.bounds
        fixture.pager.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(fixture.pager.selectedIndex, 0)
        XCTAssertEqual(fixture.pager.children, [fixture.controllers[0]!])
        XCTAssertFalse(selections.contains(2))
        XCTAssertFalse(fixture.created.contains(1))
        XCTAssertEqual(fixture.controllers[0]?.view.bounds.width, 700)
        XCTAssertEqual(fixture.controllers[0]?.events.last, "didAppear")
    }

    func testNativeAndSwiftUIInsetsStayStableThroughSwipesAndResizes() async throws {
        for rtl in [false, true] {
            let fixture = Fixture(preloadsPages: true)
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            fixture.pager.prepareNextPage()
            fixture.pager.prepareNextPage()
            UIView.setAnimationsEnabled(false)
            defer { UIView.setAnimationsEnabled(true) }
            for (width, left, right) in [(402.0, 0.0, 0.0), (466, 84, 0), (466, 0, 84), (951, 0, 84)] {
                fixture.root.additionalSafeAreaInsets = .init(top: 11, left: left, bottom: 24, right: right)
                window.frame.size.width = width
                fixture.root.view.frame = window.bounds
                fixture.pager.view.frame = fixture.root.view.bounds
                window.layoutIfNeeded()
                // Let UIKit complete the window geometry change before starting a new gesture.
                try await Task.sleep(for: .milliseconds(150))
                window.layoutIfNeeded()
                let parentInsets = fixture.pager.view.safeAreaInsets
                let parentMargins = fixture.pager.view.layoutMargins
                for start in [0, 2, 1] {
                    fixture.pager.select(index: start, animated: false)
                    try await Task.sleep(for: .milliseconds(50))
                    window.layoutIfNeeded()
                    fixture.pager.beginAdditionalPaging()
                    for translation in [-width * 0.6, width * 0.3, 0] {
                        fixture.pager.updateAdditionalPaging(translation: translation)
                        window.layoutIfNeeded()
                        try await Task.sleep(for: .milliseconds(30))
                        window.layoutIfNeeded()
                        for child in fixture.pager.children {
                            let page = try XCTUnwrap(child as? Content)
                            let context = "width=\(width), left=\(left), right=\(right), rtl=\(rtl), start=\(start), drag=\(translation), page=\(fixture.controllers.first { $0.value === page }!.key)"
                            XCTAssertEqual(page.view.bounds.size, fixture.pager.view.bounds.size, context)
                            if page.view.superview!.isHidden { continue }
                            XCTAssertEqual(page.view.safeAreaInsets, parentInsets, context)
                            XCTAssertEqual(page.view.layoutMargins, parentMargins, context)
                            XCTAssertEqual(page.additionalSafeAreaInsets, .zero, context)
                            XCTAssertTrue(page.viewRespectsSystemMinimumLayoutMargins, context)
                            XCTAssertEqual(page.hosting.view.safeAreaInsets, page.view.safeAreaInsets, context)
                            XCTAssertEqual(page.hosting.rootView.margins.left, max(0, parentMargins.left - parentInsets.left), accuracy: 0.5, context)
                            XCTAssertEqual(page.hosting.rootView.margins.right, max(0, parentMargins.right - parentInsets.right), accuracy: 0.5, context)
                            let native = page.view.layoutMarginsGuide.layoutFrame
                            let swiftUI = page.marker.convert(page.marker.bounds, to: page.view)
                            XCTAssertEqual(swiftUI.minX, native.minX, accuracy: 1, context)
                            XCTAssertEqual(swiftUI.maxX, native.maxX, accuracy: 1, context)
                        }
                    }
                    fixture.pager.endAdditionalPaging(translation: 0, velocity: 0, cancelled: true)
                }
            }
        }
    }

    func testPreparedPageResolvesInsetsBeforeItsFirstFrameAfterResize() async throws {
        let fixture = Fixture(preloadsPages: true)
        let window = fixture.show()
        defer { window.isHidden = true }
        fixture.pager.prepareNextPage()
        fixture.pager.prepareNextPage()
        for (index, left, right) in [(2, 84.0, 0.0), (1, 0.0, 84.0)] {
            let isCovered = index == 1
            if isCovered {
                fixture.pager.beginAppearanceTransition(false, animated: false)
                fixture.pager.endAppearanceTransition()
            }
            fixture.root.additionalSafeAreaInsets = .init(top: 11, left: left, bottom: 24, right: right)
            window.frame.size.width = 700
            fixture.root.view.frame = window.bounds
            fixture.pager.view.frame = fixture.root.view.bounds
            window.layoutIfNeeded()
            // Complete the external window resize before testing a page's first frame.
            try await Task.sleep(for: .milliseconds(150))
            window.layoutIfNeeded()
            let expectedInsets = fixture.pager.view.safeAreaInsets
            let expectedMargins = fixture.pager.view.layoutMargins
            let content = try XCTUnwrap(fixture.controllers[index])
            var didCheck = false
            content.onDidAppear = {
                didCheck = true
                XCTAssertEqual(content.view.safeAreaInsets, expectedInsets)
                XCTAssertEqual(content.view.layoutMargins, expectedMargins)
                XCTAssertEqual(content.hosting.view.safeAreaInsets, expectedInsets)
            }
            fixture.pager.select(index: index, animated: false)
            if isCovered {
                fixture.pager.beginAppearanceTransition(true, animated: false)
                fixture.pager.endAppearanceTransition()
            }
            XCTAssertTrue(didCheck)
            content.onDidAppear = nil
        }
    }

    func testChildOwnedInsetsAndMarginPolicyAreNotOverwritten() {
        let fixture = Fixture()
        let window = fixture.show()
        defer { window.isHidden = true }
        let first = fixture.controllers[0]!
        first.additionalSafeAreaInsets = .init(top: 0, left: 7, bottom: 64, right: 3)
        first.viewRespectsSystemMinimumLayoutMargins = false
        first.view.directionalLayoutMargins = .init(top: 0, leading: 31, bottom: 0, trailing: 25)
        let margins = first.view.directionalLayoutMargins
        fixture.pager.select(index: 2, animated: false)
        fixture.pager.select(index: 0, animated: false)
        XCTAssertEqual(first.additionalSafeAreaInsets, .init(top: 0, left: 7, bottom: 64, right: 3))
        XCTAssertFalse(first.viewRespectsSystemMinimumLayoutMargins)
        XCTAssertEqual(first.view.directionalLayoutMargins, margins)
    }

    func testSelectionDuringContainerAppearanceBalancesChildCallbacks() {
        let fixture = Fixture()
        fixture.pager.loadViewIfNeeded()
        fixture.pager.beginAppearanceTransition(true, animated: true)
        fixture.pager.select(index: 2, animated: false)
        fixture.pager.endAppearanceTransition()
        XCTAssertEqual(fixture.controllers[0]?.events, ["willAppear", "willDisappear", "didDisappear"])
        XCTAssertEqual(fixture.controllers[2]?.events, ["willAppear", "didAppear"])
        XCTAssertEqual(fixture.created, [0, 2])

        fixture.pager.beginAppearanceTransition(false, animated: true)
        fixture.pager.select(index: 1, animated: false)
        fixture.pager.endAppearanceTransition()
        XCTAssertEqual(fixture.controllers[2]?.events, ["willAppear", "didAppear", "willDisappear", "didDisappear"])
        XCTAssertEqual(fixture.controllers[1]?.events, [])
        fixture.pager.beginAppearanceTransition(true, animated: false)
        fixture.pager.endAppearanceTransition()
        XCTAssertEqual(fixture.controllers[1]?.events, ["willAppear", "didAppear"])
    }

    func testDisablingPagingCancelsDragAndCanBeMirroredFromSelectionCallback() {
        let fixture = Fixture()
        let window = fixture.show()
        defer { window.isHidden = true }
        fixture.pager.beginAdditionalPaging()
        fixture.pager.updateAdditionalPaging(translation: -200)
        var completions = 0
        fixture.pager.onSelectionChanged = { _ in
            completions += 1
            // The root reapplies the Wallet Assets editing state from this callback.
            fixture.pager.isPagingEnabled = false
        }
        fixture.pager.isPagingEnabled = false
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(fixture.pager.selectedIndex, 0)
        XCTAssertEqual(fixture.pager.children, [fixture.controllers[0]!])
        XCTAssertFalse(fixture.pager.scrollView.isScrollEnabled)
        fixture.pager.onSelectionChanged = nil
        fixture.pager.isPagingEnabled = true
        XCTAssertTrue(fixture.pager.scrollView.isScrollEnabled)
    }

    func testForwardNavigationAndToolbarGestureStayAvailable() {
        for rtl in [false, true] {
            let fixture = Fixture()
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
            let toolbar = UIView()
            var enabled = true
            var attempts = 0
            let nativePan = fixture.pager.scrollView.panGestureRecognizer
            let nativeDelegate = nativePan.delegate
            fixture.pager.setAdditionalPagingGestureView(toolbar)
            fixture.pager.setForwardNavigation(in: fixture.root.view, allowsEdgeNavigation: true,
                beginTransition: { attempts += 1; return nil }, isEnabled: { enabled })
            XCTAssertTrue(nativePan.view === fixture.pager.scrollView)
            XCTAssertTrue(nativePan.delegate === nativeDelegate)
            XCTAssertNotNil(toolbar.gestureRecognizers?.first as? WSegmentedPagingGesture)
            let forward: CGFloat = rtl ? 300 : -300
            XCTAssertFalse(fixture.pager.canBeginForwardNavigation(velocity: forward))
            _ = fixture.pager.beginForwardNavigation(velocity: .init(x: forward, y: 0), fromEdge: true)
            XCTAssertEqual(attempts, 1)
            enabled = false
            _ = fixture.pager.beginForwardNavigation(velocity: .init(x: forward, y: 0), fromEdge: true)
            XCTAssertEqual(attempts, 1)
            fixture.pager.select(index: 2, animated: false)
            XCTAssertTrue(fixture.pager.canBeginForwardNavigation(velocity: forward))
            fixture.pager.isPagingEnabled = false
            XCTAssertFalse(fixture.pager.canBeginForwardNavigation(velocity: forward))
        }
    }

    private final class Fixture {
        var created: [Int] = []
        var controllers: [Int: Content] = [:]
        let root = UIViewController()
        let preloadsPages: Bool

        init(preloadsPages: Bool = false) { self.preloadsPages = preloadsPages }

        lazy var pager = WPagerViewController(pages: (0..<3).map { index in
            .init(id: String(index)) { [unowned self] in
                created.append(index)
                let controller = Content()
                controllers[index] = controller
                return controller
            }
        }, preloadsPages: preloadsPages)

        func show(rtl: Bool = false) -> UIWindow {
            root.addChild(pager)
            root.view.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            pager.view.semanticContentAttribute = root.view.semanticContentAttribute
            if #available(iOS 17.0, *) {
                root.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
            }
            root.view.addSubview(pager.view)
            pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            pager.didMove(toParent: root)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = root
            window.makeKeyAndVisible()
            root.view.frame = window.bounds
            pager.view.frame = root.view.bounds
            window.layoutIfNeeded()
            return window
        }
    }

    private final class Content: UIViewController {
        var events: [String] = []
        var mountCount = 0
        var layoutCount = 0
        var onDidAppear: (() -> Void)?
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { mountCount += 1 }
        }
        let scrollView = UIScrollView()
        let marker = UIView()
        lazy var hosting = LayoutMarginsHostingController(rootView: MarginContent(marker: marker))
        override func viewDidLoad() {
            super.viewDidLoad()
            view.addSubview(scrollView)
            scrollView.frame = view.bounds
            scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scrollView.contentSize = CGSize(width: 0, height: 3000)
            addChild(hosting)
            view.addSubview(hosting.view)
            hosting.view.frame = view.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hosting.didMove(toParent: self)
        }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); events.append("willAppear") }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layoutCount += 1 }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); events.append("didAppear"); onDidAppear?() }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); events.append("willDisappear") }
        override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); events.append("didDisappear") }
    }
}

private struct MarginContent: View {
    @Environment(\.horizontalContentMargins) private var margins
    let marker: UIView
    var body: some View { Marker(view: marker).frame(height: 32).padding(margins) }
}

private struct Marker: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
