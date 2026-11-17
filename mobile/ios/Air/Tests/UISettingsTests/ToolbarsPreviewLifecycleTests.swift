import SwiftUI
import Testing
import UIKit
import WalletContext
@testable import UISettings

@MainActor
@Suite(.serialized)
struct ToolbarsPreviewLifecycleTests {
    @Test(arguments: [false, true])
    func deferHeightChangeUntilConfigurationReturns(isAnimated: Bool) async {
        let view = ToolbarsPreviewView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(view)
        window.isHidden = false
        defer { window.isHidden = true }
        await drainMainQueue()

        var isConfiguring = false
        var changeCount = 0
        view.onHeightChange = {
            #expect(!isConfiguring)
            changeCount += 1
        }
        var configuration = ToolbarSettings.configuration()
        configuration.sharesBackground.toggle()
        isConfiguring = true
        view.setConfiguration(configuration, animated: isAnimated)
        isConfiguring = false
        await drainMainQueue()

        #expect(changeCount > 0)
    }

    @Test
    func disconnectHeightCallbackWhenSwiftUIDismantlesTheView() async throws {
        let host = UIHostingController(rootView: AnyView(ToolbarSettingsSection()))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        await drainMainQueue()
        host.view.layoutIfNeeded()
        let view = try #require(findPreview(in: host.view))
        try #require(view.onHeightChange != nil)
        await drainMainQueue()

        var changeCount = 0
        view.onHeightChange = { changeCount += 1 }
        var configuration = ToolbarSettings.configuration()
        configuration.sharesBackground.toggle()
        view.setConfiguration(configuration, animated: false)
        host.rootView = AnyView(EmptyView())
        host.view.layoutIfNeeded()
        await drainMainQueue()

        #expect(findPreview(in: host.view) == nil)
        #expect(view.onHeightChange == nil)
        #expect(changeCount == 0)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func findPreview(in view: UIView) -> ToolbarsPreviewView? {
        if let preview = view as? ToolbarsPreviewView { return preview }
        for subview in view.subviews {
            if let preview = findPreview(in: subview) { return preview }
        }
        return nil
    }
}
