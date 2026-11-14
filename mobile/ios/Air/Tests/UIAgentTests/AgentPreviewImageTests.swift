import XCTest
import UIKit
import UIComponents
@testable import UIAgent
import WalletCore
import WalletResources

@MainActor
final class AgentPreviewImageTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// As in Telegram's chat list: an 18 pt picture with 2 pt corners, centred on the preview's first line, which
    /// alone makes room for it, so the second line runs under it at full width. Nothing shows before it has loaded.
    func testNewsRowShowsTheNewsPictureBeforeItsHeadlineOnceLoaded() async throws {
        let cell = AgentNewsCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        window.addSubview(cell)
        let url = try makeImageFile()
        let item = ApiAgentV2NewsFeedItem(
            eventId: 10,
            deliveredAt: "2026-10-19T10:00:00Z",
            headline: "Suspected UXLINK hacker wallet sits on $6.54 million ETH gain after the market turn",
            body: "News body",
            imageUrl: url.absoluteString
        )
        cell.configure(latestNews: item, unreadCount: 0)
        let imageView = try XCTUnwrap(findDescendants(of: cell.previewLabel).compactMap { $0 as? WImageView }.first)

        for _ in 0..<100 where imageView.isHidden {
            try await Task.sleep(for: .milliseconds(20))
        }
        cell.layoutIfNeeded()
        XCTAssertFalse(imageView.isHidden)
        XCTAssertNotNil(imageView.image)
        XCTAssertEqual(imageView.frame.minX, 0)
        XCTAssertEqual(imageView.frame.midY, AgentThreadRowMetrics.previewLineHeight / 2, accuracy: 0.34)
        XCTAssertEqual(imageView.frame.size, CGSize(width: 18, height: 18))
        XCTAssertEqual(imageView.layer.cornerRadius, 2)
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
        XCTAssertTrue(imageView.clipsToBounds)
        XCTAssertEqual(getParagraph(of: cell)?.firstLineHeadIndent, 23)
        XCTAssertEqual(getParagraph(of: cell)?.headIndent, 0)
        XCTAssertEqual(cell.previewLabel.attributedText?.string, item.headline)

        cell.configure(latestNews: nil, unreadCount: 0)
        XCTAssertTrue(imageView.isHidden)
        XCTAssertEqual(getParagraph(of: cell)?.firstLineHeadIndent, 0)
    }

    /// In the Digests view the News row shows the picture of the latest digest's first headline
    func testNewsRowShowsThePictureOfTheDigestsFirstHeadline() async throws {
        let cell = AgentNewsCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        window.addSubview(cell)
        let url = try makeImageFile()
        let digest = try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: Data("""
        {"id":"en:2026-10-19T06:00:00Z","deliveredAt":"2026-10-19T06:00:00Z","total":5,"top":[
        {"eventId":1,"headline":"First headline","imageUrl":"\(url.absoluteString)"},
        {"eventId":2,"headline":"Second headline"}]}
        """.utf8))
        cell.configure(latestDigest: digest, unreadCount: 0)
        let imageView = try XCTUnwrap(findDescendants(of: cell.previewLabel).compactMap { $0 as? WImageView }.first)

        for _ in 0..<100 where imageView.isHidden {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(imageView.isHidden)
        XCTAssertNotNil(imageView.image)
        XCTAssertEqual(cell.previewLabel.attributedText?.string, "First headline")
    }

    func testRowWithoutAPictureOrWithAFailedOneLeavesThePreviewWhole() async throws {
        let cell = AgentNewsCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        let item = ApiAgentV2NewsFeedItem(
            eventId: 11,
            deliveredAt: "2026-10-19T10:00:00Z",
            headline: "Headline",
            body: "Body",
            imageUrl: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).png").absoluteString
        )
        cell.configure(latestNews: item, unreadCount: 0)
        let imageView = try XCTUnwrap(findDescendants(of: cell.previewLabel).compactMap { $0 as? WImageView }.first)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(imageView.isHidden)
        XCTAssertEqual(getParagraph(of: cell)?.firstLineHeadIndent, 0)
    }

    /// A discussion shows its news's picture while the post is its latest message, and none once a message follows it
    func testDiscussionRowShowsTheNewsPictureOnlyWhileThePostIsItsLatestMessage() async throws {
        let cell = AgentThreadCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        window.addSubview(cell)
        let url = try makeImageFile()
        let imageView = try XCTUnwrap(findDescendants(of: cell.previewLabel).compactMap { $0 as? WImageView }.first)

        cell.configure(with: try makeDiscussion(messageCount: 1, imageURL: url))
        for _ in 0..<100 where imageView.isHidden {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(imageView.isHidden)
        XCTAssertEqual(getParagraph(of: cell)?.firstLineHeadIndent, 23)

        cell.configure(with: try makeDiscussion(messageCount: 3, imageURL: url))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(imageView.isHidden)
        XCTAssertEqual(getParagraph(of: cell)?.firstLineHeadIndent, 0)
    }

    private func makeDiscussion(messageCount: Int, imageURL: URL) throws -> ApiAgentV2ThreadListItem {
        let thread: [String: Any] = [
            "id": "news-thread",
            "revision": 1,
            "createdAt": "2026-10-19T10:00:00Z",
            "updatedAt": "2026-10-19T10:00:00Z",
            "lastActivityAt": "2026-10-19T10:00:00Z",
            "messageCount": messageCount,
            "title": "Stablecoin supply reaches a new record",
            "news": [
                "eventId": 12,
                "headline": "Stablecoin supply reaches a new record",
                "imageUrl": imageURL.absoluteString,
                "publishedAt": "2026-10-19T09:00:00Z",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: ["thread": thread, "preview": "The combined supply passed $300 billion"])
        return try JSONDecoder().decode(ApiAgentV2ThreadListItem.self, from: data)
    }

    private func getParagraph(of cell: AgentThreadRowCell) -> NSParagraphStyle? {
        cell.previewLabel.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }

    private func makeImageFile() throws -> URL {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 40)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-preview-\(UUID()).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
