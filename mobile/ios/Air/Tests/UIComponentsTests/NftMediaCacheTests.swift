import UIKit
import XCTest
import Kingfisher
import WalletCore
@testable import UIComponents

@MainActor
final class NftMediaCacheTests: XCTestCase {
    func testPendingCachedImageDoesNotReappearAfterReset() async throws {
        let key = "https://example.invalid/\(UUID().uuidString).png"
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        try await ImageCache.default.store(original, forKey: key, toDisk: false)
        let processor = DownsamplingImageProcessor(size: CGSize(width: 180, height: 180))
        defer {
            ImageCache.default.removeImage(forKey: key, completionHandler: nil)
            ImageCache.default.removeImage(forKey: key, processorIdentifier: processor.identifier, completionHandler: nil)
        }
        var nft = ApiNft.sample
        nft.thumbnail = key
        nft.image = key
        nft.metadata = nil
        let media = NftMediaView()
        media.animationRenderingConfiguration = .activityPreviewDefault
        media.configure(nft: nft)
        media.reset()
        for _ in 0..<100 where ImageCache.default.retrieveImageInMemoryCache(forKey: key, options: [.processor(processor)]) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(ImageCache.default.retrieveImageInMemoryCache(forKey: key, options: [.processor(processor)]),
                        "The cached decode must have finished before checking the reused view")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(media.subviews.compactMap { $0 as? UIImageView }.first?.image)
        XCTAssertNil(media.nft)
    }

    func testLargeCachedOriginalIsDownsampledForActivityPreviews() async throws {
        let key = "https://example.invalid/\(UUID().uuidString).png"
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        try await ImageCache.default.store(original, forKey: key, toDisk: false)
        let processor = DownsamplingImageProcessor(size: CGSize(width: 180, height: 180))
        let headerProcessor = DownsamplingImageProcessor(size: CGSize(width: 900, height: 900))
        defer {
            ImageCache.default.removeImage(forKey: key, completionHandler: nil)
            ImageCache.default.removeImage(forKey: key, processorIdentifier: processor.identifier, completionHandler: nil)
            ImageCache.default.removeImage(forKey: key, processorIdentifier: headerProcessor.identifier, completionHandler: nil)
        }
        var nft = ApiNft.sample
        nft.thumbnail = key
        nft.image = key
        nft.metadata = nil
        let media = NftMediaView()
        media.animationRenderingConfiguration = .activityPreviewDefault
        let loaded = expectation(description: "Cached original processed")
        media.onStateChange = { if case .loaded = $0 { loaded.fulfill() } }
        media.configure(nft: nft)
        await fulfillment(of: [loaded], timeout: 3)
        let image = try XCTUnwrap(media.subviews.compactMap { $0 as? UIImageView }.first?.image)
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height) * image.scale, 180)
        XCTAssertEqual(image.size.width / image.size.height, 1.5, accuracy: 0.02)

        let headerLoaded = expectation(description: "Larger presentation reloads from the original")
        media.onStateChange = { if case .loaded = $0 { headerLoaded.fulfill() } }
        media.animationRenderingConfiguration = .nftDetailsHeaderDefault
        XCTAssertNotNil(media.subviews.compactMap { $0 as? UIImageView }.first?.image,
                        "Keep the thumbnail visible while preparing a larger presentation")
        await fulfillment(of: [headerLoaded], timeout: 3)
        let headerImage = try XCTUnwrap(media.subviews.compactMap { $0 as? UIImageView }.first?.image)
        XCTAssertEqual(max(headerImage.size.width, headerImage.size.height) * headerImage.scale, 900, accuracy: 1)
    }

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
