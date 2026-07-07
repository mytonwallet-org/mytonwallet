import Foundation
import UserNotifications
import WalletContext

@MainActor
public protocol DeeplinkNavigator: AnyObject {
    func handle(deeplink: Deeplink)
    func handleNotification(_ notification: UNNotification)
}

@MainActor
public final class DeeplinkHandler {

    private weak var deeplinkNavigator: DeeplinkNavigator?

    public init(deeplinkNavigator: DeeplinkNavigator) {
        self.deeplinkNavigator = deeplinkNavigator
    }

    public func handle(_ url: URL, source: DeeplinkOpenSource = .generic) -> Bool {
        guard let deeplink = Deeplink(url: url) else { return false }
        if case .switchToClassic = deeplink, !isCapacitorAvailable {
            return false
        }
        if case .sell = deeplink, !source.canRouteOfframp {
            return false
        }
        if source == .exploreSearchBar, !deeplink.isAllowedFromExploreSearchBar {
            return false
        }
        deeplinkNavigator?.handle(deeplink: deeplink)
        return true
    }

    public func handleNotification(_ notification: UNNotification) {
        deeplinkNavigator?.handleNotification(notification)
    }
}
