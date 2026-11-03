package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonDataException
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.adapters.PolymorphicJsonAdapterFactory
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Availability
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedPage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ProblemReportResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunActivityEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadCreateResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDeleteResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadUpdate
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2UserQuota
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class AgentV2ContractTest {
    private val moshi = Moshi.Builder()
        .add(
            PolymorphicJsonAdapterFactory.of(ApiUpdate::class.java, "type")
                .withSubtype(ApiUpdate.ApiUpdateAgentV2::class.java, "agentV2")
        )
        .addAgentV2Adapters()
        .addLast(KotlinJsonAdapterFactory())
        .build()
    private val adapter = moshi.adapter(ApiUpdate::class.java)

    @Test
    fun decodesDappResolvedAction() {
        val resultAdapter = moshi.adapter(AgentV2ResolvedAction::class.java)
        val decoded = resultAdapter.fromJson(
            """{"kind":"openDapp","url":"https://app.ston.fi/"}"""
        )

        assertEquals(AgentV2ResolvedAction.OpenDapp("https://app.ston.fi/"), decoded)
    }

    @Test
    fun decodesTheReasonAnActionDoesNotOpen() {
        val actionAdapter = moshi.adapter(AgentV2ResolvedAction::class.java)

        assertEquals(
            AgentV2ResolvedAction.Inactive("viewOnlyWallet"),
            actionAdapter.fromJson("""{"kind":"inactive","reason":"viewOnlyWallet"}""")
        )
        assertEquals(
            AgentV2ResolvedAction.Inactive(),
            actionAdapter.fromJson("""{"kind":"inactive"}""")
        )
    }

    @Test
    fun decodesPartialSwapWithoutInventingSourceOrAmount() {
        val actionAdapter = moshi.adapter(AgentV2ResolvedAction::class.java)
        val decoded = actionAdapter.fromJson("""{"kind":"openSwap","tokenOutSlug":"trx"}""")

        assertEquals(AgentV2ResolvedAction.OpenSwap(tokenOutSlug = "trx"), decoded)
    }

    @Test
    fun decodesSendFormAskingForTheMaximumOnlyWhenItSaysSo() {
        val actionAdapter = moshi.adapter(AgentV2ResolvedAction::class.java)
        val url = "mtw://send/ton:UQ-recipient?token=toncoin"

        assertEquals(
            AgentV2ResolvedAction.SendForm(url, isMaxAmount = true),
            actionAdapter.fromJson("""{"kind":"sendForm","url":"$url","isMaxAmount":true}""")
        )
        assertEquals(
            AgentV2ResolvedAction.SendForm(url),
            actionAdapter.fromJson("""{"kind":"sendForm","url":"$url"}""")
        )
    }

    @Test
    fun decodesThreadCreationErrorsThroughTheActualApiMethod() {
        val resultAdapter = moshi.adapter<AgentV2MutationResult<AgentV2ThreadCreateResponse>>(
            ApiMethod.AgentV2.CreateThread().type
        )
        val decoded = resultAdapter.fromJson(
            """{"ok":false,"error":{"code":"invalid_event","retryable":false}}"""
        )!!
        assertFalse(decoded.ok)
        assertNull(decoded.value)
        assertEquals("invalid_event", decoded.error?.code)
        assertEquals(false, decoded.error?.retryable)
    }

    @Test
    fun serializesThreadPaginationSearchAndEmptyCreationArgumentsForTheSdk() {
        val argumentMoshi = MoshiBuilder.build()
        val list = ApiMethod.AgentV2.ListThreads("page", 20, "a\"b\n", argumentMoshi)

        assertEquals("listAgentV2Threads", list.name)
        assertEquals(
            """[{"cursor":"page","limit":20,"query":"a\"b\n"}]""",
            list.arguments
        )
        assertEquals(
            "[{}]",
            ApiMethod.AgentV2.ListThreads(null, null, null, argumentMoshi).arguments
        )
        assertEquals("createAgentV2Thread", ApiMethod.AgentV2.CreateThread().name)
        assertEquals("[]", ApiMethod.AgentV2.CreateThread().arguments)
    }

    @Test
    fun serializesNewsFeedLanguagePaginationAndThreadNewsForTheSdk() {
        val argumentMoshi = MoshiBuilder.build()
        val firstPage = ApiMethod.AgentV2.GetNewsFeed("ru-RU", null, argumentMoshi)

        assertEquals("getAgentV2NewsFeed", firstPage.name)
        assertEquals("""[{"lang":"ru-RU"}]""", firstPage.arguments)
        assertEquals(
            """[{"lang":"en","cursor":"next-page"}]""",
            ApiMethod.AgentV2.GetNewsFeed("en", "next-page", argumentMoshi).arguments
        )
        assertEquals(
            """[{"news":{"eventId":42,"locale":"ru"}}]""",
            ApiMethod.AgentV2.CreateThread(
                AgentV2ThreadNewsRequest(42, "ru"),
                argumentMoshi
            ).arguments
        )
    }

    @Test
    fun decodesNewsFeedWithoutProtocolVersionAndIgnoresUnknownFields() {
        val resultAdapter = moshi.adapter<AgentV2MutationResult<AgentV2NewsFeedPage>>(
            ApiMethod.AgentV2.GetNewsFeed("ru").type
        )
        val decoded = resultAdapter.fromJson(
            """
            {
              "ok":true,
              "value":{
                "locale":"ru",
                "items":[
                  {
                    "eventId":42,"deliveredAt":"2026-10-20T12:00:00Z",
                    "headline":"Market news","body":"A **bold** update",
                    "imageUrl":"https://example.com/news.jpg",
                    "sources":[{"name":"Source","url":"https://example.com/news","future":true}],
                    "discussion":{"threadId":"thread","icon":"🪙","future":true},
                    "future":{"field":true}
                  },
                  {
                    "eventId":41,"deliveredAt":"2026-10-19T12:00:00Z",
                    "headline":"Previous news","body":"An update","sources":[{"url":"https://example.com/previous"}]
                  }
                ],
                "nextCursor":"older-page",
                "future":true
              },
              "future":true
            }
            """.trimIndent()
        )!!

        assertTrue(decoded.ok)
        assertEquals(
            AgentV2NewsFeedPage(
                locale = "ru",
                items = listOf(
                    AgentV2NewsFeedItem(
                        42,
                        "2026-10-20T12:00:00Z",
                        "Market news",
                        "A **bold** update",
                        imageUrl = "https://example.com/news.jpg",
                        sources = listOf(
                            AgentV2NewsFeedItem.Source("Source", "https://example.com/news")
                        ),
                        discussion = AgentV2NewsFeedItem.Discussion("thread", "🪙")
                    ),
                    AgentV2NewsFeedItem(
                        41,
                        "2026-10-19T12:00:00Z",
                        "Previous news",
                        "An update",
                        sources = listOf(
                            AgentV2NewsFeedItem.Source(url = "https://example.com/previous")
                        )
                    )
                ),
                nextCursor = "older-page"
            ),
            decoded.value
        )
        val unavailable = resultAdapter.fromJson(
            """{"ok":false,"error":{"code":"news_unavailable","retryable":true}}"""
        )!!
        assertFalse(unavailable.ok)
        assertEquals("news_unavailable", unavailable.error?.code)
        assertEquals(true, unavailable.error?.retryable)
    }

    @Test
    fun serializesRenameResetAndUnpinAsDistinctThreadUpdates() {
        val argumentMoshi = MoshiBuilder.build()
        val rename = ApiMethod.AgentV2.UpdateThread(
            "thread",
            AgentV2ThreadUpdate(title = "My \"chat\""),
            argumentMoshi
        )

        assertEquals("updateAgentV2Thread", rename.name)
        assertEquals("""["thread",{"title":"My \"chat\""}]""", rename.arguments)
        assertEquals(
            """["thread",{"title":null}]""",
            ApiMethod.AgentV2.UpdateThread(
                "thread",
                AgentV2ThreadUpdate(title = null),
                argumentMoshi
            ).arguments
        )
        assertEquals(
            """["thread",{"isPinned":false}]""",
            ApiMethod.AgentV2.UpdateThread(
                "thread",
                AgentV2ThreadUpdate(isPinned = false),
                argumentMoshi
            ).arguments
        )
        assertEquals(
            """["thread",{"title":null,"isPinned":true}]""",
            ApiMethod.AgentV2.UpdateThread(
                "thread",
                AgentV2ThreadUpdate(title = null, isPinned = true),
                argumentMoshi
            ).arguments
        )
        val delete = ApiMethod.AgentV2.DeleteThread("a\"b", argumentMoshi)
        assertEquals("deleteAgentV2Thread", delete.name)
        assertEquals("""["a\"b"]""", delete.arguments)
    }

    @Test
    fun decodesThreadListMetadataPreviewAndPaginationThroughTheActualApiMethod() {
        val resultAdapter = moshi.adapter<AgentV2MutationResult<AgentV2ThreadListResponse>>(
            ApiMethod.AgentV2.ListThreads().type
        )
        val decoded = resultAdapter.fromJson(
            """
            {
              "ok":true,
              "value":{
                "protocolVersion":3,
                "threads":[
                  {
                    "thread":{
                      "id":"pinned","revision":4,"createdAt":"2026-10-18T12:00:00Z",
                      "updatedAt":"2026-10-19T12:00:00Z","lastActivityAt":"2026-10-19T12:00:00Z",
                      "clearedAt":"2026-10-18T13:00:00Z","messageCount":2,
                      "title":"My chat","icon":"🪙","hasCustomTitle":true,"isPinned":true,
                      "news":{
                        "eventId":42,"headline":"Market news","excerpt":"A short update",
                        "imageUrl":"https://example.com/news.jpg","publishedAt":"2026-10-19T12:00:00Z",
                        "source":"Source","body":"A **complete** update",
                        "sources":[{"url":"https://example.com/news","name":"Source"}],"future":true
                      }
                    },
                    "preview":"A useful answer"
                  },
                  {
                    "thread":{
                      "id":"new","revision":0,"createdAt":"2026-10-19T13:00:00Z",
                      "updatedAt":"2026-10-19T13:00:00Z","lastActivityAt":"2026-10-19T13:00:00Z",
                      "messageCount":0
                    }
                  }
                ],
                "nextCursor":"next-page"
              }
            }
            """.trimIndent()
        )!!
        val response = decoded.value!!
        val pinned = response.threads[0]
        val empty = response.threads[1]

        assertTrue(decoded.ok)
        assertEquals("next-page", response.nextCursor)
        assertEquals("A useful answer", pinned.preview)
        assertEquals(
            AgentV2ThreadSummary(
                "pinned",
                4,
                createdAt = "2026-10-18T12:00:00Z",
                updatedAt = "2026-10-19T12:00:00Z",
                lastActivityAt = "2026-10-19T12:00:00Z",
                clearedAt = "2026-10-18T13:00:00Z",
                messageCount = 2,
                title = "My chat",
                icon = "🪙",
                hasCustomTitle = true,
                isPinned = true,
                news = AgentV2ThreadNewsCard(
                    42,
                    "Market news",
                    excerpt = "A short update",
                    imageUrl = "https://example.com/news.jpg",
                    publishedAt = "2026-10-19T12:00:00Z",
                    source = "Source",
                    body = "A **complete** update",
                    sources = listOf(
                        AgentV2NewsFeedItem.Source("Source", "https://example.com/news")
                    )
                )
            ),
            pinned.thread
        )
        assertNull(empty.preview)
        assertNull(empty.thread.title)
        assertNull(empty.thread.icon)
        assertNull(empty.thread.hasCustomTitle)
        assertNull(empty.thread.isPinned)
        assertNull(empty.thread.clearedAt)
        assertNull(
            resultAdapter.fromJson("""{"ok":true,"value":{"threads":[]}}""")
                ?.value?.nextCursor
        )
    }

    @Test
    fun decodesNewsPostHistoryAndMissingOptionalNewsMetadata() {
        val resultAdapter = moshi.adapter<AgentV2MutationResult<AgentV2ThreadHydration>>(
            Types.newParameterizedType(
                AgentV2MutationResult::class.java,
                AgentV2ThreadHydration::class.java
            )
        )
        val history = resultAdapter.fromJson(
            """
            {
              "ok":true,
              "value":{
                "thread":{
                  "id":"thread","revision":1,"messageCount":2,
                  "news":{"eventId":42,"headline":"Market news","publishedAt":"2026-10-20T12:00:00Z"}
                },
                "messages":[
                  {
                    "id":"post","threadId":"thread","role":"assistant","status":"completed",
                    "createdAt":"2026-10-20T12:00:00Z","newsPost":true,
                    "content":{"kind":"markdown","text":"**Market news**\n\nA **complete** update"},
                    "followups":[{"id":"news-followup","kind":"suggested_prompt","text":"What does this mean?"}]
                  },
                  {
                    "id":"question","threadId":"thread","role":"user","status":"completed",
                    "createdAt":"2026-10-20T12:00:01Z",
                    "content":{"kind":"markdown","text":"What does this mean?"}
                  }
                ]
              }
            }
            """.trimIndent()
        )!!.value!!

        assertEquals(2, history.thread.messageCount)
        assertNull(history.thread.news?.body)
        assertNull(history.thread.news?.sources)
        assertEquals(true, history.messages[0].newsPost)
        assertEquals("assistant", history.messages[0].role)
        assertEquals(
            listOf(AgentV2FollowUp("news-followup", "suggested_prompt", "What does this mean?")),
            history.messages[0].followups
        )
        assertEquals(
            AgentV2MessageContent.Markdown("**Market news**\n\nA **complete** update"),
            history.messages[0].content
        )
        assertNull(history.messages[1].newsPost)
    }

    @Test
    fun decodesCreateUpdateAndDeleteResultsThroughTheirActualApiMethods() {
        val createAdapter = moshi.adapter<AgentV2MutationResult<AgentV2ThreadCreateResponse>>(
            ApiMethod.AgentV2.CreateThread().type
        )
        for (isCreated in listOf(true, false)) {
            val created = createAdapter.fromJson(
                """{"ok":true,"value":{"protocolVersion":3,"thread":{"id":"empty","revision":0},"created":$isCreated}}"""
            )!!
            assertEquals(
                AgentV2ThreadCreateResponse(AgentV2ThreadSummary("empty", 0), isCreated),
                created.value
            )
        }
        val updateAdapter = moshi.adapter<AgentV2MutationResult<AgentV2ThreadResponse>>(
            ApiMethod.AgentV2.UpdateThread("thread", AgentV2ThreadUpdate(title = null)).type
        )
        val updated = updateAdapter.fromJson(
            """{"ok":true,"value":{"protocolVersion":3,"thread":{"id":"thread","revision":5,"title":"Agent title","icon":"🪙"}}}"""
        )!!
        assertEquals("Agent title", updated.value?.thread?.title)
        assertNull(updated.value?.thread?.hasCustomTitle)
        assertNull(updated.value?.thread?.isPinned)

        val deleteAdapter = moshi.adapter<AgentV2MutationResult<AgentV2ThreadDeleteResponse>>(
            ApiMethod.AgentV2.DeleteThread("thread").type
        )
        assertEquals(
            AgentV2ThreadDeleteResponse("thread", duplicate = true),
            deleteAdapter.fromJson(
                """{"ok":true,"value":{"protocolVersion":3,"threadId":"thread","duplicate":true}}"""
            )?.value
        )
        for (method in listOf(
            ApiMethod.AgentV2.ListThreads(),
            ApiMethod.AgentV2.CreateThread(),
            ApiMethod.AgentV2.UpdateThread("thread", AgentV2ThreadUpdate(isPinned = true)),
            ApiMethod.AgentV2.DeleteThread("thread")
        )) {
            val failure = moshi.adapter<AgentV2MutationResult<*>>(method.type).fromJson(
                """{"ok":false,"error":{"code":"thread_not_found","retryable":false}}"""
            )!!
            assertFalse(failure.ok)
            assertNull(failure.value)
            assertEquals("thread_not_found", failure.error?.code)
        }
    }

    @Test
    fun decodesThreadChangedPresentationMetadata() {
        val decoded = adapter.fromJson(
            """
            {
              "type":"agentV2",
              "update":{
                "kind":"threadChanged","threadId":"thread",
                "thread":{"id":"thread","revision":2,"title":"Agent title","icon":"🪙","isPinned":true}
              }
            }
            """.trimIndent()
        ) as ApiUpdate.ApiUpdateAgentV2

        assertEquals(
            AgentV2Update.ThreadChanged(
                "thread",
                AgentV2ThreadSummary(
                    "thread",
                    2,
                    title = "Agent title",
                    icon = "🪙",
                    isPinned = true
                )
            ),
            decoded.update
        )
    }

    @Test
    fun decodesProblemReportResults() {
        val resultAdapter = moshi.adapter<AgentV2MutationResult<AgentV2ProblemReportResponse>>(
            Types.newParameterizedType(
                AgentV2MutationResult::class.java,
                AgentV2ProblemReportResponse::class.java
            )
        )
        val decoded = resultAdapter.fromJson(
            """
            {
              "ok": true,
              "value": {"protocolVersion":3,"reportId":"report","duplicate":true}
            }
            """.trimIndent()
        )!!

        assertEquals(AgentV2ProblemReportResponse("report", duplicate = true), decoded.value)
    }

    @Test
    fun serializesTranscriptionArgumentsForTheSdk() {
        val request = AgentV2TranscriptionRequest(audio = "YWJj+/==", lang = "ru")
        val argumentMoshi = MoshiBuilder.build()
        val method = ApiMethod.AgentV2.Transcribe(request, argumentMoshi)

        assertEquals("transcribeAgentV2Audio", method.name)
        assertEquals(
            """[{"audio":"YWJj+/==","format":"m4a","lang":"ru"}]""",
            method.arguments
        )
        assertEquals(
            """[{"audio":"YWJj+/==","format":"m4a"}]""",
            ApiMethod.AgentV2.Transcribe(request.copy(lang = null), argumentMoshi).arguments
        )
    }

    @Test
    fun decodesTranscriptionOutcomesThroughTheActualApiMethod() {
        val resultAdapter = moshi.adapter<AgentV2MutationResult<AgentV2TranscriptionResponse>>(
            ApiMethod.AgentV2.Transcribe(AgentV2TranscriptionRequest(audio = "YWJj")).type
        )

        assertEquals(
            AgentV2TranscriptionResponse(outcome = "transcribed", text = "Send ten TON"),
            resultAdapter.fromJson(
                """{"ok":true,"value":{"protocolVersion":3,"outcome":"transcribed","text":"Send ten TON"}}"""
            )?.value
        )
        assertEquals(
            AgentV2TranscriptionResponse(outcome = "no_speech"),
            resultAdapter.fromJson(
                """{"ok":true,"value":{"protocolVersion":3,"outcome":"no_speech"}}"""
            )?.value
        )
    }

    @Test
    fun decodesTheSdkRuntimeStart() {
        val decoded = adapter.fromJson(
            """{"type":"agentV2","update":{"kind":"runtimeReady","generation":3}}"""
        ) as ApiUpdate.ApiUpdateAgentV2

        assertEquals(AgentV2Update.RuntimeReady(generation = 3), decoded.update)
    }

    @Test
    fun decodesAnswerLinksFromLiveUpdatesAndHistory() {
        val link =
            AgentV2AnswerLink(textOffset = 4, textLength = 4, url = "https://help.mywallet.io/")
        val update = adapter.fromJson(
            "{\"type\":\"agentV2\",\"update\":{\"kind\":\"answerLinkAdded\"," +
                "\"clientRunId\":\"c\",\"runId\":\"r\",\"threadId\":\"t\",\"messageId\":\"m\"," +
                "\"link\":" +
                "{\"textOffset\":4,\"textLength\":4,\"url\":\"https://help.mywallet.io/\"}}}"
        ) as ApiUpdate.ApiUpdateAgentV2
        val content = moshi.adapter(AgentV2MessageContent::class.java).fromJson(
            "{\"kind\":\"markdown\",\"text\":\"See Help\",\"links\":" +
                "[{\"textOffset\":4,\"textLength\":4,\"url\":\"https://help.mywallet.io/\"}]}"
        )

        assertEquals(AgentV2Update.AnswerLinkAdded("c", "r", "t", "m", link), update.update)
        assertEquals(AgentV2MessageContent.Markdown("See Help", links = listOf(link)), content)
    }

    @Test
    fun decodesBoundFollowupsAndContentEndUpdates() {
        val followup = AgentV2FollowUp("followup", "suggested_prompt", "How does staking work?")
        val followups = adapter.fromJson(
            """
            {
              "type": "agentV2",
              "update": {
                "kind": "followupsAvailable",
                "clientRunId": "client-run",
                "runId": "run",
                "threadId": "thread",
                "messageId": "message",
                "items": [{"id":"followup","kind":"suggested_prompt","text":"How does staking work?"}]
              }
            }
            """.trimIndent()
        ) as ApiUpdate.ApiUpdateAgentV2
        val contentEnd = adapter.fromJson(
            """
            {
              "type": "agentV2",
              "update": {
                "kind": "messageContentEnded",
                "clientRunId": "client-run",
                "runId": "run",
                "threadId": "thread",
                "messageId": "message"
              }
            }
            """.trimIndent()
        ) as ApiUpdate.ApiUpdateAgentV2

        assertEquals(
            AgentV2Update.FollowupsAvailable(
                "client-run",
                "run",
                "thread",
                "message",
                listOf(followup)
            ),
            followups.update
        )
        assertEquals(
            AgentV2Update.MessageContentEnded("client-run", "run", "thread", "message"),
            contentEnd.update
        )
    }

    @Test
    fun decodesOptionalHistoryFollowups() {
        val historyAdapter = moshi.adapter(AgentV2ThreadHydration::class.java)
        val followup = AgentV2FollowUp("followup", "suggested_prompt", "How does staking work?")
        val history = historyAdapter.fromJson(
            """
            {
              "thread": {"id":"thread","revision":2},
              "messages": [
                {
                  "id":"old-message","threadId":"thread","role":"assistant",
                  "status":"completed","createdAt":"2026-10-05T12:00:00Z"
                },
                {
                  "id":"message","threadId":"thread","role":"assistant",
                  "status":"completed","createdAt":"2026-10-05T12:00:01Z",
                  "followups":[{"id":"followup","kind":"suggested_prompt","text":"How does staking work?"}]
                },
                {
                  "id":"empty-message","threadId":"thread","role":"assistant",
                  "status":"completed","createdAt":"2026-10-05T12:00:02Z",
                  "followups":[]
                }
              ]
            }
            """.trimIndent()
        )!!
        val messages = history.messages

        assertNull(messages[0].followups)
        assertEquals(listOf(followup), messages[1].followups)
        assertEquals(emptyList<AgentV2FollowUp>(), messages[2].followups)
    }

    @Test
    fun decodesRunProgressAndFailureDetails() {
        val activity = adapter.fromJson(
            """
            {
              "type":"agentV2",
              "update":{
                "kind":"runActivityChanged","clientRunId":"c","runId":"r","threadId":"t",
                "event":{
                  "type":"run_activity","protocolVersion":3,"runId":"r","sequence":4,
                  "code":"web.reading_sources","status":"completed",
                  "detail":{"kind":"source_count","count":3}
                }
              }
            }
            """.trimIndent()
        ) as ApiUpdate.ApiUpdateAgentV2
        val tool = adapter.fromJson(
            """
            {
              "type":"agentV2",
              "update":{
                "kind":"toolActivityChanged","clientRunId":"c","runId":"r","threadId":"t",
                "toolCallId":"call","toolName":"wallet.data.query",
                "operation":"portfolio.aggregate","status":"running"
              }
            }
            """.trimIndent()
        ) as ApiUpdate.ApiUpdateAgentV2
        val failure = adapter.fromJson(
            """
            {
              "type":"agentV2",
              "update":{
                "kind":"runFailed","clientRunId":"c","runId":"r","threadId":"t",
                "code":"user_quota_exceeded","retryable":true,"messageId":"m",
                "resetAt":1761436800000
              }
            }
            """.trimIndent()
        ) as ApiUpdate.ApiUpdateAgentV2

        assertEquals(
            AgentV2Update.RunActivityChanged(
                "c",
                "r",
                "t",
                AgentV2RunActivityEvent(
                    runId = "r",
                    sequence = 4,
                    code = "web.reading_sources",
                    status = "completed",
                    detail = AgentV2RunActivityEvent.Detail("source_count", 3)
                )
            ),
            activity.update
        )
        assertEquals(
            AgentV2Update.ToolActivityChanged(
                "c",
                "r",
                "t",
                toolCallId = "call",
                toolName = "wallet.data.query",
                operation = "portfolio.aggregate",
                status = "running"
            ),
            tool.update
        )
        assertEquals(
            AgentV2Update.RunFailed(
                "c",
                "r",
                "t",
                code = "user_quota_exceeded",
                retryable = true,
                messageId = "m",
                resetAt = 1_761_436_800_000
            ),
            failure.update
        )
    }

    @Test
    fun decodesLimitsAndWalletContextUpdates() {
        fun decode(json: String): AgentV2Update? {
            val update = adapter.fromJson("""{"type":"agentV2","update":$json}""")
            return (update as ApiUpdate.ApiUpdateAgentV2).update
        }

        assertEquals(
            AgentV2Update.AvailabilityChanged(
                AgentV2Availability("capacity_exhausted", resetAt = 1_761_436_800_000)
            ),
            decode(
                """
                {"kind":"availabilityChanged",
                 "availability":{"state":"capacity_exhausted","resetAt":1761436800000}}
                """.trimIndent()
            )
        )
        assertEquals(
            AgentV2Update.AvailabilityChanged(AgentV2Availability("available")),
            decode("""{"kind":"availabilityChanged","availability":{"state":"available"}}""")
        )
        assertEquals(
            AgentV2Update.UserQuotaChanged(
                AgentV2UserQuota(
                    limit = 30,
                    used = 30,
                    remaining = 0,
                    resetAt = "2026-10-26T00:00:00Z"
                )
            ),
            decode(
                """
                {"kind":"userQuotaChanged","quota":
                  {"limit":30,"used":30,"remaining":0,"resetAt":"2026-10-26T00:00:00Z"}}
                """.trimIndent()
            )
        )
        assertEquals(
            AgentV2Update.UserQuotaChanged(),
            decode("""{"kind":"userQuotaChanged"}""")
        )
        assertEquals(
            AgentV2Update.WalletAuthorityChanged(preservesActiveRuns = true),
            decode("""{"kind":"walletAuthorityChanged","preservesActiveRuns":true}""")
        )
        assertEquals(
            AgentV2Update.WalletAuthorityChanged(threadId = "t"),
            decode("""{"kind":"walletAuthorityChanged","threadId":"t"}""")
        )
        assertEquals(
            AgentV2Update.WalletContextChanged(),
            decode("""{"kind":"walletContextChanged"}""")
        )
    }

    @Test
    fun ignoresUnknownAgentUpdateKind() {
        val decoded = adapter.fromJson(
            """{"type":"agentV2","update":{"kind":"futureUpdate"}}"""
        ) as ApiUpdate.ApiUpdateAgentV2

        assertNull(decoded.update)
    }

    @Test
    fun rejectsMalformedKnownAgentUpdate() {
        assertThrows(JsonDataException::class.java) {
            adapter.fromJson(
                """
                {
                  "type": "agentV2",
                  "update": {
                    "kind": "textDelta",
                    "clientRunId": "client-run",
                    "runId": "run",
                    "threadId": "thread",
                    "messageId": "message"
                  }
                }
                """.trimIndent()
            )
        }
    }

    @Test
    fun rejectsFollowupAndContentEndUpdatesWithoutMessageBinding() {
        for ((kind, fields) in listOf(
            "followupsAvailable" to ",\"items\":[]",
            "messageContentEnded" to ""
        )) {
            assertThrows(JsonDataException::class.java) {
                adapter.fromJson(
                    """
                    {
                      "type":"agentV2",
                      "update":{
                        "kind":"$kind","clientRunId":"client-run",
                        "runId":"run","threadId":"thread"$fields
                      }
                    }
                    """.trimIndent()
                )
            }
        }
    }
}
