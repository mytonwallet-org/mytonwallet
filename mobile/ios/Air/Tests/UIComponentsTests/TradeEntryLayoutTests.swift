import SwiftUI
import Testing
import UIKit
import WalletResources
@testable import UIComponents

@Suite(.serialized) @MainActor
struct TradeEntryLayoutTests {
    @Test(arguments: [CGSize(width: 402, height: 802), CGSize(width: 320, height: 480)])
    func contentRemainsReachableAboveFixedKeypad(size: CGSize) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let editor = TradeEditor()
        let layout = TradeEntryLayout(editor: editor, hasText: false) { height in
            Color.clear.frame(height: height).accessibilityIdentifier("card")
            Color.clear.frame(height: 52).accessibilityIdentifier("payment")
        } controls: {
            TradeFractionButtons { _ in }
        }
        let controller = TradeEntryViewController(layout: layout)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        let scroll = controller.scrollView
        let panel = controller.keyboardPanel
        #expect(scroll.frame == controller.view.bounds)
        #expect(!scroll.delaysContentTouches)
        #expect(!scroll.showsVerticalScrollIndicator && !scroll.showsHorizontalScrollIndicator)
        #expect(abs(scroll.contentInset.bottom - panel.bounds.height) < 0.5)
        #expect(controller.keypad.bounds.height >= 176 && controller.keypad.bounds.height <= 248)
        #expect(abs(controller.keypad.convert(controller.keypad.bounds, to: controller.view).maxY -
                    (controller.view.bounds.maxY - max(36, controller.view.safeAreaInsets.bottom))) < 0.5)
        scroll.contentOffset.y = max(0, scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height)
        #expect(abs(scroll.contentSize.height - scroll.contentOffset.y - panel.frame.minY) < 0.5)

        let panelFrame = panel.frame
        let offset = scroll.contentOffset
        controller.update(layout: layout)
        window.layoutIfNeeded()
        #expect(panel.frame == panelFrame)
        #expect(scroll.contentOffset == offset)

        controller.additionalSafeAreaInsets.bottom = 40
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        #expect(abs(scroll.contentInset.bottom - panel.bounds.height) < 0.5)
        #expect(controller.keypad.convert(controller.keypad.bounds, to: controller.view).maxY <= controller.view.safeAreaLayoutGuide.layoutFrame.maxY)
    }
}
