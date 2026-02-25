import Foundation

public struct InAppBrowserPageConfig {
    public var url: URL
    public var title: String?
    public let injectDappConnect: Bool
    public init(
        url: URL,
        title: String? = nil,
        injectDappConnect: Bool
    ) {
        self.url = url
        self.title = title
        self.injectDappConnect = injectDappConnect
    }
}
