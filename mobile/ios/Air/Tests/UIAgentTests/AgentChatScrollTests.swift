import XCTest
import UIKit
@testable import UIAgent
import WalletResources

@MainActor
final class AgentChatScrollTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// Scrolled up by less than a screen, the scroll button springs the list down through the rows on the way, each
    /// of them shown as the list passes it
    func testScrollToLatestShowsEveryRowOnTheWay() async throws {
        let chat = makeChat(count: 30)
        try await chat.waitForStableLayout()
        let collectionView = chat.collectionView
        // Rows above settle their heights as they come into view, so the distance is set again once they have
        for _ in 0..<2 {
            collectionView.contentOffset.y = try XCTUnwrap(chat.latestOffsetY) - collectionView.bounds.height * 0.8
            try await chat.waitForStableLayout()
        }
        let end = try XCTUnwrap(chat.latestOffsetY)
        XCTAssertLessThan(end - collectionView.contentOffset.y, collectionView.bounds.height)

        // Every offset the scroll sets, however seldom the test gets to look
        let log = OffsetLog()
        let observation = collectionView.observe(\.contentOffset, options: [.new]) { _, change in
            let offsetY = change.newValue?.y ?? 0
            MainActor.assumeIsolated { log.offsets.append(offsetY) }
        }
        defer { observation.invalidate() }
        chat.controller.scrollToBottomButtonPressed()
        let start = CACurrentMediaTime()
        while chat.controller.listScrollAnimator.isRunning {
            XCTAssertLessThanOrEqual(chat.getLargestUncoveredGap(), AgentVCLayout.rowSpacing + 1)
            try await Task.sleep(for: .milliseconds(16))
            guard CACurrentMediaTime() - start < 5 else { return XCTFail("The scroll didn't end") }
        }

        // The spring takes Telegram's time over it, moves frame by frame and never runs past the end
        XCTAssertGreaterThan(CACurrentMediaTime() - start, 0.3)
        let offsets = log.offsets
        XCTAssertGreaterThan(Set(offsets.map { Int($0) }).count, 5, "\(offsets)")
        for (offset, next) in zip(offsets, offsets.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next, offset - 0.5)
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(offsets.max()), end + 0.5)
        XCTAssertEqual(collectionView.contentOffset.y, end, accuracy: 1)
        XCTAssertFalse(chat.controller.scrollToBottomButton.isButtonVisible)
    }

    /// Scrolled up by several screens, the list goes to the latest rows at once and they slide in right after the
    /// rows that were on screen, as Telegram's list relays them
    func testLongScrollToLatestBringsTheLatestRowsInAfterTheShownOnes() async throws {
        let chat = makeChat(count: 60)
        try await chat.waitForStableLayout()
        let collectionView = chat.collectionView
        collectionView.contentOffset.y = try XCTUnwrap(chat.latestOffsetY) - collectionView.bounds.height * 3
        try await chat.waitForStableLayout()

        chat.controller.scrollToBottomButtonPressed()
        XCTAssertEqual(collectionView.contentOffset.y, try XCTUnwrap(chat.latestOffsetY), accuracy: 1)
        let departingView = try XCTUnwrap(chat.controller.view.subviews.first {
            $0.accessibilityIdentifier == AgentListScrollAnimator.departingViewIdentifier
        })
        XCTAssertEqual(departingView.bounds.size, collectionView.bounds.size)
        XCTAssertEqual(departingView.frame.minY, collectionView.frame.minY, accuracy: 1)
        let start = CACurrentMediaTime()
        var sampleCount = 0
        while chat.controller.listScrollAnimator.isRunning {
            // The shown rows leave the screen exactly where the latest ones come in
            let incomingTop = collectionView.frame.minY + collectionView.layer.sublayerTransform.m42
            XCTAssertEqual(departingView.frame.maxY, incomingTop, accuracy: 1)
            XCTAssertLessThanOrEqual(chat.getLargestUncoveredGap(), AgentVCLayout.rowSpacing + 1)
            sampleCount += 1
            try await Task.sleep(for: .milliseconds(16))
            guard CACurrentMediaTime() - start < 5 else { return XCTFail("The scroll didn't end") }
        }

        XCTAssertGreaterThan(sampleCount, 5)
        XCTAssertNil(departingView.superview)
        XCTAssertTrue(CATransform3DIsIdentity(collectionView.layer.sublayerTransform))
        XCTAssertEqual(collectionView.contentOffset.y, try XCTUnwrap(chat.latestOffsetY), accuracy: 1)
    }

    /// Taking the list during the scroll leaves it with the user, with nothing left over it
    func testDraggingStopsTheScrollToLatest() async throws {
        let chat = makeChat(count: 60)
        try await chat.waitForStableLayout()
        let collectionView = chat.collectionView
        let end = try XCTUnwrap(chat.latestOffsetY)
        collectionView.contentOffset.y = end - collectionView.bounds.height * 3
        try await chat.waitForStableLayout()

        chat.controller.scrollToBottomButtonPressed()
        try await Task.sleep(for: .milliseconds(50))
        chat.controller.scrollViewWillBeginDragging(collectionView)

        XCTAssertFalse(chat.controller.listScrollAnimator.isRunning)
        XCTAssertTrue(CATransform3DIsIdentity(collectionView.layer.sublayerTransform))
        XCTAssertFalse(chat.controller.view.subviews.contains {
            $0.accessibilityIdentifier == AgentListScrollAnimator.departingViewIdentifier
        })
    }

    /// A tap on the scroll button while a fling still carries the list ends the fling, as Telegram's list stops its
    /// scroller before it scrolls to an item: once the scroll lands, the list stays at its target rather than the rest
    /// of the fling pulling it back. A bounce back from the top ends the same way, and so does a short scroll.
    func testScrollToLatestEndsTheFlingUnderWay() async throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        for (startY, velocity, targetY) in [(3000, -40, 5000), (-30, 4, 5000), (3000, -40, 3300)] as [(CGFloat, CGFloat, CGFloat)] {
            let list = FlingingCollectionView(frame: host.bounds, collectionViewLayout: TallLayout())
            host.addSubview(list)
            defer {
                list.stopFling()
                list.removeFromSuperview()
            }
            let animator = AgentListScrollAnimator(collectionView: list)
            list.contentOffset.y = startY
            list.fling(velocity: velocity)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(list.isDecelerating)

            var isFinished: Bool?
            animator.scroll(to: { targetY }) { isFinished = $0 }
            XCTAssertFalse(list.isDecelerating, "The scroll ends the fling as it starts")
            for _ in 0..<200 where isFinished == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(isFinished, true)
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(16))
                XCTAssertEqual(list.contentOffset.y, targetY, accuracy: 0.5, "From \(startY) at \(velocity) pt a frame")
            }
        }
    }

    /// An answer scrolled out of view and back shows the drawing it had, rather than being parsed, laid out and drawn
    /// again in the cell that shows it now
    func testAnswersScrolledBackIntoViewAreNotDrawnAgain() async throws {
        let chat = makeChat(count: 40)
        try await chat.waitForStableLayout()
        let collectionView = chat.collectionView
        let step = collectionView.bounds.height / 2

        func scrollThrough(_ offsets: [CGFloat]) async throws -> Set<ObjectIdentifier> {
            var drawings = Set<ObjectIdentifier>()
            for offset in offsets {
                collectionView.contentOffset.y = offset
                chat.layout()
                try await Task.sleep(for: .milliseconds(16))
                for cell in collectionView.visibleCells {
                    for view in findDescendants(of: cell) {
                        guard let imageView = view as? UIImageView, imageView.superview?.superview is AgentStreamingTextView,
                              let image = imageView.image?.cgImage else { continue }
                        drawings.insert(ObjectIdentifier(image))
                    }
                }
            }
            return drawings
        }

        let top = -collectionView.adjustedContentInset.top
        let bottom = try XCTUnwrap(chat.latestOffsetY)
        let upward = Array(stride(from: bottom, through: top, by: -step))
        let firstPass = try await scrollThrough(upward)
        let secondPass = try await scrollThrough(upward.reversed() + upward)

        XCTAssertGreaterThan(firstPass.count, 10)
        XCTAssertTrue(secondPass.isSubset(of: firstPass), "\(secondPass.subtracting(firstPass).count) answers were drawn again")
    }

    /// Answers drawn whole measure no characters; streamed ones measure each to reveal it
    func testOnlyStreamedTextMeasuresItsCharacters() {
        let text = NSAttributedString(string: String(repeating: "Gram and TON network news. ", count: 20))
        XCTAssertTrue(AgentStreamingTextLayout.make(attributedString: text, maxWidth: 300, measuresCharacters: false).lines.isEmpty)
        let streamed = AgentStreamingTextLayout.make(attributedString: text, maxWidth: 300)
        XCTAssertEqual(streamed.lines.reduce(0) { $0 + $1.characterRects.count }, text.length)
    }

    private func makeChat(count: Int) -> AgentTestChat {
        let messages = (0..<count).map { index in
            AgentMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: index.isMultiple(of: 2)
                    ? "Question \(index) about the wallet"
                    : "Answer \(index). " + String(repeating: "Gram and TON network news for the last two days. ", count: 6),
                isStreaming: false
            )
        }
        let chat = AgentTestChat(messages: messages)
        addTeardownBlock { chat.close() }
        return chat
    }
}

@MainActor
private final class OffsetLog {
    var offsets: [CGFloat] = []
}

/// A list that keeps moving on its own after a fling until something stops it, as UIKit's deceleration does: setting
/// its offset without animation ends the deceleration, as `UIScrollView.setContentOffset(_:animated:)` does
@MainActor
private final class FlingingCollectionView: UICollectionView {
    private var velocity: CGFloat = 0
    private var link: CADisplayLink?

    override var isDecelerating: Bool { link != nil }

    /// Moves the list by `velocity` a frame, slowing as a fling does
    func fling(velocity: CGFloat) {
        self.velocity = velocity
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stopFling() {
        link?.invalidate()
        link = nil
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        stopFling()
        super.setContentOffset(contentOffset, animated: animated)
    }

    @objc private func step() {
        contentOffset.y += velocity
        velocity *= 0.99
    }
}

/// A layout as tall as a long chat, with nothing in it
private final class TallLayout: UICollectionViewFlowLayout {
    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: 8000)
    }
}
