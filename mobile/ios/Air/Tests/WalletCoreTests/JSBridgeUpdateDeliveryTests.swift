import Foundation
import Testing
import WebKit
@testable import WalletCore

@Suite("JS bridge update delivery")
struct JSBridgeUpdateDeliveryTests {
    @Test @MainActor
    func pendingUpdatesReachObserversBeforeCompletion() async {
        let bridge = JSWebViewBridge()
        let observer = UpdateObserver()
        WalletCoreData.addImmediately(eventObserver: observer)
        defer { WalletCoreData.remove(observer: observer) }

        let controller = WKUserContentController()
        for generation in 1...3 {
            bridge.userContentController(controller, didReceive: UpdateMessage(generation: generation))
        }
        #expect(observer.generations.isEmpty)

        await bridge.waitForPendingUpdates()

        #expect(observer.generations == [1, 2, 3])
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
    let generation: Int

    init(generation: Int) {
        self.generation = generation
        super.init()
    }

    override var name: String { "onUpdate" }

    override var body: Any {
        ["update": "{\"type\":\"agentV2\",\"update\":{\"kind\":\"runtimeReady\",\"generation\":\(generation)}}"]
    }
}
