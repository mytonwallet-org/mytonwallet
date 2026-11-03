import Foundation
import Testing
import WebKit
@testable import WalletCore

// Serialized because every test observes the same global `runtimeReady` events.
@Suite("JS bridge update delivery", .serialized)
struct JSBridgeUpdateDeliveryTests {
    @Test @MainActor
    func nftChangesDecodeAndReachObservers() async throws {
        let source = WKWebView()
        let bridge = JSWebViewBridge()
        bridge.replaceWebView(source)
        let observer = UpdateObserver()
        WalletCoreData.addImmediately(eventObserver: observer)
        defer { WalletCoreData.remove(observer: observer) }
        let controller = WKUserContentController()
        bridge.userContentController(controller, didReceive: UpdateMessage(source: source, update: #"{"type":"nftChanged","accountId":"nft-changed-account","chain":"ton","nft":{"chain":"ton","address":"nft-address","name":"Updated NFT","isOnSale":true}}"#))
        bridge.userContentController(controller, didReceive: UpdateMessage(source: source, generation: 1))
        await bridge.waitForPendingUpdates()

        let update = try #require(observer.nftChanges.first)
        #expect(observer.nftChanges.count == 1)
        #expect(update.accountId == "nft-changed-account")
        #expect(update.chain == .ton)
        #expect(update.nft.address == "nft-address")
        #expect(update.nft.name == "Updated NFT")
        #expect(update.nft.isOnSale)
        #expect(observer.generations == [1])
    }

    @Test(arguments: ["perpsPositionBuildComplete", "perpsDepositSubmitted", "perpsExecuteComplete", "perpsExecuteFailed"])
    @MainActor func perpsProgressEventsDoNotCrashOrBlockSubsequentUpdates(type: String) async {
        let source = WKWebView()
        let bridge = JSWebViewBridge()
        bridge.replaceWebView(source)
        let observer = UpdateObserver()
        WalletCoreData.addImmediately(eventObserver: observer)
        defer { WalletCoreData.remove(observer: observer) }
        let controller = WKUserContentController()
        bridge.userContentController(controller, didReceive: PerpsUpdateMessage(source: source, type: type))
        bridge.userContentController(controller, didReceive: UpdateMessage(source: source, generation: 1))
        await bridge.waitForPendingUpdates()
        #expect(observer.generations == [1])
    }

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

@MainActor private final class PerpsUpdateMessage: WKScriptMessage {
    let source: WKWebView
    let type: String
    init(source: WKWebView, type: String) {
        self.source = source; self.type = type
        super.init()
    }
    override var name: String { "onUpdate" }
    override var webView: WKWebView? { source }
    override var body: Any {
        ["update": "{\"type\":\"\(type)\",\"accountId\":\"account\",\"flow\":\"open\",\"assetId\":\"hyperliquid:hl:BTC\"}"]
    }
}

@MainActor private final class UpdateObserver: WalletCoreData.EventsObserver {
    var generations: [Int] = []
    var nftChanges: [ApiUpdate.NftChanged] = []

    func walletCore(event: WalletCoreData.Event) {
        if case .agentV2(.runtimeReady(let generation)) = event {
            generations.append(generation)
        }
        if case .nftChanged(let update) = event {
            nftChanges.append(update)
        }
    }
}

@MainActor private final class UpdateMessage: WKScriptMessage {
    let source: WKWebView
    let update: String

    convenience init(source: WKWebView, generation: Int) {
        self.init(source: source, update: "{\"type\":\"agentV2\",\"update\":{\"kind\":\"runtimeReady\",\"generation\":\(generation)}}")
    }

    init(source: WKWebView, update: String) {
        self.source = source
        self.update = update
        super.init()
    }

    override var name: String { "onUpdate" }
    override var webView: WKWebView? { source }

    override var body: Any {
        ["update": update]
    }
}
