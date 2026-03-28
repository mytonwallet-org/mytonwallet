import Foundation

/// A deep link action button.
public struct Deeplink: Codable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// The result of processing a single intent.
public struct IntentResult: Codable, Sendable {
    public let type: String
    public var message: String?
    public var error: String?
    public var deeplinks: [Deeplink]?

    public init(type: String, message: String? = nil, error: String? = nil, deeplinks: [Deeplink]? = nil) {
        self.type = type
        self.message = message
        self.error = error
        self.deeplinks = deeplinks
    }
}
