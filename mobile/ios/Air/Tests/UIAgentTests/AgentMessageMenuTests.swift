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
    /// message stays hidden while its replica moves away from it and back, so it never shows beside the replica.
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
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(isSourceHidden(by: portal), true, "Once the replica is in place")

        XCTAssertTrue(overlay.accessibilityPerformEscape())
        XCTAssertEqual(isSourceHidden(by: portal), true, "As the replica moves back")
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
