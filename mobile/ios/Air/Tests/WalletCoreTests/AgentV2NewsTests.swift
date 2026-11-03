import Foundation
import Testing
@testable import WalletCore

@Suite("Agent V2 news")
struct AgentV2NewsTests {
    @Test
    func feedDecodesSDKResponseWithoutProtocolVersion() throws {
        let page = try JSONDecoder().decode(
            ApiAgentV2NewsFeedPage.self,
            from: Data(#"{"locale":"ru","items":[],"nextCursor":"older"}"#.utf8)
        )
        #expect(page.locale == "ru")
        #expect(page.items.isEmpty)
        #expect(page.nextCursor == "older")
    }

    @Test
    func feedDecodesDiscussionAndIgnoresUnknownFields() throws {
        let result = try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2NewsFeedPage>.self,
            from: Data(#"""
            {
              "ok": true,
              "value": {
                "locale": "ru",
                "items": [{
                  "eventId": 307,
                  "deliveredAt": "2026-10-20T10:30:00.000Z",
                  "headline": "Market news",
                  "body": "A **bold** update.",
                  "imageUrl": "https://example.com/news.jpg",
                  "sources": [
                    {"name": "Source", "url": "https://example.com/news", "futureSource": true},
                    {"url": "https://example.com/another"}
                  ],
                  "discussion": {"threadId": "thread-news", "icon": "📰", "futureDiscussion": []},
                  "futureItem": {"enabled": true}
                }],
                "nextCursor": "older-news",
                "futurePage": 1
              },
              "futureEnvelope": false
            }
            """#.utf8)
        )
        let page = try #require(result.value)
        let item = try #require(page.items.first)
        #expect(page.locale == "ru")
        #expect(page.nextCursor == "older-news")
        #expect(item.eventId == 307)
        #expect(item.deliveredAt == "2026-10-20T10:30:00.000Z")
        #expect(item.headline == "Market news")
        #expect(item.body == "A **bold** update.")
        #expect(item.imageUrl == "https://example.com/news.jpg")
        #expect(item.sources == [
            .init(name: "Source", url: "https://example.com/news"),
            .init(url: "https://example.com/another")
        ])
        #expect(item.discussion == .init(threadId: "thread-news", icon: "📰"))
        #expect(try JSONDecoder().decode(ApiAgentV2NewsFeedPage.self, from: JSONEncoder().encode(page)) == page)
    }

    @Test
    func emptyFeedAndOptionalItemFieldsDecode() throws {
        let empty = try JSONDecoder().decode(
            ApiAgentV2NewsFeedPage.self,
            from: Data(#"{"locale":"en","items":[]}"#.utf8)
        )
        #expect(empty.items.isEmpty)
        #expect(empty.nextCursor == nil)

        let item = try JSONDecoder().decode(
            ApiAgentV2NewsFeedItem.self,
            from: Data(#"{"eventId":308,"deliveredAt":"2026-10-20T11:00:00.000Z","headline":"News","body":"Update","sources":[]}"#.utf8)
        )
        #expect(item.imageUrl == nil)
        #expect(item.discussion == nil)
        #expect(item.sources.isEmpty)
    }

    @Test
    func threadSummaryDecodesWithAndWithoutNews() throws {
        let thread: [String: Any] = [
            "id": "thread-news", "revision": 1,
            "createdAt": "2026-10-20T10:30:00.000Z", "updatedAt": "2026-10-20T10:30:00.000Z",
            "lastActivityAt": "2026-10-20T10:30:00.000Z", "messageCount": 0,
            "futureSummary": true
        ]
        let plain = try JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: thread)
        )
        #expect(plain.news == nil)

        var threadWithNews = thread
        threadWithNews["news"] = [
            "eventId": 307, "headline": "Market news", "excerpt": "A bold update.",
            "imageUrl": "https://example.com/news.jpg", "publishedAt": "2026-10-20T10:30:00.000Z",
            "source": "Source", "body": "A **bold** update.",
            "sources": [["name": "Source", "url": "https://example.com/news"], ["url": "https://example.com/another"]],
            "futureNews": []
        ]
        let linked = try JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: threadWithNews)
        )
        let news = try #require(linked.news)
        #expect(news.eventId == 307)
        #expect(news.headline == "Market news")
        #expect(news.excerpt == "A bold update.")
        #expect(news.imageUrl == "https://example.com/news.jpg")
        #expect(news.publishedAt == "2026-10-20T10:30:00.000Z")
        #expect(news.source == "Source")
        #expect(news.body == "A **bold** update.")
        #expect(news.sources == [.init(name: "Source", url: "https://example.com/news"), .init(url: "https://example.com/another")])
        #expect(try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONEncoder().encode(linked)) == linked)

        threadWithNews["news"] = [
            "eventId": 308, "headline": "News", "publishedAt": "2026-10-20T11:00:00.000Z"
        ]
        let minimalNews = try JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: threadWithNews)
        ).news
        #expect(minimalNews?.excerpt == nil)
        #expect(minimalNews?.imageUrl == nil)
        #expect(minimalNews?.source == nil)
        #expect(minimalNews?.body == nil)
        #expect(minimalNews?.sources == nil)
    }

    @Test
    func savedNewsPostDecodesItsOptionalFlagAndRoundTrips() throws {
        let message: [String: Any] = [
            "id": "news-post", "threadId": "thread-news", "role": "assistant", "status": "complete",
            "content": ["kind": "markdown", "text": "**Market news**\n\nA **bold** update."],
            "createdAt": "2026-10-20T10:30:00.000Z", "newsPost": true,
            "followups": [["id": "adadadad-adad-4dad-8dad-adadadadadad", "kind": "suggested_prompt", "text": "What changed?"]]
        ]
        let post = try JSONDecoder().decode(
            ApiAgentV2PersistedMessage.self, from: JSONSerialization.data(withJSONObject: message)
        )
        #expect(post.role == .assistant)
        #expect(post.newsPost == true)
        #expect(post.content == .markdown("**Market news**\n\nA **bold** update."))
        #expect(post.followups?.map(\.id) == ["adadadad-adad-4dad-8dad-adadadadadad"])
        #expect(post.followups?.map(\.text) == ["What changed?"])
        #expect(try JSONDecoder().decode(ApiAgentV2PersistedMessage.self, from: JSONEncoder().encode(post)) == post)

        var legacyMessage = message
        legacyMessage.removeValue(forKey: "newsPost")
        let legacy = try JSONDecoder().decode(
            ApiAgentV2PersistedMessage.self, from: JSONSerialization.data(withJSONObject: legacyMessage)
        )
        #expect(legacy.newsPost == nil)
        let encodedLegacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        #expect(encodedLegacy["newsPost"] == nil)
    }

    @Test
    func pulseNewsEntryPointUsesThePublicWireShape() throws {
        let entryPoint = ApiAgentV2EntryPoint.pulseNews(eventId: 309)
        let data = try JSONEncoder().encode(entryPoint)
        let encoded = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(encoded == ["kind": "pulseNews", "eventId": 309] as NSDictionary)
        #expect(try JSONDecoder().decode(ApiAgentV2EntryPoint.self, from: data) == entryPoint)
        #expect(try JSONDecoder().decode(
            ApiAgentV2EntryPoint.self,
            from: Data(#"{"kind":"pulseNews","eventId":309,"futureEntryPoint":true}"#.utf8)
        ) == entryPoint)
    }

    @Test
    func feedRequestPassesAppLanguageWithoutNormalizingIt() throws {
        let request = ApiAgentV2NewsFeedRequest(lang: "ru-RU", cursor: "older-news")
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary)
        #expect(encoded == ["lang": "ru-RU", "cursor": "older-news"] as NSDictionary)
        let firstPage = ApiAgentV2NewsFeedRequest(lang: "es", cursor: nil)
        let firstPageEncoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(firstPage)) as? NSDictionary)
        #expect(firstPageEncoded == ["lang": "es"] as NSDictionary)
    }

    @Test
    func threadCreateRequestEncodesOptionalNews() throws {
        let request = ApiAgentV2ThreadCreateRequest(news: .init(eventId: 307, locale: "ru"))
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary)
        #expect(encoded == ["news": ["eventId": 307, "locale": "ru"]] as NSDictionary)

        let plain = ApiAgentV2ThreadCreateRequest(news: nil)
        let plainEncoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? NSDictionary)
        #expect(plainEncoded.count == 0)
    }

    @Test
    func unavailableNewsRetainsItsRetryableSDKError() throws {
        let result = try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2NewsFeedPage>.self,
            from: Data(#"{"ok":false,"error":{"code":"news_unavailable","retryable":true}}"#.utf8)
        )
        #expect(!result.ok)
        #expect(result.value == nil)
        #expect(result.error?.code == .newsUnavailable)
        #expect(result.error?.retryable == true)
    }
}
