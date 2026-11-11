import SwiftUI
import Testing
import UIKit
import WalletResources
@testable import UIComponents

@Suite(.serialized) @MainActor
struct WButtonSizingTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test(arguments: [false, true])
    func testUpdatedLabelsUseTheirFullWidth(isIntrinsicWidth: Bool) async throws {
        let titles = isIntrinsicWidth
            ? ["Удалить кошелек", "Удалить 3 кошелька", "Удалить 12 кошельков", "Удалить кошелек"]
            : ["Add Wallet", "Add Ledger", "Add View Wallet", "Add Wallet"]
        let style: WButtonStyle = isIntrinsicWidth ? .thickDestructiveCapsule : .primary
        let labelPadding: CGFloat = isIntrinsicWidth ? 20 : 0
        func makeContent(title: String) -> some View {
            Button(action: {}) {
                Text(title)
                    .padding(.horizontal, labelPadding)
                    .frame(maxWidth: isIntrinsicWidth ? nil : .infinity)
                    .animation(.smooth(duration: 0.2), value: title)
            }
            .buttonStyle(WUIButtonStyle(style: style))
            .fixedSize(horizontal: isIntrinsicWidth, vertical: false)
            .frame(width: 330)
            .animation(.smooth(duration: 0.2), value: title)
        }
        let host = UIHostingController(rootView: makeContent(title: titles[0]))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        for title in titles {
            host.rootView = makeContent(title: title)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            window.layoutIfNeeded()
            let button = try #require(findButton(in: host.view))
            let content = try #require(button.subviews.first { $0 is any UIContentView })
            let titleWidth = (title as NSString).size(withAttributes: [.font: WButton.font(for: style)]).width
            #expect(abs(content.bounds.width - button.bounds.width + 32) < 1)
            #expect(content.bounds.width >= titleWidth + labelPadding * 2 - 1)
            #expect(abs(button.intrinsicContentSize.width - titleWidth - labelPadding * 2 - 36) < 1)
        }
    }

    private func findButton(in view: UIView) -> WButton? {
        if let button = view as? WButton { return button }
        return view.subviews.lazy.compactMap { findButton(in: $0) }.first
    }
}
