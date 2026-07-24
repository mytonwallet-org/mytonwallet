import Foundation
import WalletContext

public enum InAppBrowserUrlRouting: Equatable {
    case allow
    case consume
    case handleDeeplink(source: DeeplinkOpenSource)
    case openSystemUrl
    case openNewPage
    case ignore
}

public func resolveInAppBrowserNavigationUrlRouting(
    _ url: URL,
    isMainFrame: Bool,
    shouldOpenInNewPage: Bool
) -> InAppBrowserUrlRouting {
    if !isMainFrame {
        return isWebUrl(url) && !shouldOpenInNewPage ? .allow : .consume
    }
    if isOfframpDeeplink(url) {
        return .consume
    }
    if Deeplink(url: url) != nil {
        return .handleDeeplink(source: .inAppBrowser)
    }
    if isExternalSystemUrl(url) {
        return .openSystemUrl
    }
    if shouldOpenInNewPage, isWebUrl(url) {
        return .openNewPage
    }
    return .allow
}

public func resolveInAppBrowserWindowOpenUrlRouting(_ url: URL) -> InAppBrowserUrlRouting {
    if isOfframpDeeplink(url) {
        return .consume
    }
    if Deeplink(url: url) != nil {
        return .handleDeeplink(source: .inAppBrowser)
    }
    if isExternalSystemUrl(url) {
        return .openSystemUrl
    }
    if isWebUrl(url) {
        return .openNewPage
    }
    return .ignore
}

public func resolveInAppBrowserWebKitPopupUrlRouting(_ url: URL?) -> InAppBrowserUrlRouting {
    guard let url else {
        return .openNewPage
    }
    return resolveInAppBrowserWindowOpenUrlRouting(url)
}

public func resolveInAppBrowserMessageOrigin(scheme: String, host: String, port: Int) -> String? {
    let scheme = scheme.lowercased()
    guard scheme == "http" || scheme == "https", !host.isEmpty else {
        return nil
    }

    var components = URLComponents()
    components.scheme = scheme
    components.host = host.lowercased()
    let isDefaultPort = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
    if port != 0 && !isDefaultPort {
        components.port = port
    }
    return components.url?.origin
}

private let externalSystemUrlSchemes = Set(["itms-appss", "itms-apps", "tel", "sms", "mailto", "geo", "tg", SELF_PROTOCOL_SCHEME])

private func isOfframpDeeplink(_ url: URL) -> Bool {
    guard case .sell = Deeplink(url: url) else {
        return false
    }
    return true
}

private func isExternalSystemUrl(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else {
        return false
    }
    return externalSystemUrlSchemes.contains(scheme)
}

private func isWebUrl(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return scheme == "http" || scheme == "https"
}
