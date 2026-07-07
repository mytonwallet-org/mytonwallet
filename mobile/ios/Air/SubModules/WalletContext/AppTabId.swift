import Foundation

public struct AppTabId: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let wallet = AppTabId("wallet")
    public static let agent = AppTabId("agent")
    public static let explore = AppTabId("explore")
    public static let settings = AppTabId("settings")
    public static let portfolio = AppTabId("portfolio")

    public var isRequired: Bool {
        self == .wallet || self == .settings
    }
}
