import Foundation
import UserNotifications
import WalletContext

@MainActor
public protocol DeeplinkNavigator: AnyObject {
    func handle(deeplink: Deeplink, source: DeeplinkOpenSource)
    func handleNotification(_ notification: UNNotification)
}

@MainActor
public final class DeeplinkHandler {

    private weak var deeplinkNavigator: DeeplinkNavigator?
    private let capture: (InstallAttributionSnapshot) -> Void

    public init(deeplinkNavigator: DeeplinkNavigator) {
        self.deeplinkNavigator = deeplinkNavigator
        self.capture = { InstallAttributionDelivery.shared.capture($0) }
    }

    init(deeplinkNavigator: DeeplinkNavigator, capture: @escaping (InstallAttributionSnapshot) -> Void) {
        self.deeplinkNavigator = deeplinkNavigator
        self.capture = capture
    }

    public func handle(_ url: URL, source: DeeplinkOpenSource = .generic) -> Bool {
        let attributed = splitAttributionDeeplink(url)
        if attributed.isGet {
            guard source != .exploreSearchBar else { return false }
            if let snapshot = attributed.snapshot { capture(snapshot) }
            return true
        }
        guard let deeplink = Deeplink(url: attributed.url) else { return false }
        if case .sell = deeplink, !source.canRouteOfframp {
            return false
        }
        if source == .exploreSearchBar, !deeplink.isAllowedFromExploreSearchBar {
            return false
        }
        if source != .exploreSearchBar, let snapshot = attributed.snapshot { capture(snapshot) }
        deeplinkNavigator?.handle(deeplink: deeplink, source: source)
        return true
    }

    public func handleNotification(_ notification: UNNotification) {
        deeplinkNavigator?.handleNotification(notification)
    }
}


@MainActor
final class InstallAttributionDelivery {
    static let shared = InstallAttributionDelivery { snapshot in
        try await Api.bridge.callApi("captureInstallAttribution", snapshot, decoding: Bool.self)
    }

    private let defaults: UserDefaults
    private let send: (InstallAttributionSnapshot) async throws -> Bool
    private let key = "pendingInstallAttributionV1"
    private var sendingGeneration: Int?
    private var isReady = false
    private var bridgeGeneration = 0
    private(set) var pending: InstallAttributionSnapshot?

    init(defaults: UserDefaults = .standard, send: @escaping (InstallAttributionSnapshot) async throws -> Bool) {
        self.defaults = defaults
        self.send = send
        if let data = defaults.data(forKey: key) {
            pending = try? JSONDecoder().decode(InstallAttributionSnapshot.self, from: data)
        }
    }

    func capture(_ snapshot: InstallAttributionSnapshot) {
        if pending == nil || (pending?.attributionKind == "referrer" && snapshot.attributionKind == "utm") {
            pending = snapshot
            defaults.set(try? JSONEncoder().encode(snapshot), forKey: key)
        }
        flush()
    }

    func bridgePrepared() {
        bridgeGeneration += 1
        isReady = true
        flush()
    }

    func bridgeStopped() {
        bridgeGeneration += 1
        isReady = false
    }

    private func flush() {
        guard isReady, sendingGeneration != bridgeGeneration, let selected = pending else { return }
        let generation = bridgeGeneration
        sendingGeneration = generation
        Task {
            let accepted = (try? await send(selected)) == true
            guard generation == bridgeGeneration else { return }
            sendingGeneration = nil
            if pending != selected {
                flush()
            } else if accepted {
                pending = nil
                defaults.removeObject(forKey: key)
            }
            // Failure retains the value; the next bridge preparation or link retries it.
        }
    }
}
