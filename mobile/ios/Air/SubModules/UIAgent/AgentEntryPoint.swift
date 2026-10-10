import UIKit
import WalletCore

public enum AgentEntryPoint {
    struct Request {
        let query: String?
        let entryPoint: ApiAgentV2EntryPoint?
    }

    @MainActor
    private static var pendingRequest: Request?
    static let requestDidChangeNotification = Notification.Name("AgentEntryPointRequestDidChange")

    @MainActor
    public static func makeRootViewController() -> UIViewController {
        makeRootViewController(preloader: .shared)
    }

    @MainActor
    static func makeRootViewController(preloader: AgentPreloader) -> UIViewController {
        if let model = preloader.takeReadyModel() {
            return AgentVC(model: model)
        }
        return AgentRootVC(client: preloader.client, preloader: preloader)
    }

    @MainActor
    public static func setWalletReady(_ isReady: Bool) {
        AgentPreloader.shared.setWalletReady(isReady)
    }

    @MainActor
    public static func preload() {
        AgentPreloader.shared.prepare()
    }

    @MainActor
    public static func enqueue(query: String?, entryPoint: ApiAgentV2EntryPoint?) {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = trimmedQuery?.isEmpty == false ? trimmedQuery : nil
        pendingRequest = normalizedQuery != nil || entryPoint != nil
            ? Request(query: normalizedQuery, entryPoint: entryPoint)
            : nil
        if pendingRequest != nil {
            NotificationCenter.default.post(name: requestDidChangeNotification, object: nil)
        }
    }

    @MainActor
    static func consumePendingRequest() -> Request? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    @MainActor
    static func clearPendingRequest() {
        pendingRequest = nil
    }
}
