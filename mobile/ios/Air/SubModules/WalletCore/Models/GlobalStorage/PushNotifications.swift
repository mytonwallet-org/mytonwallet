
public struct GlobalPushNotifications: Equatable, Hashable, Codable, Sendable {
    public var isAvailable: Bool?
    public var userToken: String?
    public var platform: CapacitorPlatform?
    public var enabledAccounts: [String]
    
    public init(isAvailable: Bool?, userToken: String?, platform: CapacitorPlatform?, enabledAccounts: [String]) {
        self.isAvailable = isAvailable
        self.userToken = userToken
        self.platform = platform
        self.enabledAccounts = enabledAccounts
    }
}


public struct ApiNotificationsAccountValue: Equatable, Hashable, Codable, Sendable {
    public var key: String
    
    public init(key: String) {
        self.key = key
    }
}
