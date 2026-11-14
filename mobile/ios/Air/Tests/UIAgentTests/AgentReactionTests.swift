import XCTest
import UIKit
import ContextMenuKit
@testable import UIAgent
import UIComponents
import WalletContext
import WalletCore
import WalletResources

/// An answer's reactions, as Telegram's: the cloud over the lifted answer, the chosen reaction's flight to the bubble's
/// corner, and its emoji there
@MainActor
final class AgentReactionTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    // MARK: - The cloud's placement

    /// The capsule stands 6 pt above the answer and never over it, reaching 47 pt past its trailing edge, while the
    /// tail goes down beside the answer's top trailing corner: the 16 pt circle's centre 4 pt past the edge, the 8 pt
    /// one's 13 pt past it and 8 pt below the top
    func testCloudStandsAboveTheAnswerWithItsTailAtTheCorner() throws {
        let answer = CGRect(x: 16, y: 400, width: 200, height: 80)
        let placement = makeAccessory().getPlacement(
            sourceRect: answer,
            minX: 0,
            maxX: 402,
            screenInsets: AgentMessageMenu.makeStyle(isOutgoing: false).screenInsets,
            isRightToLeft: false
        )
        XCTAssertEqual(placement.bodyOffset, 0)
        let capsule = getCapsule(in: placement, isRightToLeft: false)
        XCTAssertEqual(capsule.maxY, answer.minY - 6, accuracy: 0.01)
        XCTAssertEqual(capsule.maxX, answer.maxX + 47, accuracy: 0.01)
        XCTAssertEqual(capsule.size, CGSize(width: 108, height: 56))
        XCTAssertFalse(capsule.intersects(answer))
        let (large, small) = getTailCircles(in: placement, isRightToLeft: false)
        XCTAssertEqual(large.midX, answer.maxX + 4, accuracy: 0.01)
        XCTAssertEqual(large.midY, capsule.maxY, accuracy: 0.01)
        XCTAssertEqual(small.midX, answer.maxX + 13, accuracy: 0.01)
        XCTAssertEqual(small.midY, answer.minY + 8, accuracy: 0.01)
    }

    /// Near the screen's side the capsule slides inward and keeps 12 pt from it, while the tail stays at the answer's
    /// corner; a right-to-left layout mirrors all of it
    func testCloudSlidesInsideTheScreenWithItsTailKeptAtTheCorner() throws {
        let accessory = makeAccessory()
        let insets = AgentMessageMenu.makeStyle(isOutgoing: false).screenInsets
        let answer = CGRect(x: 16, y: 400, width: 356, height: 80)
        let placement = accessory.getPlacement(sourceRect: answer, minX: 0, maxX: 402, screenInsets: insets, isRightToLeft: false)
        let capsule = getCapsule(in: placement, isRightToLeft: false)
        XCTAssertEqual(capsule.maxX, 402 - 12, accuracy: 0.01)
        XCTAssertEqual(placement.bodyOffset, -(answer.maxX + 47 - (402 - 12)), accuracy: 0.01)
        XCTAssertEqual(placement.tailOffset, 0)
        let tail = getTailCircles(in: placement, isRightToLeft: false)
        XCTAssertEqual(tail.large.midX, answer.maxX + 4, accuracy: 0.01)
        XCTAssertEqual(tail.small.midX, answer.maxX + 13, accuracy: 0.01)
        XCTAssertTrue(placement.frame.contains(capsule))

        let mirrored = CGRect(x: 30, y: 400, width: 356, height: 80)
        let rightToLeft = accessory.getPlacement(sourceRect: mirrored, minX: 0, maxX: 402, screenInsets: insets, isRightToLeft: true)
        let mirroredCapsule = getCapsule(in: rightToLeft, isRightToLeft: true)
        XCTAssertEqual(mirroredCapsule.minX, 12, accuracy: 0.01)
        XCTAssertEqual(rightToLeft.tailOffset, 0)
        let mirroredTail = getTailCircles(in: rightToLeft, isRightToLeft: true)
        XCTAssertEqual(mirroredTail.large.midX, mirrored.minX - 4, accuracy: 0.01)
        XCTAssertEqual(mirroredTail.small.midX, mirrored.minX - 13, accuracy: 0.01)
        XCTAssertEqual(mirroredCapsule.maxY, mirrored.minY - 6, accuracy: 0.01)
    }

    /// A tail at the corner of an answer that reaches the screen's side would put its small circle past the side, so
    /// it hangs from the capsule as the design draws it, over the answer's top near its corner, at the same heights
    /// under the capsule; a right-to-left layout mirrors it
    func testTailHangsFromTheCapsuleWhenTheCornerIsAtTheScreensSide() throws {
        let accessory = makeAccessory()
        let insets = AgentMessageMenu.makeStyle(isOutgoing: false).screenInsets
        let answer = CGRect(x: 16, y: 400, width: 370, height: 80)
        let placement = accessory.getPlacement(sourceRect: answer, minX: 0, maxX: 402, screenInsets: insets, isRightToLeft: false)
        XCTAssertEqual(placement.tailOffset, placement.bodyOffset)
        let capsule = getCapsule(in: placement, isRightToLeft: false)
        XCTAssertEqual(capsule.maxX, 402 - 12, accuracy: 0.01)
        XCTAssertEqual(capsule.maxY, answer.minY - 6, accuracy: 0.01)
        let tail = getTailCircles(in: placement, isRightToLeft: false)
        XCTAssertEqual(tail.large.midX, capsule.minX + 65, accuracy: 0.01)
        XCTAssertEqual(tail.large.midY, capsule.maxY, accuracy: 0.01)
        XCTAssertEqual(tail.small.midX, capsule.minX + 74, accuracy: 0.01)
        XCTAssertEqual(tail.small.midY, capsule.minY + 70, accuracy: 0.01)
        XCTAssertTrue(tail.small.intersects(answer), "The small circle hangs over the answer's top")
        XCTAssertLessThanOrEqual(tail.small.maxX, 402 - 4)
        XCTAssertTrue(placement.frame.contains(tail.small))

        let rightToLeft = accessory.getPlacement(sourceRect: answer, minX: 0, maxX: 402, screenInsets: insets, isRightToLeft: true)
        XCTAssertEqual(rightToLeft.tailOffset, rightToLeft.bodyOffset)
        let mirroredCapsule = getCapsule(in: rightToLeft, isRightToLeft: true)
        XCTAssertEqual(mirroredCapsule.minX, 12, accuracy: 0.01)
        let mirroredTail = getTailCircles(in: rightToLeft, isRightToLeft: true)
        XCTAssertEqual(mirroredTail.large.midX, mirroredCapsule.maxX - 65, accuracy: 0.01)
        XCTAssertEqual(mirroredTail.small.midX, mirroredCapsule.maxX - 74, accuracy: 0.01)
        XCTAssertEqual(mirroredTail.small.midY, mirroredCapsule.minY + 70, accuracy: 0.01)
    }

    /// The cloud is the menu panel's material with the panel's tint and shadow: none of its own
    func testCloudHasTheMenusTintAndShadow() {
        let accessory = makeAccessory()
        XCTAssertNil(accessory.glassTint, "The menu's tint")
        XCTAssertNil(accessory.shadow, "The panel's shadow, which native glass draws as its own depth")
    }

    /// A menu that moves the answer into view makes room for the cloud above it, so the cloud never covers it
    func testMenuMovesTheAnswerToMakeRoomForTheCloudAbove() async throws {
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .user, text: "Rate this", isStreaming: false),
            makeAnswer(feedback: nil),
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat)
        let overlay = try openMenu(on: cell, in: chat)
        defer { overlay.removeFromSuperview() }
        try await Task.sleep(for: .milliseconds(700))
        let pill = try XCTUnwrap(findDescendants(of: overlay).compactMap { $0 as? AgentFeedbackPillView }.first)
        let portal = try XCTUnwrap(findDescendants(of: overlay).first { String(describing: type(of: $0)) == "_UIPortalView" })
        let pillFrame = pill.convert(pill.bounds, to: overlay)
        let answerFrame = portal.convert(portal.bounds, to: overlay)
        XCTAssertLessThanOrEqual(pillFrame.minY + AgentFeedbackPillMetrics.bodySize.height, answerFrame.minY - 6 + 0.5)
        XCTAssertEqual(pill.buttons.map(\.option), [.like, .dislike])
    }

    /// Over an answer taller than the screen, the menu opens at its panel with the answer scrolled up: the cloud stays
    /// at the menu's top limit, in reach and drawn over the answer, which scrolls under it, and rides 6 pt above the
    /// answer's top once that comes down far enough
    func testCloudStaysInReachOverALongAnswer() async throws {
        let text = (1...60).map { "Line \($0) of a long answer that keeps the reader busy." }.joined(separator: "\n")
        var answer = AgentMessage(role: .assistant, text: text, isStreaming: false)
        answer.canRate = true
        let chat = AgentTestChat(messages: [AgentMessage(role: .user, text: "Tell me more", isStreaming: false), answer])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat)
        XCTAssertGreaterThan(cell.bounds.height, chat.collectionView.bounds.height)
        let overlay = try openMenu(on: cell, in: chat)
        defer { overlay.removeFromSuperview() }
        try await Task.sleep(for: .milliseconds(700))
        let pill = try XCTUnwrap(findDescendants(of: overlay).compactMap { $0 as? AgentFeedbackPillView }.first)
        let portal = try XCTUnwrap(findDescendants(of: overlay).first { String(describing: type(of: $0)) == "_UIPortalView" })
        let scrollView = try XCTUnwrap(overlay.subviews.flatMap(\.subviews).compactMap { $0 as? UIScrollView }.first)
        let topLimit = overlay.safeAreaInsets.top + ContextMenuSourceRelocation().topInset
        let capsuleHeight = AgentFeedbackPillMetrics.bodySize.height
        func getCapsuleTop() -> CGFloat { pill.convert(pill.bounds, to: overlay).minY }
        func getAnswerTop() -> CGFloat { portal.convert(portal.bounds, to: overlay).minY }

        // Opened at the panel: the answer's top is far above, and the cloud stays at the top limit over the answer
        XCTAssertGreaterThan(scrollView.contentOffset.y, 100)
        XCTAssertEqual(getCapsuleTop(), topLimit, accuracy: 0.5)
        XCTAssertLessThan(getAnswerTop(), topLimit - capsuleHeight)
        let container = try XCTUnwrap(scrollView.superview)
        let cloudIndex = try XCTUnwrap(container.subviews.firstIndex { pill.isDescendant(of: $0) })
        let answerIndex = try XCTUnwrap(container.subviews.firstIndex { portal.isDescendant(of: $0) })
        XCTAssertGreaterThan(cloudIndex, answerIndex, "The answer scrolls under the cloud")
        XCTAssertFalse(pill.isDescendant(of: scrollView), "The cloud doesn't scroll with the answer")

        // Halfway, it still stays at the limit, without moving with the answer
        let openingOffset = scrollView.contentOffset.y
        scrollView.contentOffset.y = openingOffset / 2
        XCTAssertEqual(getCapsuleTop(), topLimit, accuracy: 0.5)

        // At the answer's top, and pulled down past it, the cloud rides above the answer as over a short one
        for offset: CGFloat in [0, -40] {
            scrollView.contentOffset.y = offset
            XCTAssertEqual(getCapsuleTop() + capsuleHeight + 6, getAnswerTop(), accuracy: 0.5, "At \(offset)")
            XCTAssertGreaterThanOrEqual(getCapsuleTop(), topLimit - 0.5)
        }
        scrollView.contentOffset.y = openingOffset
        XCTAssertEqual(getCapsuleTop(), topLimit, accuracy: 0.5)
    }

    // MARK: - The cloud's buttons

    /// The heart comes first and the broken heart second; the current rating has the same neutral circle behind it
    /// whichever it is, and choosing it again withdraws the rating, while the other one rates and its icon leaves the
    /// cloud for the answer's corner. An icon chooses as the finger lets go of it, after a long press as after a tap.
    func testCloudShowsTheRatingAndChoosingItAgainWithdrawsIt() throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        var selections: [AgentFeedbackPillView.Selection] = []
        let pill = AgentFeedbackPillView(feedback: .like) { selections.append($0) }
        window.addSubview(pill)
        pill.layoutIfNeeded()
        let heart = pill.buttons[0]
        let brokenHeart = pill.buttons[1]
        XCTAssertEqual(heart.accessibilityLabel, lang("Like"))
        XCTAssertEqual(brokenHeart.accessibilityLabel, lang("Dislike"))
        XCTAssertFalse(heart.selectionView.isHidden)
        XCTAssertTrue(brokenHeart.selectionView.isHidden)
        XCTAssertTrue(heart.accessibilityTraits.contains(.selected))
        XCTAssertEqual(heart.iconFrame.size, CGSize(width: 36, height: 36))
        XCTAssertEqual(heart.convert(heart.iconFrame, to: pill).origin, CGPoint(x: 12, y: 10))
        XCTAssertEqual(brokenHeart.convert(brokenHeart.iconFrame, to: pill).origin, CGPoint(x: 60, y: 10))
        XCTAssertEqual(heart.iconView.bounds.size, CGSize(width: 38, height: 38), "The emoji's box around the icon")
        XCTAssertEqual(heart.iconView.center, CGPoint(x: heart.iconFrame.midX, y: heart.iconFrame.midY))
        for button in [heart, brokenHeart] {
            XCTAssertEqual(button.iconView.feedback, button.option)
            XCTAssertEqual(button.iconView.animation, .select, "Each icon is the reaction's still")
            XCTAssertFalse(button.iconView.isPlaying)
            XCTAssertEqual(button.selectionView.backgroundColor, .tertiarySystemFill, "Telegram's neutral circle for each")
            XCTAssertEqual(button.selectionView.bounds.size, CGSize(width: 44, height: 44))
            XCTAssertEqual(button.selectionView.center, heart.iconView.center)
            XCTAssertTrue(button.allControlEvents.contains(.touchUpInside), "It chooses on release")
            XCTAssertTrue(button.gestureRecognizers?.isEmpty ?? true, "and a long press is a tap")
        }

        heart.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections.count, 1)
        XCTAssertNil(selections[0].feedback)
        XCTAssertNil(selections[0].icon, "Nothing leaves the cloud for a withdrawn rating")
        XCTAssertNil(pill.chosenOption)

        brokenHeart.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections.count, 2)
        XCTAssertEqual(selections[1].feedback, .dislike)
        XCTAssertTrue(selections[1].icon === brokenHeart.iconView, "The chosen icon leaves the cloud for the corner")
        XCTAssertEqual(pill.chosenOption, .dislike)
    }

    // MARK: - The corner's emoji

    /// The answer's reaction is its emoji alone, 22 pt, with no chip, ring or shadow: its middle stands 3 pt inside the
    /// bubble's trailing edge and its bottom 3 pt below the bubble's, mirrored in a right-to-left layout, and Telegram's
    /// landing plays in twice its square
    func testReactionSitsOnTheBubblesBottomTrailingCorner() {
        let bubble = CGRect(x: 16, y: 30, width: 300, height: 120)
        for isRightToLeft in [false, true] {
            let frame = AgentReactionBadgeView.getFrame(forBubble: bubble, isRightToLeft: isRightToLeft)
            XCTAssertEqual(frame.midX, isRightToLeft ? bubble.minX + 3 : bubble.maxX - 3, accuracy: 0.01)
            XCTAssertEqual(frame.maxY, bubble.maxY + 3, accuracy: 0.01)
            XCTAssertEqual(frame.size, CGSize(width: 22, height: 22))
        }
        let badge = AgentReactionBadgeView(frame: CGRect(origin: .zero, size: AgentReactionBadgeView.Metrics.size))
        badge.layoutIfNeeded()
        XCTAssertEqual(badge.subviews, [badge.iconView], "The emoji alone")
        XCTAssertEqual(badge.layer.shadowOpacity, 0)
        XCTAssertNil(badge.backgroundColor)
        XCTAssertEqual(badge.iconView.bounds.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(badge.iconView.center, CGPoint(x: 11, y: 11))
    }

    /// An answer rated before the chat opens shows its emoji at once on its bubble's bottom trailing corner, resting on
    /// the last frame of Telegram's landing, with "Liked" for VoiceOver; a question never has one. Nothing clips the
    /// emoji, and it shows over the suggestions under the bubble and over the next row.
    func testRatedAnswerShowsItsReactionOnTheCorner() async throws {
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .user, text: "Rate this", isStreaming: false),
            makeAnswer(feedback: .like),
            AgentMessage(role: .user, text: "And this", isStreaming: false),
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat)
        let badge = cell.reactionBadgeView
        XCTAssertFalse(badge.isHidden)
        XCTAssertEqual(badge.feedback, .like)
        XCTAssertEqual(badge.iconView.feedback, .like)
        XCTAssertEqual(badge.iconView.animation, .center)
        XCTAssertFalse(badge.iconView.isPlaying, "It rests on the last frame of Telegram's landing")
        let iconFrame = try XCTUnwrap(badge.presentedIconFrameInWindow)
        XCTAssertEqual(iconFrame.width, 22, accuracy: 0.01)
        XCTAssertEqual(iconFrame.height, 22, accuracy: 0.01)
        let stack = try XCTUnwrap(badge.superview as? UIStackView)
        let bubble = try XCTUnwrap(stack.arrangedSubviews.first)
        let bubbleFrame = bubble.convert(bubble.bounds, to: nil)
        XCTAssertEqual(iconFrame.midX, bubbleFrame.maxX - 3, accuracy: 0.5, "3 pt inside the bubble's trailing edge")
        XCTAssertEqual(iconFrame.maxY, bubbleFrame.maxY + 3, accuracy: 0.5, "3 pt below its bottom")
        XCTAssertTrue(findDescendants(of: cell).contains { $0.accessibilityValue == lang("Liked") })
        XCTAssertFalse(badge.isAccessibilityElement)
        XCTAssertTrue(badge.accessibilityElementsHidden)

        XCTAssertFalse(cell.clipsToBounds)
        XCTAssertFalse(cell.contentView.clipsToBounds)
        XCTAssertFalse(stack.clipsToBounds)
        XCTAssertTrue(cell.contentView.subviews.last === stack, "Over the suggestions under the bubble")
        XCTAssertTrue(stack.subviews.last === badge, "and over the action rows")
        let nextRow = try XCTUnwrap(chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first {
            $0.accessibilityIdentifier == "agent_message_user" && $0.frame.minY > cell.frame.minY
        })
        XCTAssertGreaterThan(cell.layer.zPosition, nextRow.layer.zPosition, "Over the next row")
        XCTAssertTrue(chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }
            .filter { $0 !== cell }
            .allSatisfy { $0.reactionBadgeView.isHidden })
    }

    /// The corner's emoji takes no room: a rated row is as tall as an unrated one, and the emoji covers none of the
    /// answer's text, on a one-line answer and on the last line of a long one
    func testCornersEmojiTakesNoRoomAndCoversNoText() throws {
        let long = (1...12).map { _ in "An answer whose lines run from one side of its bubble to the other." }
            .joined(separator: " ")
        for text in ["Yes.", long] {
            var rated = makeAnswer(feedback: .like)
            rated.text = text
            var unrated = makeAnswer(feedback: nil)
            unrated.text = text
            let height = getRowHeight(of: rated)
            XCTAssertEqual(height, getRowHeight(of: unrated), accuracy: 0.01, "No room for the emoji")
            let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: height))
            cell.configure(with: rated, onURLTap: { _ in })
            cell.layoutIfNeeded()
            let badge = cell.reactionBadgeView
            let stack = try XCTUnwrap(badge.superview as? UIStackView)
            let bubble = try XCTUnwrap(stack.arrangedSubviews.first)
            let textArea = bubble.frame.insetBy(
                dx: AgentMessageCellMetrics.bodyHorizontalPadding,
                dy: AgentMessageCellMetrics.bodyVerticalPadding
            )
            let overlap = badge.frame.intersection(textArea)
            XCTAssertTrue(
                overlap.isNull || min(overlap.width, overlap.height) < 0.01,
                "The emoji covers no text of \(text.count) characters"
            )
            XCTAssertEqual(badge.frame.midX, bubble.frame.maxX - 3, accuracy: 0.01)
        }
    }

    /// While the menu that changed the rating closes, the message's ratings leave the corner as it is; once released,
    /// the corner takes the rating the message has by then
    func testHeldReactionKeepsTheMenusChoiceUntilReleased() throws {
        AgentReactionMotion.isReducedOverride = false
        defer { AgentReactionMotion.isReducedOverride = nil }
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 120))
        var answer = makeAnswer(feedback: nil)
        cell.configure(with: answer, onURLTap: { _ in })
        let badge = cell.reactionBadgeView
        XCTAssertTrue(badge.isHidden)

        cell.holdFeedback()
        answer.feedback = .dislike
        cell.configure(with: answer, onURLTap: { _ in })
        XCTAssertTrue(badge.isHidden, "The corner waits for the menu's choice to land")
        cell.releaseFeedback()
        XCTAssertFalse(cell.isFeedbackHeld)
        XCTAssertEqual(badge.feedback, .dislike, "and takes the message's rating once released")
        XCTAssertFalse(badge.isHidden)

        answer.feedback = nil
        cell.configure(with: answer, onURLTap: { _ in })
        XCTAssertTrue(badge.isHidden)

        cell.holdFeedback()
        cell.prepareForReuse()
        XCTAssertFalse(cell.isFeedbackHeld)
        XCTAssertFalse(cell.isReactionLanding)
    }

    /// Choosing the heart flies it from the cloud to the bubble's corner as the cloud closes into its tail, and the
    /// corner's emoji takes it over in the frame it arrives, where the corner shows: on the menu's replica of the answer
    /// while the closing menu still shows it, in the chat once the menu is gone, with Telegram's landing and burst. A changed reaction flies the same way while the heart scales down and fades
    /// as the broken heart lands, and a withdrawn one's emoji scales down and fades out. Nothing in the chat moves.
    func testChosenReactionFliesToTheCornerAndChoosingItAgainRemovesIt() async throws {
        AgentReactionMotion.isReducedOverride = false
        defer { AgentReactionMotion.isReducedOverride = nil }
        let chat = RatingChat(messages: [
            AgentMessage(role: .user, text: "Rate this", isStreaming: false),
            makeAnswer(feedback: nil),
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat.collectionView)
        let badge = cell.reactionBadgeView
        let rowFrame = cell.frame
        XCTAssertTrue(badge.isHidden)

        let overlay = try openMenu(on: cell, in: chat.window)
        let pill = try XCTUnwrap(findDescendants(of: overlay).compactMap { $0 as? AgentFeedbackPillView }.first)
        try await Task.sleep(for: .milliseconds(450))
        let heart = pill.buttons[0]
        heart.sendActions(for: .touchUpInside)
        let flight = try XCTUnwrap(cell.reactionFlight, "The heart leaves the cloud")
        XCTAssertEqual(heart.iconView.alpha, 0)
        XCTAssertTrue(flight.iconView.superview === chat.window, "Nothing clips the flight")
        let deadline = ContinuousClock.now + .seconds(2)
        while flight.arrivalTime == nil {
            XCTAssertTrue(badge.isHidden, "The corner waits for the flying heart")
            guard ContinuousClock.now < deadline else { throw AgentTestTimeout() }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertNil(flight.iconView.superview)
        XCTAssertFalse(badge.isHidden, "The corner's emoji takes the heart over in the frame it arrives")
        XCTAssertEqual(badge.feedback, .like)
        XCTAssertEqual(badge.iconView.animation, .center)
        XCTAssertTrue(badge.iconView.isPlaying, "and plays Telegram's landing")
        XCTAssertFalse(cell.isReactionLanding)
        // The flight and the menu's close both take 0.2 s, so either can end first
        let corner = try XCTUnwrap(getReplicaFrame(of: badge, in: overlay) ?? badge.presentedIconFrameInWindow)
        XCTAssertEqual(flight.iconView.center.x, corner.midX, accuracy: 1, "The heart lands where the corner shows")
        XCTAssertEqual(flight.iconView.center.y, corner.midY, accuracy: 1)
        XCTAssertEqual(flight.iconView.transform.a, 1, accuracy: 0.001, "at the corner's emoji's size")
        let burst = try XCTUnwrap(flight.burst)
        XCTAssertEqual(burst.view.animation, .burst)
        XCTAssertTrue(burst.view.superview === chat.window)

        try await waitUntil { overlay.superview == nil && !cell.isFeedbackHeld }
        XCTAssertEqual(cell.frame, rowFrame, "Nothing in the chat moves")
        XCTAssertEqual(chat.backend.ratings, [.like])

        let changeOverlay = try openMenu(on: cell, in: chat.window)
        XCTAssertFalse(badge.isHidden, "The corner's emoji stays on the answer while its menu is open")
        XCTAssertEqual(badge.alpha, 1)
        let changePill = try XCTUnwrap(findDescendants(of: changeOverlay).compactMap { $0 as? AgentFeedbackPillView }.first)
        XCTAssertFalse(changePill.buttons[0].selectionView.isHidden, "The cloud shows the answer's rating")
        try await Task.sleep(for: .milliseconds(450))
        changePill.buttons[1].sendActions(for: .touchUpInside)
        let change = try XCTUnwrap(cell.reactionFlight)
        XCTAssertFalse(change === flight)
        XCTAssertEqual(badge.feedback, .like, "The heart stays until the broken heart lands")
        let changeDeadline = ContinuousClock.now + .seconds(2)
        while change.arrivalTime == nil {
            XCTAssertEqual(badge.feedback, .like)
            guard ContinuousClock.now < changeDeadline else { throw AgentTestTimeout() }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(badge.feedback, .dislike)
        let leaving = try XCTUnwrap(badge.subviews.first { $0 !== badge.iconView } as? UIImageView, "The heart goes")
        XCTAssertEqual(leaving.transform.a, 0.2, accuracy: 0.001, "scaling down")
        XCTAssertEqual(leaving.alpha, 0, "and fading out")
        let swap = try XCTUnwrap(leaving.layer.animation(forKey: "opacity"))
        XCTAssertEqual(swap.duration, 0.12, accuracy: 0.001, "over Telegram's 0.12 s")
        try await waitUntil { changeOverlay.superview == nil && !cell.isFeedbackHeld }
        XCTAssertEqual(cell.frame, rowFrame)

        let withdrawalOverlay = try openMenu(on: cell, in: chat.window)
        let withdrawalPill = try XCTUnwrap(findDescendants(of: withdrawalOverlay).compactMap { $0 as? AgentFeedbackPillView }.first)
        try await Task.sleep(for: .milliseconds(450))
        withdrawalPill.buttons[1].sendActions(for: .touchUpInside)
        XCTAssertTrue(cell.reactionFlight === change, "Nothing flies")
        XCTAssertEqual(badge.iconView.transform.a, 0.2, accuracy: 0.001, "The broken heart scales down")
        XCTAssertEqual(badge.iconView.alpha, 0, "and fades out")
        XCTAssertEqual(try XCTUnwrap(badge.iconView.layer.animation(forKey: "opacity")).duration, 0.12, accuracy: 0.001)
        try await waitUntil { withdrawalOverlay.superview == nil && !cell.isFeedbackHeld && badge.isHidden }
        XCTAssertEqual(cell.frame, rowFrame)
        XCTAssertEqual(chat.backend.ratings, [.like, .dislike, nil])
    }

    /// The corner's emoji stays on the answer while its menu is open, where the menu's replica of the answer shows it,
    /// and the cloud opens from its tail as on an unrated answer, the rating's circle appearing with its icon; a menu
    /// that closes without a change leaves the emoji as it is, playing nothing
    func testCornersEmojiStaysOnTheAnswerWhileItsMenuIsOpen() async throws {
        AgentReactionMotion.isReducedOverride = false
        defer { AgentReactionMotion.isReducedOverride = nil }
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .user, text: "Rate this", isStreaming: false),
            makeAnswer(feedback: .like),
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat)
        let badge = cell.reactionBadgeView

        let overlay = try openMenu(on: cell, in: chat)
        XCTAssertFalse(badge.isHidden)
        XCTAssertEqual(badge.alpha, 1)
        XCTAssertEqual(badge.iconView.alpha, 1)
        XCTAssertNil(badge.layer.animationKeys(), "Nothing leaves it, and it doesn't hide")
        let replica = try XCTUnwrap(findReplica(in: overlay))
        let mask = try XCTUnwrap(replica.layer.mask as? CAShapeLayer)
        let emojiCenter = CGPoint(x: badge.frame.midX, y: badge.frame.midY)
        XCTAssertTrue(mask.path?.contains(emojiCenter) == true, "The answer's replica shows the corner's emoji")
        XCTAssertTrue(
            mask.path?.contains(CGPoint(x: badge.frame.maxX + 8, y: badge.frame.maxY + 8)) == true,
            "and the square Telegram's landing plays in"
        )
        let pill = try XCTUnwrap(findDescendants(of: overlay).compactMap { $0 as? AgentFeedbackPillView }.first)
        let heart = pill.buttons[0]
        XCTAssertFalse(heart.selectionView.isHidden)
        XCTAssertEqual(heart.iconView.alpha, 0, "The rated icon waits for the capsule to reach it, as the other does")
        XCTAssertEqual(heart.selectionView.alpha, 0, "and its circle with it")
        try await waitUntil { heart.iconView.alpha == 1 }
        XCTAssertEqual(heart.iconView.animation, .appear)
        XCTAssertNotNil(heart.selectionView.layer.animation(forKey: "transform"), "The circle grows in with its icon")
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(overlay.accessibilityPerformEscape())
        try await waitUntil { overlay.superview == nil }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(badge.feedback, .like)
        XCTAssertFalse(badge.isHidden)
        XCTAssertEqual(badge.iconView.animation, .center)
        XCTAssertFalse(badge.iconView.isPlaying, "The emoji plays nothing")
        XCTAssertNil(badge.iconView.layer.animationKeys(), "and doesn't move")
        XCTAssertEqual(badge.iconView.transform, .identity)
    }

    /// A tap on the corner's emoji opens the answer's menu, as a long press on the bubble does
    func testTapOnTheCornersEmojiOpensTheAnswersMenu() async throws {
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .user, text: "Rate this", isStreaming: false),
            makeAnswer(feedback: .dislike),
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat)
        let badge = cell.reactionBadgeView
        let point = badge.convert(CGPoint(x: badge.bounds.maxX + 4, y: badge.bounds.midY), to: cell)
        XCTAssertTrue(cell.hitTest(point, with: nil)?.isDescendant(of: badge) == true, "A tap near the emoji reaches it")
        XCTAssertTrue(badge.gestureRecognizers?.contains { $0 is UITapGestureRecognizer } == true)
        badge.onTap?()
        let overlay = try XCTUnwrap(chat.window.subviews.last { String(describing: type(of: $0)) == "ContextMenuOverlayView" })
        defer { overlay.removeFromSuperview() }
        let pill = try XCTUnwrap(findDescendants(of: overlay).compactMap { $0 as? AgentFeedbackPillView }.first)
        XCTAssertFalse(pill.buttons[1].selectionView.isHidden)
    }

    // MARK: - Telegram's emoji

    /// The cloud's icons play Telegram's appearance as the capsule reaches them and rest on its last frame, the
    /// reaction's still; a press plays the selection under the finger
    func testCloudIconsPlayTelegramsAppearanceAndSelection() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the stills")
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .user, text: "Rate this", isStreaming: false),
            makeAnswer(feedback: nil),
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat)
        let overlay = try openMenu(on: cell, in: chat)
        defer { overlay.removeFromSuperview() }
        let pill = try XCTUnwrap(findDescendants(of: overlay).compactMap { $0 as? AgentFeedbackPillView }.first)
        XCTAssertTrue(pill.buttons.allSatisfy { $0.iconView.alpha == 0 }, "Each icon waits for the capsule to reach it")

        try await waitUntil { pill.buttons.allSatisfy { $0.iconView.animation == .appear } }
        XCTAssertTrue(pill.buttons.allSatisfy { $0.iconView.alpha == 1 && $0.iconView.feedback == $0.option })
        XCTAssertTrue(pill.buttons.contains { $0.iconView.isPlaying }, "The appearance plays")
        try await waitUntil { pill.buttons.allSatisfy { !$0.iconView.isPlaying } }
        XCTAssertTrue(pill.buttons.allSatisfy { $0.iconView.animation == .appear }, "It rests on its last frame")

        let brokenHeart = pill.buttons[1]
        brokenHeart.isHighlighted = true
        XCTAssertEqual(brokenHeart.iconView.animation, .select)
        XCTAssertTrue(brokenHeart.iconView.isPlaying, "A press plays the selection")
        XCTAssertEqual(brokenHeart.iconView.transform, CGAffineTransform(scaleX: 0.85, y: 0.85))
        brokenHeart.isHighlighted = false
        try await waitUntil { !brokenHeart.iconView.isPlaying }
    }

    /// Telegram's trajectory from the picker: through the start, a point 30 pt above the start halfway across, and the
    /// end, evenly across, so the reaction lifts a little and then drops fast; a move shorter than 5 pt both ways goes
    /// straight. It takes 0.2 s.
    func testTrajectoryLiftsAndDropsFast() {
        XCTAssertEqual(AgentReactionTrajectory.duration, 0.2, accuracy: 0.0001)
        XCTAssertEqual(AgentReactionTrajectory.elevation, 30)
        let start = CGPoint(x: 100, y: 300)
        let end = CGPoint(x: 300, y: 500)
        func getPoint(_ progress: CGFloat) -> CGPoint {
            AgentReactionTrajectory.getPoint(from: start, to: end, progress: progress)
        }
        XCTAssertEqual(getPoint(0), start)
        XCTAssertEqual(getPoint(1).x, end.x, accuracy: 0.001)
        XCTAssertEqual(getPoint(1).y, end.y, accuracy: 0.001)
        let middle = getPoint(0.5)
        XCTAssertEqual(middle.x, 200, accuracy: 0.001, "Halfway across")
        XCTAssertEqual(middle.y, 270, accuracy: 0.001, "30 pt above the start")
        let quarter = getPoint(0.25)
        XCTAssertEqual(quarter.x, 150, accuracy: 0.001, "It goes evenly across")
        // y = a x² + b x + c through the three points, as Telegram's keyframes are
        let x = [start.x, middle.x, end.x]
        let y = [start.y, middle.y, end.y]
        let denominator = (x[0] - x[1]) * (x[0] - x[2]) * (x[1] - x[2])
        let a = (x[2] * (y[1] - y[0]) + x[1] * (y[0] - y[2]) + x[0] * (y[2] - y[1])) / denominator
        let b = (x[0] * x[0] * (y[1] - y[2]) + x[2] * x[2] * (y[0] - y[1]) + x[1] * x[1] * (y[2] - y[0])) / denominator
        let c = (x[1] * x[1] * (x[2] * y[0] - x[0] * y[2]) + x[1] * (x[0] * x[0] * y[2] - x[2] * x[2] * y[0])
            + x[0] * x[2] * (x[2] - x[0]) * y[1]) / denominator
        for progress: CGFloat in [0.1, 0.25, 0.75, 0.9] {
            let point = getPoint(progress)
            XCTAssertEqual(point.y, a * point.x * point.x + b * point.x + c, accuracy: 0.01)
        }
        XCTAssertLessThan(getPoint(0.25).y, start.y, "It lifts first")
        XCTAssertGreaterThan(getPoint(1).y - getPoint(0.75).y, getPoint(0.75).y - getPoint(0.5).y, "and drops ever faster")
        let near = CGPoint(x: start.x + 4, y: start.y - 4)
        XCTAssertEqual(
            AgentReactionTrajectory.getPoint(from: start, to: near, progress: 0.5),
            CGPoint(x: start.x + 2, y: start.y - 2),
            "A move shorter than 5 pt goes straight"
        )
    }

    /// The chosen icon flies on Telegram's trajectory in 0.2 s, linearly, from its place and size in the cloud to the
    /// corner's 22 pt emoji, going over from its drawing to the first frame of Telegram's landing, and Telegram's
    /// 132 pt burst plays around the corner from 0.15 s; the hit hands it over. The icon in the cloud hides as it leaves.
    func testChosenIconFliesOnTelegramsTrajectory() async throws {
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let target = CGRect(x: 300, y: 500, width: 22, height: 22)
        let cloud = UIView(frame: CGRect(x: 70, y: 272, width: 108, height: 56))
        window.addSubview(cloud)
        let slotIcon = AgentReactionEmojiView(boxSize: 38)
        slotIcon.showStill(.select, of: .like, at: .begin)
        slotIcon.center = CGPoint(x: 30, y: 28)
        cloud.addSubview(slotIcon)
        let slotDrawing = try XCTUnwrap(slotIcon.currentDrawing)
        var arrivals = 0
        let flight = try XCTUnwrap(AgentReactionFlight.start(feedback: .like, in: window, from: slotIcon, at: { target }) {
            arrivals += 1
        })
        XCTAssertTrue(slotIcon.superview === cloud)
        XCTAssertEqual(slotIcon.alpha, 0, "The icon leaves its place in the cloud")
        let icon = flight.iconView
        XCTAssertTrue(icon.superview === window)
        XCTAssertEqual(icon.bounds.size, CGSize(width: 44, height: 44), "The corner's emoji's box")
        XCTAssertEqual(icon.center, CGPoint(x: 100, y: 300), "It starts where the icon is")
        XCTAssertEqual(icon.transform.a, 36.0 / 22.0, accuracy: 0.001, "as large as the cloud's 36 pt icon")
        XCTAssertEqual(icon.crossFade ?? -1, 1, accuracy: 0.001)
        let crossFadeImage = try XCTUnwrap(findDescendants(of: icon).compactMap { $0 as? UIImageView }.first {
            $0.image === slotDrawing
        })
        XCTAssertEqual(crossFadeImage.bounds.width * icon.transform.a, 38, accuracy: 0.01, "showing the icon's drawing")
        XCTAssertEqual(icon.animation, .center, "over the first frame of Telegram's landing")
        XCTAssertFalse(icon.isPlaying)
        XCTAssertNil(flight.burst)

        // On every frame it stands on the trajectory, its size and drawing going over linearly with it
        var samples: [(time: CFTimeInterval, center: CGPoint, scale: CGFloat, crossFade: CGFloat)] = []
        let deadline = ContinuousClock.now + .seconds(2)
        while arrivals == 0 {
            samples.append((CACurrentMediaTime(), icon.center, icon.transform.a, icon.crossFade ?? 0))
            guard ContinuousClock.now < deadline else { throw AgentTestTimeout() }
            try await Task.sleep(for: .milliseconds(4))
        }
        let start = CGPoint(x: 100, y: 300)
        let end = CGPoint(x: target.midX, y: target.midY)
        for sample in samples.dropFirst() where sample.center != start {
            let progress = (sample.center.x - start.x) / (end.x - start.x)
            let point = AgentReactionTrajectory.getPoint(from: start, to: end, progress: progress)
            XCTAssertEqual(sample.center.y, point.y, accuracy: 0.01, "On the trajectory")
            XCTAssertEqual(sample.scale, 36.0 / 22.0 + (1 - 36.0 / 22.0) * progress, accuracy: 0.001)
            XCTAssertEqual(sample.crossFade, 1 - progress, accuracy: 0.001)
            let elapsed = CGFloat((sample.time - flight.startTime) / AgentReactionTrajectory.duration)
            XCTAssertEqual(progress, elapsed, accuracy: 0.15, "Linear in time")
        }
        XCTAssertEqual(arrivals, 1)
        XCTAssertNil(icon.superview, "The hit hands the emoji over")
        XCTAssertEqual(icon.center, end, "on the corner")
        XCTAssertEqual(icon.transform.a, 1, accuracy: 0.001, "as large as the corner's 22 pt emoji")
        let flightTime = try XCTUnwrap(flight.arrivalTime) - flight.startTime
        XCTAssertGreaterThanOrEqual(flightTime, 0.2, "Telegram's 0.2 s")
        XCTAssertLessThan(flightTime, 0.3)
        let burstDelay = try XCTUnwrap(flight.burstStartTime) - flight.startTime
        XCTAssertGreaterThanOrEqual(burstDelay, 0.15, "The burst starts 0.15 s into the flight")
        XCTAssertLessThanOrEqual(burstDelay, flightTime)
        let burst = try XCTUnwrap(flight.burst)
        XCTAssertEqual(burst.view.animation, .burst)
        XCTAssertEqual(burst.view.feedback, .like)
        XCTAssertEqual(burst.view.bounds.size, CGSize(width: 132, height: 132))
        XCTAssertEqual(burst.view.center, end, "around the corner")
        XCTAssertTrue(burst.view.superview === window, "over everything")
        XCTAssertTrue(window.subviews.last === burst.view)
        try await waitUntil { burst.view.superview == nil }
    }

    /// Changing the corner's reaction swaps it as Telegram does: the old emoji scales to 0.2 and fades out over 0.12 s as
    /// the new one lands, playing Telegram's landing; withdrawing scales the emoji down and fades it out the same way
    func testCornersEmojiSwapsAsTelegramsDoes() async throws {
        AgentReactionMotion.isReducedOverride = false
        defer { AgentReactionMotion.isReducedOverride = nil }
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let badge = AgentReactionBadgeView(frame: CGRect(origin: CGPoint(x: 100, y: 300), size: AgentReactionBadgeView.Metrics.size))
        window.addSubview(badge)
        badge.show(.like)
        badge.layoutIfNeeded()
        let heartDrawing = try XCTUnwrap(badge.iconView.currentDrawing)

        badge.land(.dislike)
        XCTAssertEqual(badge.feedback, .dislike)
        XCTAssertEqual(badge.iconView.animation, .center)
        XCTAssertTrue(badge.iconView.isPlaying, "The new one plays Telegram's landing from its first frame")
        XCTAssertEqual(badge.iconView.alpha, 1)
        let leaving = try XCTUnwrap(badge.subviews.first { $0 !== badge.iconView } as? UIImageView)
        XCTAssertTrue(leaving.image === heartDrawing, "The heart goes as it shows")
        XCTAssertEqual(leaving.bounds, badge.iconView.bounds)
        XCTAssertEqual(leaving.center, badge.iconView.center)
        XCTAssertEqual(leaving.transform.a, 0.2, accuracy: 0.001)
        XCTAssertEqual(leaving.alpha, 0)
        XCTAssertEqual(try XCTUnwrap(leaving.layer.animation(forKey: "transform")).duration, 0.12, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(leaving.layer.animation(forKey: "opacity")).duration, 0.12, accuracy: 0.001)
        try await waitUntil { leaving.superview == nil }

        badge.animate(to: nil)
        XCTAssertNil(badge.feedback)
        XCTAssertEqual(badge.iconView.transform.a, 0.2, accuracy: 0.001)
        XCTAssertEqual(badge.iconView.alpha, 0)
        XCTAssertEqual(try XCTUnwrap(badge.iconView.layer.animation(forKey: "opacity")).duration, 0.12, accuracy: 0.001)
        try await waitUntil { badge.isHidden }
        XCTAssertEqual(badge.iconView.transform, .identity)
    }

    /// With Reduce Motion, the icons keep their stills under the finger, and a chosen reaction
    /// neither flies nor bursts: the corner's emoji fades in on the landing's last frame, and fades out
    func testReduceMotionKeepsTheEmojiStill() throws {
        AgentReactionMotion.isReducedOverride = true
        defer { AgentReactionMotion.isReducedOverride = nil }
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        var selections: [AgentFeedbackPillView.Selection] = []
        let pill = AgentFeedbackPillView(feedback: nil) { selections.append($0) }
        window.addSubview(pill)
        pill.layoutIfNeeded()
        let heart = pill.buttons[0]

        heart.isHighlighted = true
        XCTAssertEqual(heart.iconView.animation, .select)
        XCTAssertFalse(heart.iconView.isPlaying, "No selection plays")
        heart.isHighlighted = false
        heart.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections.first?.feedback, .like)

        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 300, width: 402, height: 160))
        cell.configure(with: makeAnswer(feedback: nil), onURLTap: { _ in })
        window.addSubview(cell)
        cell.layoutIfNeeded()
        let badge = cell.reactionBadgeView
        var didLand = false
        cell.flyReaction(.like, from: heart.iconView, onLanding: { didLand = true })
        XCTAssertNil(cell.reactionFlight, "Nothing flies")
        XCTAssertTrue(didLand, "The reaction lands at once")
        XCTAssertEqual(heart.iconView.alpha, 1, "The icon stays in the cloud")
        XCTAssertFalse(window.subviews.contains { $0 is AgentReactionEmojiView }, "No burst")
        XCTAssertFalse(badge.isHidden)
        XCTAssertEqual(badge.iconView.animation, .center)
        XCTAssertFalse(badge.iconView.isPlaying, "The emoji shows the landing's last frame")
        let fadeIn = try XCTUnwrap(badge.iconView.layer.animation(forKey: "opacity"), "fading in")
        XCTAssertEqual(fadeIn.duration, 0.2, accuracy: 0.01)
        cell.animateFeedback(nil)
        XCTAssertEqual(badge.iconView.alpha, 0)
        XCTAssertEqual(badge.iconView.transform, .identity, "It fades out without scaling")

        AgentReactionMotion.isReducedOverride = false
        badge.animate(to: .dislike)
        XCTAssertEqual(badge.iconView.feedback, .dislike)
        XCTAssertTrue(badge.iconView.isPlaying, "Without Reduce Motion the emoji plays the landing")
    }

    /// The animations come from the app's bundle, one per reaction and kind, and the still icon is drawn once
    func testEveryReactionAnimationLoadsOnce() {
        for feedback in ApiAgentV2AnswerFeedback.reactionOrder {
            for animation in AgentReactionAnimation.allCases {
                XCTAssertNotNil(AgentReactionAnimations.getSource(animation, of: feedback), "\(feedback) \(animation)")
            }
            XCTAssertTrue(feedback.reactionImage === feedback.reactionImage)
            XCTAssertEqual(feedback.reactionImage.size, CGSize(width: 36, height: 36))
        }
        let gzip = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x02, 0xff, 0xab, 0xae, 0x05, 0x00, 0x43, 0xbf, 0xa6, 0xa3, 0x02, 0, 0, 0])
        XCTAssertEqual(AgentReactionAnimations.inflateGzip(gzip), Data("{}".utf8))
        XCTAssertNil(AgentReactionAnimations.inflateGzip(Data("{}".utf8)))
    }

    // MARK: - The first reactions' toasts

    /// The reaction's toast is Telegram's copy toast, with the reaction's landing where the copy icon plays: its emoji
    /// 24 pt in the middle of the first 50 pt, playing once the toast is in and resting on its last frame
    func testReactionsToastIsTelegramsCopyToastWithItsLanding() throws {
        for feedback in ApiAgentV2AnswerFeedback.reactionOrder {
            let toast = AgentReactionToasts.makeToast(for: feedback)
            let copyToast = AgentClipboard.copiedToast
            XCTAssertEqual(toast.style, copyToast.style)
            XCTAssertEqual(toast.transition, copyToast.transition)
            XCTAssertEqual(toast.duration, copyToast.duration)
            XCTAssertEqual(toast.icon, .animation(name: AgentReactionAnimations.getName(.center, of: feedback), size: 48))
        }
        XCTAssertEqual(AgentReactionToasts.makeToast(for: .like).message, lang("$agent_feedback_liked_toast"))
        XCTAssertEqual(AgentReactionToasts.makeToast(for: .dislike).message, lang("$agent_feedback_disliked_toast"))

        let controller = UIViewController()
        let window = makeKeyWindow(showing: controller)
        defer { window.isHidden = true }
        let container = try XCTUnwrap(controller.view)
        container.layoutIfNeeded()
        let toastController = ToastController(containerView: container)
        var config = AgentReactionToasts.makeToast(for: .like)
        config.duration = 5
        toastController.showToast(config)
        let toastView = try XCTUnwrap(container.subviews.compactMap { $0 as? ToastView }.first)
        defer { toastView.removeFromSuperview() }
        container.layoutIfNeeded()
        XCTAssertEqual(toastView.frame.height, 50, accuracy: 0.5)
        let label = try XCTUnwrap(findDescendants(of: toastView).compactMap { $0 as? UILabel }.first { $0.text == config.message })
        XCTAssertEqual(label.convert(label.bounds, to: toastView).minX, 50, accuracy: 0.5, "The text starts where the copy toast's does")
        let icon = try XCTUnwrap(findDescendants(of: toastView).first { $0 is WAnimatedSticker })
        let iconFrame = icon.convert(icon.bounds, to: toastView)
        XCTAssertEqual(iconFrame.midX, 25, accuracy: 0.5)
        XCTAssertEqual(iconFrame.midY, toastView.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(iconFrame.width, 48, accuracy: 0.5)
        XCTAssertTrue(toastView.bounds.contains(iconFrame), "The landing plays inside the toast")
        let player = try XCTUnwrap(findDescendants(of: icon).compactMap { $0 as? LottieAnimationView }.first)
        XCTAssertNotNil(player.animationInfo, "The landing is loaded")
        guard case .file(let path)? = player.source else {
            return XCTFail("The landing comes from the bundle's file")
        }
        XCTAssertTrue(path.hasSuffix("/agent_reaction_heart_center.tgs"))

        // Level with the text and as tall as the copy toast: the emoji is drawn in the middle of its square, which
        // stands in the middle of the toast as the text's one line does, where the copy icon stands
        let labelFrame = label.convert(label.bounds, to: toastView)
        XCTAssertEqual(labelFrame.midY, iconFrame.midY, accuracy: 0.5, "The icon's middle is level with the text's")
        XCTAssertLessThan(
            label.textRect(forBounds: label.bounds, limitedToNumberOfLines: label.numberOfLines).height,
            label.font.lineHeight * 1.5,
            "The text takes one line"
        )
        for feedback in ApiAgentV2AnswerFeedback.reactionOrder {
            let landing = AgentReactionAnimations.getStill(.center, of: feedback, at: .end, boxSize: 48, size: 48)
            let drawnCenter = try XCTUnwrap(getDrawnCenter(of: landing), "The landing draws its emoji")
            XCTAssertEqual(drawnCenter.x, 24, accuracy: 1.5, "\(feedback)'s emoji stands in the middle of its square")
            XCTAssertEqual(drawnCenter.y, 24, accuracy: 1.5, "\(feedback)'s emoji stands in the middle of its square")
        }
        let copyController = UIViewController()
        let copyWindow = makeKeyWindow(showing: copyController)
        defer { copyWindow.isHidden = true }
        let copyContainer = try XCTUnwrap(copyController.view)
        copyContainer.layoutIfNeeded()
        let copyToastController = ToastController(containerView: copyContainer)
        copyToastController.showToast(AgentClipboard.copiedToast)
        let copyToastView = try XCTUnwrap(copyContainer.subviews.compactMap { $0 as? ToastView }.first)
        defer { copyToastView.removeFromSuperview() }
        copyContainer.layoutIfNeeded()
        XCTAssertEqual(toastView.frame.height, copyToastView.frame.height, accuracy: 0.5, "As tall as the copy toast")
        let copyIcon = try XCTUnwrap(findDescendants(of: copyToastView).first { $0 is WAnimatedSticker })
        let copyIconFrame = copyIcon.convert(copyIcon.bounds, to: copyToastView)
        XCTAssertEqual(iconFrame.midX, copyIconFrame.midX, accuracy: 0.5, "Where the copy icon stands")
        XCTAssertEqual(
            iconFrame.midY - toastView.bounds.midY,
            copyIconFrame.midY - copyToastView.bounds.midY,
            accuracy: 0.5,
            "Where the copy icon stands"
        )

        // Telegram's overlay colour in the dark theme, a little lighter than a black screen, and the toasts' dark glass
        // in the light one
        let background = try XCTUnwrap(findDescendants(of: toastView).first { $0 is WBlurView }?.backgroundColor)
        func getComponents(_ color: UIColor, _ style: UIUserInterfaceStyle) -> [CGFloat] {
            var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            _ = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return [red, green, blue, alpha]
        }
        let telegramDark: [CGFloat] = [0x1D / 255, 0x1D / 255, 0x1D / 255, 0.9]
        for (value, expected) in zip(getComponents(background, .dark), telegramDark) {
            XCTAssertEqual(value, expected, accuracy: 0.002)
        }
        XCTAssertEqual(getComponents(background, .light), getComponents(.air.toastBackground, .light))
    }

    /// In the chat a toast stands above the composer, as Telegram's chat keeps its overlays above its input panel: 12 pt
    /// over the messages' bottom inset, which ends 11 pt above the field
    func testToastStandsAboveTheComposer() async throws {
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .user, text: "Rate this", isStreaming: false),
            makeAnswer(feedback: nil),
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let controller = chat.controller
        let view = try XCTUnwrap(controller.view)
        controller.showToast(AgentReactionToasts.makeToast(for: .like))
        let toastView = try XCTUnwrap(view.subviews.compactMap { $0 as? ToastView }.first)
        defer { toastView.removeFromSuperview() }
        view.layoutIfNeeded()
        let composer = controller.composerView
        XCTAssertEqual(composer.bounds.height, composer.intrinsicContentSize.height, accuracy: 0.5, "The toast squeezes nothing")
        let fieldTop = composer.convert(composer.inputBackgroundFrame, to: view).minY
        XCTAssertEqual(toastView.frame.maxY, fieldTop - 23, accuracy: 0.5)
    }

    /// Each reaction's toast shows, with its own text, the first time a reaction of its kind lands, and never again on
    /// this install, after a new start as well
    func testEachReactionsToastShowsOnceOnThisInstall() throws {
        let suiteName = "AgentReactionTests.toastsOnce"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let liked = lang("$agent_feedback_liked_toast")
        let disliked = lang("$agent_feedback_disliked_toast")
        XCTAssertFalse(liked.hasPrefix("$"), "The strings come from the catalog")
        XCTAssertFalse(disliked.hasPrefix("$"))
        XCTAssertNotEqual(liked, disliked)
        var toasts: [String] = []
        let reactionToasts = AgentReactionToasts(userDefaults: defaults) { toasts.append($0.message) }

        reactionToasts.explain(.like)
        XCTAssertEqual(toasts, [liked], "The first like")
        reactionToasts.explain(.like)
        XCTAssertEqual(toasts, [liked], "The second like shows nothing")
        reactionToasts.explain(.dislike)
        XCTAssertEqual(toasts, [liked, disliked], "The first dislike")
        reactionToasts.explain(.dislike)
        XCTAssertEqual(toasts, [liked, disliked], "The second dislike shows nothing")

        let supportLiked = lang("$agent_feedback_support_liked_toast")
        let supportDisliked = lang("$agent_feedback_support_disliked_toast")
        XCTAssertFalse(supportLiked.hasPrefix("$"))
        XCTAssertFalse(supportDisliked.hasPrefix("$"))
        XCTAssertNotEqual(supportLiked, supportDisliked)
        reactionToasts.explain(.like, isOperatorReply: true)
        reactionToasts.explain(.like, isOperatorReply: true)
        reactionToasts.explain(.dislike, isOperatorReply: true)
        reactionToasts.explain(.dislike, isOperatorReply: true)
        XCTAssertEqual(toasts, [liked, disliked, supportLiked, supportDisliked], "An operator's reply has its own, once each")

        let restarted = AgentReactionToasts(userDefaults: defaults) { toasts.append($0.message) }
        restarted.explain(.like)
        restarted.explain(.dislike)
        restarted.explain(.like, isOperatorReply: true)
        restarted.explain(.dislike, isOperatorReply: true)
        XCTAssertEqual(toasts, [liked, disliked, supportLiked, supportDisliked], "The install remembers all four")
    }

    /// The user's first like and first dislike explain themselves in a toast as their emoji lands on the corner, a
    /// change to the other kind as a first one. A rating from the server, a withdrawal and a second reaction of a kind
    /// show none.
    func testFirstLikeAndDislikeExplainThemselvesAsTheyLand() async throws {
        AgentReactionMotion.isReducedOverride = false
        defer { AgentReactionMotion.isReducedOverride = nil }
        let suiteName = "AgentReactionTests.toastsOnLanding"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let liked = lang("$agent_feedback_liked_toast")
        let disliked = lang("$agent_feedback_disliked_toast")
        var toasts: [String] = []
        let chat = RatingChat(
            messages: [AgentMessage(role: .user, text: "Rate this", isStreaming: false), makeAnswer(feedback: nil)],
            reactionToasts: AgentReactionToasts(userDefaults: defaults) { toasts.append($0.message) }
        )
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat.collectionView)

        var fromServer = try XCTUnwrap(chat.backend.messages.last)
        fromServer.feedback = .like
        chat.backend.messages[chat.backend.messages.count - 1] = fromServer
        chat.backend.context?.updateMessage(fromServer, animated: false, scrollToBottom: false)
        try await waitUntil { cell.reactionBadgeView.feedback == .like }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(toasts, [], "A rating from the server explains nothing")

        try await chooseReaction(.dislike, on: cell, in: chat) {
            XCTAssertEqual(toasts, [], "The toast waits for the landing")
        }
        XCTAssertEqual(toasts, [disliked], "A change to a first dislike")
        try await chooseReaction(.like, on: cell, in: chat) {
            XCTAssertEqual(toasts, [disliked])
        }
        XCTAssertEqual(toasts, [disliked, liked], "A change to a first like")
        try await chooseReaction(.like, on: cell, in: chat) {}
        XCTAssertNil(cell.reactionBadgeView.feedback)
        XCTAssertEqual(toasts, [disliked, liked], "A withdrawal explains nothing")
        try await chooseReaction(.like, on: cell, in: chat) {}
        XCTAssertEqual(cell.reactionBadgeView.feedback, .like)
        XCTAssertEqual(toasts, [disliked, liked], "The second like")
        try await chooseReaction(.dislike, on: cell, in: chat) {}
        XCTAssertEqual(cell.reactionBadgeView.feedback, .dislike)
        XCTAssertEqual(toasts, [disliked, liked], "The second dislike")
        XCTAssertEqual(chat.backend.ratings, [.dislike, .like, nil, .like, .dislike])
    }

    /// A support operator's reply explains its first like and first dislike with the support team's toasts, apart from
    /// the toasts of the agent's answers
    func testOperatorRepliesReactionsExplainThemselvesWithTheSupportTeamsToasts() async throws {
        AgentReactionMotion.isReducedOverride = false
        defer { AgentReactionMotion.isReducedOverride = nil }
        let suiteName = "AgentReactionTests.operatorToasts"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let liked = lang("$agent_feedback_support_liked_toast")
        let disliked = lang("$agent_feedback_support_disliked_toast")
        var toasts: [String] = []
        var reply = makeAnswer(feedback: nil)
        reply.author = .operator(ApiAgentV2OperatorAuthor(operatorId: "alex", name: "Alex"))
        let chat = RatingChat(
            messages: [AgentMessage(role: .user, text: "Rate this", isStreaming: false), reply],
            reactionToasts: AgentReactionToasts(userDefaults: defaults) { toasts.append($0.message) }
        )
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat.collectionView)

        try await chooseReaction(.like, on: cell, in: chat) {}
        try await waitUntil { !toasts.isEmpty }
        XCTAssertEqual(toasts, [liked])
        try await chooseReaction(.dislike, on: cell, in: chat) {}
        try await waitUntil { toasts.count == 2 }
        XCTAssertEqual(toasts, [liked, disliked])
        XCTAssertFalse(defaults.bool(forKey: "agent-feedback-liked-toast-shown"))
        XCTAssertFalse(defaults.bool(forKey: "agent-feedback-disliked-toast-shown"))
        XCTAssertEqual(chat.backend.ratings, [.like, .dislike])
    }

    /// A first reaction explains itself only once its rating is saved and it is still the answer's, and a failed or
    /// replaced one leaves its toast for a later reaction
    func testFirstReactionExplainsItselfOnceItsRatingIsSaved() async throws {
        AgentReactionMotion.isReducedOverride = false
        defer { AgentReactionMotion.isReducedOverride = nil }
        let suiteName = "AgentReactionTests.toastsOnSaving"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let liked = lang("$agent_feedback_liked_toast")
        var toasts: [String] = []
        let chat = RatingChat(
            messages: [AgentMessage(role: .user, text: "Rate this", isStreaming: false), makeAnswer(feedback: nil)],
            reactionToasts: AgentReactionToasts(userDefaults: defaults) { toasts.append($0.message) }
        )
        defer { chat.close() }
        chat.backend.holdsRatings = true
        try await chat.waitForStableLayout()
        let cell = try findAnswerCell(in: chat.collectionView)

        try await chooseReaction(.like, on: cell, in: chat) {}
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(toasts, [], "The landed like waits for its rating")
        chat.backend.settleRating(didSave: true)
        try await waitUntil { toasts == [liked] }

        try await chooseReaction(.dislike, on: cell, in: chat) {}
        chat.backend.settleRating(didSave: false)
        try await waitUntil { cell.reactionBadgeView.feedback == .like }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(toasts, [liked], "A failed dislike explains nothing")
        XCTAssertFalse(defaults.bool(forKey: "agent-feedback-disliked-toast-shown"))

        try await chooseReaction(.dislike, on: cell, in: chat) {}
        try await chooseReaction(.dislike, on: cell, in: chat) {}
        XCTAssertNil(cell.reactionBadgeView.feedback)
        XCTAssertEqual(chat.backend.heldRatingCount, 2)
        chat.backend.settleRating(didSave: true)
        chat.backend.settleRating(didSave: true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(toasts, [liked], "A dislike withdrawn before its rating is saved explains nothing")
        XCTAssertFalse(defaults.bool(forKey: "agent-feedback-disliked-toast-shown"))

        try await chooseReaction(.dislike, on: cell, in: chat) {}
        try await chooseReaction(.like, on: cell, in: chat) {}
        XCTAssertEqual(cell.reactionBadgeView.feedback, .like)
        chat.backend.settleRating(didSave: true)
        chat.backend.settleRating(didSave: true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(toasts, [liked], "A dislike changed before its rating is saved explains nothing")
        XCTAssertFalse(defaults.bool(forKey: "agent-feedback-disliked-toast-shown"))
        XCTAssertEqual(chat.backend.ratings, [.like, .dislike, .dislike, nil, .dislike, .like])
    }

    // MARK: - Helpers

    /// The middle of what `image` draws, leaving out its faint edges, in points from its top leading corner
    private func getDrawnCenter(of image: UIImage) -> CGPoint? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var drawn: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 32 {
                let current = drawn ?? (x, y, x, y)
                drawn = (min(current.minX, x), min(current.minY, y), max(current.maxX, x), max(current.maxY, y))
            }
        }
        guard let drawn else { return nil }
        return CGPoint(
            x: CGFloat(drawn.minX + drawn.maxX + 1) / 2 / image.scale,
            y: CGFloat(drawn.minY + drawn.maxY + 1) / 2 / image.scale
        )
    }

    /// Chooses `option` in the cloud of the answer's menu, checking `beforeLanding` until a chosen reaction lands, and
    /// waits for the menu to go
    private func chooseReaction(
        _ option: ApiAgentV2AnswerFeedback,
        on cell: AgentMessageCell,
        in chat: RatingChat,
        beforeLanding: () -> Void
    ) async throws {
        let overlay = try openMenu(on: cell, in: chat.window)
        let pill = try XCTUnwrap(findDescendants(of: overlay).compactMap { $0 as? AgentFeedbackPillView }.first)
        try await Task.sleep(for: .milliseconds(450))
        let previousFlight = cell.reactionFlight
        try XCTUnwrap(pill.buttons.first { $0.option == option }).sendActions(for: .touchUpInside)
        if let flight = cell.reactionFlight, flight !== previousFlight {
            let deadline = ContinuousClock.now + .seconds(2)
            while flight.arrivalTime == nil {
                beforeLanding()
                guard ContinuousClock.now < deadline else { throw AgentTestTimeout() }
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        try await waitUntil { overlay.superview == nil && !cell.isFeedbackHeld }
    }

    /// The menu's replica of the answer
    private func findReplica(in overlay: UIView) -> UIView? {
        findDescendants(of: overlay).first { String(describing: type(of: $0)) == "ContextMenuPortalView" }
    }

    /// Where the corner's 22 pt emoji shows on the menu's replica of the answer at the moment, in the window's
    /// coordinates
    private func getReplicaFrame(of badge: AgentReactionBadgeView, in overlay: UIView) -> CGRect? {
        guard let replica = findReplica(in: overlay), let window = replica.window else { return nil }
        let layer = replica.layer.presentation() ?? replica.layer
        return layer.convert(badge.frame, to: window.layer.presentation() ?? window.layer)
    }

    /// The height of a row that shows `message`
    private func getRowHeight(of message: AgentMessage) -> CGFloat {
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 100))
        cell.configure(with: message, onURLTap: { _ in })
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.size = CGSize(width: 402, height: 100)
        return cell.preferredLayoutAttributesFitting(attributes).size.height
    }

    private func makeAccessory() -> ContextMenuAccessory {
        AgentFeedbackPillView.makeMenuAccessory(feedback: nil, onSelect: { _ in }, onMenuDidClose: { _ in })
    }

    /// The capsule's frame on screen: the accessory's first capsule, where its body slid to
    private func getCapsule(in placement: ContextMenuAccessoryPlacement, isRightToLeft: Bool) -> CGRect {
        let originX = getDesignOriginX(in: placement) + placement.bodyOffset
        let body = CGRect(origin: .zero, size: AgentFeedbackPillMetrics.bodySize)
        return mirror(body, isRightToLeft: isRightToLeft).offsetBy(dx: originX, dy: placement.frame.minY)
    }

    private func getTailCircles(in placement: ContextMenuAccessoryPlacement, isRightToLeft: Bool) -> (large: CGRect, small: CGRect) {
        let originX = getDesignOriginX(in: placement) + placement.tailOffset
        return (
            mirror(AgentFeedbackPillMetrics.largeTailCircle, isRightToLeft: isRightToLeft).offsetBy(dx: originX, dy: placement.frame.minY),
            mirror(AgentFeedbackPillMetrics.smallTailCircle, isRightToLeft: isRightToLeft).offsetBy(dx: originX, dy: placement.frame.minY)
        )
    }

    /// Where the accessory's own frame stands, where the answer's corner puts it, before its body or tail moved
    private func getDesignOriginX(in placement: ContextMenuAccessoryPlacement) -> CGFloat {
        placement.frame.minX - min(placement.tailOffset, placement.bodyOffset)
    }

    private func mirror(_ rect: CGRect, isRightToLeft: Bool) -> CGRect {
        guard isRightToLeft else { return rect }
        return CGRect(x: AgentFeedbackPillMetrics.size.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }

    private func makeAnswer(feedback: ApiAgentV2AnswerFeedback?) -> AgentMessage {
        var answer = AgentMessage(role: .assistant, text: "Here is the answer.", isStreaming: false)
        answer.canRate = true
        answer.feedback = feedback
        return answer
    }

    private func findAnswerCell(in chat: AgentTestChat) throws -> AgentMessageCell {
        try findAnswerCell(in: chat.collectionView)
    }

    private func findAnswerCell(in collectionView: UICollectionView) throws -> AgentMessageCell {
        try XCTUnwrap(collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first {
            $0.accessibilityIdentifier == "agent_message_assistant"
        })
    }

    private func openMenu(on cell: AgentMessageCell, in chat: AgentTestChat) throws -> UIView {
        try openMenu(on: cell, in: chat.window)
    }

    /// Opens the answer's menu as VoiceOver's "More actions" does
    private func openMenu(on cell: AgentMessageCell, in window: UIWindow) throws -> UIView {
        let menuAction = try XCTUnwrap(
            ([cell] + findDescendants(of: cell)).lazy
                .compactMap { $0.accessibilityCustomActions?.first { $0.name == lang("More actions") } }
                .first
        )
        XCTAssertEqual(menuAction.actionHandler?(menuAction), true)
        return try XCTUnwrap(window.subviews.last { String(describing: type(of: $0)) == "ContextMenuOverlayView" })
    }

    private func assertEqual(
        _ frame: CGRect,
        _ expected: CGRect,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (value, expectedValue) in [
            (frame.midX, expected.midX),
            (frame.midY, expected.midY),
            (frame.width, expected.width),
            (frame.height, expected.height),
        ] {
            XCTAssertEqual(value, expectedValue, accuracy: 0.5, "\(frame) is not \(expected). \(message)", file: file, line: line)
        }
    }

    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw AgentTestTimeout() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// A chat whose backend keeps the answers' ratings, as the Agent's does
@MainActor
private final class RatingChat {
    final class Backend: AgentBackend {
        var context: AgentBackendContext?
        var isLoadingOlderMessages = false
        var messages: [AgentMessage] = []
        private(set) var ratings: [ApiAgentV2AnswerFeedback?] = []

        func attach(to context: AgentBackendContext) { self.context = context }
        func detach() { context = nil }
        func loadHints(animated: Bool) {}
        func prepareForEditing(_ editContext: AgentBackendEditContext) {}
        func didSendUserMessage(
            _ text: String,
            userMessageID: AgentItemID,
            source: AgentBackendSendSource,
            editContext: AgentBackendEditContext?
        ) {}
        func clearConversation() {}

        /// While set, each rating shows at once and waits for `settleRating(didSave:)`, which takes a failed one back
        var holdsRatings = false
        private var heldRatings: [CheckedContinuation<Bool, Never>] = []

        var heldRatingCount: Int { heldRatings.count }

        func rateMessage(messageID: AgentItemID, feedback: ApiAgentV2AnswerFeedback?) async -> Bool {
            guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return false }
            ratings.append(feedback)
            let previous = messages[index].feedback
            setFeedback(feedback, at: index)
            guard holdsRatings else { return true }
            let didSave = await withCheckedContinuation { heldRatings.append($0) }
            if !didSave, messages[index].feedback == feedback {
                setFeedback(previous, at: index)
            }
            return didSave
        }

        /// Settles the oldest held rating
        func settleRating(didSave: Bool) {
            heldRatings.removeFirst().resume(returning: didSave)
        }

        private func setFeedback(_ feedback: ApiAgentV2AnswerFeedback?, at index: Int) {
            messages[index].feedback = feedback
            context?.updateMessage(messages[index], animated: false, scrollToBottom: false)
        }
    }

    let backend = Backend()
    let model: AgentModel
    let controller: AgentVC
    let window: UIWindow

    var collectionView: AgentCollectionView { controller.collectionView }

    /// `reactionToasts` shows nothing and keeps its flags apart from the app's unless a test gives its own
    init(messages: [AgentMessage], reactionToasts: AgentReactionToasts? = nil) {
        backend.messages = messages
        model = AgentModel(backend: backend)
        backend.context?.replaceTimeline(with: messages.map(AgentTimelineItem.message), animated: false)
        controller = AgentVC(
            model: model,
            reactionToasts: reactionToasts ?? AgentReactionToasts(
                userDefaults: UserDefaults(suiteName: "AgentReactionTests.ratingChat") ?? .standard,
                showToast: { _ in }
            )
        )
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
    }

    func close() {
        window.rootViewController = nil
        window.isHidden = true
    }

    func waitForStableLayout() async throws {
        var previous: CGFloat = -1
        var stableSamples = 0
        for _ in 0..<600 where stableSamples < 20 {
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded()
            let offset = collectionView.contentOffset.y + collectionView.collectionViewLayout.collectionViewContentSize.height
            stableSamples = abs(offset - previous) < 0.5 ? stableSamples + 1 : 0
            previous = offset
        }
    }
}
