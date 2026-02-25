import Foundation
import WebKit
import WalletContext

extension Api {
    
    public static func subscribeNotifications(props: ApiSubscribeNotificationsProps) async throws -> ApiSubscribeNotificationsResult {
        try await bridge.callApi("subscribeNotifications", props, decoding: ApiSubscribeNotificationsResult.self)
    }

    public static func unsubscribeNotifications(props: ApiUnsubscribeNotificationsProps) async throws -> Any? {
        try await bridge.callApiRaw("unsubscribeNotifications", props)
    }
}


// MARK: - Types

public struct ApiNotificationAddress: Encodable {
    public let title: String?
    public let address: String
    public let chain: ApiChain

    public init(title: String? = nil, address: String, chain: ApiChain) {
        self.title = title
        self.address = address
        self.chain = chain
    }
}

public struct ApiSubscribeNotificationsProps: Encodable {
    public let userToken: String
    public let platform: CapacitorPlatform
    public let langCode: String
    public let addresses: [ApiNotificationAddress]

    public init(userToken: String, platform: CapacitorPlatform, langCode: String, addresses: [ApiNotificationAddress]) {
        self.userToken = userToken
        self.platform = platform
        self.langCode = langCode
        self.addresses = addresses
    }
}

public struct ApiSubscribeNotificationsResult: Decodable {
    public let ok: Bool
    public let addressKeys: [String: ApiNotificationsAccountValue]
}


public enum CapacitorPlatform: String, Equatable, Hashable, Codable, Sendable {
    case ios = "ios"
    case android = "android"
}

public struct ApiUnsubscribeNotificationsProps: Encodable {
    public let userToken: String
    public let addresses: [ApiNotificationAddress]

    public init(userToken: String, addresses: [ApiNotificationAddress]) {
        self.userToken = userToken
        self.addresses = addresses
    }
}
