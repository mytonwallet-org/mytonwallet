import Foundation
import Testing
import WalletContext
import WebKit
@testable import WalletCore

@Suite("JS bridge installation calls", .timeLimit(.minutes(1)))
@MainActor
struct JSBridgeInstallationTests {
    @Test func collectionWakesTheSDKWhichDeliversAndAcknowledgesTheEvent() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(component: "JSBridgeInstallationTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var next = 0
        let installations = AppInstallationStore(
            fileURL: directory.appending(component: "installation.json"),
            readTransaction: {
                .transaction(isVerified: true, originalPurchaseDate: Date(timeIntervalSince1970: 1_700_000_000), environment: "production")
            },
            containerCreationDate: { Date(timeIntervalSince1970: 1_791_600_000) },
            makeUUID: {
                next += 1
                return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", next))!
            }
        )
        let source = RecordingWebView()
        let bridge = JSWebViewBridge(
            storage: JSBridgeStorage(provider: UnusedStorageProvider()),
            updateQueue: DispatchQueue(label: "updateDelivery"),
            webView: source,
            installations: installations
        )
        let controller = WKUserContentController()

        bridge.userContentController(controller, didReceive: InstallationCallMessage(source: source, methodName: "airInstallationGetPending"))
        let answerAndWake = [await source.nextCall(), await source.nextCall()]
        #expect(answerAndWake.contains { ($0.result as? [Any])?.isEmpty == true })
        #expect(answerAndWake.contains { $0.functionBody == "window.airBridge?.handleInstallationStateChange?.()" })

        bridge.userContentController(controller, didReceive: InstallationCallMessage(source: source, methodName: "airInstallationGetPending"))
        let deliveries = try #require((await source.nextCall()).result as? [[String: Any]])
        let body = try #require(deliveries.first?["body"] as? [String: Any])
        #expect(deliveries.count == 1)
        #expect(body["collectionStatus"] as? String == "ok")

        let answer = """
            {"ok":true,"schemaVersion":2,"installationId":"\(body["installationId"] as? String ?? "")","eventId":"\(body["eventId"] as? String ?? "")"}
            """
        bridge.userContentController(controller, didReceive: InstallationCallMessage(
            source: source, methodName: "airInstallationAcknowledge", arg0: "app_transaction", arg1: answer
        ))
        #expect((await source.nextCall()).result as? Bool == true)
        #expect(installations.pendingDeliveries().isEmpty)
    }
}

@MainActor private final class InstallationCallMessage: WKScriptMessage {
    private let source: WKWebView
    private let methodName: String
    private let arg0: String?
    private let arg1: String?

    init(source: WKWebView, methodName: String, arg0: String? = nil, arg1: String? = nil) {
        self.source = source
        self.methodName = methodName
        self.arg0 = arg0
        self.arg1 = arg1
        super.init()
    }

    override var name: String { "nativeCall" }
    override var webView: WKWebView? { source }
    override var body: Any {
        var data: [String: Any] = ["requestNumber": 1, "methodName": methodName]
        if let arg0 { data["arg0"] = arg0 }
        if let arg1 { data["arg1"] = arg1 }
        return data
    }
}

@MainActor private final class RecordingWebView: WKWebView {
    struct Call {
        let functionBody: String
        let result: Any?
    }

    private var calls: [Call] = []
    private var delivered = 0

    init() {
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func nextCall() async -> Call {
        while calls.count <= delivered {
            try? await Task.sleep(for: .milliseconds(5))
        }
        delivered += 1
        return calls[delivered - 1]
    }

    // Intercept the imported Objective-C entry point, without loading or executing an SDK page.
    override func __callAsyncJavaScript(
        _ functionBody: String,
        arguments: [String: Any]?,
        inFrame frame: WKFrameInfo?,
        in contentWorld: WKContentWorld,
        completionHandler: (@MainActor @Sendable (Any?, Error?) -> Void)?
    ) {
        calls.append(Call(functionBody: functionBody, result: arguments?["result"]))
        completionHandler?(nil, nil)
    }
}

private struct UnusedStorageProvider: IKeychainStorageProvider {
    func set(key: String, value: String) -> Bool { false }
    func get(key: String) -> (Bool, String?) { (false, nil) }
    func remove(key: String) -> Bool { false }
    func keys() -> [String] { [] }
    func load(key: String) throws -> String? { nil }
    func store(key: String, value: String) throws {}
    func removeOrThrow(key: String) throws {}
}
