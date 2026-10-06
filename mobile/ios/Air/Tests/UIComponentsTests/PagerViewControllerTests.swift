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
            let fixture = Fixture()
            let window = fixture.show(rtl: rtl)
            defer { window.isHidden = true }
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
                            let context = "width=\(width), left=\(left), right=\(right), rtl=\(rtl), start=\(start), drag=\(translation)"
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
        lazy var pager = WPagerViewController(pages: (0..<3).map { index in
            .init(id: String(index)) { [unowned self] in
                created.append(index)
                let controller = Content()
                controllers[index] = controller
                return controller
            }
        })

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
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); events.append("didAppear") }
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
