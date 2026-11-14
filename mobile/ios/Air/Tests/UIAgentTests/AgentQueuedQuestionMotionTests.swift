import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletResources

/// How the questions sent while an answer is written show in the chat as they wait and go
@MainActor
final class AgentQueuedQuestionMotionTests: XCTestCase {
    /// How far below what shows the chat's end stays as the user reads above it, farther than the near-bottom margin
    /// even once a typing row above has gone
    private static let scrolledAwayDistance: CGFloat = 240

    /// A question sent while an answer is written turns into its bubble in the pass that puts it in the chat: the first
    /// frame after that pass shows the bubble faded out, never whole in its place before its appearance, both for a
    /// question that leaves the field and for one sent otherwise, as a transcript is
    func testAWaitingQuestionShowsOnlyThroughItsAppearance() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the bubble at once")
        let chat = QueueTestChat()
        addTeardownBlock { chat.close() }
        try await chat.sendAndWaitForTypingRow()
        for isFromField in [true, false] {
            let text = isFromField ? "Тест" : "Another test"
            if isFromField {
                chat.controller.composerView.setDraftText(text, focus: false)
                chat.layout()
                chat.controller.composerView.onSend?()
            } else {
                chat.backend.context?.sendMessage(text, source: .composer)
            }
            // Still in the pass that put the question in the chat
            let id = try XCTUnwrap(chat.backend.waitingIDs.last, "\(text): it waits")
            XCTAssertEqual(chat.model.message(for: id)?.text, text)
            let bubble = try XCTUnwrap(chat.cell(for: id), "\(text): on screen").sentAppearanceView
            CATransaction.flush()
            XCTAssertLessThan(
                bubble.layer.presentation()?.opacity ?? 1,
                0.5,
                "\(text): the first frame shows the bubble faded out"
            )
            try await chat.waitForStableLayout()
            try await Task.sleep(for: .seconds(AgentSentMessageMorph.duration + 0.2))
            let opacity = bubble.layer.presentation()?.opacity ?? 0
            XCTAssertEqual(opacity, 1, accuracy: 0.01, "\(text): it shows once it has appeared")
        }
    }

    /// A tapped suggestion whose question waits, as a discussion's first question waits for its thread, turns into the
    /// bubble out of the suggestion rather than appearing in its place
    func testAWaitingQuestionGrowsOutOfTheTappedSuggestion() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the bubble at once")
        let chat = QueueTestChat()
        addTeardownBlock { chat.close() }
        try await chat.sendAndWaitForTypingRow()
        let title = "Why does it matter?"
        let button = AgentSuggestionButton()
        button.configure(title: title)
        button.frame = CGRect(origin: CGPoint(x: 16, y: 480), size: button.intrinsicContentSize)
        chat.controller.view.addSubview(button)
        button.layoutIfNeeded()
        chat.controller.pendingSentSource = try XCTUnwrap(
            AgentSentMessageSource.makeSuggestion(of: button, in: chat.controller.view)
        )
        button.removeFromSuperview()

        chat.backend.context?.sendMessage(title, source: .composer)

        let id = try XCTUnwrap(chat.backend.waitingIDs.last, "It waits")
        let morph = try XCTUnwrap(chat.controller.suggestionMorph, "The suggestion turns into the question")
        XCTAssertFalse(morph.isFinished)
        try await chat.waitUntil { _ in morph.isFinished }
        XCTAssertEqual(chat.cell(for: id)?.sentAppearanceView.alpha, 1, "The bubble shows once the morph ends")
    }

    /// A Stop while the Agent thinks takes its typing row out from above the questions that wait, and the next answer's
    /// typing row comes in above them: each time, frame by frame, the waiting rows move from where they showed to their
    /// new places on the chat's row-move curve rather than in one frame, while the rows above stay where they show
    func testWaitingQuestionsMoveToTheirPlacesAsATypingRowGoesAndComes() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion puts the rows in their places at once")
        let chat = QueueTestChat()
        addTeardownBlock { chat.close() }
        try await chat.sendAndWaitForTypingRow()
        let waitingIDs = try await chat.queue(["Тест", "Тест 2"])
        chat.backend.sendsNextOnStop = false
        let changes: [(name: String, run: () -> Void)] = [
            ("The stopped typing row goes", { chat.model.stopAnswer() }),
            ("The next typing row comes", { chat.backend.startThinking() }),
        ]
        for change in changes {
            let before = chat.getRowScreenMinYs()
            change.run()
            try chat.checkRowsMove(waitingIDs, from: before, change.name)
            try await chat.waitForStableLayout()
            try await Task.sleep(for: .seconds(AgentVCLayout.dissolvedGapCloseDuration + 0.1))
        }
    }

    /// A Stop that sends the first question that waits: in the Stop's pass the questions under the stopped typing row,
    /// the one that goes too, move up from where they showed, and once the chat has brought that question up, the one
    /// still waiting moves down from where it showed as the next answer's typing row comes in above it
    func testAStopMovesTheQuestionsThatWaitRatherThanJumpingThem() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion puts the rows in their places at once")
        let chat = QueueTestChat()
        addTeardownBlock { chat.close() }
        try await chat.sendAndWaitForTypingRow()
        let waitingIDs = try await chat.queue(["Тест", "Тест 2"])
        let aboveIDs = chat.getRowScreenMinYs().keys.filter { !waitingIDs.contains($0) }

        chat.model.stopAnswer()
        XCTAssertEqual(chat.backend.waitingIDs, [waitingIDs[1]], "The first question went")
        for id in waitingIDs {
            XCTAssertTrue(chat.getRowMoveShifts(of: id).contains { $0 > 0.5 }, "It moves up from where it showed")
        }
        for id in aboveIDs {
            XCTAssertTrue(chat.getRowMoveShifts(of: id).isEmpty, "A row above doesn't move with them")
        }

        try await chat.waitUntil { chat in
            guard let typingID = chat.backend.typingIndicatorID else { return false }
            return chat.model.itemIDs.contains(typingID)
        }
        XCTAssertTrue(
            chat.getRowMoveShifts(of: waitingIDs[1]).contains { $0 < -0.5 },
            "The one still waiting moves down under the next typing row"
        )
        XCTAssertFalse(chat.getRowMoveShifts(of: waitingIDs[0]).contains { $0 < -0.5 }, "The one that went stays above it")
    }

    /// The user scrolled up to read while questions wait, so the scroll-to-bottom button shows: the next question that
    /// goes, as a Stop sends it, leaves the chat where it is, while the questions that wait move to their places as
    /// they do at the chat's end and the button stays. Nor does the chat move as the Agent's typing row comes under the
    /// question, its answer comes and grows, or the area the composer covers changes. The button then takes the user to
    /// the chat's end.
    func testAQuestionThatGoesLeavesAReaderWhoScrolledUpWhereTheyAre() async throws {
        let chat = QueueTestChat(historyCount: 24)
        addTeardownBlock { chat.close() }
        try await chat.sendAndWaitForTypingRow()
        // The last question is long, so the questions that wait still show with the chat's end out of reach
        let waitingIDs = try await chat.queue(["Тест", String(repeating: "Тест 2 ", count: 100)])
        try await chat.waitForStableLayout()
        let collectionView = chat.collectionView
        let button = chat.controller.scrollToBottomButton
        let lastIndexPath = try XCTUnwrap(chat.controller.messageIndexPath(for: waitingIDs[1]))
        let lastFrame = try XCTUnwrap(collectionView.layoutAttributesForItem(at: lastIndexPath)).frame
        chat.controller.scrollViewWillBeginDragging(collectionView)
        collectionView.contentOffset.y = lastFrame.maxY - Self.scrolledAwayDistance - collectionView.bounds.height
            + chat.controller.occlusionBottomInset
        try await chat.waitForStableLayout()
        XCTAssertTrue(button.isButtonVisible, "Scrolled away from the chat's end")
        let offsetY = collectionView.contentOffset.y
        let stoppedTypingID = try XCTUnwrap(chat.backend.typingIndicatorID)
        // The rows the user reads, above the questions that wait and the typing row that goes. The list's offset itself
        // changes as the date line far above, which each timeline change makes anew, takes the estimated row height,
        // while what shows stays.
        let readRows = chat.getRowScreenMinYs().filter { !waitingIDs.contains($0.key) && $0.key != stoppedTypingID }
        XCTAssertFalse(readRows.isEmpty, "The user reads rows above the questions that wait")

        chat.model.stopAnswer()
        XCTAssertEqual(chat.backend.waitingIDs, [waitingIDs[1]], "The first question went")
        try await chat.waitUntil { chat in
            guard let typingID = chat.backend.typingIndicatorID else { return false }
            return chat.model.itemIDs.contains(typingID)
        }
        if !UIAccessibility.isReduceMotionEnabled {
            let wentShifts = chat.getRowMoveShifts(of: waitingIDs[0])
            XCTAssertTrue(wentShifts.contains { $0 > 0.5 }, "The one that went moves up from where it showed")
            XCTAssertFalse(wentShifts.contains { $0 < -0.5 }, "And stays above the next typing row")
            XCTAssertTrue(
                chat.getRowMoveShifts(of: waitingIDs[1]).contains { $0 < -0.5 },
                "The one still waiting moves down under the next typing row"
            )
            for id in readRows.keys {
                XCTAssertTrue(chat.getRowMoveShifts(of: id).isEmpty, "A row above doesn't move with them")
            }
        }
        // Longer than the chat takes to bring a question up
        let shift = try await chat.measureLargestRowShift(from: readRows, during: .milliseconds(800))
        XCTAssertLessThan(
            shift,
            1,
            "The chat stays where the user reads, its offset moved by \(collectionView.contentOffset.y - offsetY)"
        )
        XCTAssertTrue(button.isButtonVisible, "The scroll-to-bottom button stays")

        let typingID = try XCTUnwrap(chat.backend.typingIndicatorID)
        var answer = AgentMessage(role: .assistant, text: "The answer starts", isStreaming: true)
        chat.backend.context?.replaceItem(id: typingID, with: .message(answer), animated: true)
        try await chat.waitForStableLayout()
        answer.text += " and grows. " + String(repeating: "Gram and TON network news for the last two days. ", count: 6)
        chat.backend.context?.updateMessage(answer, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        answer.isStreaming = false
        chat.backend.context?.updateMessage(answer, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        XCTAssertLessThan(chat.getLargestRowShift(from: readRows), 1, "Nor as the answer comes")

        let composer = chat.controller.composerView
        composer.setDraftText((1...6).map(String.init).joined(separator: "\n"), focus: false)
        try await chat.waitForStableLayout()
        XCTAssertLessThan(chat.getLargestRowShift(from: readRows), 1, "Nor as the covered area grows")
        composer.clearDraft()
        try await chat.waitForStableLayout()
        XCTAssertLessThan(chat.getLargestRowShift(from: readRows), 1, "Or shrinks")
        XCTAssertTrue(button.isButtonVisible, "The scroll-to-bottom button is still there")

        chat.controller.scrollToBottomButtonPressed()
        try await chat.waitUntil { !$0.controller.listScrollAnimator.isRunning }
        try await chat.waitForStableLayout()
        XCTAssertTrue(chat.controller.isNearBottom(), "The button takes the user to the chat's end")
        XCTAssertFalse(button.isButtonVisible)
        let lastRow = try XCTUnwrap(chat.getCell(for: waitingIDs[1]), "The question still waiting shows")
        XCTAssertEqual(
            lastRow.frame.maxY,
            collectionView.contentOffset.y + collectionView.bounds.height - chat.controller.occlusionBottomInset,
            accuracy: 1,
            "At the bottom of what shows"
        )
    }

    /// At the chat's end, following it, the next question that goes, as a Stop sends it, is brought up to the top, as a
    /// question just sent is, with the Agent's typing row coming under it
    func testAQuestionThatGoesIsBroughtUpWhileTheUserFollowsTheChatEnd() async throws {
        let chat = QueueTestChat()
        addTeardownBlock { chat.close() }
        try await chat.sendAndWaitForTypingRow()
        let waitingIDs = try await chat.queue(["Тест", "Тест 2"])
        try await chat.waitForStableLayout()
        let button = chat.controller.scrollToBottomButton
        XCTAssertFalse(button.isButtonVisible, "At the chat's end")
        let offsetY = chat.collectionView.contentOffset.y

        chat.model.stopAnswer()
        try await chat.waitUntil { chat in
            guard let typingID = chat.backend.typingIndicatorID else { return false }
            return chat.model.itemIDs.contains(typingID)
        }
        try await chat.waitForStableLayout()
        XCTAssertEqual(chat.controller.pinnedUserMessageID, waitingIDs[0], "The question that went is the one pinned")
        let pinnedOffsetY = try XCTUnwrap(chat.controller.pinnedOffsetY(for: waitingIDs[0]))
        XCTAssertEqual(
            chat.collectionView.contentOffset.y,
            chat.controller.clampedContentOffsetY(pinnedOffsetY),
            accuracy: 1,
            "It is brought up to the top"
        )
        XCTAssertGreaterThan(chat.collectionView.contentOffset.y, offsetY + 1, "The chat moved to bring it up")
        XCTAssertFalse(button.isButtonVisible)
    }

    /// With animations off, as UI tests run, the questions that wait take their new places at once
    func testWaitingQuestionsTakeTheirPlacesAtOnceWithAnimationsOff() async throws {
        let chat = QueueTestChat()
        addTeardownBlock { chat.close() }
        try await chat.sendAndWaitForTypingRow()
        let waitingIDs = try await chat.queue(["Тест", "Тест 2"])
        chat.backend.sendsNextOnStop = false
        let before = chat.getRowScreenMinYs()
        UIView.setAnimationsEnabled(false)
        addTeardownBlock { UIView.setAnimationsEnabled(true) }

        chat.model.stopAnswer()
        UIView.setAnimationsEnabled(true)
        chat.collectionView.layoutIfNeeded()
        for id in waitingIDs {
            let cell = try XCTUnwrap(chat.getCell(for: id))
            XCTAssertTrue(chat.getRowMoveShifts(of: id).isEmpty, "No move")
            XCTAssertLessThan(
                cell.frame.minY - chat.collectionView.contentOffset.y,
                try XCTUnwrap(before[id]) - 0.5,
                "Already up in the stopped row's place"
            )
        }
    }
}

/// A chat in a key window over `QueueTestBackend`, with a few messages before the questions a test sends
@MainActor
private final class QueueTestChat {
    let backend = QueueTestBackend()
    let model: AgentModel
    let controller: AgentVC
    let window: UIWindow

    var collectionView: AgentCollectionView { controller.collectionView }

    init(historyCount: Int = 6) {
        _ = WalletResourcesBundle.bundle.load()
        model = AgentModel(backend: backend)
        let history: [AgentTimelineItem] = (0..<historyCount).map { index in
            .message(AgentMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: "History message \(index) with enough text to take a couple of lines in the chat",
                isStreaming: false
            ))
        }
        backend.context?.replaceTimeline(with: history, animated: false)
        controller = AgentVC(model: model)
        window = makeKeyWindow(showing: UINavigationController(rootViewController: controller))
    }

    func close() {
        window.rootViewController = nil
        window.isHidden = true
    }

    func layout() {
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
    }

    func cell(for id: AgentItemID) -> AgentMessageCell? {
        getCell(for: id) as? AgentMessageCell
    }

    func getCell(for id: AgentItemID) -> UICollectionViewCell? {
        controller.messageIndexPath(for: id).flatMap(collectionView.cellForItem(at:))
    }

    /// Asks a question, which the chat brings up, and waits for the Agent's typing row under it
    func sendAndWaitForTypingRow() async throws {
        backend.context?.sendMessage("Как работают обмены", source: .composer)
        try await waitUntil { chat in chat.collectionView.visibleCells.contains { $0 is AgentTypingIndicatorCell } }
        try await waitForStableLayout()
    }

    /// Sends `texts` while the Agent thinks, each once the one before has turned into its bubble, and returns the rows
    /// of those that wait
    func queue(_ texts: [String]) async throws -> [AgentItemID] {
        for text in texts {
            backend.context?.sendMessage(text, source: .composer)
            try await waitForStableLayout()
            try await Task.sleep(for: .seconds(AgentSentMessageAppearance.duration + 0.1))
        }
        XCTAssertEqual(backend.waitingIDs.count, texts.count, "They wait")
        return backend.waitingIDs
    }

    /// Where each row on screen stands on it, by its id
    func getRowScreenMinYs() -> [AgentItemID: CGFloat] {
        var minYs: [AgentItemID: CGFloat] = [:]
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let id = controller.messageItemID(at: indexPath) else { continue }
            minYs[id] = cell.frame.minY - collectionView.contentOffset.y
        }
        return minYs
    }

    /// How far each running move of the row `id` takes it, from where it showed to where it stands
    func getRowMoveShifts(of id: AgentItemID) -> [CGFloat] {
        guard let layer = getCell(for: id)?.layer else { return [] }
        return (layer.animationKeys() ?? []).filter { $0.hasPrefix(AgentVC.rowMoveAnimationKey) }.compactMap { key in
            ((layer.animation(forKey: key) as? CABasicAnimation)?.fromValue as? NSValue)?.cgPointValue.y
        }
    }

    /// The farthest a row of `screenMinYs` gets from where it showed on screen over `duration`, looked at every frame
    func measureLargestRowShift(
        from screenMinYs: [AgentItemID: CGFloat],
        during duration: Duration
    ) async throws -> CGFloat {
        let deadline = ContinuousClock.now + duration
        var largestShift = getLargestRowShift(from: screenMinYs)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(16))
            layout()
            largestShift = max(largestShift, getLargestRowShift(from: screenMinYs))
        }
        return largestShift
    }

    /// How far the row of `screenMinYs` farthest from where it showed on screen is from there, by the list's layout;
    /// infinite for a row the list no longer has
    func getLargestRowShift(from screenMinYs: [AgentItemID: CGFloat]) -> CGFloat {
        let offsetY = collectionView.contentOffset.y
        return screenMinYs.map { row -> CGFloat in
            guard let indexPath = controller.messageIndexPath(for: row.key),
                  let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return .infinity }
            return abs(frame.minY - offsetY - row.value)
        }.max() ?? 0
    }

    /// Checks, frame by frame through the move the change just started, that each row of `movingIDs` that showed in
    /// `before` goes from there to its new place without a jump, and that the other rows stay where they showed
    func checkRowsMove(
        _ movingIDs: [AgentItemID],
        from before: [AgentItemID: CGFloat],
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        collectionView.layoutIfNeeded()
        let offsetY = collectionView.contentOffset.y
        var movedCount = 0
        for (id, minYBefore) in before {
            guard let cell = getCell(for: id) else { continue }
            let minYAfter = cell.frame.minY - offsetY
            let moveKeys = (cell.layer.animationKeys() ?? []).filter { $0.hasPrefix(AgentVC.rowMoveAnimationKey) }
            guard movingIDs.contains(id) else {
                XCTAssertEqual(minYAfter, minYBefore, accuracy: 0.5, "\(name): a row above stays", file: file, line: line)
                XCTAssertTrue(moveKeys.isEmpty, "\(name): a row above doesn't move", file: file, line: line)
                continue
            }
            let distance = minYAfter - minYBefore
            XCTAssertGreaterThan(abs(distance), 20, "\(name): the row has a new place", file: file, line: line)
            let move = try XCTUnwrap(
                moveKeys.first.flatMap(cell.layer.animation(forKey:)),
                "\(name): the row moves",
                file: file,
                line: line
            )
            let frameCount = Int((move.duration * 60).rounded(.up))
            var previous = minYBefore
            for index in 0...frameCount {
                let elapsed = move.duration * Double(index) / Double(frameCount)
                let time = cell.layer.convertTime(move.beginTime + elapsed, to: nil)
                let minY = try XCTUnwrap(
                    AgentLayerAnimationSampler.getMinY(of: cell.layer, at: time),
                    "\(name): the move is one the sampler follows",
                    file: file,
                    line: line
                ) - offsetY
                let frameName = "\(name), frame \(index)"
                if index == 0 {
                    XCTAssertEqual(minY, minYBefore, accuracy: 0.5, "\(frameName): where it showed", file: file, line: line)
                }
                XCTAssertLessThan(abs(minY - previous), abs(distance) / 4, "\(frameName): no jump", file: file, line: line)
                XCTAssertGreaterThanOrEqual((minY - previous) * distance, -0.01, "\(frameName): one way", file: file, line: line)
                previous = minY
            }
            XCTAssertEqual(previous, minYAfter, accuracy: 0.5, "\(name): it ends in its place", file: file, line: line)
            movedCount += 1
        }
        XCTAssertEqual(movedCount, movingIDs.count, "\(name): every waiting row moves", file: file, line: line)
    }

    func waitUntil(timeout: Duration = .seconds(10), _ condition: (QueueTestChat) -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        layout()
        while !condition(self) {
            guard ContinuousClock.now < deadline else { throw AgentTestTimeout() }
            try await Task.sleep(for: .milliseconds(16))
            layout()
        }
    }

    /// Waits until the list's offset, insets and rows stay put for 20 frames
    func waitForStableLayout(timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now + timeout
        var state = layoutState
        var stableSamples = 0
        while stableSamples < 20 {
            guard ContinuousClock.now < deadline else { throw AgentTestTimeout() }
            try await Task.sleep(for: .milliseconds(16))
            layout()
            let nextState = layoutState
            stableSamples = nextState == state ? stableSamples + 1 : 0
            state = nextState
        }
    }

    private var layoutState: [CGFloat] {
        [
            collectionView.contentOffset.y,
            collectionView.contentInset.bottom,
            collectionView.collectionViewLayout.collectionViewContentSize.height,
        ]
    }
}

/// A backend that answers nothing and keeps the questions sent while the Agent thinks waiting at the chat's end, as the
/// Agent's does: Stop ends the thinking, its typing row leaving, and sends the first question that waits
@MainActor
private final class QueueTestBackend: AgentBackend {
    var context: AgentBackendContext?
    private(set) var typingIndicatorID: AgentItemID?
    private(set) var waitingIDs: [AgentItemID] = []
    /// Stop sends the first question that waits, as the Agent's does
    var sendsNextOnStop = true

    var canSendMessages: Bool { typingIndicatorID == nil && waitingIDs.isEmpty }
    var canAcceptMessages: Bool { true }
    var trailingItemIDs: [AgentItemID] { waitingIDs }
    var canStopAnswer: Bool { typingIndicatorID != nil }

    func attach(to context: AgentBackendContext) { self.context = context }
    func detach() { context = nil }
    func loadHints(animated: Bool) {}
    func prepareForEditing(_ editContext: AgentBackendEditContext) {}
    func clearConversation() {}

    func didSendUserMessage(
        _ text: String,
        userMessageID: AgentItemID,
        source: AgentBackendSendSource,
        editContext: AgentBackendEditContext?
    ) {
        guard canSendMessages else {
            waitingIDs.append(userMessageID)
            return
        }
        startThinking()
    }

    func stopAnswer() {
        guard let typingIndicatorID else { return }
        self.typingIndicatorID = nil
        context?.removeItem(id: typingIndicatorID, animated: false)
        guard sendsNextOnStop, !waitingIDs.isEmpty else { return }
        let next = waitingIDs.removeFirst()
        context?.revealSentMessage(next) { self.startThinking() }
    }

    /// The Agent thinks: its typing row comes, above the questions that wait
    func startThinking() {
        let indicator = AgentTypingIndicator()
        typingIndicatorID = indicator.id
        context?.append(.typingIndicator(indicator), animated: true)
    }
}
