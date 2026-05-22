import Foundation

public struct InAppBrowserPageConfig {
    public var url: URL
    public var title: String?
    public let injectDappConnect: Bool
    public let historyTag: String?

    public init(
        url: URL,
        title: String? = nil,
        injectDappConnect: Bool,
        historyTag: String? = nil
    ) {
        self.url = url
        self.title = title
        self.injectDappConnect = injectDappConnect
        self.historyTag = historyTag
    }
}
