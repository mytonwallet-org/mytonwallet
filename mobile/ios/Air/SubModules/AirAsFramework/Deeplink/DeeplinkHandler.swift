
import Foundation
import UIKit
import WalletContext

protocol DeeplinkNavigator: AnyObject {
    func handle(deeplink: Deeplink)
    func handleNotification(_ notification: UNNotification)
}

final class DeeplinkHandler {

    private weak var deeplinkNavigator: DeeplinkNavigator? = nil

    init(deeplinkNavigator: DeeplinkNavigator) {
        self.deeplinkNavigator = deeplinkNavigator
    }
    
    func handle(_ url: URL, source: DeeplinkOpenSource = .generic) -> Bool {
        guard let deeplink = Deeplink(url: url) else { return false }
        if source == .exploreSearchBar, !deeplink.isAllowedFromExploreSearchBar {
            return false
        }
        deeplinkNavigator?.handle(deeplink: deeplink)
        return true
    }
    
    func handleNotification(_ notification: UNNotification) {
        deeplinkNavigator?.handleNotification(notification)
    }
}
