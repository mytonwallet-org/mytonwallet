import Foundation
import Testing
import WebKit
@testable import WalletCore

// Serialized because every test observes the same global `runtimeReady` events.
@Suite("JS bridge update delivery", .serialized)
struct JSBridgeUpdateDeliveryTests {
    @Test @MainActor
    func pendingUpdatesReachObserversBeforeCompletion() async {
        let source = WKWebView()
        let bridge = JSWebViewBridge()
        bridge.replaceWebView(source)
        let observer = UpdateObserver()
        WalletCoreData.addImmediately(eventObserver: observer)
        defer { WalletCoreData.remove(observer: observer) }

        let controller = WKUserContentController()
        for generation in 1...3 {
            bridge.userContentController(controller, didReceive: UpdateMessage(source: source, generation: generation))
        }
        #expect(observer.generations.isEmpty)

        await bridge.waitForPendingUpdates()

        #expect(observer.generations == [1, 2, 3])
    }

    @Test @MainActor
    func updatesFromAReplacedWebViewDoNotReachObservers() async {
        let stale = WKWebView()
        let current = WKWebView()
        let bridge = JSWebViewBridge()
        bridge.replaceWebView(current)
        let observer = UpdateObserver()
        WalletCoreData.addImmediately(eventObserver: observer)
        defer { WalletCoreData.remove(observer: observer) }

        let controller = WKUserContentController()
        bridge.userContentController(controller, didReceive: UpdateMessage(source: stale, generation: 1))
        bridge.userContentController(controller, didReceive: UpdateMessage(source: current, generation: 2))
        await bridge.waitForPendingUpdates()

        #expect(observer.generations == [2])
    }
}

@MainActor private final class UpdateObserver: WalletCoreData.EventsObserver {
    var generations: [Int] = []

    func walletCore(event: WalletCoreData.Event) {
        if case .agentV2(.runtimeReady(let generation)) = event {
            generations.append(generation)
        }
    }
}

@MainActor private final class UpdateMessage: WKScriptMessage {
    let source: WKWebView
    let generation: Int

    init(source: WKWebView, generation: Int) {
        self.source = source
        self.generation = generation
        super.init()
    }

    override var name: String { "onUpdate" }
    override var webView: WKWebView? { source }

    override var body: Any {
        ["update": "{\"type\":\"agentV2\",\"update\":{\"kind\":\"runtimeReady\",\"generation\":\(generation)}}"]
    }
}
