import Foundation
import Testing
import Perception
import WalletContext
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
    func digestHeadlineDecodesAnOptionalPicture() throws {
        let headlines = try JSONDecoder().decode(
            [ApiAgentV2DigestHeadline].self,
            from: Data(#"""
            [{"eventId":1,"headline":"A","imageUrl":"https://example.com/1.png"},
             {"eventId":2,"headline":"B"},
             {"eventId":3,"headline":"C","imageUrl":null}]
            """#.utf8)
        )
        #expect(headlines.map(\.imageUrl) == ["https://example.com/1.png", nil, nil])
        #expect(headlines.map(\.headline) == ["A", "B", "C"])
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
                  "discussionNaming": {"title": "Discuss market news", "icon": "📈", "followups": ["What changed?", "What comes next?"]},
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
        #expect(item.discussionNaming == .init(title: "Discuss market news", icon: "📈", followups: ["What changed?", "What comes next?"]))
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
        #expect(empty.digests == nil)

        let item = try JSONDecoder().decode(
            ApiAgentV2NewsFeedItem.self,
            from: Data(#"{"eventId":308,"deliveredAt":"2026-10-20T11:00:00.000Z","headline":"News","body":"Update","sources":[]}"#.utf8)
        )
        #expect(item.imageUrl == nil)
        #expect(item.discussion == nil)
        #expect(item.discussionNaming == nil)
        #expect(item.sources.isEmpty)
    }

    @Test
    func decodeFeedKeepingItemWithMalformedDiscussionNaming() throws {
        let page = try JSONDecoder().decode(
            ApiAgentV2NewsFeedPage.self,
            from: Data(#"""
            {"locale":"en","items":[{
              "eventId":308,"deliveredAt":"2026-10-20T11:00:00.000Z","headline":"News","body":"Update","sources":[],
              "discussionNaming":{"title":"Discuss news","followups":["What changed?",42]}
            }]}
            """#.utf8)
        )
        #expect(page.items.count == 1)
        #expect(page.items.first?.eventId == 308)
        #expect(page.items.first?.discussionNaming == nil)
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
        #expect(plain.digest == nil)

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
    func supportHistoryDecodesEveryRoleAndSkipsUnknownEvents() throws {
        let common: [String: Any] = [
            "threadId": "support-thread", "status": "complete", "createdAt": "2026-11-08T10:30:00.000Z"
        ]
        let author = ["operatorId": "support-42", "name": "Alex", "avatarUrl": "https://example.com/avatar.jpg"]
        let messageFields: [[String: Any]] = [
            ["id": "user", "role": "user", "content": ["kind": "markdown", "text": "Help"]],
            ["id": "assistant", "role": "assistant", "content": ["kind": "markdown", "text": "Connecting"]],
            ["id": "requested", "role": "event", "code": "support_requested"],
            ["id": "joined", "role": "event", "code": "operator_joined", "author": author],
            ["id": "operator", "role": "operator", "text": "**Plain text**", "author": author],
            ["id": "unknown", "role": "event", "code": "future_support_event"],
            ["id": "closed", "role": "event", "code": "support_closed", "reason": "inactivity"]
        ]
        let page: [String: Any] = [
            "thread": [
                "id": "support-thread", "revision": 2,
                "createdAt": "2026-11-08T10:30:00.000Z", "updatedAt": "2026-11-08T10:30:00.000Z",
                "lastActivityAt": "2026-11-08T10:30:00.000Z", "messageCount": 7,
                "support": ["state": "closed"]
            ],
            "messages": messageFields.map { common.merging($0) { _, new in new } },
            "nextCursor": "older"
        ]
        let history = try JSONDecoder().decode(
            ApiAgentV2ThreadHydration.self, from: JSONSerialization.data(withJSONObject: page)
        )
        #expect(history.messages.map(\.id) == ["user", "assistant", "requested", "joined", "operator", "closed"])
        #expect(history.messages.map(\.role) == [.user, .assistant, .event, .event, .operator, .event])
        #expect(history.messages[2].code == .supportRequested)
        #expect(history.messages[3].code == .operatorJoined)
        #expect(history.messages[3].author?.name == "Alex")
        #expect(history.messages[4].content == nil)
        #expect(history.messages[4].text == "**Plain text**")
        #expect(history.messages[4].author == .init(
            operatorId: "support-42", name: "Alex", avatarUrl: "https://example.com/avatar.jpg"
        ))
        #expect(history.messages[5].code == .supportClosed)
        #expect(history.messages[5].reason == .inactivity)
        #expect(history.thread.support?.state == .closed)
        #expect(history.nextCursor == "older")
        #expect(try JSONDecoder().decode(ApiAgentV2ThreadHydration.self, from: JSONEncoder().encode(history)) == history)
    }

    @Test
    func threadSupportDecodesInSummariesAndLiveUpdates() throws {
        let base: [String: Any] = [
            "id": "support-thread", "revision": 2,
            "createdAt": "2026-11-08T10:30:00.000Z", "updatedAt": "2026-11-08T10:30:00.000Z",
            "lastActivityAt": "2026-11-08T10:30:00.000Z", "messageCount": 4
        ]
        let plain = try JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: base)
        )
        #expect(plain.support == nil)
        for state in ["waiting", "operator", "closed"] {
            var thread = base
            thread["support"] = ["state": state, "lastOperatorMessageAt": "2026-11-08T10:31:00.000Z"]
            let summary = try JSONDecoder().decode(
                ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: thread)
            )
            #expect(summary.support?.state.rawValue == state)
            #expect(summary.support?.lastOperatorMessageAt == "2026-11-08T10:31:00.000Z")
            #expect(summary.makeCopy(isPinned: true).support == summary.support)
            let envelope = try JSONDecoder().decode(
                ApiAgentV2ClientUpdateEnvelope.self,
                from: JSONSerialization.data(withJSONObject: [
                    "type": "agentV2",
                    "update": ["kind": "threadChanged", "threadId": "support-thread", "thread": thread]
                ])
            )
            guard case .threadChanged(let threadId, let updatedThread) = envelope.update else {
                Issue.record("Expected a live thread summary")
                continue
            }
            #expect(threadId == summary.id)
            #expect(updatedThread.support == summary.support)
        }
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

    @Test(arguments: [
        ApiAgentV2EntryPoint.SupportRequestSource.starterHint,
        .header,
        .menu,
    ])
    func supportRequestEntryPointUsesThePublicWireShape(source: ApiAgentV2EntryPoint.SupportRequestSource) throws {
        let entryPoint = ApiAgentV2EntryPoint.supportRequest(source: source)
        let data = try JSONEncoder().encode(entryPoint)
        let encoded = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(encoded == ["kind": "supportRequest", "source": source.rawValue] as NSDictionary)
        #expect(try JSONDecoder().decode(ApiAgentV2EntryPoint.self, from: data) == entryPoint)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ApiAgentV2EntryPoint.self, from: Data(#"{"kind":"supportRequest","source":"composer"}"#.utf8))
        }
    }

    @Test
    func supportEscalationLimitDecodesAsItsOwnNonRetryableCode() throws {
        let result = try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2NewsFeedPage>.self,
            from: Data(#"{"ok":false,"error":{"code":"support_escalation_rate_limited","retryable":false}}"#.utf8)
        )
        #expect(result.error?.code == .supportEscalationRateLimited)
        #expect(result.error?.retryable == false)
        #expect(ApiAgentV2ErrorCode.supportEscalationRateLimited.rawValue == "support_escalation_rate_limited")
    }

    @Test
    func feedRequestPassesAppLanguageWithoutNormalizingIt() throws {
        let request = ApiAgentV2NewsFeedRequest(lang: "ru-RU", cursor: "older-news", digestHour: 21, digestMinute: 45, timeZone: "Europe/Moscow")
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary)
        #expect(encoded == [
            "lang": "ru-RU", "cursor": "older-news", "digestHour": 21, "digestMinute": 45, "timeZone": "Europe/Moscow"
        ] as NSDictionary)
        let firstPage = ApiAgentV2NewsFeedRequest(lang: "es", cursor: nil, digestHour: 7, digestMinute: 0, timeZone: "Europe/Madrid")
        let firstPageEncoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(firstPage)) as? NSDictionary)
        #expect(firstPageEncoded == ["lang": "es", "digestHour": 7, "digestMinute": 0, "timeZone": "Europe/Madrid"] as NSDictionary)
        let digests = ApiAgentV2NewsFeedRequest(
            lang: "ru-RU", cursor: "older-digests", digestHour: 21, digestMinute: 15, timeZone: "Europe/Moscow", view: .digests
        )
        let digestsEncoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(digests)) as? NSDictionary)
        #expect(digestsEncoded == [
            "lang": "ru-RU", "cursor": "older-digests", "digestHour": 21, "digestMinute": 15, "timeZone": "Europe/Moscow", "view": "digests"
        ] as NSDictionary)
        let all = ApiAgentV2NewsFeedRequest(lang: "es", cursor: nil, digestHour: 7, digestMinute: 0, timeZone: "Europe/Madrid", view: .all)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(all) == encoder.encode(firstPage))
    }

    @Test @MainActor
    func verifyNewsFeedViewPersistenceAndFallbackWithoutChangingTheDigestHour() async {
        let name = "AgentNewsSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AgentNewsNotificationSettings(userDefaults: defaults)
        #expect(settings.newsFeedView == .all)
        _ = await settings.setDigestTime(hour: 9, minute: 0)
        settings.setNewsFeedView(.digests)
        #expect(AgentNewsNotificationSettings(userDefaults: defaults).newsFeedView == .digests)
        settings.setNewsFeedView(.all)
        #expect(AgentNewsNotificationSettings(userDefaults: defaults).newsFeedView == .all)
        for storedView in ["unknown", ""] {
            defaults.set(Data("""
            {"mode":"off","digestHour":9,"newsFeedView":"\(storedView)"}
            """.utf8), forKey: "agent-mypulse-notifications")
            let restored = AgentNewsNotificationSettings(userDefaults: defaults)
            #expect(restored.newsFeedView == .all)
            #expect(restored.digestHour == 9)
        }
        defaults.set(Data(#"{"mode":"off","digestHour":9}"#.utf8), forKey: "agent-mypulse-notifications")
        #expect(AgentNewsNotificationSettings(userDefaults: defaults).newsFeedView == .all)
        #expect(AgentNewsNotificationSettings(userDefaults: defaults).digestHour == 9)
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

    @Test(arguments: [ApiAgentV2ErrorCode.newsUnavailable, .digestUnavailable])
    func unavailableDiscussionRetainsItsRetryableSDKError(code: ApiAgentV2ErrorCode) throws {
        let result = try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2NewsFeedPage>.self,
            from: Data("{\"ok\":false,\"error\":{\"code\":\"\(code.rawValue)\",\"retryable\":true}}".utf8)
        )
        #expect(!result.ok)
        #expect(result.value == nil)
        #expect(result.error?.code == code)
        #expect(result.error?.retryable == true)
    }
    @Test
    func digestsDecodeOnFeedAndThreadAndKeepUnstartedThreadsOutOfTheList() throws {
        let digestId = "ru:2026-11-08T18:00:00.000Z"
        let top: [[String: Any]] = [["eventId": 307, "headline": "Market news"]]
        let page = try JSONDecoder().decode(ApiAgentV2NewsFeedPage.self, from: JSONSerialization.data(withJSONObject: [
            "locale": "ru", "items": [], "digests": [[
                "id": digestId, "deliveredAt": "2026-11-08T18:00:00.000Z", "top": top, "total": 5,
                "discussion": ["threadId": "digest-thread", "icon": "📰"]
            ]]
        ]))
        let digest = try #require(page.digests?.first)
        #expect(digest.id == digestId)
        #expect(digest.top.first?.eventId == 307)
        #expect(digest.total == 5)
        #expect(digest.discussion?.threadId == "digest-thread")
        #expect(digest.discussionNaming == nil)
        let named = try JSONDecoder().decode(ApiAgentV2NewsFeedPage.self, from: JSONSerialization.data(withJSONObject: [
            "locale": "ru", "items": [], "digests": [
                [
                    "id": digestId, "deliveredAt": "2026-11-08T18:00:00.000Z", "top": top, "total": 5,
                    "discussionNaming": ["title": "Evening digest", "icon": "🌙", "followups": ["What matters most?"]]
                ],
                [
                    "id": "ru:2026-11-07T18:00:00.000Z", "deliveredAt": "2026-11-07T18:00:00.000Z", "top": top, "total": 5,
                    "discussionNaming": ["title": "Evening digest", "followups": ["What matters most?", 42]]
                ],
                [
                    "id": "ru:2026-11-06T18:00:00.000Z", "deliveredAt": "2026-11-06T18:00:00.000Z", "top": top, "total": 5,
                    "discussionNaming": ["title": "Morning digest", "followups": ["What changed?", "What comes next?"]]
                ]
            ]
        ]))
        #expect(named.digests?.map(\.discussionNaming) == [
            .init(title: "Evening digest", icon: "🌙", followups: ["What matters most?"]), nil,
            .init(title: "Morning digest", followups: ["What changed?", "What comes next?"])
        ])
        #expect(named.digests?.last?.discussionNaming?.icon == nil)
        #expect(try JSONDecoder().decode(ApiAgentV2NewsFeedPage.self, from: JSONEncoder().encode(named)) == named)
        for count in [1, 2] {
            let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: [
                "id": "digest-thread", "revision": 1, "createdAt": digest.deliveredAt,
                "updatedAt": digest.deliveredAt, "lastActivityAt": digest.deliveredAt, "messageCount": count,
                "digest": ["id": digestId, "windowEnd": digest.deliveredAt, "top": top, "total": 5]
            ]))
            #expect(thread.digest?.id == digestId)
            #expect(thread.digest?.windowEnd == digest.deliveredAt)
            #expect(thread.digest?.top == digest.top)
            #expect(thread.isStarted == (count > 1))
            #expect(thread.makeCopy(isPinned: true).digest == thread.digest)
        }
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            ApiAgentV2ThreadCreateRequest(news: nil, digest: .init(id: digestId))
        )) as? NSDictionary
        #expect(encoded == ["digest": ["id": digestId]] as NSDictionary)
    }

    @Test @MainActor
    func notificationModesRequirePermissionAndOnlyPersistSuccessfulCalls() async throws {
        let name = "AgentNewsSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var hasPermission = false
        var shouldSucceed = true
        var calls: [ApiSetNewsNotificationsProps] = []
        let store = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { "token" },
            ensureToken: { hasPermission ? "token" : nil }, apply: { calls.append($0); return shouldSucceed }
        )
        #expect(store.mode == .off)
        #expect(store.digestHour == 21)
        #expect(await store.setMode(.digest) == .permissionDenied)
        #expect(store.mode == .off)
        #expect(calls.isEmpty)
        hasPermission = true
        let hasObservedChange = UnfairLock(initialState: false)
        withPerceptionTracking { _ = store.mode } onChange: { hasObservedChange.withLock { $0 = true } }
        #expect(await store.setMode(.digest) == .ok)
        #expect(hasObservedChange.withLock { $0 })
        #expect(store.mode == .digest)
        shouldSucceed = false
        #expect(await store.setMode(.news) == .failed)
        #expect(store.mode == .digest)
        hasPermission = false
        #expect(await store.setMode(.news) == .permissionDenied)
        #expect(store.mode == .digest)
        #expect(calls.count == 2)
        #expect(AgentNewsNotificationSettings(userDefaults: defaults).mode == .digest)
        shouldSucceed = true
        #expect(await store.setMode(.off) == .ok)
        #expect(store.mode == .off)
        #expect(calls.last?.mode == .off)
    }

    @Test @MainActor
    func digestTimePersistsImmediatelyAndOnlyReappliesDigestMode() async {
        let name = "AgentNewsHour.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var calls: [ApiSetNewsNotificationsProps] = []
        var shouldSucceed = true
        let store = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { "token" }, ensureToken: { "token" },
            apply: { calls.append($0); return shouldSucceed }
        )
        #expect(store.digestMinute == 0)
        #expect(await store.setDigestTime(hour: 8, minute: 15) == .ok)
        #expect(calls.isEmpty)
        #expect(await store.setMode(.news) == .ok)
        #expect(await store.setDigestTime(hour: 9, minute: 15) == .ok)
        #expect(calls.count == 1)
        #expect(await store.setMode(.digest) == .ok)
        #expect(await store.setDigestTime(hour: 9, minute: 45) == .ok)
        #expect(await store.reapplyIfNeeded() == .ok)
        let reopened = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { "token" }, apply: { calls.append($0); return true }
        )
        #expect(reopened.digestMinute == 45)
        #expect(await reopened.reapplyIfNeeded() == .ok)
        #expect(calls.count == 3)
        #expect(await store.setDigestTime(hour: 9, minute: 20) == .failed)
        shouldSucceed = false
        #expect(await store.setDigestTime(hour: 10, minute: 30) == .failed)
        #expect(store.digestHour == 10)
        #expect(store.digestMinute == 30)
        let restored = AgentNewsNotificationSettings(userDefaults: defaults)
        #expect(restored.digestHour == 10)
        #expect(restored.digestMinute == 30)
        #expect(calls.map(\.digestHour) == [8, 9, 9, 10])
        #expect(calls.map(\.digestMinute) == [15, 15, 45, 30])
    }

    @Test @MainActor
    func stateSavedWithoutTheDigestMinuteKeepsItsSubscriptionAtMinuteZero() async throws {
        let name = "AgentNewsLegacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"""
        {"mode":"digest","digestHour":9,"newsFeedView":"digests","applied":{"mode":"digest","userToken":"token",\#
        "langCode":"en","digestHour":9,"timeZone":"Europe/Moscow"}}
        """#.utf8), forKey: "agent-mypulse-notifications")
        var calls: [ApiSetNewsNotificationsProps] = []
        let store = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { "token" }, language: { "en" }, timeZone: { "Europe/Moscow" },
            apply: { calls.append($0); return true }
        )
        #expect(store.mode == .digest)
        #expect(store.digestHour == 9)
        #expect(store.digestMinute == 0)
        #expect(store.newsFeedView == .digests)
        #expect(await store.reapplyIfNeeded() == .ok)
        #expect(calls.isEmpty)
        #expect(await store.setDigestTime(hour: 9, minute: 15) == .ok)
        #expect(calls.map(\.digestMinute) == [15])
    }

    @Test @MainActor
    func subscriptionsReapplyChangedDeviceParametersAndResetToOff() async {
        let name = "AgentNewsReapply.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var token = "token-1"
        var language = "en"
        var zone = "Europe/London"
        var calls: [ApiSetNewsNotificationsProps] = []
        let store = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { token }, ensureToken: { token },
            language: { language }, timeZone: { zone }, apply: { calls.append($0); return true }
        )
        #expect(await store.reapplyIfNeeded() == .ok)
        #expect(calls.isEmpty)
        #expect(await store.setMode(.digest) == .ok)
        #expect(await store.reapplyIfNeeded() == .ok)
        #expect(calls.count == 1)
        token = "token-2"
        #expect(await store.reapplyIfNeeded() == .ok)
        language = "ru"
        #expect(await store.reapplyIfNeeded() == .ok)
        zone = "Europe/Moscow"
        #expect(await store.reapplyIfNeeded() == .ok)
        #expect(calls.count == 4)
        #expect(calls.last?.userToken == token)
        #expect(calls.last?.langCode == language)
        #expect(calls.last?.timeZone == zone)
        let restored = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { token }, language: { language }, timeZone: { zone },
            apply: { calls.append($0); return true }
        )
        #expect(await restored.reapplyIfNeeded() == .ok)
        #expect(calls.count == 4)
        #expect(await restored.reset().value == .ok)
        #expect(restored.mode == .off)
        #expect(calls.last?.mode == .off)
        token = "token-3"
        #expect(await restored.reapplyIfNeeded() == .ok)
        #expect(calls.count == 5)
    }

    @Test @MainActor
    func resetPersistsOffBeforePendingRequestsAndRetriesAfterFailedDelivery() async {
        let name = "AgentNewsReset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let started = AsyncStream<Void>.makeStream()
        var pendingRequest: CheckedContinuation<Bool, Never>?
        var modes: [AgentNewsNotificationSettings.Mode] = []
        let store = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { "token" }, ensureToken: { "token" },
            apply: { props in
                modes.append(props.mode)
                if props.mode == .news {
                    return await withCheckedContinuation {
                        pendingRequest = $0
                        started.continuation.yield(())
                    }
                }
                return props.mode == .digest
            }
        )
        #expect(await store.setMode(.digest) == .ok)
        let pendingMode = Task { await store.setMode(.news) }
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()
        let reset = store.reset()
        #expect(store.mode == .off)
        #expect(AgentNewsNotificationSettings(userDefaults: defaults).mode == .off)
        pendingRequest?.resume(returning: true)
        #expect(await pendingMode.value == .failed)
        #expect(await reset.value == .failed)
        #expect(store.mode == .off)
        #expect(modes == [.digest, .news, .off])
        let restored = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { "token" },
            apply: { modes.append($0.mode); return true }
        )
        #expect(await restored.reapplyIfNeeded() == .ok)
        #expect(await restored.reapplyIfNeeded() == .ok)
        #expect(modes == [.digest, .news, .off, .off])
    }

    @Test @MainActor
    func resetTimeoutAllowsRestartWithoutWalletsToRetryOff() async {
        let name = "AgentNewsResetTimeout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let started = AsyncStream<Void>.makeStream()
        var pendingOff: CheckedContinuation<Bool, Never>?
        var modes: [AgentNewsNotificationSettings.Mode] = []
        let store = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { "token" }, ensureToken: { "token" },
            apply: { props in
                modes.append(props.mode)
                if props.mode == .off {
                    return await withCheckedContinuation {
                        pendingOff = $0
                        started.continuation.yield(())
                    }
                }
                return true
            }
        )
        defer { pendingOff?.resume(returning: false) }
        #expect(await store.setMode(.digest) == .ok)
        let reset = store.reset()
        var startedIterator = started.stream.makeAsyncIterator()
        await startedIterator.next()
        #expect(await store.waitForReset(reset, timeout: .milliseconds(30)) == .failed)
        #expect(pendingOff != nil)
        #expect(store.mode == .off)
        #expect(AccountStore.accountsById.isEmpty)
        let retried = AsyncStream<Void>.makeStream()
        let restarted = AgentNewsNotificationSettings(
            userDefaults: defaults, getToken: { "token" },
            apply: { props in
                modes.append(props.mode)
                retried.continuation.yield(())
                return true
            }
        )
        restarted.start()
        defer { restarted.stop() }
        var retryIterator = retried.stream.makeAsyncIterator()
        await retryIterator.next()
        #expect(await restarted.reapplyIfNeeded() == .ok)
        #expect(modes == [.digest, .off, .off])
        pendingOff?.resume(returning: false)
        pendingOff = nil
        #expect(await reset.value == .failed)
    }

}
