import XCTest
import UIKit
import UIComponents
@testable import UIAgent
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class AgentClipboardTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// The pasteboard stays out of the tests: reading it in the simulator can wait on a paste permission prompt
    func testCopyIsConfirmedWithTelegramsCopyToast() {
        let toast = AgentClipboard.copiedToast
        XCTAssertEqual(toast.style, .overlay)
        XCTAssertEqual(toast.icon, .animatedCopy)
        XCTAssertEqual(toast.message, lang("$agent_message_copied"))
        XCTAssertEqual(toast.duration, 3)
        XCTAssertEqual(toast.transition, .scale)
    }

    /// Telegram's undo overlay: 12 pt from the screen's edges and above the safe area, 25 pt corners, the icon centred
    /// in the first 50 pt and the text after it on up to two lines, also on the Agent's screens, whose keyboard guide
    /// leaves the safe area out
    func testCopyToastSitsAndMovesAsTelegramsUndoOverlay() async throws {
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        controller.view.keyboardLayoutGuide.usesBottomSafeArea = false
        let window = makeKeyWindow(showing: controller)
        defer { window.isHidden = true }
        let container = try XCTUnwrap(controller.view)
        container.layoutIfNeeded()
        let toastController = ToastController(containerView: container)
        var config = AgentClipboard.copiedToast
        config.duration = 0.3
        toastController.showToast(config)

        let toastView = try XCTUnwrap(container.subviews.compactMap { $0 as? ToastView }.first)
        container.layoutIfNeeded()
        let safeArea = container.safeAreaInsets
        XCTAssertEqual(toastView.frame.minX, safeArea.left + 12, accuracy: 0.5)
        XCTAssertEqual(toastView.frame.maxX, container.bounds.width - safeArea.right - 12, accuracy: 0.5)
        XCTAssertEqual(toastView.frame.maxY, container.bounds.height - safeArea.bottom - 12, accuracy: 0.5)
        XCTAssertEqual(toastView.frame.height, 50, accuracy: 0.5)
        XCTAssertEqual(toastView.layer.cornerRadius, 25)

        let label = try XCTUnwrap(findDescendants(of: toastView).compactMap { $0 as? UILabel }.first { $0.text == config.message })
        let labelFrame = label.convert(label.bounds, to: toastView)
        XCTAssertEqual(label.font, .systemFont(ofSize: 14))
        XCTAssertEqual(label.numberOfLines, 2)
        XCTAssertEqual(labelFrame.minX, 50, accuracy: 0.5)
        XCTAssertEqual(labelFrame.maxX, toastView.bounds.width - 24, accuracy: 0.5)
        XCTAssertEqual(labelFrame.midY, toastView.bounds.midY, accuracy: 0.5)
        let icon = try XCTUnwrap(findDescendants(of: toastView).first { $0 is WAnimatedSticker })
        let iconFrame = icon.convert(icon.bounds, to: toastView)
        XCTAssertEqual(iconFrame.midX, 25, accuracy: 0.5)
        XCTAssertEqual(iconFrame.midY, toastView.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(iconFrame.width, 34, accuracy: 0.5)

        // In: a fade as it grows from 96% on a spring
        let scaleIn = try XCTUnwrap(toastView.layer.animation(forKey: "scale") as? CASpringAnimation)
        XCTAssertEqual(scaleIn.keyPath, "transform.scale")
        XCTAssertEqual(scaleIn.fromValue as? CGFloat, 0.96)
        XCTAssertEqual(scaleIn.toValue as? CGFloat, 1)
        XCTAssertNotNil(toastView.layer.animation(forKey: "opacity"))

        // Out, after its time: a quicker fade as it shrinks back
        try await Task.sleep(for: .milliseconds(400))
        let scaleOut = try XCTUnwrap(toastView.layer.animation(forKey: "scale") as? CASpringAnimation)
        XCTAssertEqual(scaleOut.fromValue as? CGFloat, 1)
        XCTAssertEqual(scaleOut.toValue as? CGFloat, 0.96)
        if let fadeOut = toastView.layer.animation(forKey: "opacity") {
            XCTAssertEqual(fadeOut.duration, 0.25, accuracy: 0.01)
        }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(toastView.superview)
    }
}
