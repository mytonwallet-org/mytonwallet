import ContextMenuKit
import Kingfisher
import XCTest
import UIKit
@testable import UIAgent
@testable import UIComponents
import WalletContext
import WalletCore
import WalletResources

/// News pictures open in the media viewer, which pages through them as Telegram's gallery does
@MainActor
final class AgentMediaViewerTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// A tap on a card's picture opens the viewer at it, over all the feed's loaded pictures in the feed's order
    func testCardPictureOpensTheViewerOverTheFeedsPicturesInOrder() async throws {
        let items = [
            makeNewsItem(1, imageURL: "invalid-news-image://1"),
            makeNewsItem(2),
            makeNewsItem(3, imageURL: "invalid-news-image://3"),
            makeNewsItem(4, imageURL: "invalid-news-image://4"),
        ]
        let feed = TestFeed(page: .init(locale: "en", items: items.reversed()))
        defer { feed.close() }
        func findCard() -> AgentNewsFeedCardCell? {
            feed.controller.collectionView.visibleCells.first { $0.accessibilityIdentifier == "AgentNewsCard-3" } as? AgentNewsFeedCardCell
        }
        try await feed.waitUntil { findCard() != nil }
        let card = try XCTUnwrap(findCard())
        card.onPictureTap?(card.newsView.imageView)
        let viewer = try XCTUnwrap(feed.window.subviews.compactMap { $0 as? MediaViewer }.first)
        XCTAssertTrue(viewer.accessibilityViewIsModal)
        XCTAssertEqual(viewer.currentIndex, 1)
        // A swipe pages on, as far as the last picture
        XCTAssertTrue(viewer.accessibilityScroll(.left))
        XCTAssertEqual(viewer.currentIndex, 2)
        XCTAssertFalse(viewer.accessibilityScroll(.left))
        viewer.showPicture(at: 0)
        XCTAssertEqual(viewer.currentIndex, 0)
        XCTAssertFalse(viewer.accessibilityScroll(.right))

        var isClosed = false
        viewer.onClose = { isClosed = true }
        XCTAssertTrue(viewer.accessibilityPerformEscape())
        try await feed.waitUntil { isClosed && viewer.superview == nil }
    }

    /// The viewer stands its picture at the picture's proportions in its middle, zoomable as an NFT
    func testViewerFitsThePictureAndZoomsAsTheNftViewer() async throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: [.init(url: nil, image: makePicture(), title: "Headline")],
            index: 0,
            in: window,
            source: { _ in nil }
        ))
        viewer.layoutIfNeeded()
        let zoom = try XCTUnwrap(findDescendants(of: viewer).compactMap { $0 as? MediaZoomView }.first)
        XCTAssertEqual(zoom.fittedSize.width, window.bounds.width, accuracy: 0.5)
        XCTAssertEqual(zoom.fittedSize.height, window.bounds.width * 90 / 160, accuracy: 0.5)
        XCTAssertEqual(zoom.maximumZoomScale, 4)
        let picture = zoom.contentContainerView.convert(zoom.contentContainerView.bounds, to: viewer)
        XCTAssertEqual(picture.midY, viewer.bounds.midY, accuracy: 1)
        XCTAssertTrue(findDescendants(of: viewer).contains { $0.accessibilityLabel == "Headline" && $0.accessibilityTraits.contains(.image) })
        viewer.close()
    }

    /// The viewer opens out of the list's picture, which gives way to it. A swipe pages to the next picture, whose list
    /// picture gives way in turn, and closing flies the shown picture back into its place in the list.
    func testViewerFliesOutOfTheListPictureAndBackIntoTheShownOne() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion fades the viewer in and out")
        let list = UIViewController()
        let window = makeKeyWindow(showing: list)
        defer { window.isHidden = true }
        let sources = (0..<2).map { index in
            let source = UIImageView(image: makePicture())
            source.frame = CGRect(x: 20, y: 120 + CGFloat(index) * 200, width: 320, height: 180)
            source.layer.cornerRadius = 19
            list.view.addSubview(source)
            return source
        }
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: sources.indices.map { .init(url: nil, image: sources[$0].image, title: "Picture \($0)") },
            index: 0,
            in: window,
            source: { sources[$0] }
        ))
        XCTAssertEqual(sources[0].alpha, 0)
        XCTAssertNotNil(findFlight(in: viewer))
        try await waitUntil { findFlight(in: viewer) == nil }
        XCTAssertEqual(sources[0].alpha, 0)

        let pager = try XCTUnwrap(viewer.subviews.first { $0 is UIScrollView } as? UIScrollView)
        pager.contentOffset.x = pager.bounds.width
        XCTAssertEqual(viewer.currentIndex, 1)
        XCTAssertEqual(sources[0].alpha, 1)
        XCTAssertEqual(sources[1].alpha, 0)
        XCTAssertEqual(viewer.headerView.titleLabel.text, L10n.agentWalletPageIndicator(current: 2, total: 2))

        var isClosed = false
        viewer.onClose = { isClosed = true }
        viewer.close()
        let closing = try XCTUnwrap(findFlight(in: viewer))
        let target = sources[1].convert(sources[1].bounds, to: viewer)
        XCTAssertEqual(closing.frame.minX, target.minX, accuracy: 0.5)
        XCTAssertEqual(closing.frame.minY, target.minY, accuracy: 0.5)
        XCTAssertEqual(closing.frame.width, target.width, accuracy: 0.5)
        XCTAssertEqual(closing.frame.height, target.height, accuracy: 0.5)
        XCTAssertEqual(closing.layer.cornerRadius, 19)
        try await waitUntil { isClosed && viewer.superview == nil }
        XCTAssertEqual(sources.map(\.alpha), [1, 1])
    }

    /// The picture flying out of a list keeps under the list's header until the viewer's backdrop covers the header,
    /// and flying back keeps under it again as the backdrop goes, so the header is never drawn under a picture that
    /// isn't full screen yet. A list without a header leaves the flight whole.
    func testFlightKeepsUnderTheListHeaderUntilTheViewerCoversIt() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion fades the viewer in and out")
        let list = UIViewController()
        let window = makeKeyWindow(showing: list)
        defer { window.isHidden = true }
        let scrollView = UIScrollView(frame: list.view.bounds)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset.top = 100
        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: 2000)
        scrollView.contentOffset.y = -100
        list.view.addSubview(scrollView)
        // The list's picture reaches under its header
        let source = UIImageView(image: makePicture())
        source.frame = CGRect(x: 20, y: -40, width: 320, height: 180)
        scrollView.addSubview(source)
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: [.init(url: nil, image: makePicture(), title: "Picture")],
            index: 0,
            in: window,
            source: { _ in source }
        ))
        defer { viewer.removeFromSuperview() }
        XCTAssertNotNil(findFlight(in: viewer))
        let opening = try XCTUnwrap(viewer.flightHeaderMaskState)
        XCTAssertEqual(opening.height, 100, accuracy: 0.5)
        XCTAssertEqual(opening.opacity, 1, "The header is fully covered once the backdrop is")
        try await waitUntil { findFlight(in: viewer) == nil }
        XCTAssertNil(viewer.flightHeaderMaskState, "The full-screen viewer covers the header")

        var isClosed = false
        viewer.onClose = { isClosed = true }
        viewer.close()
        XCTAssertNotNil(findFlight(in: viewer))
        let closing = try XCTUnwrap(viewer.flightHeaderMaskState)
        XCTAssertEqual(closing.height, 100, accuracy: 0.5)
        XCTAssertEqual(closing.opacity, 0, "The header shows over the picture once the backdrop is gone")
        try await waitUntil { isClosed }

        let plain = UIImageView(image: makePicture())
        plain.frame = CGRect(x: 20, y: 200, width: 320, height: 180)
        list.view.addSubview(plain)
        let other = try XCTUnwrap(MediaViewer.present(
            pictures: [.init(url: nil, image: makePicture(), title: "Picture")],
            index: 0,
            in: window,
            source: { _ in plain }
        ))
        defer { other.removeFromSuperview() }
        XCTAssertNotNil(findFlight(in: other))
        XCTAssertNil(other.flightHeaderMaskState)
    }

    /// The list's header always has the picture under its glass: a copy of the flight inside the list, over its content
    /// and under its header, stands in for the list's picture from the first frame and moves with the flight until the
    /// viewer's backdrop has covered the header, and as the viewer closes it flies back under the header until the
    /// list's picture shows again, as Telegram's gallery flies a copy on the chat's transition surface
    func testListHeaderKeepsThePictureUnderItsGlassAsTheViewerOpensAndCloses() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion fades the viewer in and out")
        let list = ListUnderHeader()
        defer { list.window.isHidden = true }
        let viewer = try list.presentViewer()
        defer { viewer.removeFromSuperview() }
        func checkCopyFollowsTheFlight(_ phase: String) {
            guard let copy = viewer.surfaceCopy, let flight = findFlight(in: viewer) else { return }
            let copyFrame = list.getShownFrame(of: copy)
            let flightFrame = list.getShownFrame(of: flight)
            XCTAssertEqual(copyFrame.minX, flightFrame.minX, accuracy: 1, phase)
            XCTAssertEqual(copyFrame.minY, flightFrame.minY, accuracy: 1, phase)
            XCTAssertEqual(copyFrame.width, flightFrame.width, accuracy: 1, phase)
            XCTAssertEqual(copyFrame.height, flightFrame.height, accuracy: 1, phase)
        }

        // From the first frame the copy stands in for the hidden list picture, over the list's content and under its
        // header
        XCTAssertEqual(list.source.alpha, 0)
        let opening = try XCTUnwrap(viewer.surfaceCopy)
        let subviews = list.controller.view.subviews
        XCTAssertEqual(subviews.firstIndex(of: opening), try XCTUnwrap(subviews.firstIndex(of: list.scrollView)) + 1)
        XCTAssertLessThan(try XCTUnwrap(subviews.firstIndex(of: opening)), try XCTUnwrap(subviews.firstIndex(of: list.header)))
        var sampledOpening = 0
        while findFlight(in: viewer) != nil, sampledOpening < 200 {
            try await Task.sleep(for: .milliseconds(8))
            sampledOpening += 1
            if list.getBackdrop(of: viewer) < 0.99 {
                XCTAssertNotNil(viewer.surfaceCopy?.superview, "The header has the picture under it until the backdrop covers it")
            }
            checkCopyFollowsTheFlight("Opening")
        }
        XCTAssertGreaterThan(sampledOpening, 5)
        XCTAssertNil(viewer.surfaceCopy)
        XCTAssertNil(opening.superview)
        XCTAssertEqual(list.source.alpha, 0)
        XCTAssertEqual(list.getBackdrop(of: viewer), 1, accuracy: 0.01)

        var isClosed = false
        viewer.onClose = { isClosed = true }
        viewer.close()
        let closing = try XCTUnwrap(viewer.surfaceCopy)
        XCTAssertTrue(closing.superview === list.controller.view)
        var sampledClosing = 0
        while !isClosed, sampledClosing < 300 {
            try await Task.sleep(for: .milliseconds(8))
            sampledClosing += 1
            XCTAssertTrue(viewer.surfaceCopy?.superview != nil || list.source.alpha == 1, "The header has a picture under it on every frame")
            checkCopyFollowsTheFlight("Closing")
        }
        XCTAssertTrue(isClosed)
        XCTAssertGreaterThan(sampledClosing, 5)
        XCTAssertEqual(list.source.alpha, 1)
        XCTAssertNil(closing.superview)
    }

    /// The viewer's bars come over the list's as its backdrop covers them, and go as it uncovers them, as Telegram's
    /// gallery brings its bars and its backdrop in together over 0.15 s and takes them away over 0.1 s: on every frame
    /// the bars, the backdrop and the flight's part over the list's header are as far along as each other, so the two
    /// bars' capsules are never both at full strength
    func testViewerBarsComeOverTheListsAsTheBackdropCoversThem() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion fades the viewer in and out")
        let list = ListUnderHeader()
        defer { list.window.isHidden = true }
        let viewer = try list.presentViewer()
        defer { viewer.removeFromSuperview() }
        func getBars() -> CGFloat {
            let content = viewer.headerView.titleGlass.contentView
            return CGFloat(content.layer.presentation()?.opacity ?? content.layer.opacity)
        }
        func checkFrame(_ phase: String, barsAccuracy: CGFloat) {
            let backdrop = list.getBackdrop(of: viewer)
            if let shown = viewer.shownFlightHeaderOpacity {
                XCTAssertEqual(CGFloat(shown), backdrop, accuracy: 0.1, "\(phase): the flight shows over the header as the backdrop covers it")
            }
            XCTAssertEqual(getBars(), backdrop, accuracy: barsAccuracy, "\(phase): the viewer's bars come and go with the backdrop over the list's")
        }
        var sampled: [CGFloat] = []
        while findFlight(in: viewer) != nil, sampled.count < 200 {
            try await Task.sleep(for: .milliseconds(8))
            sampled.append(list.getBackdrop(of: viewer))
            checkFrame("Opening", barsAccuracy: 0.1)
        }
        XCTAssertTrue(sampled.contains { $0 > 0.1 && $0 < 0.9 }, "Frames are sampled while the backdrop comes")
        XCTAssertEqual(MediaViewer.appearanceDuration, 0.15)
        XCTAssertEqual(MediaViewer.disappearanceDuration, 0.1)

        var isClosed = false
        viewer.onClose = { isClosed = true }
        viewer.close()
        var sampledClosing = 0
        while !isClosed, sampledClosing < 300 {
            try await Task.sleep(for: .milliseconds(8))
            sampledClosing += 1
            // The bars go on Telegram's ease-in-out curve beside the backdrop's linear one
            if !isClosed { checkFrame("Closing", barsAccuracy: 0.2) }
        }
        XCTAssertTrue(isClosed)
    }

    /// As in Telegram's gallery, a tap at the left or right edge pages at once, as far as the first or the last picture,
    /// and a tap elsewhere shows or hides the bars
    func testEdgeTapsPageAndATapElsewhereShowsOrHidesTheBars() throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: (0..<3).map { .init(url: nil, image: makePicture(), title: "Picture \($0)") },
            index: 1,
            in: window,
            source: { _ in nil }
        ))
        defer { viewer.removeFromSuperview() }
        let tap = TapAtPoint()
        tap.point = CGPoint(x: 10, y: viewer.bounds.midY)
        for expectedIndex in [0, 0] {
            viewer.handleEdgeTap(tap)
            XCTAssertEqual(viewer.currentIndex, expectedIndex)
        }
        tap.point.x = viewer.bounds.width - 10
        for expectedIndex in [1, 2, 2] {
            viewer.handleEdgeTap(tap)
            XCTAssertEqual(viewer.currentIndex, expectedIndex)
        }
        tap.point.x = viewer.bounds.midX
        viewer.handleEdgeTap(tap)
        XCTAssertEqual(viewer.currentIndex, 2)

        XCTAssertFalse(viewer.isChromeHidden)
        viewer.handleTap(tap)
        XCTAssertTrue(viewer.isChromeHidden)
        viewer.handleTap(tap)
        XCTAssertFalse(viewer.isChromeHidden)
    }

    /// As in Telegram's gallery, the edge under a finger darkens while the finger stays down and still, and only on a
    /// side with a picture beyond it
    func testPressedEdgeDarkensUntilTheFingerLiftsOrMoves() throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: (0..<2).map { .init(url: nil, image: makePicture(), title: "Picture \($0)") },
            index: 0,
            in: window,
            source: { _ in nil }
        ))
        defer { viewer.removeFromSuperview() }
        let left = CGPoint(x: 10, y: viewer.bounds.midY)
        let right = CGPoint(x: viewer.bounds.width - 10, y: viewer.bounds.midY)
        viewer.updateEdgeFade(isTouching: true, at: left)
        XCTAssertEqual(viewer.getEdgeFadeAlpha(side: -1), 0, "No picture lies before the first")
        viewer.updateEdgeFade(isTouching: true, at: right)
        XCTAssertEqual(viewer.getEdgeFadeAlpha(side: 1), 1)
        viewer.updateEdgeFade(isTouching: false, at: right)
        XCTAssertEqual(viewer.getEdgeFadeAlpha(side: 1), 0)
        viewer.updateEdgeFade(isTouching: true, at: CGPoint(x: viewer.bounds.midX, y: viewer.bounds.midY))
        XCTAssertEqual(viewer.getEdgeFadeAlpha(side: 1), 0)

        // The finger counts as lifted once it moves over 2 pt, as Telegram's tap gives up
        let host = UIView(frame: viewer.bounds)
        let recognizer = MediaViewerTouchRecognizer(target: nil, action: nil)
        host.addGestureRecognizer(recognizer)
        let event = UIEvent()
        recognizer.touchesBegan([TouchAtPoint(right, in: host)], with: event)
        XCTAssertTrue(recognizer.isTouching)
        recognizer.touchesMoved([TouchAtPoint(CGPoint(x: right.x - 1.5, y: right.y), in: host)], with: event)
        XCTAssertTrue(recognizer.isTouching)
        recognizer.touchesMoved([TouchAtPoint(CGPoint(x: right.x - 3, y: right.y), in: host)], with: event)
        XCTAssertFalse(recognizer.isTouching)
    }

    /// Telegram's footer heights: a caption up to 100 pt shows whole, a longer one shows 80 pt and scrolls, and pulled
    /// up it rises with the panel until 238 pt of the screen stay above it
    func testFooterLayoutClampsALongCaptionAndPullsItUpAsFarAsThePanelRises() {
        func makeLayout(_ textHeight: CGFloat?, offset: CGFloat = 0) -> MediaViewerFooterLayout {
            MediaViewerFooterLayout(textHeight: textHeight, contentOffsetY: offset, viewHeight: 874, bottomInset: 34)
        }
        XCTAssertEqual(makeLayout(nil).panelHeight, 54 + 34)

        let short = makeLayout(100)
        XCTAssertFalse(short.isScrollable)
        XCTAssertEqual(short.visibleTextHeight, 100)
        XCTAssertEqual(short.panelHeight, 54 + 34 + 100 + 30)
        XCTAssertEqual(short.expandedOffsetY, 0)
        XCTAssertFalse(short.isExpanded(atOffsetY: 0))

        let long = makeLayout(300)
        XCTAssertTrue(long.isScrollable)
        XCTAssertEqual(long.visibleTextHeight, 80)
        XCTAssertEqual(long.panelHeight, 54 + 34 + 80 + 30)
        XCTAssertEqual(long.expandedOffsetY, 300 - 80)
        XCTAssertFalse(long.isExpanded(atOffsetY: 0))
        XCTAssertTrue(long.isExpanded(atOffsetY: 220))

        let pulled = makeLayout(300, offset: 150)
        XCTAssertEqual(pulled.textOffset, 150)
        XCTAssertEqual(pulled.panelHeight, long.panelHeight + 150)

        // A caption longer than the screen rises until 238 pt stay above the panel's rest, and scrolls on from there
        let maxOffset: CGFloat = 874 - 34 - 238
        XCTAssertEqual(makeLayout(2000).expandedOffsetY, maxOffset)
        let scrolledOn = makeLayout(2000, offset: 1000)
        XCTAssertEqual(scrolledOn.textOffset, maxOffset)
        XCTAssertEqual(scrolledOn.panelHeight, long.panelHeight + maxOffset)
        // Telegram's panel stops a screen pixel short of the 238 pt
        let onScreen = MediaViewerFooterLayout(textHeight: 2000, contentOffsetY: 1000, viewHeight: 874, bottomInset: 34, pixel: 1.0 / 3)
        XCTAssertEqual(onScreen.textOffset, maxOffset - 1.0 / 3, accuracy: 0.001)
    }

    /// The bars' shades are Telegram's edge effect: black at 65 % from the screen's edge, fading over the last 120 pt
    /// toward the picture on its curve, which keeps most of the shade through the first fifth of the fade and lets it go
    /// in an S, rather than evenly
    func testShadesFadeOnTelegramsEdgeCurve() throws {
        for isTop in [true, false] {
            let shade = MediaViewerShadeView(isTop: isTop, opacity: 0.65)
            shade.frame = CGRect(x: 0, y: 0, width: 10, height: 200)
            shade.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: shade.bounds.size, format: format).image { context in
                shade.layer.render(in: context.cgContext)
            }
            let cgImage = try XCTUnwrap(image.cgImage)
            let data = try XCTUnwrap(cgImage.dataProvider?.data)
            let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
            func getAlpha(atFade progress: CGFloat) -> CGFloat {
                // `progress` runs from where the fade starts at the screen's side to the picture's end
                let y = isTop ? 80 + progress * 120 : 120 - progress * 120
                let row = min(cgImage.height - 1, max(0, Int(y.rounded(.down))))
                return CGFloat(bytes[row * cgImage.bytesPerRow + 5 * cgImage.bitsPerPixel / 8 + 3]) / 255
            }
            let side = isTop ? "header" : "footer"
            XCTAssertEqual(getAlpha(atFade: -0.3), 0.65, accuracy: 0.02, "\(side): solid at the screen's edge")
            XCTAssertEqual(getAlpha(atFade: 0.2), 0.65 * 0.941, accuracy: 0.03, side)
            XCTAssertEqual(getAlpha(atFade: 0.5), 0.65 * 0.483, accuracy: 0.03, side)
            XCTAssertEqual(getAlpha(atFade: 0.7), 0.65 * 0.136, accuracy: 0.03, side)
            XCTAssertLessThan(getAlpha(atFade: 0.97), 0.03, side)
        }
    }

    /// A tap on a long caption pulls it up as far as the panel rises, its first line at the panel's top, and another
    /// lets it back down
    func testCaptionTapPullsALongCaptionUpAndLetsItBackDown() throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let caption = NSAttributedString(
            string: (1...40).map { "Line \($0)" }.joined(separator: "\n"),
            attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.white]
        )
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: [.init(url: nil, image: makePicture(), title: "Picture", details: .init(
                date: "Today, 10:00", caption: caption, actions: []
            ))],
            index: 0,
            in: window,
            source: { _ in nil }
        ))
        defer { viewer.removeFromSuperview() }
        viewer.layoutIfNeeded()
        let footer = viewer.footerView
        XCTAssertTrue(footer.layout.isScrollable)
        XCTAssertEqual(footer.layout.visibleTextHeight, 80)
        XCTAssertEqual(footer.frame.maxY, viewer.bounds.height, accuracy: 0.5)
        let restingTop = footer.frame.minY
        XCTAssertFalse(footer.isCaptionExpanded)

        // A scroll view's own animation needs a host app, so the caption moves at once here
        let expandedOffsetY = footer.layout.expandedOffsetY
        XCTAssertGreaterThan(expandedOffsetY, 0)
        footer.toggleCaptionExpansion(animated: false)
        XCTAssertEqual(footer.captionScrollView.contentOffset.y, expandedOffsetY, accuracy: 0.5)
        XCTAssertTrue(footer.isCaptionExpanded)
        XCTAssertEqual(footer.frame.minY, restingTop - expandedOffsetY, accuracy: 0.5)
        let captionTop = footer.captionTextView.convert(CGPoint.zero, to: viewer).y
        XCTAssertEqual(captionTop, footer.frame.minY + MediaViewerFooterLayout.captionTopInset, accuracy: 0.5)

        footer.toggleCaptionExpansion(animated: false)
        XCTAssertEqual(footer.captionScrollView.contentOffset.y, 0, accuracy: 0.5)
        XCTAssertFalse(footer.isCaptionExpanded)
        XCTAssertEqual(footer.frame.minY, restingTop, accuracy: 0.5)
    }

    /// "N of M" is the capsule's first line over several pictures, over the date, and stays as they page; a single
    /// picture has no counter, its date alone on the first line
    func testCounterIsTheCapsulesTitleOverSeveralPictures() throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: (0..<3).map {
                .init(url: nil, image: makePicture(), title: "Picture \($0)", details: .init(
                    date: "Today, 10:0\($0)", caption: nil, actions: []
                ))
            },
            index: 1,
            in: window,
            source: { _ in nil }
        ))
        defer { viewer.removeFromSuperview() }
        viewer.layoutIfNeeded()
        let header = viewer.headerView
        XCTAssertEqual(viewer.counterText, L10n.agentWalletPageIndicator(current: 2, total: 3))
        XCTAssertEqual(header.titleLabel.text, viewer.counterText)
        XCTAssertEqual(header.titleLabel.font, MediaViewerHeaderView.titleFont)
        XCTAssertEqual(header.subtitleLabel.text, "Today, 10:01")
        XCTAssertEqual(header.titleGlass.accessibilityLabel, "\(viewer.counterText!), Today, 10:01")
        let title = header.titleLabel.convert(header.titleLabel.bounds, to: header.titleGlass)
        let subtitle = header.subtitleLabel.convert(header.subtitleLabel.bounds, to: header.titleGlass)
        XCTAssertLessThan(title.maxY, subtitle.minY + 0.5)
        XCTAssertEqual(title.minY, header.titleGlass.bounds.height - subtitle.maxY, accuracy: 1)
        // No pill of its own hangs under the capsule
        XCTAssertFalse(header.subviews.contains { $0 is WGlassView && $0 !== header.titleGlass })

        viewer.showPicture(at: 2)
        XCTAssertEqual(header.titleLabel.text, L10n.agentWalletPageIndicator(current: 3, total: 3))
        XCTAssertEqual(header.subtitleLabel.text, "Today, 10:02")
        XCTAssertTrue(header.titleGlass.isMaterialized)

        let single = try XCTUnwrap(MediaViewer.present(
            pictures: [.init(url: nil, image: makePicture(), title: "Picture", details: .init(
                date: "Today, 10:00", caption: nil, actions: []
            ))],
            index: 0,
            in: window,
            source: { _ in nil }
        ))
        defer { single.removeFromSuperview() }
        single.layoutIfNeeded()
        XCTAssertNil(single.counterText)
        XCTAssertEqual(single.headerView.titleLabel.text, "Today, 10:00")
        XCTAssertNil(single.headerView.subtitleLabel.text)
        XCTAssertEqual(single.headerView.titleGlass.accessibilityLabel, "Today, 10:00")
        let lone = single.headerView.titleLabel.convert(single.headerView.titleLabel.bounds, to: single.headerView.titleGlass)
        XCTAssertEqual(lone.midY, single.headerView.titleGlass.bounds.midY, accuracy: 1)
    }

    /// The counter changes only its digits as the pictures page: the text both pages share stays, and only what
    /// differs rolls
    func testCounterChangesOnlyWhatDiffers() {
        func change(_ old: String, _ new: String) -> MediaViewerAnimatedLabel.Change {
            MediaViewerAnimatedLabel.getChange(from: old, to: new)
        }
        XCTAssertEqual(change("5 of 24", "6 of 24"), .init(prefix: "", removed: "5", inserted: "6", suffix: " of 24"))
        XCTAssertEqual(change("11 of 24", "12 of 24"), .init(prefix: "1", removed: "1", inserted: "2", suffix: " of 24"))
        XCTAssertEqual(change("9 of 24", "10 of 24"), .init(prefix: "", removed: "9", inserted: "10", suffix: " of 24"))
        XCTAssertEqual(change("10 of 24", "9 of 24"), .init(prefix: "", removed: "10", inserted: "9", suffix: " of 24"))
        XCTAssertEqual(change("1 of 11", "11 of 11"), .init(prefix: "1", removed: "", inserted: "1", suffix: " of 11"))
        XCTAssertEqual(change("Today, 10:00", "Today, 10:00"), .init(prefix: "Today, 10:00", removed: "", inserted: "", suffix: ""))

        let label = MediaViewerAnimatedLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        window.addSubview(label)
        label.setText("5 of 24", direction: .forward, animated: false)
        XCTAssertEqual(label.runLabels.map(\.text), ["5 of 24"])
        label.setText("6 of 24", direction: .forward, animated: true)
        XCTAssertEqual(label.text, "6 of 24")
        XCTAssertEqual(label.runLabels.map(\.text), ["", "6", " of 24"])
        label.layoutIfNeeded()
        // The parts stand side by side as the whole text would, centred
        let frames = label.runLabels.map(\.frame)
        XCTAssertEqual(frames[1].maxX, frames[2].minX, accuracy: 1)
        XCTAssertEqual(frames[1].minX + frames[2].maxX, label.bounds.width, accuracy: 2)
    }

    /// A tap on the picture slides the bars out and back as Telegram's gallery does, and while they are out their
    /// controls neither show nor take touches nor reach VoiceOver
    func testTapHidesTheBarsAndTheirControls() throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let actions = [
            MediaViewer.Action(title: "Share", image: nil, placement: .leading) { _ in },
            MediaViewer.Action(title: "Copy", image: nil, placement: .trailing) { _ in },
        ]
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: [.init(url: nil, image: makePicture(), title: "Picture", details: .init(
                date: "Today, 10:00", caption: NSAttributedString(string: "Caption"), actions: actions
            ))],
            index: 0,
            in: window,
            source: { _ in nil }
        ))
        defer { viewer.removeFromSuperview() }
        viewer.layoutIfNeeded()
        let header = viewer.headerView
        let footer = viewer.footerView
        let backPoint = header.convert(CGPoint(x: header.backGroup.frame.midX, y: header.backGroup.frame.midY), to: viewer)
        let buttonsPoint = footer.convert(CGPoint(x: footer.trailingGroup.frame.midX, y: footer.trailingGroup.frame.midY), to: viewer)
        let picturePoint = CGPoint(x: viewer.bounds.midX, y: viewer.bounds.midY)
        XCTAssertTrue(viewer.isOnChrome(backPoint))
        XCTAssertTrue(viewer.isOnChrome(buttonsPoint))
        XCTAssertFalse(viewer.isOnChrome(picturePoint))
        XCTAssertTrue(header.backGroup.glassView.isMaterialized)
        XCTAssertTrue(footer.trailingGroup.glassView.isMaterialized)
        XCTAssertEqual(header.backGroup.buttons.first?.accessibilityLabel, lang("Back"))
        XCTAssertEqual(header.titleGlass.accessibilityLabel, "Today, 10:00")
        XCTAssertEqual(footer.leadingGroup.buttons.map(\.accessibilityLabel), ["Share"])
        XCTAssertEqual(footer.trailingGroup.buttons.map(\.accessibilityLabel), ["Copy"])
        XCTAssertLessThan(footer.leadingGroup.frame.minX, footer.trailingGroup.frame.minX)
        let shownFooterY = footer.frame.minY

        let tap = TapAtPoint()
        tap.point = picturePoint
        viewer.handleTap(tap)
        XCTAssertTrue(viewer.isChromeHidden)
        XCTAssertFalse(header.backGroup.glassView.isMaterialized)
        XCTAssertFalse(footer.leadingGroup.glassView.isMaterialized)
        XCTAssertTrue(header.accessibilityElementsHidden)
        XCTAssertTrue(footer.accessibilityElementsHidden)
        XCTAssertFalse(viewer.isOnChrome(backPoint))
        XCTAssertFalse(viewer.isOnChrome(buttonsPoint))
        if !UIAccessibility.isReduceMotionEnabled {
            XCTAssertEqual(header.frame.maxY, 0, accuracy: 0.5)
            XCTAssertEqual(footer.frame.minY, shownFooterY + 54, accuracy: 0.5)
        }

        viewer.handleTap(tap)
        XCTAssertFalse(viewer.isChromeHidden)
        XCTAssertTrue(header.backGroup.glassView.isMaterialized)
        XCTAssertFalse(header.accessibilityElementsHidden)
        XCTAssertEqual(header.frame.minY, 0, accuracy: 0.5)
        XCTAssertEqual(footer.frame.minY, shownFooterY, accuracy: 0.5)
    }

    /// The bars' buttons are Telegram's (`GlassControlGroupComponent`) and the Agent header's: 44 pt squares on 44 pt
    /// glass with no padding of its own, each glyph in its button's middle and as large as Telegram's footer icons draw
    /// theirs, and the footer's groups 8 pt above the home indicator, 8 pt from the sides beside a tall one and 26 pt
    /// beside a short one, as Telegram's
    func testBarButtonsAreTelegramsSizeWithTheirGlyphsInTheirMiddle() throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let item = makeNewsItem(7, imageURL: "invalid-news-image://7")
        let viewer = try XCTUnwrap(AgentNewsPictureViewer.present(
            posts: [.init(content: AgentNewsFeedCardCell.makeContent(for: item), date: .now, image: makePicture(), locale: "en")],
            index: 0,
            in: window,
            openSource: { _ in },
            source: { _ in nil }
        ))
        defer { viewer.removeFromSuperview() }
        viewer.layoutIfNeeded()
        XCTAssertEqual(AgentChatNavigation.buttonSize, MediaViewerButtonGroup.itemSize)
        let header = viewer.headerView
        let footer = viewer.footerView
        let groups = [header.backGroup, header.menuGroup, footer.leadingGroup, footer.trailingGroup]
        XCTAssertEqual(groups.map(\.buttons.count), [1, 1, 1, 1])
        for group in groups {
            group.layoutIfNeeded()
            XCTAssertEqual(group.bounds.size, CGSize(width: 44 * CGFloat(group.buttons.count), height: 44))
            XCTAssertEqual(group.glassView.frame, group.bounds)
            for (index, button) in group.buttons.enumerated() {
                button.layoutIfNeeded()
                XCTAssertEqual(button.frame, CGRect(x: 44 * CGFloat(index), y: 0, width: 44, height: 44))
                let glyph = try XCTUnwrap(button.imageView?.frame)
                let label = button.accessibilityLabel ?? ""
                XCTAssertEqual(glyph.midX, 22, accuracy: 1, label)
                XCTAssertEqual(glyph.midY, 22, accuracy: 1, label)
                // At least 9 pt of glass around the symbol's box on every side
                XCTAssertLessThanOrEqual(max(glyph.width, glyph.height), 26, label)
            }
        }
        // The footer's symbols are drawn at their own size, the 18 pt regular one Telegram's footer icons match
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let names = ["square.and.arrow.up", "doc.on.doc"]
        for (button, name) in zip(footer.leadingGroup.buttons + footer.trailingGroup.buttons, names) {
            let glyph = try XCTUnwrap(button.imageView?.frame)
            let size = try XCTUnwrap(UIImage(systemName: name, withConfiguration: configuration)?.size)
            XCTAssertEqual(glyph.width, size.width, accuracy: 0.5, name)
            XCTAssertEqual(glyph.height, size.height, accuracy: 0.5, name)
        }
        let safeArea = viewer.safeAreaInsets
        let sideInset: CGFloat = safeArea.bottom <= 32 ? 26 : 8
        let leading = footer.convert(footer.leadingGroup.frame, to: viewer)
        let trailing = footer.convert(footer.trailingGroup.frame, to: viewer)
        XCTAssertEqual(leading.minX, safeArea.left + sideInset, accuracy: 0.5)
        XCTAssertEqual(trailing.maxX, viewer.bounds.width - safeArea.right - sideInset, accuracy: 0.5)
        XCTAssertEqual(leading.maxY, viewer.bounds.height - safeArea.bottom - 8, accuracy: 0.5)
        XCTAssertEqual(trailing.maxY, leading.maxY, accuracy: 0.5)
        // With no navigation bar under it, the bar's row stands where a navigation bar starts, under the status bar
        let backFrame = header.convert(header.backGroup.frame, to: viewer)
        let barTop = max(safeArea.top, window.windowScene?.statusBarManager?.statusBarFrame.height ?? 0)
        XCTAssertEqual(backFrame, CGRect(x: safeArea.left + 16, y: barTop, width: 44, height: 44))
    }

    /// The viewer's back button draws the Agent header's back chevron as the header does, in a plain button, which
    /// draws a bar's 17 pt semibold symbol at the large scale: the same glyph at the same size in the same place of
    /// its 44 pt circle
    func testViewerBackButtonDrawsTheAgentHeadersChevron() async throws {
        let screen = try await AgentHeaderScreen()
        defer { screen.window.isHidden = true }
        let viewer = try screen.presentViewer(over: screen.source)
        defer { viewer.removeFromSuperview() }
        let button = try XCTUnwrap(viewer.headerView.backGroup.buttons.first)
        button.layoutIfNeeded()
        let glyph = try XCTUnwrap(button.imageView)
        let glyphFrame = glyph.convert(glyph.bounds, to: viewer.headerView.backGroup)
        let chatGlyphFrame = screen.chatGlyph.convert(screen.chatGlyph.bounds, to: screen.circle)
        XCTAssertEqual(glyphFrame.minX, chatGlyphFrame.minX, accuracy: 0.5)
        XCTAssertEqual(glyphFrame.minY, chatGlyphFrame.minY, accuracy: 0.5)
        XCTAssertEqual(glyphFrame.width, chatGlyphFrame.width, accuracy: 0.5)
        XCTAssertEqual(glyphFrame.height, chatGlyphFrame.height, accuracy: 0.5)
        XCTAssertEqual(glyph.preferredSymbolConfiguration, screen.chatGlyph.preferredSymbolConfiguration)
        // As large as the large-scale 17 pt semibold chevron
        let large = try XCTUnwrap(UIImage(
            systemName: "chevron.backward",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold, scale: .large)
        )?.size)
        XCTAssertEqual(glyphFrame.width, large.width, accuracy: 0.5)
        XCTAssertEqual(glyphFrame.height, large.height, accuracy: 0.5)
    }

    /// The viewer's bar stands where the Agent chat's header stands on the same screen, as Telegram's gallery bar stands
    /// where the chat's does: the back button in the threads button's place and the capsule on the title pill's line.
    /// The navigation bar puts its buttons at its top, 44 pt bars and the 54 pt ones of iOS 26 alike.
    func testViewerBarStandsWhereTheAgentHeaderStands() async throws {
        let screen = try await AgentHeaderScreen()
        defer { screen.window.isHidden = true }
        let chatBack = screen.circle.convert(screen.circle.bounds, to: screen.window)
        let chatPill = screen.pill.convert(screen.pill.bounds, to: screen.window)
        let bar = try XCTUnwrap(screen.chat.navigationController?.navigationBar)
        XCTAssertEqual(chatBack.minY, bar.convert(bar.bounds, to: screen.window).minY, accuracy: 0.5)
        XCTAssertEqual(chatPill.minY, chatBack.minY, accuracy: 0.5)
        XCTAssertEqual(chatPill.height, 44)
        let viewer = try screen.presentViewer(over: screen.source)
        defer { viewer.removeFromSuperview() }
        let header = viewer.headerView
        let back = header.backGroup.convert(header.backGroup.bounds, to: screen.window)
        XCTAssertEqual(back.minX, chatBack.minX, accuracy: 0.5)
        XCTAssertEqual(back.minY, chatBack.minY, accuracy: 0.5)
        XCTAssertEqual(back.size, chatBack.size)
        let capsule = header.titleGlass.convert(header.titleGlass.bounds, to: screen.window)
        XCTAssertEqual(capsule.minY, chatPill.minY, accuracy: 0.5)
        XCTAssertEqual(capsule.height, chatPill.height)
        XCTAssertEqual(capsule.midX, chatPill.midX, accuracy: 1)
    }

    /// The bars fade as a swipe down moves the picture, gone once it has moved 50 pt as in Telegram, and come back as
    /// the picture springs back
    func testSwipeDownFadesTheBars() throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: [.init(url: nil, image: makePicture(), title: "Picture", details: .init(
                date: "Today, 10:00", caption: NSAttributedString(string: "Caption"), actions: []
            ))],
            index: 0,
            in: window,
            source: { _ in nil }
        ))
        defer { viewer.removeFromSuperview() }
        let pan = PanByTranslation()
        pan.fakeState = .changed
        pan.translation = CGPoint(x: 0, y: 20)
        viewer.handleDismissPan(pan)
        XCTAssertEqual(viewer.footerView.captionClipView.alpha, 0.6, accuracy: 0.01)
        XCTAssertTrue(viewer.headerView.titleGlass.isMaterialized)
        pan.translation.y = 30
        viewer.handleDismissPan(pan)
        XCTAssertEqual(viewer.footerView.captionClipView.alpha, 0.4, accuracy: 0.01)
        XCTAssertFalse(viewer.headerView.titleGlass.isMaterialized)
        pan.fakeState = .ended
        viewer.handleDismissPan(pan)
        XCTAssertEqual(viewer.footerView.captionClipView.alpha, 1)
        XCTAssertTrue(viewer.headerView.titleGlass.isMaterialized)
    }

    /// A digest whose headlines have pictures leads each row with a square: the picture, a target of its own that opens
    /// the digest's pictures that load, captioned with their headlines, or the News mark, which opens the row. Without
    /// pictures the rows keep their bullets.
    func testDigestHeadlinePicturesOpenTheViewerApartFromTheirRows() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let imageKeys = [1, 3].map { "https://example.invalid/digest-\($0)-\(UUID().uuidString).png" }
        for key in imageKeys { try await ImageCache.default.store(makePicture(), forKey: key, toDisk: false) }
        defer { for key in imageKeys { ImageCache.default.removeImage(forKey: key, fromDisk: false, completionHandler: nil) } }
        let imageUrls = [imageKeys[0], nil, imageKeys[1], "invalid-news-image://4"]
        let cell = AgentNewsDigestCardCell(frame: CGRect(x: 0, y: 0, width: 375, height: 700))
        window.rootViewController?.view.addSubview(cell)
        cell.configure(with: try makeDigest(imageUrls: imageUrls))
        let view = try XCTUnwrap(findDescendants(of: cell).compactMap { $0 as? AgentNewsDigestHeadlinesView }.first)
        var openedEventIds: [Int] = []
        cell.headlineAction = { openedEventIds.append($0) }
        try await waitUntil { view.thumbnails.allSatisfy { $0.isShowingPicture || $0.hasFailed } }
        cell.layoutIfNeeded()

        XCTAssertTrue(view.hasThumbnails)
        XCTAssertEqual(view.thumbnails.map(\.headline.eventId), [1, 3, 4])
        XCTAssertEqual(view.thumbnails.map(\.hasFailed), [false, false, true])
        // The News mark stands in for the picture of a headline without one and of one whose picture fails
        let rows = view.headlineButtons
        let marks = rows.map { findDescendants(of: $0).compactMap { $0 as? AgentNewsIconView }.filter { !$0.isHidden }.count }
        XCTAssertEqual(marks, [0, 1, 0, 1])
        // Every headline's text stands 12 pt past its 40 pt square
        XCTAssertEqual(findHeadlineLabels(in: view).map { $0.convert($0.bounds, to: view).minX }, [52, 52, 52, 52])
        let picture = view.thumbnails[1].imageView
        XCTAssertEqual(picture.convert(picture.bounds, to: view).size, CGSize(width: 40, height: 40))
        XCTAssertEqual(picture.layer.cornerCurve, .continuous)

        // A tap on a picture keeps to it, and one on the News mark opens the row
        func hit(_ target: UIView) -> UIView? {
            view.hitTest(target.convert(CGPoint(x: target.bounds.midX, y: target.bounds.midY), to: view), with: nil)
        }
        XCTAssertTrue(hit(view.thumbnails[1].button) === view.thumbnails[1].button)
        let mark = try XCTUnwrap(findDescendants(of: rows[1]).compactMap { $0 as? AgentNewsIconView }.first)
        let markTarget = try XCTUnwrap(hit(mark) as? UIControl)
        XCTAssertTrue(markTarget === rows[1])
        markTarget.sendActions(for: .touchUpInside)
        XCTAssertEqual(openedEventIds, [2])

        view.thumbnails[1].button.sendActions(for: .touchUpInside)
        let viewer = try XCTUnwrap(window.subviews.compactMap { $0 as? MediaViewer }.first)
        defer { viewer.removeFromSuperview() }
        XCTAssertEqual(viewer.currentIndex, 1)
        XCTAssertEqual(viewer.counterText, L10n.agentWalletPageIndicator(current: 2, total: 2))
        // Each page is captioned with its own headline alone, without a news post's actions and sources
        XCTAssertEqual(viewer.pictures.map(\.title), ["Headline 1", "Headline 3"])
        XCTAssertEqual(viewer.pictures.map(\.url?.absoluteString), imageKeys)
        XCTAssertEqual(viewer.pictures.map { $0.details?.caption?.string }, ["Headline 1", "Headline 3"])
        XCTAssertTrue(viewer.pictures.allSatisfy { $0.details?.actions.isEmpty == true && $0.details?.menu == nil })
        XCTAssertEqual(viewer.footerView.captionTextView.attributedText.string, "Headline 3")
        XCTAssertTrue(viewer.footerView.leadingGroup.buttons.isEmpty)
        XCTAssertTrue(viewer.footerView.trailingGroup.buttons.isEmpty)
        XCTAssertTrue(viewer.headerView.menuGroup.isHidden)
        XCTAssertEqual(openedEventIds, [2])

        // A digest without pictures keeps its bullets
        cell.prepareForReuse()
        cell.configure(with: try makeDigest(imageUrls: [nil, nil]))
        cell.layoutIfNeeded()
        XCTAssertFalse(view.hasThumbnails)
        XCTAssertTrue(view.thumbnails.isEmpty)
        XCTAssertFalse(findDescendants(of: view).contains { $0 is AgentNewsIconView })
        XCTAssertEqual(findHeadlineLabels(in: view).map { $0.convert($0.bounds, to: view).minX }, [16, 16])
    }

    /// VoiceOver opens a digest's picture once it has loaded through an action named after it and its headline: on the
    /// feed card's row and among the actions of the digest's post, apart from opening the row
    func testDigestPicturesOpenFromAccessibilityActionsOnceLoaded() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let imageKeys = [1, 3].map { "https://example.invalid/digest-actions-\($0)-\(UUID().uuidString).png" }
        for key in imageKeys { try await ImageCache.default.store(makePicture(), forKey: key, toDisk: false) }
        defer { for key in imageKeys { ImageCache.default.removeImage(forKey: key, fromDisk: false, completionHandler: nil) } }
        let digest = try makeDigest(imageUrls: [imageKeys[0], nil, imageKeys[1], "invalid-news-image://4"])
        func pictureActionName(_ eventId: Int) -> String { "\(lang("Picture")), Headline \(eventId)" }
        func findViewer() throws -> MediaViewer { try XCTUnwrap(window.subviews.compactMap { $0 as? MediaViewer }.first) }

        let cell = AgentNewsDigestCardCell(frame: CGRect(x: 0, y: 0, width: 375, height: 700))
        window.rootViewController?.view.addSubview(cell)
        cell.configure(with: digest)
        var openedEventIds: [Int] = []
        cell.headlineAction = { openedEventIds.append($0) }
        let view = try XCTUnwrap(findDescendants(of: cell).compactMap { $0 as? AgentNewsDigestHeadlinesView }.first)
        try await waitUntil { view.thumbnails.allSatisfy { $0.isShowingPicture || $0.hasFailed } }
        // Only the rows whose pictures loaded have the action
        XCTAssertEqual(
            view.headlineButtons.map { $0.accessibilityCustomActions?.map(\.name) ?? [] },
            [[pictureActionName(1)], [], [pictureActionName(3)], []]
        )
        let rowAction = try XCTUnwrap(view.headlineButtons[2].accessibilityCustomActions?.first)
        XCTAssertEqual(rowAction.actionHandler?(rowAction), true)
        let viewer = try findViewer()
        XCTAssertEqual(viewer.currentIndex, 1)
        XCTAssertEqual(viewer.pictures.map(\.title), ["Headline 1", "Headline 3"])
        viewer.removeFromSuperview()
        XCTAssertEqual(openedEventIds, [])

        let post = AgentNewsPostView()
        window.rootViewController?.view.addSubview(post)
        var openedFromPost: [Int] = []
        post.onDigestHeadlineTap = { openedFromPost.append($0) }
        post.configure(with: .init(digest: ApiAgentV2ThreadDigestCard(
            id: digest.id, windowEnd: digest.deliveredAt, total: digest.total, top: digest.top
        )), isHeaderVisible: true)
        let postHeadlines = try XCTUnwrap(findDescendants(of: post).compactMap { $0 as? AgentNewsDigestHeadlinesView }.first)
        try await waitUntil { postHeadlines.thumbnails.allSatisfy { $0.isShowingPicture || $0.hasFailed } }
        let actions = post.accessibilityContentElement.accessibilityCustomActions ?? []
        XCTAssertEqual(actions.map(\.name), [
            lang("More actions"), "Headline 1", pictureActionName(1), "Headline 2", "Headline 3", pictureActionName(3), "Headline 4",
        ])
        let postAction = try XCTUnwrap(actions.first { $0.name == pictureActionName(1) })
        XCTAssertEqual(postAction.actionHandler?(postAction), true)
        let postViewer = try findViewer()
        XCTAssertEqual(postViewer.currentIndex, 0)
        XCTAssertEqual(postViewer.pictures.map(\.title), ["Headline 1", "Headline 3"])
        postViewer.removeFromSuperview()
        XCTAssertEqual(openedFromPost, [])
    }

    /// A news picture shows its post as Telegram's gallery shows a message: the date on the capsule, the headline and the
    /// body as the caption, Share at the footer's leading end and Copy at its trailing one, and the post's sources in a
    /// menu at the header's trailing end
    func testNewsPictureShowsItsPostAroundIt() async throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let item = makeNewsItem(7, imageURL: "invalid-news-image://7")
        let date = AgentV2DateParser.date(item.deliveredAt)
        var openedSources: [String] = []
        let content = AgentNewsFeedCardCell.makeContent(for: item)
        let viewer = try XCTUnwrap(AgentNewsPictureViewer.present(
            posts: [.init(content: content, date: date, image: makePicture(), locale: "en")],
            index: 0,
            in: window,
            openSource: { openedSources.append($0) },
            source: { _ in nil }
        ))
        defer { viewer.removeFromSuperview() }
        let (day, time) = AgentModel.formatChatDate(for: date)
        XCTAssertEqual(viewer.headerView.titleLabel.text, "\(day), \(time)")
        XCTAssertNil(viewer.headerView.subtitleLabel.text)
        XCTAssertEqual(viewer.headerView.titleGlass.accessibilityLabel, "\(day), \(time)")
        let caption = viewer.footerView.captionTextView.attributedText.string
        XCTAssertEqual(caption, "Headline 7\nNews body 7.")
        XCTAssertEqual(viewer.footerView.leadingGroup.buttons.map(\.accessibilityLabel), [lang("Share")])
        XCTAssertEqual(viewer.footerView.trailingGroup.buttons.map(\.accessibilityLabel), [lang("Copy")])
        XCTAssertNil(viewer.counterText)
        let header = viewer.headerView
        XCTAssertFalse(header.menuGroup.isHidden)
        XCTAssertEqual(header.menuGroup.buttons.map(\.accessibilityLabel), [lang("$agent_news_sources")])
        viewer.layoutIfNeeded()
        let menuFrame = header.convert(header.menuGroup.frame, to: viewer)
        XCTAssertEqual(menuFrame.maxX, viewer.bounds.width - viewer.safeAreaInsets.right - 16, accuracy: 0.5)
        XCTAssertEqual(menuFrame.minY, header.convert(header.backGroup.frame, to: viewer).minY, accuracy: 0.5)

        // The menu lists the sources; one opens its link as the viewer fades
        let configuration = try XCTUnwrap(header.makeMenuConfiguration?())
        let actions = configuration.rootPage.items.compactMap { item -> ContextMenuAction? in
            if case .action(let action) = item { return action }
            return nil
        }
        XCTAssertEqual(actions.map(\.title), content.sources.map(\.name))
        var isClosed = false
        viewer.onClose = { isClosed = true }
        try XCTUnwrap(actions.first?.handler)()
        XCTAssertEqual(openedSources, [try XCTUnwrap(content.sources.first?.url)])
        try await waitUntil { isClosed && viewer.superview == nil }
    }

    /// The picture follows a swipe down as the NFT viewer's does, springs back when let go early, and closes the
    /// viewer past the NFT viewer's threshold
    func testSwipeDownFollowsTheFingerAndClosesAsTheNftViewer() async throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: [.init(url: nil, image: makePicture(), title: "Picture")],
            index: 0,
            in: window,
            source: { _ in nil }
        ))
        let zoom = try XCTUnwrap(findDescendants(of: viewer).compactMap { $0 as? MediaZoomView }.first)
        let pan = PanByTranslation()
        pan.translation = CGPoint(x: 0, y: 100)
        pan.fakeState = .changed
        viewer.handleDismissPan(pan)
        XCTAssertEqual(zoom.transform, MediaViewerMotion.getDismissTransform(for: pan.translation, in: viewer.bounds))
        XCTAssertEqual(try XCTUnwrap(viewer.backgroundColor?.cgColor.alpha), 0.5, accuracy: 0.01)
        pan.fakeState = .ended
        viewer.handleDismissPan(pan)
        XCTAssertEqual(zoom.transform, .identity)
        XCTAssertNotNil(viewer.superview)

        var isClosed = false
        viewer.onClose = { isClosed = true }
        pan.translation.y = viewer.bounds.height * 0.25
        pan.fakeState = .changed
        viewer.handleDismissPan(pan)
        pan.fakeState = .ended
        viewer.handleDismissPan(pan)
        try await waitUntil { isClosed && viewer.superview == nil }

        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        XCTAssertFalse(MediaViewerMotion.shouldDismiss(translation: CGPoint(x: 0, y: 174), velocity: .zero, in: bounds))
        XCTAssertTrue(MediaViewerMotion.shouldDismiss(translation: CGPoint(x: 0, y: 175), velocity: .zero, in: bounds))
        XCTAssertTrue(MediaViewerMotion.shouldDismiss(translation: CGPoint(x: 0, y: 13), velocity: CGPoint(x: 0, y: 801), in: bounds))
        XCTAssertFalse(MediaViewerMotion.shouldDismiss(translation: CGPoint(x: 0, y: 12), velocity: CGPoint(x: 0, y: 2_000), in: bounds))
    }

    /// A picture in the list still zooms in place under a pinch, beside the one-finger tap that opens the viewer
    func testListPictureStillPinchesBesideTheTapThatOpensTheViewer() throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let card = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: 402, height: 600))
        card.configure(with: makeNewsItem(1, imageURL: "invalid-news-image://1"))
        window.addSubview(card)
        let imageView = card.newsView.imageView
        imageView.image = makePicture()
        let recognizers = imageView.gestureRecognizers ?? []
        let pinch = try XCTUnwrap(recognizers.compactMap { $0 as? UIPinchGestureRecognizer }.first)
        XCTAssertTrue(pinch.isEnabled)
        XCTAssertTrue(pinch.delegate?.gestureRecognizerShouldBegin?(pinch) == true)
        let taps = recognizers.compactMap { $0 as? UITapGestureRecognizer }
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps.first?.numberOfTouchesRequired, 1)
    }

    private func findHeadlineLabels(in view: AgentNewsDigestHeadlinesView) -> [UILabel] {
        view.headlineButtons.compactMap { row in
            findDescendants(of: row).compactMap { $0 as? UILabel }.first { $0.text == row.accessibilityLabel }
        }
    }

    private func makeDigest(imageUrls: [String?]) throws -> ApiAgentV2NewsFeedDigest {
        let top = imageUrls.enumerated().map { index, imageUrl -> [String: Any] in
            var headline: [String: Any] = ["eventId": index + 1, "headline": "Headline \(index + 1)"]
            headline["imageUrl"] = imageUrl
            return headline
        }
        return try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: JSONSerialization.data(withJSONObject: [
            "id": "en:2026-11-08T18:00:00.000Z", "deliveredAt": "2026-11-08T18:00:00.000Z", "total": top.count, "top": top,
        ]))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw AgentTestTimeout()
    }
}

/// The picture flying between the list and the viewer
@MainActor
private func findFlight(in viewer: MediaViewer) -> UIView? {
    viewer.subviews.lazy.flatMap(\.subviews).first { $0.subviews.count == 1 && $0.subviews.first is UIImageView }
}

@MainActor
private func makePicture() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90)).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
    }
}

/// A tap that lands at `point`, for calling the viewer's tap handlers without a host app to send touches
private final class TapAtPoint: UITapGestureRecognizer {
    var point = CGPoint.zero

    override func location(in view: UIView?) -> CGPoint {
        point
    }
}

/// A pan at `translation` in `fakeState`, for calling the viewer's swipe-down handler without a host app
private final class PanByTranslation: UIPanGestureRecognizer {
    var translation = CGPoint.zero
    var fakeState: UIGestureRecognizer.State = .possible

    override var state: UIGestureRecognizer.State {
        get { fakeState }
        set { fakeState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint {
        translation
    }

    override func velocity(in view: UIView?) -> CGPoint {
        .zero
    }
}

/// A touch at a point of `view`, for feeding a recognizer touches without a host app
private final class TouchAtPoint: UITouch {
    private let point: CGPoint
    private weak var touchView: UIView?

    init(_ point: CGPoint, in view: UIView) {
        self.point = point
        touchView = view
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint {
        guard let view, let touchView else { return point }
        return touchView.convert(point, to: view)
    }
}

/// A list whose picture reaches 40 pt under a 100 pt header standing over the list's scroll view
@MainActor
private final class ListUnderHeader {
    let controller: UIViewController
    let window: UIWindow
    let scrollView: UIScrollView
    let header: UIView
    let source: UIImageView

    init() {
        let controller = UIViewController()
        window = makeKeyWindow(showing: controller)
        let scrollView = UIScrollView(frame: controller.view.bounds)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset.top = 100
        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: 2000)
        scrollView.contentOffset.y = -100
        controller.view.addSubview(scrollView)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: controller.view.bounds.width, height: 100))
        controller.view.addSubview(header)
        let source = UIImageView(image: makePicture())
        source.frame = CGRect(x: 20, y: -40, width: 320, height: 180)
        source.layer.cornerRadius = 19
        scrollView.addSubview(source)
        self.controller = controller
        self.scrollView = scrollView
        self.header = header
        self.source = source
    }

    func presentViewer() throws -> MediaViewer {
        let source = source
        return try XCTUnwrap(MediaViewer.present(
            pictures: [.init(url: nil, image: makePicture(), title: "Picture", details: .init(
                date: "Today, 10:00", caption: nil, actions: []
            ))],
            index: 0,
            in: window,
            source: { _ in source }
        ))
    }

    /// Where `view` is drawn on the frame on screen, in the window
    func getShownFrame(of view: UIView) -> CGRect {
        let frame = view.layer.presentation()?.frame ?? view.frame
        return view.superview?.convert(frame, to: window) ?? frame
    }

    /// How far the viewer's backdrop has come on the frame on screen
    func getBackdrop(of viewer: MediaViewer) -> CGFloat {
        (viewer.layer.presentation()?.backgroundColor ?? viewer.backgroundColor?.cgColor)?.alpha ?? 0
    }
}

/// A pushed screen with the Agent chat's header, the threads button and the title pill, over a list with a picture
@MainActor
private final class AgentHeaderScreen {
    let window: UIWindow
    let chat: WViewController
    let source: UIImageView
    let circle: AgentGlassCircleButton
    let chatGlyph: UIImageView
    let pill: UIView

    init() async throws {
        let chat = WViewController()
        let navigation = WNavigationController(rootViewController: WViewController())
        let window = makeKeyWindow(showing: navigation)
        navigation.pushViewController(chat, animated: false)
        let scrollView = UIScrollView(frame: chat.view.bounds)
        chat.view.addSubview(scrollView)
        let source = UIImageView(image: makePicture())
        source.frame = CGRect(x: 20, y: 300, width: 320, height: 180)
        scrollView.addSubview(source)
        let title = UILabel()
        title.text = "News"
        AgentChatNavigation.installHeader(in: chat, titleView: title, scrollView: scrollView)
        AgentChatNavigation.installThreadsButton(in: chat)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        window.layoutIfNeeded()
        let button = try XCTUnwrap(AgentChatNavigation.findButton(in: chat.navigationItem.leftBarButtonItem))
        button.layoutIfNeeded()
        self.window = window
        self.chat = chat
        self.source = source
        circle = try XCTUnwrap(AgentChatNavigation.findCircle(in: chat.navigationItem.leftBarButtonItem))
        chatGlyph = try XCTUnwrap(button.imageView)
        pill = try XCTUnwrap((chat.navigationItem.titleView as? NavigationHeader2)?.contentView)
    }

    /// Opens two pictures from `source`, the first of them shown
    func presentViewer(over source: UIImageView?) throws -> MediaViewer {
        let viewer = try XCTUnwrap(MediaViewer.present(
            pictures: (0..<2).map { .init(url: nil, image: makePicture(), title: "Picture \($0)", details: .init(
                date: "Today, 10:00", caption: nil, actions: []
            )) },
            index: 0,
            in: window,
            source: { _ in source }
        ))
        viewer.layoutIfNeeded()
        return viewer
    }
}
