
import Foundation

protocol DeeplinkNavigator: AnyObject {
    func handle(deeplink: Deeplink)
}

class DeeplinkHandler {

    private weak var deeplinkNavigator: DeeplinkNavigator? = nil

    init(deeplinkNavigator: DeeplinkNavigator) {
        self.deeplinkNavigator = deeplinkNavigator
    }
    
    func handle(_ url: URL) -> Bool {
        guard let deeplink = Deeplink(url: url) else { return false }
        deeplinkNavigator?.handle(deeplink: deeplink)
        return true
    }
}
