import Foundation
import os
import Testing
import WalletContext
import WebKit
@testable import WalletCore

@Suite("JS bridge message routing", .timeLimit(.minutes(1)))
struct JSBridgeMessageRoutingTests {
    enum RuntimeChange: CaseIterable, Sendable {
        case replace, stop
    }

    @Test @MainActor
    func storageCompletesWhileUpdateDeliveryIsBlocked() async {
        let provider = RoutingStorageProbe()
        let source = CallbackWebView()
        let queue = DispatchQueue(label: "blockedUpdateDelivery")
        let bridge = JSWebViewBridge(storage: JSBridgeStorage(provider: provider), updateQueue: queue, webView: source)
        let gate = await QueueGate.blocking(queue)
        defer { gate.release() }

        bridge.userContentController(WKUserContentController(), didReceive: NativeCallMessage.storage(source: source))
        let response = await source.nextResponse()

        #expect(response?.requestNumber == 1)
        #expect(response?.value == "stored value")
        #expect(!gate.finished.withLock { $0 })
        #expect(provider.calls.withLock { $0 } == [.get])
    }

    @Test @MainActor
    func staleSourceCannotAccessStorageOrCompleteCurrentRuntime() async {
        let provider = RoutingStorageProbe()
        let stale = CallbackWebView()
        let current = CallbackWebView()
        let bridge = JSWebViewBridge(
            storage: JSBridgeStorage(provider: provider),
            updateQueue: DispatchQueue(label: "updateDelivery"),
            webView: current
        )

        bridge.userContentController(WKUserContentController(), didReceive: NativeCallMessage.storage(
            source: stale, method: .set, value: "stale write"
        ))
        bridge.userContentController(WKUserContentController(), didReceive: NativeCallMessage.storage(source: current))
        let response = await current.nextResponse()

        #expect(response?.value == "stored value")
        #expect(provider.calls.withLock { $0 } == [.get])
        #expect(stale.responses.isEmpty)
        #expect(current.responses.count == 1)
    }

    @Test(arguments: RuntimeChange.allCases) @MainActor
    func delayedResponseDoesNotReachAChangedRuntime(change: RuntimeChange) async {
        let gate = QueueGate()
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let provider = RoutingStorageProbe(beforeFirstLoad: {
            continuation.yield(())
            continuation.finish()
            gate.wait()
        })
        let storage = JSBridgeStorage(provider: provider)
        let oldSource = CallbackWebView()
        let newSource = CallbackWebView()
        let bridge = JSWebViewBridge(
            storage: storage,
            updateQueue: DispatchQueue(label: "updateDelivery"),
            webView: oldSource
        )
        defer { gate.release() }

        bridge.userContentController(WKUserContentController(), didReceive: NativeCallMessage.storage(source: oldSource))
        for await _ in started { break }
        #expect(!gate.finished.withLock { $0 })

        switch change {
        case .replace: bridge.replaceWebView(newSource)
        case .stop: bridge.stop()
        }
        gate.release()
        await drainStorageCallbacks(storage)

        #expect(oldSource.responses.isEmpty)
        #expect(newSource.responses.isEmpty)
    }

    @Test @MainActor
    func ledgerExchangeRepliesOnlyToItsCurrentSource() async {
        let apdu = "current-source"
        let stale = CallbackWebView()
        let current = CallbackWebView()
        let bridge = JSWebViewBridge(
            storage: JSBridgeStorage(provider: RoutingStorageProbe()),
            updateQueue: DispatchQueue(label: "updateDelivery"),
            webView: current
        )
        let observer = LedgerExchangeObserver(apdu: apdu)
        WalletCoreData.addImmediately(eventObserver: observer)
        defer { WalletCoreData.remove(observer: observer) }

        bridge.userContentController(WKUserContentController(), didReceive: NativeCallMessage.ledgerExchange(source: stale, apdu: apdu))
        bridge.userContentController(WKUserContentController(), didReceive: NativeCallMessage.ledgerExchange(source: current, apdu: apdu))
        await bridge.waitForPendingUpdates()
        #expect(observer.callbacks.count == 1)
        await observer.callbacks.first?("9000")

        #expect(stale.responses.isEmpty)
        #expect(current.responses.map(\.value) == ["9000"])
    }

    @Test(arguments: RuntimeChange.allCases) @MainActor
    func delayedLedgerResponseDoesNotReachAChangedRuntime(change: RuntimeChange) async {
        let apdu = "delayed-\(change)"
        let oldSource = CallbackWebView()
        let newSource = CallbackWebView()
        let bridge = JSWebViewBridge(
            storage: JSBridgeStorage(provider: RoutingStorageProbe()),
            updateQueue: DispatchQueue(label: "updateDelivery"),
            webView: oldSource
        )
        let observer = LedgerExchangeObserver(apdu: apdu)
        WalletCoreData.addImmediately(eventObserver: observer)
        defer { WalletCoreData.remove(observer: observer) }

        bridge.userContentController(WKUserContentController(), didReceive: NativeCallMessage.ledgerExchange(source: oldSource, apdu: apdu))
        await bridge.waitForPendingUpdates()
        #expect(observer.callbacks.count == 1)

        switch change {
        case .replace: bridge.replaceWebView(newSource)
        case .stop: bridge.stop()
        }
        await observer.callbacks.first?("9000")

        #expect(oldSource.responses.isEmpty)
        #expect(newSource.responses.isEmpty)
    }

    @Test(arguments: RuntimeChange.allCases) @MainActor
    func queuedNativeCallDoesNotStartForAChangedRuntime(change: RuntimeChange) async {
        let apdu = "queued-\(change)"
        let source = CallbackWebView()
        let queue = DispatchQueue(label: "blockedUpdateDelivery")
        let bridge = JSWebViewBridge(
            storage: JSBridgeStorage(provider: RoutingStorageProbe()),
            updateQueue: queue,
            webView: source
        )
        let observer = LedgerExchangeObserver(apdu: apdu)
        WalletCoreData.addImmediately(eventObserver: observer)
        defer { WalletCoreData.remove(observer: observer) }
        let gate = await QueueGate.blocking(queue)
        defer { gate.release() }

        bridge.userContentController(WKUserContentController(), didReceive: NativeCallMessage.ledgerExchange(source: source, apdu: apdu))
        switch change {
        case .replace: bridge.replaceWebView(CallbackWebView())
        case .stop: bridge.stop()
        }
        gate.release()
        await bridge.waitForPendingUpdates()

        #expect(observer.callbacks.isEmpty)
        #expect(source.responses.isEmpty)
    }

    @MainActor private func drainStorageCallbacks(_ storage: JSBridgeStorage) async {
        // The storage barrier runs after its earlier completion scheduled the main-actor reply.
        await withCheckedContinuation { continuation in
            storage.enqueue(.keys) { _ in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}

@MainActor private final class NativeCallMessage: WKScriptMessage {
    private let source: WKWebView
    private let methodName: String
    private let arg0: String
    private let arg1: String?

    init(source: WKWebView, methodName: String, arg0: String, arg1: String? = nil) {
        self.source = source
        self.methodName = methodName
        self.arg0 = arg0
        self.arg1 = arg1
        super.init()
    }

    static func storage(source: WKWebView, method: JSBridgeStorage.Method = .get, value: String? = nil) -> NativeCallMessage {
        NativeCallMessage(source: source, methodName: method.rawValue, arg0: "storage-key", arg1: value)
    }

    static func ledgerExchange(source: WKWebView, apdu: String) -> NativeCallMessage {
        NativeCallMessage(source: source, methodName: "exchangeWithLedger", arg0: apdu)
    }

    override var name: String { "nativeCall" }
    override var webView: WKWebView? { source }
    override var body: Any {
        var data: [String: Any] = ["requestNumber": 1, "methodName": methodName, "arg0": arg0]
        if let arg1 { data["arg1"] = arg1 }
        return data
    }
}

@MainActor private final class LedgerExchangeObserver: WalletCoreData.EventsObserver {
    private let apdu: String
    var callbacks: [@MainActor (String?) async -> ()] = []

    init(apdu: String) {
        self.apdu = apdu
    }

    func walletCore(event: WalletCoreData.Event) {
        if case .exchangeWithLedger(let eventApdu, let callback) = event, eventApdu == apdu {
            callbacks.append(callback)
        }
    }
}

@MainActor private final class CallbackWebView: WKWebView {
    struct Response: Sendable {
        let requestNumber: Int?
        let value: String?
    }

    private let stream: AsyncStream<Response>
    private let continuation: AsyncStream<Response>.Continuation
    var responses: [Response] = []

    init() {
        (stream, continuation) = AsyncStream<Response>.makeStream()
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func nextResponse() async -> Response? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    // Intercept the imported Objective-C entry point, without loading or executing an SDK page.
    override func __callAsyncJavaScript(
        _ functionBody: String,
        arguments: [String: Any]?,
        inFrame frame: WKFrameInfo?,
        in contentWorld: WKContentWorld,
        completionHandler: (@MainActor @Sendable (Any?, Error?) -> Void)?
    ) {
        let response = Response(
            requestNumber: arguments?["requestNumber"] as? Int,
            value: arguments?["result"] as? String
        )
        responses.append(response)
        continuation.yield(response)
        completionHandler?(nil, nil)
    }
}

private final class QueueGate: Sendable {
    let finished = OSAllocatedUnfairLock(initialState: false)
    private let semaphore = DispatchSemaphore(value: 0)

    /// Occupies `queue` until the gate is released.
    static func blocking(_ queue: DispatchQueue) async -> QueueGate {
        let gate = QueueGate()
        let (started, continuation) = AsyncStream<Void>.makeStream()
        queue.async {
            continuation.yield(())
            continuation.finish()
            gate.wait()
        }
        for await _ in started { break }
        return gate
    }

    func wait() {
        _ = semaphore.wait(timeout: .now() + 5)
        finished.withLock { $0 = true }
    }

    func release() { semaphore.signal() }
}

private final class RoutingStorageProbe: IKeychainStorageProvider, Sendable {
    let calls = OSAllocatedUnfairLock(initialState: [JSBridgeStorage.Method]())
    private let values = OSAllocatedUnfairLock(initialState: ["storage-key": "stored value"])
    private let beforeFirstLoad: (@Sendable () -> Void)?
    private let hasLoaded = OSAllocatedUnfairLock(initialState: false)

    init(beforeFirstLoad: (@Sendable () -> Void)? = nil) {
        self.beforeFirstLoad = beforeFirstLoad
    }

    func load(key: String) throws -> String? {
        calls.withLock { $0.append(.get) }
        let isFirstLoad = hasLoaded.withLock { loaded in
            defer { loaded = true }
            return !loaded
        }
        if isFirstLoad { beforeFirstLoad?() }
        return values.withLock { $0[key] }
    }

    func store(key: String, value: String) throws {
        calls.withLock { $0.append(.set) }
        values.withLock { $0[key] = value }
    }

    func removeOrThrow(key: String) throws {
        calls.withLock { $0.append(.remove) }
        _ = values.withLock { $0.removeValue(forKey: key) }
    }

    func keys() -> [String] {
        calls.withLock { $0.append(.keys) }
        return values.withLock { $0.keys.sorted() }
    }

    func remove(key: String) -> Bool {
        try? removeOrThrow(key: key)
        return true
    }

    func set(key: String, value: String) -> Bool { fatalError("Unexpected legacy set") }
    func get(key: String) -> (Bool, String?) { fatalError("Unexpected legacy get") }
}
