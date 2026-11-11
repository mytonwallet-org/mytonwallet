import XCTest
import UIKit
@testable import UIAgent
import WalletResources

@MainActor
final class AgentTypingAnswerMorphTests: XCTestCase {
    /// The typing row turns into the answer that takes its place: its spinning top and status go from where they
    /// stood, and the answer's bubble shows within the row's frame at first and whole once the morph ends
    func testTypingRowTurnsIntoTheAnswer() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion swaps the row for the answer")
        _ = WalletResourcesBundle.bundle.load()
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let container = try XCTUnwrap(window.rootViewController?.view)
        let typing = AgentTypingIndicatorCell(frame: CGRect(x: 0, y: 100, width: 402, height: 44))
        container.addSubview(typing)
        typing.configure(statusText: "Analyzing the request")
        typing.layoutIfNeeded()
        // The row has been on screen, as one the chat replaces has; a picture needs it drawn once
        try await Task.sleep(for: .milliseconds(100))
        let source = try XCTUnwrap(typing.makeAnswerMorphSource(in: container))
        XCTAssertTrue(source.rowFrame.contains(source.topFrame))
        XCTAssertTrue(source.rowFrame.contains(source.statusFrame))
        typing.removeFromSuperview()

        let answer = AgentMessageCell(frame: CGRect(x: 0, y: 100, width: 402, height: 120))
        container.addSubview(answer)
        answer.configure(with: AgentMessage(role: .assistant, text: "The answer", isStreaming: true), onURLTap: { _ in })
        answer.layoutIfNeeded()
        let bubble = answer.bubbleBackgroundView
        let morph = try XCTUnwrap(AgentTypingAnswerMorph.start(from: source, into: bubble, in: container))
        XCTAssertTrue(source.topPicture.superview === container, "The spinning top goes from where it stood")
        XCTAssertTrue(source.statusPicture.superview === container, "So does the status")
        let mask = try XCTUnwrap(bubble.layer.mask as? CAShapeLayer)
        let shown = try XCTUnwrap(mask.path).boundingBox
        let row = container.convert(source.rowFrame, to: bubble)
        XCTAssertEqual(shown.minX, row.minX, accuracy: 0.5, "The bubble shows within the row's frame at first")
        XCTAssertEqual(shown.minY, row.minY, accuracy: 0.5)
        XCTAssertEqual(shown.height, row.height, accuracy: 0.5)

        for _ in 0..<100 where bubble.layer.mask != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(bubble.layer.mask, "The bubble shows whole once the morph ends")
        for _ in 0..<100 where source.topPicture.superview != nil || source.statusPicture.superview != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(source.topPicture.superview)
        XCTAssertNil(source.statusPicture.superview)
        withExtendedLifetime(morph) {}
    }

    /// The status lands on the answer's first line also when the answer's row is a reused one, whose layer still shows
    /// the row's previous place as the morph starts
    func testStatusLandsOnTheAnswersFirstLineInAReusedRow() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion swaps the row for the answer")
        _ = WalletResourcesBundle.bundle.load()
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let container = try XCTUnwrap(window.rootViewController?.view)
        let typing = AgentTypingIndicatorCell(frame: CGRect(x: 0, y: 100, width: 402, height: 44))
        container.addSubview(typing)
        typing.configure(statusText: "Analyzing the request")
        typing.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let source = try XCTUnwrap(typing.makeAnswerMorphSource(in: container))
        typing.removeFromSuperview()

        // The row showed another message lower down, and its layer shows that place until the next commit
        let answer = AgentMessageCell(frame: CGRect(x: 0, y: 600, width: 402, height: 120))
        container.addSubview(answer)
        answer.configure(with: AgentMessage(role: .assistant, text: "Earlier", isStreaming: false), onURLTap: { _ in })
        answer.layoutIfNeeded()
        CATransaction.flush()
        answer.frame.origin.y = 100
        answer.configure(with: AgentMessage(role: .assistant, text: "The answer", isStreaming: true), onURLTap: { _ in })
        answer.layoutIfNeeded()
        let bubble = answer.bubbleBackgroundView
        let morph = try XCTUnwrap(AgentTypingAnswerMorph.start(from: source, into: bubble, in: container))
        defer { morph.cancel() }
        let status = source.statusPicture
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(60))

        let padding = CGPoint(x: AgentMessageCellMetrics.bodyHorizontalPadding, y: AgentMessageCellMetrics.bodyVerticalPadding)
        let firstLine = bubble.convert(
            CGRect(x: padding.x, y: padding.y, width: bubble.bounds.width - 2 * padding.x, height: 22),
            to: container
        )
        XCTAssertTrue(status.superview === container, "Still dissolving")
        // Its frame with the transform it moves by, where it ends
        XCTAssertTrue(status.frame.intersects(firstLine), "On the answer's first line: \(status.frame) and \(firstLine)")
    }
}
