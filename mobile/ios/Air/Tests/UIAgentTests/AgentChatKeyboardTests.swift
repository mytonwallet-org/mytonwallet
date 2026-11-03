import XCTest
import UIKit
@testable import UIAgent
import WalletResources

/// The area the composer and the keyboard cover changes here as the keyboard changes it: the composer moves inside an
/// animation, and the list's insets follow from its frame. A draft of several lines grows the composer the way the
/// keyboard raises it; the simulator's software keyboard, when it shows, raises it for real.
@MainActor
final class AgentChatKeyboardTests: XCTestCase {
    private static let tallDraft = (1...6).map { "Line \($0)" }.joined(separator: "\n")

    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    func testContentAtTheEndRidesUpWithTheCoveredAreaAndComesBackDown() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        let composer = chat.controller.composerView
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)

        let shortComposerY = composer.frame.minY
        try await changeCoveredArea(in: chat) { composer.setDraftText(Self.tallDraft, focus: false) }
        XCTAssertLessThan(composer.frame.minY, shortComposerY - 60)
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)

        try await changeCoveredArea(in: chat) { composer.clearDraft() }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)
        XCTAssertEqual(chat.controller.reserveSpacerHeight, 0)
    }

    /// The chat of Artem's recording: a question sent in it, answered at length and read to the end, keeps its end at
    /// the composer, with no space left under it when the covered area shrinks
    func testAnsweredQuestionDoesNotHoldTheListAgainstTheCoveredArea() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        let composer = chat.controller.composerView
        composer.setDraftText("What should I check before paying with crypto?", focus: false)
        composer.onSend?()
        try await chat.waitForStableLayout()
        XCTAssertNotNil(chat.controller.pinnedUserMessageID)
        let reply = AgentMessage(
            role: .assistant,
            text: String(repeating: "Check the address, the network and the amount before you confirm. ", count: 30),
            isStreaming: false
        )
        chat.backend.context?.append(.message(reply), animated: false)
        try await chat.waitForStableLayout()
        chat.collectionView.contentOffset.y = try XCTUnwrap(chat.latestOffsetY)
        try await chat.waitForStableLayout()
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)

        try await changeCoveredArea(in: chat) { composer.setDraftText(Self.tallDraft, focus: false) }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)

        try await changeCoveredArea(in: chat) { composer.clearDraft() }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)
        XCTAssertEqual(chat.controller.reserveSpacerHeight, 0, accuracy: 0.5)
    }

    /// Scrolled up, the rows stay where they are as the covered area grows and shrinks
    func testScrolledUpRowsKeepTheirPlace() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        let composer = chat.controller.composerView
        chat.collectionView.contentOffset.y -= 1_000
        try await chat.waitForStableLayout()
        let offsetY = chat.collectionView.contentOffset.y

        try await changeCoveredArea(in: chat) { composer.setDraftText(Self.tallDraft, focus: false) }
        XCTAssertEqual(chat.collectionView.contentOffset.y, offsetY, accuracy: 1)

        try await changeCoveredArea(in: chat) { composer.clearDraft() }
        XCTAssertEqual(chat.collectionView.contentOffset.y, offsetY, accuracy: 1)
    }

    /// The software keyboard, where the simulator shows it
    func testContentAtTheEndRidesTheKeyboard() async throws {
        let chat = makeChat()
        try await chat.waitForStableLayout()
        let controller = chat.controller
        let textView = try XCTUnwrap(findDescendants(of: controller.composerView).compactMap { $0 as? UITextView }.first)

        let opening = try await followCoveredArea(in: chat) { _ = textView.becomeFirstResponder() }
        guard controller.view.keyboardLayoutGuide.layoutFrame.height > 100 else {
            textView.resignFirstResponder()
            throw XCTSkip("The simulator shows no software keyboard")
        }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)
        // The keyboard's own animation is one the list can follow at the time its frames show
        XCTAssertGreaterThan(opening.count, 0, opening.unfollowed)

        let closing = try await followCoveredArea(in: chat) { _ = textView.resignFirstResponder() }
        XCTAssertEqual(try getSpaceUnderContent(in: chat), 0, accuracy: 1)
        XCTAssertGreaterThan(closing.count, 0, closing.unfollowed)
        XCTAssertEqual(controller.reserveSpacerHeight, 0)
    }

    /// Applies `change` in the keyboard's animation time, then follows the list
    private func changeCoveredArea(in chat: AgentTestChat, _ change: @escaping () -> Void) async throws {
        let sampling = try await followCoveredArea(in: chat) {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut]) {
                change()
                chat.controller.view.layoutIfNeeded()
            }
        }
        XCTAssertGreaterThan(sampling.count, 0, sampling.unfollowed)
    }

    /// Runs `change` and checks every frame until the list settles that the rows on screen are all drawn and, for
    /// content that ends at the composer, that its end moves with the composer. The list is set on display link ticks
    /// for the time their frame shows, while the composer's presentation here is of the moment of the check, and the
    /// last tick may come before the previous check, so the two may stand as far apart as the composer moves over the
    /// last two checks. Returns how many of the composer's animated frames `AgentLayerAnimationSampler` followed, each
    /// matching its presentation, and the animations of those it didn't. A busy simulator draws few of them.
    @discardableResult
    private func followCoveredArea(in chat: AgentTestChat, _ change: () -> Void) async throws -> (count: Int, unfollowed: String) {
        let controller = chat.controller
        let composer = controller.composerView
        let isAtEnd = abs(try getSpaceUnderContent(in: chat)) < 1
        // Where the list's visible bottom stands relative to the composer's top, which the change keeps
        let composerToVisibleBottom = chat.collectionView.bounds.height - controller.occlusionBottomInset - composer.frame.minY
        var previousComposerY = composer.frame.minY
        var earlierComposerY = previousComposerY
        var sampledFrameCount = 0
        var unfollowed: Set<String> = []
        change()
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < 1 {
            try await Task.sleep(for: .milliseconds(16))
            XCTAssertLessThanOrEqual(chat.getLargestUncoveredGap(), AgentVCLayout.rowSpacing + 1)
            let timeBeforePresentation = CACurrentMediaTime()
            guard let composerY = composer.layer.presentation()?.frame.minY else { continue }
            let timeAfterPresentation = CACurrentMediaTime()
            defer {
                earlierComposerY = previousComposerY
                previousComposerY = composerY
            }
            if let keys = composer.layer.animationKeys(), !keys.isEmpty {
                // The presentation is of a moment between these two
                if let earliestY = AgentLayerAnimationSampler.getMinY(of: composer.layer, at: timeBeforePresentation),
                   let latestY = AgentLayerAnimationSampler.getMinY(of: composer.layer, at: timeAfterPresentation) {
                    XCTAssertGreaterThanOrEqual(composerY, min(earliestY, latestY) - 0.5)
                    XCTAssertLessThanOrEqual(composerY, max(earliestY, latestY) + 0.5)
                    sampledFrameCount += 1
                } else {
                    unfollowed.formUnion(keys.compactMap { key in
                        composer.layer.animation(forKey: key).map { "\(key): \(type(of: $0)) \(($0 as? CAPropertyAnimation)?.keyPath ?? "")" }
                    })
                }
            }
            guard isAtEnd, controller.occlusionFollow != nil,
                  let indexPath = controller.lastItemIndexPath,
                  let lastFrame = chat.collectionView.layoutAttributesForItem(at: indexPath)?.frame else { continue }
            let contentEndY = lastFrame.maxY - chat.collectionView.contentOffset.y
            XCTAssertEqual(contentEndY, composerY + composerToVisibleBottom, accuracy: abs(composerY - earlierComposerY) + 2)
        }
        try await chat.waitForStableLayout()
        XCTAssertNil(controller.occlusionFollow)
        return (sampledFrameCount, unfollowed.sorted().joined(separator: "; "))
    }

    /// The space between the end of the content and the composer
    private func getSpaceUnderContent(in chat: AgentTestChat) throws -> CGFloat {
        let indexPath = try XCTUnwrap(chat.controller.lastItemIndexPath)
        let lastFrame = try XCTUnwrap(chat.collectionView.layoutAttributesForItem(at: indexPath)).frame
        let visibleBottom = chat.collectionView.contentOffset.y + chat.collectionView.bounds.height
            - chat.controller.occlusionBottomInset
        return visibleBottom - lastFrame.maxY
    }

    private func makeChat() -> AgentTestChat {
        let messages = (0..<30).map { index in
            AgentMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: index.isMultiple(of: 2)
                    ? "Question \(index) about the wallet"
                    : "Answer \(index). " + String(repeating: "Gram and TON network news for the last two days. ", count: 4),
                isStreaming: false
            )
        }
        let chat = AgentTestChat(messages: messages)
        addTeardownBlock { chat.close() }
        return chat
    }
}
