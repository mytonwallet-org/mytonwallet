import SwiftUI
import Testing
import UIKit
import WalletResources
@testable import UIComponents

@MainActor
@Suite(.serialized)
struct BubbleViewTests {
    private let comment = "Test transaction with multiple words that should wrap to multiple lines"

    init() {
        _ = WalletResourcesBundle.bundle.load()
    }

    @Test(arguments: [320.0, 393.0, 430.0])
    func revealedCommentFitsAfterWidthProbes(width: CGFloat) async throws {
        let host = UIHostingController(rootView: content(.encryptedComment))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 800))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        await settle(host)
        #expect(host.view.bounds.width == width)

        host.rootView = content(.comment(comment))
        await settle(host)
        try checkComment(in: host.view, text: comment)

        // A parent can request ideal and alternate widths before returning to its actual bounds.
        _ = host.sizeThatFits(in: CGSize(width: 700, height: 800))
        _ = host.sizeThatFits(in: CGSize(width: 250, height: 800))
        host.view.setNeedsLayout()
        await settle(host)
        try checkComment(in: host.view, text: comment)

        host.rootView = content(.encryptedComment)
        await settle(host)
        host.rootView = content(.comment(comment))
        await settle(host)
        try checkComment(in: host.view, text: comment)
    }

    @Test
    func explicitLineBreaksAreNotCappedAtThirtyLines() async throws {
        let text = (1...35).map { "Line \($0)" }.joined(separator: "\n")
        let host = UIHostingController(rootView: content(.comment(text)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        await settle(host)
        let bubble = try checkComment(in: host.view, text: text)
        #expect(bubble.label.bounds.height >= 35 * 17)
    }

    private func content(_ value: SBubbleView.Content) -> some View {
        ScrollView {
            VStack {
                SBubbleView(content: value, direction: .outgoing, isError: false)
                    .padding(.horizontal, 44)
            }
        }
    }

    private func settle<Content: View>(_ host: UIHostingController<Content>) async {
        host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(50))
        host.view.layoutIfNeeded()
    }

    @discardableResult
    private func checkComment(in view: UIView, text: String) throws -> BubbleView {
        let bubble = try #require(findBubble(in: view))
        let label = bubble.label
        #expect(label.text == text)
        #expect(bubble.bounds.width <= view.bounds.width - 88 + 1)
        #expect(label.frame.maxX <= bubble.bounds.width - 13 + 1)
        #expect(label.frame.maxY <= bubble.bounds.height - 8 + 1)
        #expect(label.bounds.height > 17)
        return bubble
    }

    private func findBubble(in view: UIView) -> BubbleView? {
        if let bubble = view as? BubbleView { return bubble }
        return view.subviews.lazy.compactMap { findBubble(in: $0) }.first
    }
}
