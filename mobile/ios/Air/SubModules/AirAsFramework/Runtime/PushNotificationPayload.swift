import Foundation
import WalletContext
import WalletCoreTypes

struct PushNotificationPayload {
    enum Action: String {
        case openUrl
        case nativeTx
        case swap
        case jettonTx
        case staking
        case expiringDns
    }

    let action: Action?
    let address: String?
    let chain: ApiChain
    let url: URL?
    let isExternal: Bool
    let title: String?
    let txId: String?
    let slug: String?
    let stakingId: String?
    let domainAddress: String?

    init(userInfo: [AnyHashable: Any]) {
        action = userInfo.string(for: "action").flatMap(Action.init(rawValue:))
        address = userInfo.string(for: "address")
        chain = userInfo.string(for: "chain").flatMap(ApiChain.init(rawValue:)) ?? .ton
        url = userInfo.string(for: "url").flatMap(URL.init(string:))
        isExternal = userInfo.bool(for: "isExternal") ?? false
        title = userInfo.string(for: "title")
        txId = userInfo.string(for: "txId")
        slug = userInfo.string(for: "slug")
        stakingId = userInfo.string(for: "stakingId")
        domainAddress = userInfo.string(for: "domainAddress")
    }
}

private extension Dictionary where Key == AnyHashable, Value == Any {
    func string(for key: String) -> String? {
        switch self[AnyHashable(key)] {
        case let value as String:
            value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        case let value as NSNumber:
            value.stringValue.nilIfEmpty
        default:
            nil
        }
    }

    func bool(for key: String) -> Bool? {
        switch self[AnyHashable(key)] {
        case let value as Bool:
            value
        case let value as NSNumber:
            value.boolValue
        case let value as String:
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                true
            case "false", "0", "no":
                false
            default:
                nil
            }
        default:
            nil
        }
    }
}
