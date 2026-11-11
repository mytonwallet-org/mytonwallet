import XCTest
import UIKit
import ContextMenuKit
@testable import UIAgent
import WalletContext
import WalletCore
import WalletResources

/// The menu of a message whose replica moves to make room for the menu
@MainActor
final class AgentMessageMenuTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// A message taller than the chat reaches under its header and composer, and its replica moves up for the menu. The
    /// message stays hidden while its replica moves away from it and back, so it never shows beside the replica. Until
    /// the menu's backdrop covers the bars, and again as it goes, a copy of the message's parts under the bars keeps
    /// what their blur shows, and it leaves the chat's visible area clear.
    func testLongMessageStaysHiddenWhileItsReplicaMoves() async throws {
        let text = (1...60).map { "Line \($0) of a long answer that keeps the reader busy." }.joined(separator: "\n")
        let chat = AgentTestChat(messages: [AgentMessage(role: .assistant, text: text, isStreaming: false)])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try XCTUnwrap(chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first)
        XCTAssertGreaterThan(cell.bounds.height, chat.collectionView.bounds.height)
        let source = try XCTUnwrap(findMenuSource(in: cell))
        let menuAction = try XCTUnwrap(
            ([cell] + findDescendants(of: cell)).lazy
                .compactMap { $0.accessibilityCustomActions?.first { $0.name == lang("More actions") } }
                .first
        )

        XCTAssertEqual(menuAction.actionHandler?(menuAction), true)
        let overlay = try XCTUnwrap(chat.window.subviews.last { getTypeName($0) == "ContextMenuOverlayView" })
        defer { overlay.removeFromSuperview() }
        let portal = try XCTUnwrap(findDescendants(of: overlay).first { getTypeName($0) == "_UIPortalView" })
        try XCTSkipUnless(
            ["sourceView", "hidesSourceView"].allSatisfy { portal.responds(to: NSSelectorFromString($0)) },
            "The portal doesn't say what it shows and whether it hides it"
        )
        XCTAssertTrue(portal.value(forKey: "sourceView") as? UIView === source)
        XCTAssertTrue(
            findDescendants(of: overlay).contains { $0.layer.animation(forKey: "position.y.contextMenuSpring") != nil },
            "The replica moves away from the message"
        )
        XCTAssertEqual(isSourceHidden(by: portal), true, "As the replica moves away")
        let standIn = try XCTUnwrap(findBarsStandIn(beside: source), "The bars keep showing the message")
        let mask = try XCTUnwrap(standIn.layer.mask as? CAShapeLayer)
        let visibleCenter = CGPoint(x: chat.collectionView.bounds.midX, y: chat.collectionView.bounds.midY)
        let standInVisibleCenter = standIn.convert(visibleCenter, from: chat.collectionView)
        XCTAssertEqual(mask.fillRule, .evenOdd)
        XCTAssertEqual(mask.path?.contains(standInVisibleCenter, using: .evenOdd), false, "The chat's visible area stays clear")
        let ends = [CGPoint(x: standIn.bounds.midX, y: 1), CGPoint(x: standIn.bounds.midX, y: standIn.bounds.maxY - 1)]
        XCTAssertTrue(ends.contains { mask.path?.contains($0, using: .evenOdd) == true }, "Under a bar")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(isSourceHidden(by: portal), true, "Once the replica is in place")
        XCTAssertNil(findBarsStandIn(beside: source), "Once the backdrop covers the bars")

        XCTAssertTrue(overlay.accessibilityPerformEscape())
        XCTAssertEqual(isSourceHidden(by: portal), true, "As the replica moves back")
        XCTAssertNotNil(findBarsStandIn(beside: source), "As the backdrop leaves the bars")
        overlay.removeFromSuperview()
        XCTAssertNil(findBarsStandIn(beside: source), "Once the menu is gone")
    }

    /// A long answer's corner emoji reaches past the answer's bounds, and it hides with the answer for as long as the
    /// replica stands in: as the replica moves away, once it is in place and as it moves back. The replica shows the
    /// whole emoji, and the bars' copy shows none of it in the chat's visible area.
    func testLongAnswersCornerEmojiHidesWithItWhileItsReplicaStandsIn() async throws {
        let text = (1...60).map { "Line \($0) of a long answer that keeps the reader busy." }.joined(separator: "\n")
        var answer = AgentMessage(role: .assistant, text: text, isStreaming: false)
        answer.canRate = true
        answer.feedback = .like
        let chat = AgentTestChat(messages: [AgentMessage(role: .user, text: "Tell me more", isStreaming: false), answer])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try XCTUnwrap(chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first {
            $0.accessibilityIdentifier == "agent_message_assistant"
        })
        XCTAssertGreaterThan(cell.bounds.height, chat.collectionView.bounds.height)
        let source = try XCTUnwrap(findMenuSource(in: cell))
        let badge = cell.reactionBadgeView
        XCTAssertFalse(badge.isHidden)
        let contentArea = try XCTUnwrap(cell.contextMenuConfigurationProvider?()?.sourceRelocation?.contentAreaInWindow)
        // The square the emoji draws in, every 2 pt, in the window's coordinates
        let emojiBox = badge.iconView.convert(badge.iconView.bounds, to: nil)
        let emojiPoints = stride(from: emojiBox.minY + 1, to: emojiBox.maxY, by: 2).flatMap { y in
            stride(from: emojiBox.minX + 1, to: emojiBox.maxX, by: 2).map { CGPoint(x: $0, y: y) }
        }
        let visibleEmojiPoints = emojiPoints.filter { contentArea.contains($0) }
        let iconFrame = badge.convert(badge.bounds, to: nil)
        XCTAssertTrue(contentArea.contains(CGPoint(x: iconFrame.midX, y: iconFrame.midY)), "The emoji is in the visible area")
        let sourceFrame = source.convert(source.bounds, to: nil)
        XCTAssertTrue(visibleEmojiPoints.contains { !sourceFrame.contains($0) }, "and reaches past the answer's bounds")
        let menuAction = try XCTUnwrap(
            ([cell] + findDescendants(of: cell)).lazy
                .compactMap { $0.accessibilityCustomActions?.first { $0.name == lang("More actions") } }
                .first
        )

        XCTAssertEqual(menuAction.actionHandler?(menuAction), true)
        let overlay = try XCTUnwrap(chat.window.subviews.last { getTypeName($0) == "ContextMenuOverlayView" })
        defer { overlay.removeFromSuperview() }
        let portal = try XCTUnwrap(findDescendants(of: overlay).first { getTypeName($0) == "_UIPortalView" })
        try XCTSkipUnless(
            ["sourceView", "hidesSourceView"].allSatisfy { portal.responds(to: NSSelectorFromString($0)) },
            "The portal doesn't say what it shows and whether it hides it"
        )
        XCTAssertTrue(portal.value(forKey: "sourceView") as? UIView === source)
        let replica = try XCTUnwrap(findDescendants(of: overlay).first { getTypeName($0) == "ContextMenuPortalView" })
        let replicaMask = try XCTUnwrap(replica.layer.mask as? CAShapeLayer)
        let hiddenOnReplica = emojiPoints.filter { replicaMask.path?.contains(source.convert($0, from: nil)) != true }
        XCTAssertEqual(hiddenOnReplica, [], "The replica shows the whole emoji")

        func assertNothingIsLeftBehind(_ moment: String) {
            XCTAssertEqual(isSourceHidden(by: portal), true, "\(moment): the answer hides with its emoji")
            guard let standIn = findBarsStandIn(beside: source) else { return }
            let mask = standIn.layer.mask as? CAShapeLayer
            let shownByCopy = visibleEmojiPoints.filter { point in
                mask?.path?.contains(standIn.convert(point, from: nil), using: .evenOdd) != false
            }
            XCTAssertEqual(shownByCopy, [], "\(moment): the bars' copy shows none of the emoji in the visible area")
        }

        XCTAssertNotNil(findBarsStandIn(beside: source), "The bars keep showing the answer")
        assertNothingIsLeftBehind("As the replica moves away")
        try await Task.sleep(for: .milliseconds(100))
        assertNothingIsLeftBehind("As it still moves")
        try await Task.sleep(for: .milliseconds(200))
        assertNothingIsLeftBehind("Once it is in place")

        XCTAssertTrue(overlay.accessibilityPerformEscape())
        XCTAssertNotNil(findBarsStandIn(beside: source), "As the backdrop leaves the bars")
        assertNothingIsLeftBehind("As the replica moves back")
        try await Task.sleep(for: .milliseconds(100))
        if overlay.superview != nil {
            assertNothingIsLeftBehind("As it still moves back")
        }
    }

    /// An answer still being written opens no menu, by a long press or by VoiceOver, so it offers no reactions either;
    /// once complete, it opens its menu as an earlier answer does all along
    func testAnswerBeingWrittenOpensNoMenuUntilItsComplete() async throws {
        var earlier = AgentMessage(role: .assistant, text: "An earlier answer.", isStreaming: false)
        earlier.canRate = true
        var streaming = AgentMessage(role: .assistant, text: "An answer still being", isStreaming: true)
        streaming.canRate = true
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .user, text: "Tell me", isStreaming: false),
            earlier,
            AgentMessage(role: .user, text: "And more", isStreaming: false),
            streaming,
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()

        func findCell(of message: AgentMessage) throws -> AgentMessageCell {
            try XCTUnwrap(chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first { $0.messageID == message.id })
        }
        /// Whether the message offers its menu: a menu to open, VoiceOver's action and a press on the bubble's edge
        func getMenuOffers(of message: AgentMessage) throws -> [Bool] {
            let cell = try findCell(of: message)
            cell.layoutIfNeeded()
            let source = try XCTUnwrap(findMenuSource(in: cell))
            let recognizer = try XCTUnwrap(source.gestureRecognizers?.first {
                $0.delegate is ContextMenuInteraction && !($0 is UITapGestureRecognizer)
            })
            let interaction = try XCTUnwrap(recognizer.delegate as? ContextMenuInteraction)
            return [
                cell.contextMenuConfigurationProvider?() != nil,
                ([cell] + findDescendants(of: cell)).contains {
                    $0.accessibilityCustomActions?.contains { $0.name == lang("More actions") } == true
                },
                interaction.gestureRecognizer(recognizer, shouldReceive: LinkMenuTouch(CGPoint(x: 8, y: 6), in: source)),
            ]
        }

        XCTAssertEqual(try getMenuOffers(of: earlier), [true, true, true], "An earlier answer")
        XCTAssertEqual(try getMenuOffers(of: streaming), [false, false, false], "An answer being written")

        var completed = streaming
        completed.text = "An answer still being written, now complete."
        completed.isStreaming = false
        chat.backend.context?.updateMessage(completed, animated: false, scrollToBottom: false)
        try await chat.waitForStableLayout()
        XCTAssertEqual(try getMenuOffers(of: completed), [true, true, true], "The complete answer")
        XCTAssertEqual(try getMenuOffers(of: earlier), [true, true, true], "The earlier answer")
    }

    /// The bars never keep the message where its replica has left it: their copy of it moves with the replica, up as
    /// the menu opens and back down as it closes. Like the replica, the copy is a portal of the message, so it shows
    /// the message at the replica's size all along, as the press's squeeze lets go once the menu is open, and neither
    /// bar shows the message twice.
    func testBarsCopyMovesWithTheReplica() async throws {
        let text = (1...60).map { "Line \($0) of a long answer that keeps the reader busy." }.joined(separator: "\n")
        let chat = AgentTestChat(messages: [AgentMessage(role: .assistant, text: text, isStreaming: false)])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cell = try XCTUnwrap(chat.collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first)
        let source = try XCTUnwrap(findMenuSource(in: cell))
        let sourceMidY = source.convert(source.bounds, to: nil).midY
        let menuAction = try XCTUnwrap(
            ([cell] + findDescendants(of: cell)).lazy
                .compactMap { $0.accessibilityCustomActions?.first { $0.name == lang("More actions") } }
                .first
        )
        // The press squeezes the message's content and lets it go once the menu is open, as it does when the menu opens
        // before the press reaches its depth
        let squeeze: CGFloat = 0.95
        source.layer.sublayerTransform = CATransform3DMakeScale(squeeze, squeeze, 1)
        CATransaction.flush()

        XCTAssertEqual(menuAction.actionHandler?(menuAction), true)
        let release = CABasicAnimation(keyPath: "sublayerTransform")
        release.fromValue = NSValue(caTransform3D: source.layer.sublayerTransform)
        release.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        release.duration = 0.2
        release.timingFunction = CAMediaTimingFunction(name: .easeOut)
        source.layer.sublayerTransform = CATransform3DIdentity
        source.layer.add(release, forKey: "sublayerTransform.contextMenuBasic")
        let overlay = try XCTUnwrap(chat.window.subviews.last { getTypeName($0) == "ContextMenuOverlayView" })
        defer { overlay.removeFromSuperview() }
        let replica = try XCTUnwrap(findDescendants(of: overlay).first { getTypeName($0) == "ContextMenuPortalView" })
        let copy = try XCTUnwrap(findBarsStandIn(beside: source)?.subviews.first, "The bars keep showing the message")
        let replicaPortal = try XCTUnwrap(findDescendants(of: replica).first { getTypeName($0) == "_UIPortalView" })
        let copyPortal = try XCTUnwrap(
            findDescendants(of: copy).first { getTypeName($0) == "_UIPortalView" },
            "The copy shows the message itself, its squeeze included"
        )
        try XCTSkipUnless(
            ["sourceView", "hidesSourceView"].allSatisfy { copyPortal.responds(to: NSSelectorFromString($0)) },
            "The portal doesn't say what it shows and whether it hides it"
        )
        XCTAssertTrue(replicaPortal.value(forKey: "sourceView") as? UIView === source)
        XCTAssertTrue(copyPortal.value(forKey: "sourceView") as? UIView === source)
        XCTAssertEqual(isSourceHidden(by: copyPortal), false, "The replica alone hides the message")

        func getFrameOnScreen(_ view: UIView) throws -> CGRect {
            let layer = try XCTUnwrap(view.layer.presentation())
            let window = try XCTUnwrap(chat.window.layer.presentation())
            return layer.convert(layer.bounds, to: window)
        }
        /// Both portals show the message with its own squeeze about their middle, so the frames they take on screen
        /// tell where and at what size each shows it
        func assertCopyCoincides(_ copy: UIView, _ moment: String) throws {
            let copyFrame = try getFrameOnScreen(copy)
            let replicaFrame = try getFrameOnScreen(replica)
            XCTAssertEqual(copyFrame.minX, replicaFrame.minX, accuracy: 0.5, "\(moment): left")
            XCTAssertEqual(copyFrame.width, replicaFrame.width, accuracy: 0.5, "\(moment): width")
            XCTAssertEqual(copyFrame.height, replicaFrame.height, accuracy: 0.5, "\(moment): height")
            XCTAssertEqual(copyFrame.midY, replicaFrame.midY, accuracy: 1.0, "\(moment): vertical middle")
        }
        func getSqueeze() -> CGFloat {
            (source.layer.presentation() ?? source.layer).sublayerTransform.m11
        }

        var openingMoves: [CGFloat] = []
        var openingSqueezes: [CGFloat] = []
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(40))
            guard findBarsStandIn(beside: source) != nil else { break }
            try assertCopyCoincides(copy, "As the menu opens")
            openingSqueezes.append(getSqueeze())
            openingMoves.append(try getFrameOnScreen(replica).midY - sourceMidY)
        }
        XCTAssertTrue(openingMoves.contains { abs($0) > 4 }, "The replica moves away from the message: \(openingMoves)")
        XCTAssertTrue(
            openingSqueezes.contains { $0 > squeeze + 0.001 && $0 < 0.999 },
            "The squeeze lets go as the copy shows: \(openingSqueezes)"
        )
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(findBarsStandIn(beside: source), "Once the backdrop covers the bars")

        XCTAssertTrue(overlay.accessibilityPerformEscape())
        let returningCopy = try XCTUnwrap(findBarsStandIn(beside: source)?.subviews.first, "As the backdrop leaves the bars")
        var closingMoves: [CGFloat] = []
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(40))
            guard overlay.superview != nil, findBarsStandIn(beside: source) != nil else { break }
            try assertCopyCoincides(returningCopy, "As the menu closes")
            closingMoves.append(try getFrameOnScreen(replica).midY - sourceMidY)
        }
        XCTAssertTrue(closingMoves.contains { abs($0) > 4 }, "The replica is on its way back: \(closingMoves)")
    }

    func testLongPressOnInlineLinkUsesTheLinkMenu() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let url = "https://example.org/wallet/setup/instructions-for-mobile-devices"
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .assistant, text: "Read the [setup instructions](\(url)) for more information.", isStreaming: false),
            AgentMessage(role: .user, text: "What should I do next?", isStreaming: false),
        ])
        defer { chat.close() }
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            chat.window.windowScene = scene
            chat.window.frame = scene.coordinateSpace.bounds
            chat.window.makeKeyAndVisible()
        }
        try await chat.waitForStableLayout()

        var linkInteraction: ContextMenuInteraction?
        for (view, recognizer, interaction) in linkRecognizers(in: chat.controller.view) {
            for y in stride(from: CGFloat(2), to: view.bounds.height, by: 4) {
                for x in stride(from: CGFloat(2), to: view.bounds.width, by: 4) where linkInteraction == nil {
                    if interaction.gestureRecognizer(recognizer, shouldReceive: LinkMenuTouch(CGPoint(x: x, y: y), in: view)) {
                        linkInteraction = interaction
                    }
                }
            }
        }
        let interaction = try XCTUnwrap(linkInteraction, "An inline link must activate its own long-press interaction")
        interaction.present()

        let overlay = try XCTUnwrap(chat.window.subviews.last { getTypeName($0) == "ContextMenuOverlayView" })
        let preview = try XCTUnwrap(chat.window.subviews.first { $0.accessibilityIdentifier == "AgentLinkURLPreview" })
        defer {
            overlay.removeFromSuperview()
            preview.removeFromSuperview()
        }
        let label = try XCTUnwrap(findDescendants(of: preview).compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(label.text, url)
        XCTAssertEqual(label.font, AgentMessageTextRenderer.baseFont)
        XCTAssertGreaterThan(label.intrinsicContentSize.width, label.bounds.width,
                             "This URL must need more than one line at the message's font size")
        XCTAssertGreaterThan(label.bounds.height, ceil(label.font.lineHeight),
                             "The preview expands vertically instead of squeezing the URL onto one line")
        XCTAssertLessThanOrEqual(label.bounds.height, ceil(label.font.lineHeight * 2))
        XCTAssertGreaterThanOrEqual(preview.frame.minX, chat.window.safeAreaInsets.left + 16)
        XCTAssertLessThanOrEqual(preview.frame.maxX, chat.window.bounds.maxX - chat.window.safeAreaInsets.right - 16)
        XCTAssertFalse(preview.isDescendant(of: chat.controller.view))
        let actions = findDescendants(of: overlay).filter { getTypeName($0) == "ContextMenuRowView" }
        XCTAssertEqual(actions.compactMap(\.accessibilityLabel), [
            lang("Open"), lang("Open in Browser"), lang("Copy Link"), lang("Add to Reading List"),
        ])
        XCTAssertFalse(findDescendants(of: overlay).contains { getTypeName($0) == "ContextMenuCustomRowView" },
                       "The link menu has no message date or other message-level header")
        let blur = try XCTUnwrap(overlay.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        XCTAssertNotNil(blur.effect)
        XCTAssertEqual(blur.frame, overlay.bounds)
        let portal = try XCTUnwrap(findDescendants(of: overlay).first { getTypeName($0) == "_UIPortalView" })
        XCTAssertTrue(portal.value(forKey: "sourceView") as? UIView === preview)
        XCTAssertEqual(isSourceHidden(by: portal), true, "Only the live replica shows the URL during presentation")
        let navigation = try XCTUnwrap(findDescendants(of: overlay).first { getTypeName($0) == "ContextMenuNavigationView" })
        XCTAssertEqual(navigation.convert(navigation.bounds, to: chat.window).midX, preview.frame.midX, accuracy: 0.5)

        let previewContent = try XCTUnwrap(preview.subviews.first)
        let openingFade = try XCTUnwrap(opacityAnimation(of: previewContent))
        XCTAssertEqual(openingFade.duration, 0.2, accuracy: 0.001)
        XCTAssertEqual((openingFade.fromValue as? NSNumber)?.doubleValue, 0)
        XCTAssertEqual((openingFade.toValue as? NSNumber)?.floatValue ?? previewContent.layer.opacity, 1)
        try await Task.sleep(for: .milliseconds(80))
        let openingOpacity = try XCTUnwrap(previewContent.layer.presentation()?.opacity)
        XCTAssertGreaterThan(openingOpacity, 0)
        XCTAssertLessThan(openingOpacity, 1, "The URL is still fading in while the action panel opens")

        try await Task.sleep(for: .milliseconds(400))
        attachWindow(chat.window, name: "Link menu fully open — two-line URL and centered actions")
        XCTAssertTrue(overlay.accessibilityPerformEscape())
        XCTAssertEqual(previewContent.alpha, 0, "The URL fades while the menu closes, before its source is removed")
        let fade = try XCTUnwrap(opacityAnimation(of: previewContent))
        XCTAssertEqual(fade.duration, 0.2, accuracy: 0.001)
        XCTAssertEqual((fade.fromValue as? NSNumber)?.doubleValue, 1)
        XCTAssertEqual((fade.toValue as? NSNumber)?.floatValue ?? previewContent.layer.opacity, 0)
        XCTAssertNotNil(preview.superview)
        try await Task.sleep(for: .milliseconds(80))
        let closingOpacity = try XCTUnwrap(previewContent.layer.presentation()?.opacity)
        XCTAssertGreaterThan(closingOpacity, 0)
        XCTAssertLessThan(closingOpacity, 1, "The URL fades out with the actions instead of disappearing in one frame")
        attachWindow(chat.window, name: "Link menu during dismissal — live URL replica fades with the actions")
        for _ in 0..<100 where overlay.superview != nil || preview.superview != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(overlay.superview)
        XCTAssertNil(preview.superview)
        interaction.present()
        XCTAssertFalse(chat.window.subviews.contains { getTypeName($0) == "ContextMenuOverlayView" },
                       "The dismissed link selection must not reopen without a new link hit")
    }

    func testPlainMessageTextDoesNotActivateTheInlineLinkMenu() async throws {
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .assistant, text: "These are ordinary instructions without a hyperlink.", isStreaming: false),
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let recognizers = linkRecognizers(in: chat.controller.view)
        XCTAssertFalse(recognizers.isEmpty)
        for (view, recognizer, interaction) in recognizers {
            for y in stride(from: CGFloat(2), to: view.bounds.height, by: 8) {
                for x in stride(from: CGFloat(2), to: view.bounds.width, by: 8) {
                    guard !interaction.gestureRecognizer(recognizer, shouldReceive: LinkMenuTouch(CGPoint(x: x, y: y), in: view)) else {
                        return XCTFail("Plain text activated the link menu at \(CGPoint(x: x, y: y))")
                    }
                }
            }
            interaction.present()
        }
        XCTAssertFalse(chat.window.subviews.contains { $0.accessibilityIdentifier == "AgentLinkURLPreview" })
        XCTAssertFalse(chat.window.subviews.contains { getTypeName($0) == "ContextMenuOverlayView" })
    }

    private func linkRecognizers(in root: UIView) -> [(UIView, UILongPressGestureRecognizer, ContextMenuInteraction)] {
        findDescendants(of: root).filter { $0 is UITextView || $0 is AgentStreamingTextView }.flatMap { view in
            (view.gestureRecognizers ?? []).compactMap { recognizer in
                guard let recognizer = recognizer as? UILongPressGestureRecognizer,
                      let interaction = recognizer.delegate as? ContextMenuInteraction else { return nil }
                return (view, recognizer, interaction)
            }
        }
    }

    private func findBarsStandIn(beside source: UIView) -> UIView? {
        source.superview?.subviews.first { getTypeName($0) == "ContextMenuSourceBarsStandIn" }
    }

    private func isSourceHidden(by portal: UIView) -> Bool? {
        portal.value(forKey: "hidesSourceView") as? Bool
    }

    private func opacityAnimation(of view: UIView) -> CABasicAnimation? {
        (view.layer.animationKeys() ?? []).compactMap {
            view.layer.animation(forKey: $0) as? CABasicAnimation
        }.first { $0.keyPath == "opacity" }
    }

    private func attachWindow(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func getTypeName(_ view: UIView) -> String {
        String(describing: type(of: view))
    }

    /// The view the long-press menu hangs from: the one its press recognizer is on
    private func findMenuSource(in view: UIView) -> UIView? {
        ([view] + findDescendants(of: view)).first { candidate in
            candidate.gestureRecognizers?.contains {
                String(describing: type(of: $0)).contains("ContextMenuPressAnimation")
            } == true
        }
    }
}

private final class LinkMenuTouch: UITouch {
    private let point: CGPoint
    private weak var sourceView: UIView?

    init(_ point: CGPoint, in sourceView: UIView) {
        self.point = point
        self.sourceView = sourceView
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint {
        guard let view, let sourceView else { return point }
        return sourceView.convert(point, to: view)
    }
}
