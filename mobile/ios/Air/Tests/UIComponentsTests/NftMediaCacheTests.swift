import UIKit
import XCTest
import Kingfisher
import WalletCore
@testable import UIComponents

@MainActor
final class NftMediaCacheTests: XCTestCase {
    func testCachedImageIsAvailableImmediatelyAndClearedOnReuse() async throws {
        let key = "https://example.invalid/\(UUID().uuidString).png"
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        try await ImageCache.default.store(image, forKey: key, toDisk: false)
        defer { ImageCache.default.removeImage(forKey: key, fromDisk: false, completionHandler: nil) }
        var nft = ApiNft.sample
        nft.thumbnail = key
        nft.image = key
        nft.metadata = nil
        let media = NftMediaView()
        var loaded = false
        media.onStateChange = { if case .loaded = $0 { loaded = true } }
        media.configure(nft: nft)
        XCTAssertTrue(loaded)
        let imageView = try XCTUnwrap(media.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertTrue(imageView.image === image)
        media.configure(nft: nil)
        XCTAssertNil(imageView.image)
        XCTAssertNil(media.nft)
    }
}
