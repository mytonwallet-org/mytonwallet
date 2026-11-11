import XCTest
import UIKit
@testable import UIAgent
import WalletResources

@MainActor
final class AgentFollowupRevealTests: XCTestCase {
    private let followups = [
        AgentMessageControl(id: "followup:why", title: "Why does it matter?", isEnabled: true, kind: .followup),
        AgentMessageControl(id: "followup:next", title: "What happens next?", isEnabled: true, kind: .followup),
    ]

    /// Suggestions that come with a chat's history show with it, without a blur-in of their own, and a re-layout of the
    /// same answer doesn't play one
    func testHistorySuggestionsDoNotBlurIn() throws {
        _ = WalletResourcesBundle.bundle.load()
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 120))
        window.rootViewController?.view.addSubview(cell)
        let message = AgentMessage(role: .assistant, text: "Answer", isStreaming: false, controls: followups)
        cell.configure(with: message, onURLTap: { _ in })
        cell.layoutIfNeeded()
        let suggestions = try XCTUnwrap(findDescendants(of: cell).compactMap { $0 as? AgentFollowupView }.first)
        XCTAssertFalse(suggestions.isHidden)
        XCTAssertFalse(suggestions.isRevealing, "Suggestions with the history show as it does")

        cell.configure(with: message, onURLTap: { _ in })
        cell.frame.size.width = 320
        cell.layoutIfNeeded()
        XCTAssertFalse(suggestions.isRevealing, "Nor does a re-layout play them")
    }

    /// Suggestions that come under an answer written in this session come in out of a blur, one after another
    func testSuggestionsOfACompletedAnswerBlurIn() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the suggestions at once")
        _ = WalletResourcesBundle.bundle.load()
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 120))
        window.rootViewController?.view.addSubview(cell)
        var message = AgentMessage(role: .assistant, text: "Answer", isStreaming: true)
        cell.configure(with: message, onURLTap: { _ in })
        cell.layoutIfNeeded()
        message.isStreaming = false
        message.controls = followups
        cell.configure(with: message, onURLTap: { _ in })
        let suggestions = try XCTUnwrap(findDescendants(of: cell).compactMap { $0 as? AgentFollowupView }.first)
        var hasRevealed = false
        for _ in 0..<200 where !hasRevealed {
            cell.layoutIfNeeded()
            hasRevealed = !suggestions.isHidden && suggestions.isRevealing
            if !hasRevealed { try await Task.sleep(for: .milliseconds(10)) }
        }
        XCTAssertTrue(hasRevealed, "The completed answer's suggestions blur in")
        let blurred = suggestions.arrangedSubviews.filter { $0.layer.filters?.isEmpty == false }
        XCTAssertEqual(blurred.count, followups.count, "Each suggestion comes out of its own blur")
    }

    /// Suggestions beyond the placeholders come in after the titles that fill them, one after another, as suggestions do
    func testSuggestionsBeyondThePlaceholdersBlurInAfterTheFilledOnes() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the suggestions at once")
        _ = WalletResourcesBundle.bundle.load()
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        let bubble = UIView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(bubble)
        let column = UILayoutGuide()
        host.addLayoutGuide(column)
        let suggestions = AgentFollowupView()
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: host.topAnchor),
            column.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: host.topAnchor, constant: 100),
            bubble.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            bubble.widthAnchor.constraint(equalToConstant: 200),
            bubble.heightAnchor.constraint(equalToConstant: 40),
        ] + suggestions.install(in: host, below: bubble, contentLayoutGuide: column))
        suggestions.showLoading()
        host.layoutIfNeeded()
        let placeholderCount = suggestions.arrangedSubviews.count
        let controls = (1...placeholderCount + 2).map {
            AgentMessageControl(id: "followup:\($0)", title: "Suggestion \($0)", isEnabled: true, kind: .followup)
        }

        let startTime = CACurrentMediaTime()
        suggestions.configure(controls: controls, isVisible: true, animatesAppearance: true, onControlTap: { _ in })
        let revealStarts = suggestions.arrangedSubviews.map {
            $0.layer.animation(forKey: "agentFollowupRevealOpacity")?.beginTime
        }
        XCTAssertEqual(revealStarts.count, controls.count)
        XCTAssertTrue(suggestions.isFillingPlaceholders)
        XCTAssertTrue(revealStarts.prefix(placeholderCount).allSatisfy { $0 == nil }, "The filled pills fade their titles in")
        let addedStarts = revealStarts.suffix(2).compactMap { $0 }
        XCTAssertEqual(addedStarts.count, 2, "Each suggestion beyond the placeholders comes in")
        // The last of the placeholders' titles starts 0.14 s and two steps of 0.15 s in, and the next suggestion a step on
        let lastTitleDelay = 0.14 + 0.15 * Double(placeholderCount - 1)
        XCTAssertEqual(addedStarts[0] - startTime, lastTitleDelay + 0.15, accuracy: 0.05)
        XCTAssertEqual(addedStarts[1] - addedStarts[0], 0.15, accuracy: 0.001)
    }
}
