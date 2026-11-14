package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonDataException
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.adapters.PolymorphicJsonAdapterFactory
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.api.readAgentV2Cache
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Availability
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedPage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2OperatorAuthor
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ProblemReportResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunActivityEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2SupportRequestSource
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadCreateResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDeleteResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSupport
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadUpdate
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2UserQuota
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.parseBridgeResult
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsFeedView
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationMode
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationOutcome
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationSettings
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationState
import org.mytonwallet.app_air.walletcore.pushNotifications.NewsNotificationPermissionDenied

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
    fun cachedThreadReadsDecodeTheSdkCacheAndTurnEveryFailureIntoNull() = runBlocking {
        val threads = ApiMethod.AgentV2.GetCachedThreads()
        val messages = ApiMethod.AgentV2.GetCachedMessages("thread", MoshiBuilder.build())
        val thread = """{"id":"thread","revision":2,"messageCount":1,"isPinned":true}"""

        assertEquals("getAgentV2CachedThreads", threads.name)
        assertEquals("[]", threads.arguments)
        assertEquals("getAgentV2CachedMessages", messages.name)
        assertEquals("""["thread"]""", messages.arguments)
        assertEquals(
            listOf(
                AgentV2ThreadListItem(
                    AgentV2ThreadSummary("thread", 2, messageCount = 1, isPinned = true),
                    "You hold 5 TON."
                )
            ),
            readCache(threads, """[{"thread":$thread,"preview":"You hold 5 TON."}]""")
        )
        val cached = readCache(
            messages,
            """
            {
              "thread":$thread,
              "messages":[{
                "id":"question","threadId":"thread","role":"user","status":"complete",
                "createdAt":"2026-10-20T12:00:01Z",
                "content":{"kind":"markdown","text":"Cached question"}
              }],
              "hasOlder":true
            }
            """.trimIndent()
        )!!
        assertEquals("thread", cached.thread.id)
        assertEquals(listOf("question"), cached.messages.map { it.id })
        assertTrue(cached.hasOlder)

        for (raw in listOf("undefined", """{"thread":""", """{"thread":$thread}""")) {
            assertNull(readCache(threads, raw))
            assertNull(readCache(messages, raw))
        }
    }

    private suspend fun <T> readCache(method: ApiMethod<T?>, raw: String) = readAgentV2Cache {
        parseBridgeResult<T?>(method.name, raw, method.type, moshi)
    }

    @Test
    fun serializesNewsFeedLanguagePaginationAndThreadNewsForTheSdk() {
        val argumentMoshi = MoshiBuilder.build()
        val firstPage = ApiMethod.AgentV2.GetNewsFeed(
            AgentV2NewsFeedRequest("ru-RU"),
            argumentMoshi
        )

        assertEquals("getAgentV2NewsFeed", firstPage.name)
        assertEquals("""[{"lang":"ru-RU"}]""", firstPage.arguments)
        assertEquals(
            """[{"lang":"en","cursor":"next-page"}]""",
            ApiMethod.AgentV2.GetNewsFeed(
                AgentV2NewsFeedRequest("en", "next-page"),
                argumentMoshi
            ).arguments
        )
        assertEquals(
            """[{"news":{"eventId":42,"locale":"ru"}}]""",
            ApiMethod.AgentV2.CreateThread(
                AgentV2ThreadNewsRequest(42, "ru"),
                null,
                argumentMoshi
            ).arguments
        )
    }

    @Test
    fun serializesDigestSchedulingCreationAndPushSettingsForTheSdk() {
        val argumentMoshi = MoshiBuilder.build()
        assertEquals(
            """[{"lang":"en","cursor":"older","digestHour":21,"digestMinute":45,"timeZone":"Europe/Moscow"}]""",
            ApiMethod.AgentV2.GetNewsFeed(
                AgentV2NewsFeedRequest("en", "older", 21, 45, "Europe/Moscow"),
                argumentMoshi
            ).arguments
        )
        assertEquals(
            """[{"lang":"en","cursor":"older","digestHour":21,"digestMinute":0,"timeZone":"Europe/Moscow","view":"digests"}]""",
            ApiMethod.AgentV2.GetNewsFeed(
                AgentV2NewsFeedRequest("en", "older", 21, 0, "Europe/Moscow", "digests"),
                argumentMoshi
            ).arguments
        )
        val digestId = "ru:2026-11-08T18:00:00.000Z"
        assertEquals(
            """[{"digest":{"id":"$digestId"}}]""",
            ApiMethod.AgentV2.CreateThread(
                null,
                AgentV2ThreadDigestRequest(digestId),
                argumentMoshi
            ).arguments
        )
        val method = ApiMethod.Notifications.SetNewsNotifications(
            ApiMethod.Notifications.SetNewsNotifications.Props(
                "digest",
                "push-token",
                "ru",
                21,
                45,
                "Europe/Moscow"
            ),
            argumentMoshi
        )
        assertEquals("setNewsNotifications", method.name)
        assertEquals(
            """[{"mode":"digest","userToken":"push-token","langCode":"ru","digestHour":21,""" +
                """"digestMinute":45,"timeZone":"Europe/Moscow","platform":"android"}]""",
            method.arguments
        )
    }

    @Test
    fun decodesOptionalFeedDigestsAndThreadDigestWithTheirServerPost() {
        val digestId = "ru:2026-11-08T18:00:00.000Z"
        val pageAdapter = moshi.adapter(AgentV2NewsFeedPage::class.java)
        assertNull(pageAdapter.fromJson("""{"locale":"ru","items":[]}""")!!.digests)
        val page = pageAdapter.fromJson(
            """{"locale":"ru","items":[],"digests":[{
                "id":"$digestId","deliveredAt":"2026-11-08T18:00:00.000Z","total":7,
                "top":[{"eventId":42,"headline":"Headline"},
                    {"eventId":43,"headline":"Pictured","imageUrl":"https://example.com/43.jpg"},
                    {"eventId":44,"headline":"Null picture","imageUrl":null}],
                "discussion":{"threadId":"digest-thread","icon":"📰"},
                "discussionNaming":{"title":"Daily discussion","icon":"📰","followups":["Explain the digest"],"future":true}
            }]}"""
        )!!
        val digest = page.digests!!.single()
        assertEquals(digestId, digest.id)
        assertEquals("2026-11-08T18:00:00.000Z", digest.deliveredAt)
        assertEquals(7, digest.total)
        assertEquals(listOf(42, 43, 44), digest.top.map { it.eventId })
        assertEquals("Headline", digest.top.first().headline)
        assertEquals(
            listOf(null, "https://example.com/43.jpg", null),
            digest.top.map {
                it.imageUrl
            }
        )
        assertEquals(AgentV2NewsFeedItem.Discussion("digest-thread", "📰"), digest.discussion)
        assertEquals(
            AgentV2NewsFeedItem.DiscussionNaming(
                "Daily discussion",
                "📰",
                listOf("Explain the digest")
            ),
            digest.discussionNaming
        )
        val digestAdapter = moshi.adapter(AgentV2NewsFeedDigest::class.java)
        val withoutNaming =
            """{"id":"$digestId","deliveredAt":"2026-11-08T18:00:00.000Z","total":0,"top":[]}"""
        assertNull(digestAdapter.fromJson(withoutNaming)!!.discussionNaming)
        assertEquals(
            AgentV2NewsFeedItem.DiscussionNaming("Daily discussion", null, listOf("Question")),
            digestAdapter.fromJson(
                """{"id":"$digestId","deliveredAt":"2026-11-08T18:00:00.000Z","total":0,"top":[],"discussionNaming":{"title":"Daily discussion","followups":["Question"]}}"""
            )!!.discussionNaming
        )
        assertNull(
            moshi.adapter(
                AgentV2ThreadSummary::class.java
            ).fromJson("""{"id":"old","revision":1}""")!!.digest
        )
        val hydration = moshi.adapter(AgentV2ThreadHydration::class.java).fromJson(
            """{"thread":{"id":"digest-thread","revision":1,"messageCount":1,"digest":{
                "id":"$digestId","windowEnd":"2026-11-08T18:00:00.000Z","total":7,
                "top":[{"eventId":42,"headline":"Headline"},
                    {"eventId":43,"headline":"Pictured","imageUrl":"https://example.com/43.jpg"},
                    {"eventId":44,"headline":"Null picture","imageUrl":null}]
            }},"messages":[{"id":"post","threadId":"digest-thread","role":"assistant","status":"complete",
                "createdAt":"2026-11-08T18:00:00.000Z",
                "newsPost":true,"content":{"kind":"markdown","text":"Daily digest"}
            }]}"""
        )!!
        assertEquals(digestId, hydration.thread.digest!!.id)
        assertEquals(digest.deliveredAt, hydration.thread.digest!!.windowEnd)
        assertEquals(digest.total, hydration.thread.digest!!.total)
        assertEquals(digest.top, hydration.thread.digest!!.top)
        assertEquals(true, hydration.messages.single().newsPost)
    }

    @Test
    fun newsNotificationModePersistsOnlyAfterPermissionTokenAndSuccessfulSubscription() =
        runBlocking {
            var stored: String? = null
            var token = "token"
            var language = "en"
            var zone = "Europe/London"
            var canRequest = false
            var shouldFailToken = false
            var shouldSucceed = true
            val calls = mutableListOf<ApiMethod.Notifications.SetNewsNotifications.Props>()
            val states = mutableListOf<AgentNewsNotificationState>()
            val settings = AgentNewsNotificationSettings(
                read = { stored },
                write = { stored = it },
                ensurePushToken = {
                    if (!canRequest) throw NewsNotificationPermissionDenied()
                    if (shouldFailToken) error("Token unavailable")
                    token
                },
                getToken = { token },
                language = { language },
                timeZone = { zone },
                apply = {
                    calls += it
                    shouldSucceed
                }
            )
            val observation =
                launch(start = CoroutineStart.UNDISPATCHED) {
                    settings.state.take(3).toList(states)
                }
            assertEquals(AgentNewsNotificationState(), settings.state.value)
            assertEquals(AgentNewsNotificationOutcome.Ok, settings.reapplyIfNeeded())
            assertTrue(calls.isEmpty())
            assertEquals(
                AgentNewsNotificationOutcome.PermissionDenied,
                settings.setMode(AgentNewsNotificationMode.Digest)
            )
            assertEquals(AgentNewsNotificationMode.Off, settings.mode)
            assertTrue(calls.isEmpty())
            canRequest = true
            shouldFailToken = true
            assertEquals(
                AgentNewsNotificationOutcome.Failed,
                settings.setMode(AgentNewsNotificationMode.News)
            )
            assertTrue(calls.isEmpty())
            shouldFailToken = false
            assertEquals(
                AgentNewsNotificationOutcome.Ok,
                settings.setMode(AgentNewsNotificationMode.Digest)
            )
            kotlinx.coroutines.yield()
            shouldSucceed = false
            assertEquals(
                AgentNewsNotificationOutcome.Failed,
                settings.setMode(AgentNewsNotificationMode.News)
            )
            assertEquals(AgentNewsNotificationMode.Digest, settings.mode)
            assertEquals(
                AgentNewsNotificationMode.Digest,
                AgentNewsNotificationSettings(read = { stored }, write = {}).mode
            )
            shouldSucceed = true
            assertEquals(
                AgentNewsNotificationOutcome.Ok,
                settings.setMode(AgentNewsNotificationMode.Off)
            )
            observation.join()
            assertEquals(
                listOf(
                    AgentNewsNotificationMode.Off,
                    AgentNewsNotificationMode.Digest,
                    AgentNewsNotificationMode.Off
                ),
                states.map {
                    it.mode
                }
            )
            val offCount = calls.size
            token = "next-token"
            language = "ru"
            zone = "Europe/Moscow"
            settings.setDigestTime(18, 0)
            assertEquals(AgentNewsNotificationOutcome.Ok, settings.reapplyIfNeeded())
            assertEquals(offCount, calls.size)
        }

    @Test
    fun newsNotificationPermissionWaitDoesNotBlockHourResetOrReapplication() = runBlocking {
        val calls = mutableListOf<String>()
        val settings = AgentNewsNotificationSettings(
            read = { null },
            write = {},
            ensurePushToken = { awaitCancellation() },
            getToken = { "token" },
            language = { "en" },
            timeZone = { "Etc/UTC" },
            apply = {
                calls += it.mode
                true
            }
        )
        val enabling = launch(start = CoroutineStart.UNDISPATCHED) {
            settings.setMode(AgentNewsNotificationMode.Digest)
        }
        try {
            withTimeout(1_000) {
                assertEquals(AgentNewsNotificationOutcome.Ok, settings.setDigestTime(18, 0))
                assertEquals(AgentNewsNotificationOutcome.Ok, settings.reset())
                assertEquals(AgentNewsNotificationOutcome.Ok, settings.reapplyIfNeeded())
            }
            assertTrue(enabling.isActive)
            assertEquals(18, settings.digestHour)
            assertEquals(AgentNewsNotificationMode.Off, settings.mode)
            assertEquals(listOf("off"), calls)
        } finally {
            enabling.cancelAndJoin()
        }
    }

    @Test
    fun newsNotificationResetDiscardsModePreparedBeforeReset() = runBlocking {
        val gate = CompletableDeferred<Unit>()
        val calls = mutableListOf<String>()
        val settings = AgentNewsNotificationSettings(
            read = { null },
            write = {},
            ensurePushToken = {
                gate.await()
                "token"
            },
            getToken = { "token" },
            language = { "en" },
            timeZone = { "Etc/UTC" },
            apply = {
                calls += it.mode
                true
            }
        )
        val enabling = async(start = CoroutineStart.UNDISPATCHED) {
            settings.setMode(AgentNewsNotificationMode.Digest)
        }
        try {
            withTimeout(1_000) {
                assertEquals(AgentNewsNotificationOutcome.Ok, settings.reset())
                gate.complete(Unit)
                assertEquals(AgentNewsNotificationOutcome.Failed, enabling.await())
            }
            assertEquals(AgentNewsNotificationMode.Off, settings.mode)
            assertEquals(listOf("off"), calls)
        } finally {
            enabling.cancelAndJoin()
        }
    }

    @Test
    fun newsNotificationNewerModeDiscardsPendingEnable() = runBlocking {
        for (newerMode in listOf(AgentNewsNotificationMode.Off, AgentNewsNotificationMode.News)) {
            val gate = CompletableDeferred<Unit>()
            var shouldWaitForToken = true
            val calls = mutableListOf<String>()
            var stored: String? = null
            val settings = AgentNewsNotificationSettings(
                read = { stored },
                write = { stored = it },
                ensurePushToken = {
                    if (shouldWaitForToken) {
                        shouldWaitForToken = false
                        gate.await()
                    }
                    "token"
                },
                getToken = { "token" },
                language = { "en" },
                timeZone = { "Etc/UTC" },
                apply = {
                    calls += it.mode
                    true
                }
            )
            val enabling = async(start = CoroutineStart.UNDISPATCHED) {
                settings.setMode(AgentNewsNotificationMode.Digest)
            }
            try {
                withTimeout(1_000) {
                    assertEquals(AgentNewsNotificationOutcome.Ok, settings.setMode(newerMode))
                    gate.complete(Unit)
                    assertEquals(AgentNewsNotificationOutcome.Failed, enabling.await())
                }
                assertEquals(newerMode, settings.mode)
                assertEquals(
                    newerMode,
                    AgentNewsNotificationSettings(read = {
                        stored
                    }, write = {}).mode
                )
                assertEquals(listOf(newerMode.name.lowercase()), calls)
            } finally {
                enabling.cancelAndJoin()
            }
        }
    }

    @Test
    fun newsViewPersistsBesideDigestHourAndFallsBackToAll() = runBlocking {
        var stored: String? = null
        fun restore() = AgentNewsNotificationSettings(read = { stored }, write = { stored = it })
        val settings = restore()
        assertEquals(AgentNewsFeedView.All, settings.newsView)
        val changes = mutableListOf<AgentNewsNotificationState>()
        val observer = launch(start = CoroutineStart.UNDISPATCHED) {
            settings.state.take(2).toList(changes)
        }
        settings.setNewsView(AgentNewsFeedView.Digests)
        observer.join()
        assertEquals("digests", changes.last().newsView)
        settings.setDigestTime(9, 0)
        assertEquals(AgentNewsFeedView.Digests, restore().newsView)
        assertEquals(9, restore().digestHour)
        stored = stored!!.replace("digests", "unknown")
        assertEquals(AgentNewsFeedView.All, restore().newsView)
        stored = stored!!.replace("\"unknown\"", "null")
        assertEquals(AgentNewsFeedView.All, restore().newsView)
        val restored = restore()
        restored.setNewsView(AgentNewsFeedView.All)
        assertEquals("all", restored.state.value.newsView)
        assertEquals(AgentNewsFeedView.All, restore().newsView)
    }

    @Test
    fun newsViewChangesAndPersistsWhileReapplicationWaitsForNetwork() = runBlocking {
        var stored: String? = null
        var zone = "Etc/UTC"
        val gate = CompletableDeferred<Unit>()
        val settings = AgentNewsNotificationSettings(
            read = { stored },
            write = { stored = it },
            ensurePushToken = { "token" },
            getToken = { "token" },
            language = { "en" },
            timeZone = { zone },
            apply = {
                if (it.timeZone != "Etc/UTC") gate.await()
                true
            }
        )
        settings.setMode(AgentNewsNotificationMode.Digest)
        zone = "Europe/Moscow"
        val reapplying = async(start = CoroutineStart.UNDISPATCHED) {
            settings.reapplyIfNeeded()
        }
        try {
            assertTrue(reapplying.isActive)
            withTimeout(1_000) { settings.setNewsView(AgentNewsFeedView.Digests) }
            assertEquals("digests", settings.state.value.newsView)
            assertEquals(
                AgentNewsFeedView.Digests,
                AgentNewsNotificationSettings(read = { stored }, write = {}).newsView
            )
            gate.complete(Unit)
            assertEquals(AgentNewsNotificationOutcome.Ok, reapplying.await())
            assertEquals("digests", settings.state.value.newsView)
            assertEquals(
                AgentNewsFeedView.Digests,
                AgentNewsNotificationSettings(read = { stored }, write = {}).newsView
            )
        } finally {
            reapplying.cancelAndJoin()
        }
    }

    @Test
    fun newsNotificationHourAndChangedDeviceContextReapplyAndResetTurnsPushesOff() = runBlocking {
        var stored: String? = null
        var token = "first-token"
        var language = "en"
        var zone = "Europe/London"
        var shouldSucceed = true
        val calls = mutableListOf<ApiMethod.Notifications.SetNewsNotifications.Props>()
        fun restore() = AgentNewsNotificationSettings(
            read = {
                stored
            },
            write = { stored = it },
            ensurePushToken = { token },
            getToken = { token },
            language = { language },
            timeZone = { zone },
            apply = {
                calls += it
                shouldSucceed
            }
        )
        val settings = restore()
        settings.setDigestTime(19, 0)
        assertTrue(calls.isEmpty())
        settings.setMode(AgentNewsNotificationMode.News)
        settings.setDigestTime(20, 0)
        assertEquals(1, calls.size)
        settings.setMode(AgentNewsNotificationMode.Digest)
        settings.setDigestTime(21, 0)
        assertEquals(3, calls.size)
        assertEquals(21, calls.last().digestHour)
        assertEquals(0, calls.last().digestMinute)
        settings.setDigestTime(21, 45)
        assertEquals(4, calls.size)
        assertEquals(21, calls.last().digestHour)
        assertEquals(45, calls.last().digestMinute)
        shouldSucceed = false
        assertEquals(AgentNewsNotificationOutcome.Failed, settings.setDigestTime(22, 15))
        assertEquals(22, restore().digestHour)
        assertEquals(15, restore().digestMinute)
        shouldSucceed = true
        val restored = restore()
        restored.reapplyIfNeeded()
        assertEquals(22, calls.last().digestHour)
        assertEquals(15, calls.last().digestMinute)
        val unchangedCount = calls.size
        restore().reapplyIfNeeded()
        assertEquals(unchangedCount, calls.size)
        token = "next-token"
        restored.reapplyIfNeeded()
        language = "ru"
        restored.reapplyIfNeeded()
        zone = "Europe/Moscow"
        restored.reapplyIfNeeded()
        assertEquals(unchangedCount + 3, calls.size)
        assertEquals("next-token", calls.last().userToken)
        assertEquals("ru", calls.last().langCode)
        assertEquals("Europe/Moscow", calls.last().timeZone)
        shouldSucceed = false
        assertEquals(AgentNewsNotificationOutcome.Failed, restored.reset())
        assertEquals("off", calls.last().mode)
        val resetCount = calls.size
        val resetSettings = restore()
        assertEquals(AgentNewsNotificationMode.Off, resetSettings.mode)
        shouldSucceed = true
        assertEquals(AgentNewsNotificationOutcome.Ok, resetSettings.reapplyIfNeeded())
        assertEquals(resetCount + 1, calls.size)
        assertEquals("off", calls.last().mode)
        restore().reapplyIfNeeded()
        assertEquals(resetCount + 1, calls.size)
    }

    @Test
    fun newsNotificationSettingsStoredWithoutMinuteKeepTheirChoiceOnTheHourWithoutReapplying() =
        runBlocking {
            val stored = """{"state":{"mode":"Digest","digestHour":9,"newsView":"digests"},""" +
                """"lastApplied":{"mode":"digest","userToken":"token","langCode":"en",""" +
                """"digestHour":9,"timeZone":"Europe/Moscow","platform":"android"}}"""
            val calls = mutableListOf<ApiMethod.Notifications.SetNewsNotifications.Props>()
            val settings = AgentNewsNotificationSettings(
                read = { stored },
                write = {},
                getToken = { "token" },
                language = { "en" },
                timeZone = { "Europe/Moscow" },
                apply = {
                    calls += it
                    true
                }
            )
            assertEquals(AgentNewsNotificationMode.Digest, settings.mode)
            assertEquals(9, settings.digestHour)
            assertEquals(0, settings.digestMinute)
            assertEquals(AgentNewsFeedView.Digests, settings.newsView)
            assertEquals(AgentNewsNotificationOutcome.Ok, settings.reapplyIfNeeded())
            assertTrue(calls.isEmpty())
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
                    "discussionNaming":{"title":"Market discussion","icon":"🪙","followups":["Explain this news"],"future":true},
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
                        discussion = AgentV2NewsFeedItem.Discussion("thread", "🪙"),
                        discussionNaming = AgentV2NewsFeedItem.DiscussionNaming(
                            "Market discussion",
                            "🪙",
                            listOf("Explain this news")
                        )
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

        val withoutIcon = moshi.adapter(AgentV2NewsFeedItem::class.java).fromJson(
            """{"eventId":42,"deliveredAt":"2026-10-20T12:00:00Z","headline":"News","body":"Body","sources":[],"discussionNaming":{"title":"News","followups":["Q"]}}"""
        )!!
        assertEquals(
            AgentV2NewsFeedItem.DiscussionNaming("News", null, listOf("Q")),
            withoutIcon.discussionNaming
        )
    }

    @Test
    fun discardsMalformedDiscussionNamingWithoutLosingTheFeedEntry() {
        val itemAdapter = moshi.adapter(AgentV2NewsFeedItem::class.java)
        val digestAdapter = moshi.adapter(AgentV2NewsFeedDigest::class.java)
        val expected =
            AgentV2NewsFeedItem(42, "2026-10-20T12:00:00Z", "News", "Body", sources = emptyList())
        val expectedDigest =
            AgentV2NewsFeedDigest("digest", "2026-10-20T12:00:00Z", emptyList(), 0)
        for (naming in listOf(
            "null",
            "false",
            """{"title":"News"}""",
            """{"title":42,"followups":[]}""",
            """{"title":"News","icon":42,"followups":[]}""",
            """{"title":"News","followups":[42]}"""
        )) {
            assertEquals(
                expected,
                itemAdapter.fromJson(
                    """{"eventId":42,"deliveredAt":"2026-10-20T12:00:00Z","headline":"News","body":"Body","sources":[],"discussionNaming":$naming}"""
                )
            )
            assertEquals(
                expectedDigest,
                digestAdapter.fromJson(
                    """{"id":"digest","deliveredAt":"2026-10-20T12:00:00Z","total":0,"top":[],"discussionNaming":$naming}"""
                )
            )
        }
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
    fun decodesSupportMessagesAlongsideAgentHistoryAndUnknownEventCodes() {
        val history = moshi.adapter(AgentV2ThreadHydration::class.java).fromJson(
            """
            {
              "thread":{"id":"thread","revision":7,"support":{"state":"operator","lastOperatorMessageAt":"2026-11-08T12:00:04Z"}},
              "messages":[
                {
                  "id":"user","threadId":"thread","role":"user","status":"complete",
                  "createdAt":"2026-11-08T12:00:00Z","content":{"kind":"markdown","text":"Help"}
                },
                {
                  "id":"assistant","threadId":"thread","role":"assistant","status":"complete",
                  "createdAt":"2026-11-08T12:00:01Z","content":{"kind":"markdown","text":"Connecting"}
                },
                {
                  "id":"requested","threadId":"thread","role":"event","status":"complete",
                  "createdAt":"2026-11-08T12:00:02Z","code":"support_requested"
                },
                {
                  "id":"joined","threadId":"thread","role":"event","status":"complete",
                  "createdAt":"2026-11-08T12:00:03Z","code":"operator_joined",
                  "author":{"operatorId":"operator","name":"Alex","avatarUrl":"https://example.com/avatar.png"}
                },
                {
                  "id":"operator","threadId":"thread","role":"operator","status":"complete",
                  "createdAt":"2026-11-08T12:00:04Z","text":"**Plain text**",
                  "author":{"operatorId":"operator","name":"Alex"}
                },
                {
                  "id":"future","threadId":"thread","role":"event","status":"complete",
                  "createdAt":"2026-11-08T12:00:05Z","code":"future_support_event"
                },
                {
                  "id":"closed","threadId":"thread","role":"event","status":"complete",
                  "createdAt":"2026-11-08T12:00:06Z","code":"support_closed","reason":"inactivity"
                }
              ],
              "nextCursor":"older"
            }
            """.trimIndent()
        )!!

        assertEquals(7, history.messages.size)
        assertEquals("older", history.nextCursor)
        assertEquals(
            AgentV2ThreadSupport("operator", "2026-11-08T12:00:04Z"),
            history.thread.support
        )
        assertEquals(AgentV2MessageContent.Markdown("Help"), history.messages[0].content)
        assertEquals(AgentV2MessageContent.Markdown("Connecting"), history.messages[1].content)
        assertEquals("support_requested", history.messages[2].code)
        assertEquals(
            AgentV2OperatorAuthor("operator", "Alex", "https://example.com/avatar.png"),
            history.messages[3].author
        )
        assertEquals("operator_joined", history.messages[3].code)
        assertEquals("operator", history.messages[4].role)
        assertEquals("**Plain text**", history.messages[4].text)
        assertEquals(AgentV2OperatorAuthor("operator", "Alex"), history.messages[4].author)
        assertNull(history.messages[4].content)
        assertEquals("future_support_event", history.messages[5].code)
        assertEquals("support_closed", history.messages[6].code)
        assertEquals("inactivity", history.messages[6].reason)
    }

    @Test
    fun decodesSupportFromThreadListsAndLiveThreadChanges() {
        val list = moshi.adapter(AgentV2ThreadListResponse::class.java).fromJson(
            """
            {"threads":[
              {"thread":{"id":"waiting","revision":1,"support":{"state":"waiting"}}},
              {"thread":{"id":"ordinary","revision":0}}
            ]}
            """.trimIndent()
        )!!
        val update = adapter.fromJson(
            """
            {
              "type":"agentV2",
              "update":{
                "kind":"threadChanged","threadId":"waiting",
                "thread":{"id":"waiting","revision":2,"support":{"state":"closed"}}
              }
            }
            """.trimIndent()
        ) as ApiUpdate.ApiUpdateAgentV2

        assertEquals(AgentV2ThreadSupport("waiting"), list.threads[0].thread.support)
        assertNull(list.threads[1].thread.support)
        assertEquals(
            AgentV2Update.ThreadChanged(
                "waiting",
                AgentV2ThreadSummary("waiting", 2, support = AgentV2ThreadSupport("closed"))
            ),
            update.update
        )
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
    fun describesSupportRequestsAndDecodesTheirDailyLimit() {
        assertEquals(
            listOf("starterHint", "header", "menu").map {
                AgentV2EntryPoint(kind = "supportRequest", source = it)
            },
            AgentV2SupportRequestSource.entries.map(AgentV2EntryPoint::supportRequest)
        )
        assertTrue(
            AgentV2EntryPoint.isSupportRequest(
                AgentV2EntryPoint.supportRequest(AgentV2SupportRequestSource.HEADER)
            )
        )
        assertFalse(AgentV2EntryPoint.isSupportRequest(AgentV2EntryPoint()))
        assertFalse(AgentV2EntryPoint.isSupportRequest(null))

        val failure = adapter.fromJson(
            """
            {
              "type":"agentV2",
              "update":{
                "kind":"runFailed","clientRunId":"c","threadId":"t",
                "code":"support_escalation_rate_limited","retryable":false
              }
            }
            """.trimIndent()
        ) as ApiUpdate.ApiUpdateAgentV2
        assertEquals(
            AgentV2Update.RunFailed(
                "c",
                threadId = "t",
                code = "support_escalation_rate_limited",
                retryable = false
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
