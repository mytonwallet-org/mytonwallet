import SwiftUI
import Testing
import UIKit
@testable import UIComponents

@MainActor
@Suite(.serialized)
struct TelegramDiamondLifecycleTests {
    @Test(arguments: [true, false])
    func deferInteractionResetUntilConfigurationReturns(isActive: Bool) async throws {
        let container = TelegramDiamondContainerView(size: 80)
        let diamond = try #require(container.subviews.first as? TelegramDiamondMetalView)
        container.configure(active: true)
        await drainMainQueue()

        var isConfiguring = false
        var pressChanges: [Bool] = []
        var hoverChanges: [Bool] = []
        container.onPressChange = {
            #expect(!isConfiguring)
            pressChanges.append($0)
        }
        container.onHoverChange = {
            #expect(!isConfiguring)
            hoverChanges.append($0)
        }
        diamond.setHolding(true, at: CACurrentMediaTime())
        diamond.onHoverChange?(true)
        await drainMainQueue()
        #expect(pressChanges == [true])
        #expect(hoverChanges == [true])

        isConfiguring = true
        container.configure(active: isActive, animated: !isActive)
        isConfiguring = false
        await drainMainQueue()

        #expect(pressChanges.last == false)
        #expect(hoverChanges.last == false)
        #expect(diamond.isPaused)
    }

    @Test
    func preserveInteractionOrderAcrossDeferredDelivery() async throws {
        let container = TelegramDiamondContainerView(size: 80)
        let diamond = try #require(container.subviews.first as? TelegramDiamondMetalView)
        await drainMainQueue()
        var pressChanges: [Bool] = []
        var hoverChanges: [Bool] = []
        container.onPressChange = { pressChanges.append($0) }
        container.onHoverChange = { hoverChanges.append($0) }

        diamond.setHolding(true, at: CACurrentMediaTime())
        diamond.onHoverChange?(true)
        diamond.setHolding(false, at: CACurrentMediaTime())
        diamond.onHoverChange?(false)
        await drainMainQueue()

        #expect(pressChanges == [true, false])
        #expect(hoverChanges == [true, false])
    }

    @Test
    func disconnectCallbacksWhenSwiftUIDismantlesTheView() async throws {
        var pressChanges: [Bool] = []
        var hoverChanges: [Bool] = []
        let host = UIHostingController(rootView: AnyView(TelegramDiamondView(
            onPressChange: { pressChanges.append($0) },
            onHoverChange: { hoverChanges.append($0) }
        )))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        await drainMainQueue()
        host.view.layoutIfNeeded()
        let container = try #require(findContainer(in: host.view))
        let diamond = try #require(container.subviews.first as? TelegramDiamondMetalView)
        try #require(container.onPressChange != nil)
        try #require(container.onHoverChange != nil)
        await drainMainQueue()
        pressChanges.removeAll()
        hoverChanges.removeAll()

        diamond.setHolding(true, at: CACurrentMediaTime())
        diamond.onHoverChange?(true)
        host.rootView = AnyView(EmptyView())
        host.view.layoutIfNeeded()
        await drainMainQueue()

        #expect(findContainer(in: host.view) == nil)
        #expect(pressChanges.isEmpty)
        #expect(hoverChanges.isEmpty)
        #expect(diamond.isPaused)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func findContainer(in view: UIView) -> TelegramDiamondContainerView? {
        if let container = view as? TelegramDiamondContainerView { return container }
        for subview in view.subviews {
            if let container = findContainer(in: subview) { return container }
        }
        return nil
    }
}
