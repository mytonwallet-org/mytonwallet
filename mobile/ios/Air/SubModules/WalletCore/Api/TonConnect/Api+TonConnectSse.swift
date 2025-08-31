
import Foundation
import WalletContext

extension Api {
    
    public struct SseConnectionParams: Encodable {
        public struct DeviceInfo: Encodable {
            public let platform: String
            public let appName: String
            public let appVersion: String
            public let maxProtocolVersion: Int
            public let features: [AnyEncodable]
            public init(platform: String, appName: String, appVersion: String, maxProtocolVersion: Int, features: [AnyEncodable]) {
                self.platform = platform
                self.appName = appName
                self.appVersion = appVersion
                self.maxProtocolVersion = maxProtocolVersion
                self.features = features
            }
        }

        public let url: String
        public let deviceInfo: DeviceInfo
        public let isWalletBrowser: Bool
        public let identifier: String
        public init(url: String,
                    deviceInfo: DeviceInfo,
                    isWalletBrowser: Bool,
                    identifier: String
        ) {
            self.url = url
            self.deviceInfo = deviceInfo
            self.isWalletBrowser = isWalletBrowser
            self.identifier = identifier
        }
    }
    
    public static var deviceInfo: SseConnectionParams.DeviceInfo {
        let feature: [String: AnyEncodable] = ["name": AnyEncodable("SendTransaction"), "maxMessages": AnyEncodable(4)]
        return Api.SseConnectionParams.DeviceInfo(platform: devicePlatform,
                                                            appName: appName,
                                                            appVersion: appVersion,
                                                            maxProtocolVersion: supportedTonConnectVersion,
                                                            features: [
                                                                AnyEncodable("SendTransaction"),
                                                                AnyEncodable(feature)
                                                            ])
    }
    
    public enum ReturnStrategy: Equatable, Hashable, Codable {
        case none
        case back
        case url(String)
        
        init(string ret: String) {
            switch ret {
            case "back":
                self = .back
            case "none":
                self = .none
            default:
                self = .url(ret)
            }
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            self = ReturnStrategy(string: string)
        }
        
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .none:
                try container.encode("none")
            case .back:
                try container.encode("back")
            case .url(let url):
                try container.encode(url)
            }
        }
    }
    
    public static func startSseConnection(url: String, identifier: String ) async throws -> ReturnStrategy? {
        
        let params = Api.SseConnectionParams(
            url: url,
            deviceInfo: deviceInfo,
            isWalletBrowser: false,
            identifier: identifier)
        
        let data = try await bridge.callApiRaw("startSseConnection", params)
        if let ret = data as? String {
            return ReturnStrategy(string: ret)
        } else {
            return nil
        }
    }
}
