import Foundation
import WalletContext

private let log = Log("UpdateAccountBanners")

extension ApiUpdate {
    public struct UpdateAccountBanners: Equatable, Codable, Sendable {
        public var accountId: String
        public var homeBanners: [ApiPromotion]
        public var stakingBanners: [ApiPromotion]

        private enum CodingKeys: String, CodingKey {
            case accountId
            case homeBanners
            case stakingBanners
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accountId = try container.decode(String.self, forKey: .accountId)
            homeBanners = try Self.decodeBanners(from: container, forKey: .homeBanners)
            stakingBanners = try Self.decodeBanners(from: container, forKey: .stakingBanners)
        }

        private static func decodeBanners(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> [ApiPromotion] {
            var elements = try container.nestedUnkeyedContainer(forKey: key)
            var banners: [ApiPromotion] = []
            while !elements.isAtEnd {
                let index = elements.currentIndex
                let decoder = try elements.superDecoder()
                do {
                    banners.append(try ApiPromotion(from: decoder))
                } catch {
                    log.error("Skipping invalid \(key.rawValue, .public)[\(index)]: \(error)")
                }
            }
            return banners
        }
    }
}
