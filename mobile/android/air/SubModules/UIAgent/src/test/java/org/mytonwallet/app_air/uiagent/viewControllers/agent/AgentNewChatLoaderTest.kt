package org.mytonwallet.app_air.uiagent.viewControllers.agent

import java.lang.reflect.Proxy
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.json.JSONObject
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.BeforeClass
import org.junit.Test
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationController
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationRecorder
import org.mytonwallet.app_air.uiagent.agentV2.AgentHostContextSnapshot
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2HostContextProvider
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ErrorText
import org.mytonwallet.app_air.uiagent.agentV2.getAgentSupportRequestText
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsDigestSchedule
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsFeedClient
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Availability
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2CachedMessages
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUpReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2HintsResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationError
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedPage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2StarterHint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2SupportRequestSource
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadCreateResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDeleteResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSupport
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2UserQuota
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsFeedView
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class AgentNewChatLoaderTest {
    @Test
    fun createsOrReusesThreadOnlyAfterExplicitConsent() = runBlocking {
        val calls = mutableListOf<String>()
        val emptyThread = AgentV2ThreadSummary("empty", 1)
        var hasConsent = false
        val loader = AgentNewChatLoader(
            consent = { hasConsent },
            acceptConsent = {
                calls += "consent"
                hasConsent = true
            },
            createThread = {
                calls += "create"
                emptyThread
            }
        )

        assertNull(loader.load())
        assertEquals(emptyList<String>(), calls)
        assertEquals(emptyThread, loader.load(shouldAcceptConsent = true)?.thread)
        assertEquals(emptyThread, loader.load()?.thread)
        assertEquals(listOf("consent", "create", "create"), calls)
    }

    @Test
    fun newsDiscussionCreatesItsThreadBeforeConsent() = runBlocking {
        val news = AgentV2ThreadNewsRequest(42, "en")
        val requests = mutableListOf<AgentV2ThreadNewsRequest?>()
        val loader = AgentNewChatLoader(
            consent = { error("A news discussion opens without asking for consent") },
            acceptConsent = { error("Opening a news discussion never records consent") },
            createThread = {
                requests += it
                AgentV2ThreadSummary("news", 1)
            },
            news = news
        )

        assertEquals("news", loader.load()?.thread?.id)
        assertEquals(listOf<AgentV2ThreadNewsRequest?>(news), requests)
    }

    @Test
    fun deferredPreviewNeverCreatesAThreadOnOpeningConsentOrExit() =
        testDeferredDiscussions { isDigest ->
            for (hasConsent in listOf(false, true)) {
                val client = FakeNewsClient(createDiscussionThread(isDigest)).apply {
                    this.hasConsent =
                        hasConsent
                }
                val opening = createDeferredDiscussionOpening(
                    isDigest = isDigest,
                    client = client
                )

                assertNull(opening.create())
                assertNull(opening.create(shouldAcceptConsent = true))
                opening.readConsent()
                assertEquals(hasConsent, opening.hasConsent)
                assertTrue(opening.canSubmitDiscussionMessage)
                assertFalse(opening.isConsentRequired)
                assertFalse(opening.canReportProblem)
                assertEquals(0, client.acceptedConsentCount)
                assertTrue(opening.messages.isEmpty())

                var allowConsent: (() -> Unit)? = null
                var actionCount = 0
                val consentGate = createDiscussionConsentGate(
                    model = { null },
                    opening = { opening },
                    askForConsent = { onAllowed, _ -> allowConsent = onAllowed }
                )
                consentGate.request { actionCount++ }
                if (!hasConsent) {
                    assertEquals(0, actionCount)
                    consentGate.request { fail("An action waits for the open consent sheet") }
                    client.hasConsent = true
                    checkNotNull(allowConsent).invoke()
                }
                assertEquals(1, actionCount)
                assertEquals(true, opening.hasConsent)
                assertNull(opening.create())
                assertTrue(opening.messages.isEmpty())

                val reports = mutableListOf<Boolean>()
                opening.reportProblem("Wrong summary") { reports += it }
                opening.deleteChat { fail("A preview has no thread to delete") }
                yield()
                assertEquals(listOf(false), reports)
                assertTrue(client.newsRequests.isEmpty())
                assertEquals(0, client.messageRequests)
                assertTrue(client.deletedThreads.isEmpty())
                assertTrue(client.reports.isEmpty())
            }
        }

    @Test
    fun deferredNewsDiscussionCanRequestHeaderSupport() = verifyDeferredHeaderSupport(false)

    @Test
    fun deferredDigestDiscussionCanRequestHeaderSupport() = verifyDeferredHeaderSupport(true)

    @Test
    fun deferredHeaderSupportDropsAfterWalletChangesDuringCreation() =
        verifyDeferredHeaderSupportWalletChanges(shouldSwitchDuringHydration = false)

    @Test
    fun deferredHeaderSupportDropsAfterWalletChangesDuringHydration() =
        verifyDeferredHeaderSupportWalletChanges(shouldSwitchDuringHydration = true)

    @Test
    fun deferredDictationProducesADraftWithoutCreatingAThread() =
        testDeferredDiscussions { isDigest ->
            for (hasConsent in listOf(false, true)) {
                val client = FakeNewsClient(createDiscussionThread(isDigest)).apply {
                    this.hasConsent =
                        hasConsent
                }
                val requests = mutableListOf<AgentV2TranscriptionRequest>()
                val opening = createDeferredDiscussionOpening(
                    isDigest = isDigest,
                    client = object : AgentV2Client by client {
                        override suspend fun transcribe(
                            request: AgentV2TranscriptionRequest
                        ): AgentV2TranscriptionResponse {
                            requests += request
                            return AgentV2TranscriptionResponse("transcribed", "Draft question")
                        }
                    }
                )
                opening.readConsent()
                val recordingStarted = CompletableDeferred<Unit>()
                val transcriptReady = CompletableDeferred<String>()
                var now = 0L
                val controller = AgentDictationController(
                    scope = this,
                    recorderFactory = {
                        object : AgentDictationRecorder {
                            override fun start() {
                                recordingStarted.complete(Unit)
                            }
                            override fun amplitude() = 2000
                            override fun pause() = Unit
                            override fun resume() = Unit
                            override suspend fun finish() = "audio"
                            override fun cancel() = Unit
                        }
                    },
                    requestPermission = { true },
                    transcribe = opening::transcribeAudio,
                    nowMs = { now },
                    onStateChanged = {},
                    onTranscript = { transcriptReady.complete(it) },
                    onFailure = { fail("Dictation failed: $it") }
                )
                val consentAsked = CompletableDeferred<() -> Unit>()
                val consentGate = createDiscussionConsentGate(
                    model = { null },
                    opening = { opening },
                    askForConsent = { onAllowed, _ -> consentAsked.complete(onAllowed) }
                )
                try {
                    consentGate.requestDiscussionConsent(this, opening = { opening }) {
                        controller.startHandsFree()
                    }
                    if (!hasConsent) {
                        val allowConsent = withTimeout(1_000) { consentAsked.await() }
                        assertFalse(recordingStarted.isCompleted)
                        assertTrue(requests.isEmpty())
                        client.hasConsent = true
                        allowConsent()
                    }
                    withTimeout(1_000) { recordingStarted.await() }
                    now = 1000
                    controller.finish()
                    assertEquals("Draft question", withTimeout(1_000) { transcriptReady.await() })
                    assertEquals(
                        listOf(
                            AgentV2TranscriptionRequest(
                                "audio",
                                lang = LocaleController.activeLanguage.langCode
                            )
                        ),
                        requests
                    )
                    assertTrue(opening.messages.isEmpty())
                    assertTrue(client.newsRequests.isEmpty())
                    assertEquals(0, client.messageRequests)
                    assertTrue(client.sent.isEmpty())
                } finally {
                    controller.cancel()
                }
            }
        }

    @Test
    fun deferredDiscussionReadsLimitsAtOpeningAndBlocksMessagesAndSuggestionsWithoutAThread() =
        testDeferredDiscussions { isDigest ->
            for (isQuotaExhausted in listOf(true, false)) {
                val client = FakeNewsClient(createDiscussionThread(isDigest))
                val opening = createDeferredDiscussionOpening(
                    isDigest = isDigest,
                    client = client
                )
                client.onLoadAvailability = {
                    opening.onBridgeUpdate(
                        ApiUpdate.ApiUpdateAgentV2(
                            AgentV2Update.AvailabilityChanged(
                                AgentV2Availability(
                                    if (isQuotaExhausted) "available" else "capacity_exhausted",
                                    if (isQuotaExhausted) {
                                        null
                                    } else {
                                        System.currentTimeMillis() +
                                            60_000
                                    }
                                )
                            )
                        )
                    )
                }
                client.onLoadUserQuota = {
                    opening.onBridgeUpdate(
                        ApiUpdate.ApiUpdateAgentV2(
                            AgentV2Update.UserQuotaChanged(
                                AgentV2UserQuota(10, 10, 0, "2099-01-01T00:00:00Z")
                                    .takeIf { isQuotaExhausted }
                            )
                        )
                    )
                }

                opening.readConsent()
                assertEquals(1, client.availabilityRequests)
                assertEquals(1, client.quotaRequests)
                assertTrue(opening.isInputBlockedByLimit)
                assertFalse(opening.canSubmitDiscussionMessage)
                assertFalse(opening.stageDiscussionMessage("Question"))
                assertFalse(opening.stageDiscussionMessage("Suggestion", isFollowup = true))
                assertFalse(opening.prepareDiscussionSubmission())
                assertNull(opening.create())
                assertTrue(opening.messages.isEmpty())
                assertTrue(client.newsRequests.isEmpty())
                assertEquals(0, client.messageRequests)
                if (!isQuotaExhausted) {
                    opening.onBridgeUpdate(
                        ApiUpdate.ApiUpdateAgentV2(
                            AgentV2Update.AvailabilityChanged(
                                AgentV2Availability("capacity_exhausted")
                            )
                        )
                    )
                    assertFalse(opening.isInputBlockedByLimit)
                    assertTrue(opening.canSubmitDiscussionMessage)
                    assertTrue(opening.prepareDiscussionSubmission())
                }
            }
        }

    @Test
    fun deferredSubmissionWaitsForConsentAndLimitsAndKeepsBlockedDraft() =
        testDeferredDiscussions { isDigest ->
            for (isQuotaExhausted in listOf(true, false)) {
                val quotaRequested = CompletableDeferred<Unit>()
                val quotaLoaded = CompletableDeferred<Unit>()
                val runStarted = CompletableDeferred<Unit>()
                val client = FakeNewsClient(createDiscussionThread(isDigest)).apply {
                    hasConsent = false
                    onStartRun = { runStarted.complete(Unit) }
                }
                val opening = createDeferredDiscussionOpening(
                    isDigest = isDigest,
                    client = client
                )
                client.onLoadUserQuota = {
                    quotaRequested.complete(Unit)
                    quotaLoaded.await()
                    opening.onBridgeUpdate(
                        ApiUpdate.ApiUpdateAgentV2(
                            AgentV2Update.UserQuotaChanged(
                                AgentV2UserQuota(
                                    10,
                                    if (isQuotaExhausted) 10 else 0,
                                    if (isQuotaExhausted) 0 else 10,
                                    "2099-01-01T00:00:00Z"
                                )
                            )
                        )
                    )
                }
                opening.readConsent()
                assertEquals(0, client.availabilityRequests)
                assertEquals(0, client.quotaRequests)
                var allowConsent: (() -> Unit)? = null
                var draft = "First question"
                var thread: AgentV2ThreadSummary? = null
                val gate = createDiscussionConsentGate(
                    model = { null },
                    opening = { opening },
                    askForConsent = { onAllowed, _ -> allowConsent = onAllowed }
                )
                coroutineScope {
                    gate.requestDiscussionConsent(this, opening = { opening }) {
                        launch {
                            if (opening.stageDiscussionMessage(draft)) {
                                draft = ""
                                thread = opening.create()
                            }
                        }
                    }
                    withTimeout(1_000) {
                        while (allowConsent == null) yield()
                    }
                    client.acceptConsent()
                    checkNotNull(allowConsent).invoke()
                    withTimeout(1_000) { quotaRequested.await() }
                    assertEquals("First question", draft)
                    assertFalse(opening.canSubmitDiscussionMessage)
                    assertTrue(opening.messages.isEmpty())
                    assertTrue(client.newsRequests.isEmpty())
                    quotaLoaded.complete(Unit)
                }
                assertEquals(1, client.availabilityRequests)
                assertEquals(1, client.quotaRequests)
                if (isQuotaExhausted) {
                    assertNull(thread)
                    assertTrue(opening.isInputBlockedByLimit)
                    assertEquals("First question", draft)
                    assertTrue(opening.messages.isEmpty())
                    assertTrue(client.newsRequests.isEmpty())
                    assertEquals(0, client.messageRequests)
                } else {
                    assertEquals("", draft)
                    val model = newModel(client, checkNotNull(thread), opening)
                    try {
                        withTimeout(1_000) { runStarted.await() }
                        awaitReady(model)
                        assertEquals(listOf("First question" to null), client.sent)
                        assertEquals(1, client.newsRequests.size)
                    } finally {
                        model.onDestroy()
                    }
                }
            }
        }

    @Test
    fun deferredDiscussionLimitAfterStagingKeepsTheMessageWithAnErrorUntilCreationIsRetried() =
        testDeferredDiscussions { isDigest ->
            val client = FakeNewsClient(createDiscussionThread(isDigest))
            val opening = createDeferredDiscussionOpening(
                isDigest = isDigest,
                client = client
            )
            opening.readConsent()
            assertTrue(opening.stageDiscussionMessage("First question"))
            val optimisticMessage = opening.messages.single()
            opening.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.UserQuotaChanged(
                        AgentV2UserQuota(10, 10, 0, "2099-01-01T00:00:00Z")
                    )
                )
            )

            assertNull(opening.create())
            assertEquals(
                "user_quota_exhausted",
                (opening.error as? AgentV2OperationException)?.error?.code
            )
            assertEquals(listOf(optimisticMessage), opening.messages)
            assertTrue(client.newsRequests.isEmpty())

            opening.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(AgentV2Update.UserQuotaChanged()))
            assertEquals("news-thread", opening.create()?.id)
            assertNull(opening.error)
            assertEquals(listOf(optimisticMessage), opening.messages)
            assertEquals(1, client.newsRequests.size)
        }

    @Test
    fun deferredDiscussionFirstMessageCreatesOnceWaitsForHistoryAndResolvesOnlyExactSuggestions() =
        testDeferredDiscussions { isDigest ->
            val followup =
                AgentV2FollowUp("news-followup", "suggested_prompt", "Why does this matter?")
            for (followupText in listOf(
                null,
                followup.text,
                "A different question",
                "why does this matter?",
                " Why does this matter? "
            )) {
                val created = CompletableDeferred<Unit>()
                val historyRequested = CompletableDeferred<Unit>()
                val historyLoaded = CompletableDeferred<Unit>()
                val modelQuotaRequested = CompletableDeferred<Unit>()
                val modelQuotaLoaded = CompletableDeferred<Unit>()
                val runStarted = CompletableDeferred<Unit>()
                val thread = createDiscussionThread(isDigest).copy(messageCount = 1)
                val savedPost = AgentV2PersistedMessage(
                    "post",
                    thread.id,
                    "assistant",
                    "complete",
                    content = AgentV2MessageContent.Markdown("News body"),
                    createdAt = "2026-10-20T00:00:00Z",
                    followups = listOf(followup),
                    newsPost = true
                )
                val client = FakeNewsClient(thread, listOf(savedPost)).apply {
                    onCreate = { created.await() }
                    onMessages = {
                        historyRequested.complete(Unit)
                        historyLoaded.await()
                    }
                    onLoadUserQuota = {
                        if (quotaRequests == 2) {
                            modelQuotaRequested.complete(Unit)
                            modelQuotaLoaded.await()
                        }
                    }
                    onStartRun = { runStarted.complete(Unit) }
                }
                val opening = createDeferredDiscussionOpening(
                    isDigest = isDigest,
                    client = client
                )
                val text = followupText ?: followup.text
                assertTrue(opening.stageDiscussionMessage(text, isFollowup = followupText != null))
                val optimisticMessage = opening.messages.single()
                assertEquals(text, optimisticMessage.text)
                assertEquals(AgentMessageRole.USER, optimisticMessage.role)
                assertFalse(opening.stageDiscussionMessage(text, isFollowup = true))

                val creation = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }
                assertFalse(creation.isCompleted)
                assertNull(opening.create())
                assertEquals(
                    listOf(AgentV2ThreadNewsRequest(42, "en").takeUnless { isDigest }),
                    client.newsRequests
                )
                assertEquals(
                    listOf(AgentV2ThreadDigestRequest(DIGEST_ID).takeIf { isDigest }),
                    client.digestRequests
                )
                assertEquals(listOf(optimisticMessage), opening.messages)
                created.complete(Unit)
                val createdThread = checkNotNull(creation.await())
                assertEquals(createdThread, opening.create())
                val sessions = modelSessions()
                val model = sessions.acquire(createdThread.id) {
                    newModel(client, createdThread, opening)
                }
                try {
                    withTimeout(1_000) { historyRequested.await() }
                    sessions.release(createdThread.id, model)
                    assertSame(
                        model,
                        sessions.acquire(createdThread.id) {
                            error("The pending first message retains its session")
                        }
                    )
                    assertEquals(listOf(optimisticMessage), model.messages)
                    assertTrue(model.hasUnsentOpening)
                    assertFalse(model.sendMessage(text))
                    assertTrue(client.sent.isEmpty())
                    historyLoaded.complete(Unit)
                    withTimeout(1_000) { modelQuotaRequested.await() }
                    yield()
                    assertTrue(client.sent.isEmpty())
                    modelQuotaLoaded.complete(Unit)
                    withTimeout(1_000) { runStarted.await() }
                    awaitReady(model)
                    model.retry()
                    yield()
                    assertEquals(1, client.newsRequests.size)
                    assertEquals(1, client.messageRequests)
                    assertEquals(listOf(text to null), client.sent)
                    assertEquals(
                        listOf(
                            AgentV2FollowUpReference(savedPost.id, followup.id)
                                .takeIf { followupText == followup.text }
                        ),
                        client.sentFollowups
                    )
                    assertEquals(
                        listOf(optimisticMessage.id),
                        model.messages.filter { it.role == AgentMessageRole.USER }.map { it.id }
                    )
                } finally {
                    historyLoaded.complete(Unit)
                    modelQuotaLoaded.complete(Unit)
                    sessions.release(createdThread.id, model)
                }
            }
        }

    @Test
    fun deferredFirstMessageKeepsTheWalletChosenWhenSending() =
        testDeferredDiscussions { isDigest ->
            val originalAccountId = AccountStore.activeAccountId
            try {
                for (shouldReturnToWallet in listOf(false, true)) {
                    AccountStore.updateActiveAccount("preview-wallet")
                    val created = CompletableDeferred<Unit>()
                    val runStarted = CompletableDeferred<Unit>()
                    val client = FakeNewsClient(createDiscussionThread(isDigest)).apply {
                        onCreate = { created.await() }
                        onStartRun = { runStarted.complete(Unit) }
                    }
                    val opening = createDeferredDiscussionOpening(
                        isDigest = isDigest,
                        client = client
                    )
                    opening.readConsent()
                    AccountStore.updateActiveAccount("wallet-a")
                    assertTrue(opening.stageDiscussionMessage("First question"))
                    val optimisticMessage = opening.messages.single()
                    val creation = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }
                    assertEquals(1, client.newsRequests.size)
                    assertFalse(creation.isCompleted)

                    AccountStore.updateActiveAccount("wallet-b")
                    if (shouldReturnToWallet) AccountStore.updateActiveAccount("wallet-a")
                    created.complete(Unit)
                    val model = newModel(client, checkNotNull(creation.await()), opening)
                    try {
                        awaitReady(model)
                        if (shouldReturnToWallet) {
                            withTimeout(1_000) { runStarted.await() }
                            awaitReady(model)
                            assertEquals(listOf("First question" to null), client.sent)
                            assertTrue(model.messages.none { it.isFailure })
                        } else {
                            yield()
                            assertTrue(client.sent.isEmpty())
                            val failure = model.messages.single { it.isFailure }
                            assertEquals(agentV2ErrorText(null), failure.text)
                            assertTrue(model.failureRetry != null)
                            assertFalse(model.hasUnsentOpening)
                        }
                        assertEquals(
                            listOf(optimisticMessage.id),
                            model.messages.filter { it.role == AgentMessageRole.USER }.map { it.id }
                        )
                        assertEquals(1, client.newsRequests.size)
                    } finally {
                        model.onDestroy()
                    }
                }
            } finally {
                AccountStore.updateActiveAccount(originalAccountId)
            }
        }

    @Test
    fun deferredCreationRetryKeepsTheFirstMessageAndSendsOnce() =
        testDeferredDiscussions { isDigest ->
            val failures = listOf(
                IllegalStateException("No response"),
                AgentV2OperationException(AgentV2MutationError("rate_limited", retryable = true)),
                AgentV2OperationException(
                    AgentV2MutationError("news_unavailable", retryable = false)
                )
            )
            for (failure in failures) {
                val runStarted = CompletableDeferred<Unit>()
                val client = FakeNewsClient(createDiscussionThread(isDigest)).apply {
                    onCreate = { throw failure }
                    onStartRun = { runStarted.complete(Unit) }
                }
                val opening = createDeferredDiscussionOpening(
                    isDigest = isDigest,
                    client = client
                )
                assertTrue(opening.stageDiscussionMessage("First question"))
                val optimisticMessage = opening.messages.single()
                assertNull(opening.create())
                assertSame(failure, opening.error)
                assertEquals(listOf(optimisticMessage), opening.messages)
                assertTrue(client.sent.isEmpty())
                client.onCreate = {}

                val thread = checkNotNull(opening.create())
                assertNull(opening.error)
                val model = newModel(client, thread, opening)
                try {
                    withTimeout(1_000) { runStarted.await() }
                    awaitReady(model)
                    model.retry()
                    yield()
                    assertEquals(2, client.newsRequests.size)
                    assertEquals(1, client.messageRequests)
                    assertEquals(listOf("First question" to null), client.sent)
                    assertEquals(
                        listOf(optimisticMessage.id),
                        model.messages.filter { it.role == AgentMessageRole.USER }.map { it.id }
                    )
                } finally {
                    model.onDestroy()
                }
            }
        }

    @Test
    fun deferredFirstMessageLeftBeforeItsThreadIsSentOnceToTheCreatedThread() =
        testDeferredDiscussions { isDigest ->
            val discussion = LeftDiscussion(this, isDigest)
            try {
                discussion.leave()
                discussion.complete()
                val model = discussion.awaitSent()
                assertEquals(listOf(model.currentThread.id), discussion.learnedThreadIds)
                assertEquals(listOf(discussion.staged.id), model.userMessageIds)
            } finally {
                discussion.close()
            }
        }

    @Test
    fun deferredDiscussionReopenedWhileItsThreadIsCreatedJoinsThePendingOpening() =
        testDeferredDiscussions { isDigest ->
            val discussion = LeftDiscussion(this, isDigest)
            try {
                discussion.leave()
                val originalAccountId = AccountStore.activeAccountId
                try {
                    AccountStore.updateActiveAccount("another-wallet")
                    assertNull(discussion.discussions.find(discussion.key))
                } finally {
                    AccountStore.updateActiveAccount(originalAccountId)
                }
                val reopened = checkNotNull(discussion.discussions.find(discussion.key))
                assertSame(discussion.opening, reopened)
                assertEquals(listOf(discussion.staged), reopened.messages)
                val reopenedModels = mutableListOf<AgentVM>()
                discussion.discussions.create(discussion.key, reopened, reopenedModels::add, null)
                discussion.complete()
                val model = discussion.awaitSent()
                assertEquals(listOf(model), reopenedModels)
                assertTrue(discussion.learnedThreadIds.isEmpty())
                assertEquals(listOf(discussion.staged.id), model.userMessageIds)
            } finally {
                discussion.close()
            }
        }

    @Test
    fun deferredDiscussionReopenedAfterItsThreadIsCreatedShowsTheThreadsChat() =
        testDeferredDiscussions { isDigest ->
            val discussion = LeftDiscussion(this, isDigest)
            try {
                discussion.leave()
                discussion.complete()
                val model = discussion.awaitSent()
                assertNull(discussion.discussions.find(discussion.key))
                val reopened = discussion.sessions.acquire(model.currentThread.id) {
                    error("The created thread's chat stays loaded")
                }
                discussion.sessions.release(model.currentThread.id, reopened)
                assertSame(model, reopened)
                assertTrue(reopened.isThreadStarted)
                assertEquals(listOf(discussion.staged.id), reopened.userMessageIds)
            } finally {
                discussion.close()
            }
        }

    /** A deferred discussion whose first message is staged, left while `createThread` waits for [complete] */
    private inner class LeftDiscussion(scope: CoroutineScope, isDigest: Boolean) {
        private val created = CompletableDeferred<Unit>()
        private val runStarted = CompletableDeferred<Unit>()
        private val client = FakeNewsClient(createDiscussionThread(isDigest)).apply {
            onCreate = { created.await() }
            onStartRun = { runStarted.complete(Unit) }
        }
        private val models = mutableListOf<AgentVM>()

        // The feed keeps the chat of a discussion it learns
        private val retained = mutableListOf<AgentVM>()
        val sessions = modelSessions()
        val discussions = AgentPendingDiscussions(
            scope,
            acquireOpening = { thread, opening ->
                sessions.acquire(thread.id) {
                    scope.newModel(client, thread, opening).also(models::add)
                }
            },
            release = { sessions.release(it.currentThread.id, it) }
        )
        val key = checkNotNull(
            getAgentDeferredDiscussionKey(
                AgentNewsChatRequest(42, "en", shouldDeferCreation = true).takeUnless { isDigest },
                DIGEST_ID.takeIf { isDigest },
                shouldDeferCreation = isDigest
            )
        )
        val opening = createDeferredDiscussionOpening(client, isDigest)
        val learnedThreadIds = mutableListOf<String>()
        val staged: AgentMessage

        init {
            assertTrue(opening.stageDiscussionMessage("First question"))
            staged = opening.messages.single()
        }

        suspend fun leave() {
            val chat: (AgentVM) -> Unit = { fail("A left chat takes no model") }
            discussions.create(key, opening, chat, { thread ->
                learnedThreadIds += thread.id
                retained +=
                    sessions.acquire(thread.id) { error("The created thread's chat is loaded") }
            })
            withTimeout(1_000) {
                while (client.newsRequests.isEmpty()) yield()
            }
            discussions.leave(key, chat)
        }

        fun complete() = created.complete(Unit)

        suspend fun awaitSent(): AgentVM {
            withTimeout(1_000) { runStarted.await() }
            val model = models.single()
            awaitReady(model)
            assertEquals(listOf("First question" to null), client.sent)
            assertEquals(1, client.newsRequests.size)
            return model
        }

        fun close() {
            created.complete(Unit)
            retained.forEach { sessions.release(it.currentThread.id, it) }
            models.forEach(AgentVM::onDestroy)
        }
    }

    private val AgentVM.userMessageIds
        get() = messages.filter { it.role == AgentMessageRole.USER }.map { it.id }

    @Test
    fun digestOpeningCreatesAndLoadsItsPostBeforeConsentAndStaysUnstarted() = runBlocking {
        val digestId = "ru:2026-11-08T18:00:00.000Z"
        val thread = AgentV2ThreadSummary(
            "digest",
            1,
            messageCount = 1,
            digest = AgentV2ThreadDigestCard(
                digestId,
                "2026-11-08T18:00:00.000Z",
                1,
                listOf(AgentV2NewsDigestHeadline(42, "Headline"))
            )
        )
        val client = FakeNewsClient(thread).apply { hasConsent = false }
        val opening = AgentChatOpening(digestId = digestId, client = client)
        assertEquals(thread, opening.create())
        assertEquals(listOf(AgentV2ThreadDigestRequest(digestId)), client.digestRequests)
        assertFalse(opening.isConsentRequired)
        assertEquals(0, client.acceptedConsentCount)
        val modelScope = CoroutineScope(coroutineContext + SupervisorJob())
        val model = modelScope.newModel(client, thread)
        try {
            awaitReady(model)
            assertEquals(1, client.messageRequests)
            assertFalse(model.isThreadStarted)
            assertTrue(model.visibleHints.isEmpty())
        } finally {
            model.onDestroy()
            modelScope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    @Test
    fun newsPushOpeningUsesFeedLocaleForCurrentLanguage() = runBlocking {
        val client = FakeNewsClient(newsThread()).apply { hasConsent = false }
        val languages = mutableListOf<String>()
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42),
            client = client,
            feedClient = object : AgentNewsFeedClient {
                override suspend fun getNewsFeed(
                    lang: String,
                    cursor: String?,
                    schedule: AgentNewsDigestSchedule,
                    view: AgentNewsFeedView
                ): AgentV2NewsFeedPage {
                    languages += lang
                    assertNull(cursor)
                    return AgentV2NewsFeedPage("ru", emptyList())
                }
            }
        )
        assertEquals("news-thread", opening.create()?.id)
        assertEquals(listOf(LocaleController.activeLanguage.langCode), languages)
        assertEquals(listOf(AgentV2ThreadNewsRequest(42, "ru")), client.newsRequests)
    }

    @Test
    fun failedConsentNeverCreatesThreadAndCanBeRetried() = runBlocking {
        var shouldFailConsent = true
        var createCount = 0
        val loader = AgentNewChatLoader(
            consent = { false },
            acceptConsent = { if (shouldFailConsent) error("offline") },
            createThread = {
                createCount++
                AgentV2ThreadSummary("thread", 1)
            }
        )

        try {
            loader.load(shouldAcceptConsent = true)
            fail("Consent failure must propagate")
        } catch (_: IllegalStateException) {
            assertEquals(0, createCount)
        }
        shouldFailConsent = false
        assertEquals("thread", loader.load(shouldAcceptConsent = true)?.thread?.id)
        assertEquals(1, createCount)
    }

    @Test
    fun questionOpensBeforeCreationAndSendsTheSameNormalizedMessagesOnce() = runBlocking {
        val text = "  Explain my portfolio \n"
        val entryPoint = AgentV2EntryPoint(kind = "portfolio", accountScope = "all")
        val created = CompletableDeferred<Unit>()
        val runStarted = CompletableDeferred<Unit>()
        val runFinished = CompletableDeferred<Unit>()
        val client = FakeNewsClient(AgentV2ThreadSummary("question-thread", 1)).apply {
            onCreate = { created.await() }
            onStartRun = {
                runStarted.complete(Unit)
                runFinished.await()
            }
        }
        val opening = AgentChatOpening(
            prompt = AgentPromptChatRequest(text, entryPoint),
            client = client
        )
        val optimisticMessages = opening.messages.toList()
        assertEquals(
            listOf(AgentMessageRole.USER, AgentMessageRole.ASSISTANT),
            optimisticMessages.map { it.role }
        )
        assertEquals(listOf("Explain my portfolio", ""), optimisticMessages.map { it.text })
        assertTrue(optimisticMessages.all { it.isStreaming })

        val creation = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }
        assertFalse(creation.isCompleted)
        assertTrue(opening.isCreating)
        assertEquals(optimisticMessages, opening.messages)
        assertEquals(listOf<AgentV2ThreadNewsRequest?>(null), client.newsRequests)
        assertTrue(client.sent.isEmpty())

        created.complete(Unit)
        val thread = checkNotNull(creation.await())
        assertEquals(optimisticMessages, opening.messages)
        val model = newModel(client, thread, opening)
        try {
            withTimeout(1_000) { runStarted.await() }
            assertEquals(optimisticMessages, model.messages)
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunStarted(
                        client.startedRunIds.last(),
                        "server-run",
                        thread.id,
                        thread.revision,
                        "user-sdk"
                    )
                )
            )
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.MessageStarted(
                        client.startedRunIds.last(),
                        "server-run",
                        thread.id,
                        "answer-sdk",
                        "markdown"
                    )
                )
            )
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.TextDelta(
                        client.startedRunIds.last(),
                        "server-run",
                        thread.id,
                        "answer-sdk",
                        "Analysis"
                    )
                )
            )
            assertEquals(optimisticMessages.map { it.id }, model.messages.map { it.id })
            assertEquals(optimisticMessages.map { it.date }, model.messages.map { it.date })
            assertEquals("Explain my portfolio", model.messages.first().text)
            assertEquals("Analysis", model.messages.last().text)
            runFinished.complete(Unit)
            awaitReady(model)
            model.retry()
            yield()
            assertEquals(listOf("Explain my portfolio" to entryPoint), client.sent)
            assertEquals(0, client.messageRequests)
            assertEquals(optimisticMessages.map { it.id }, model.messages.map { it.id })
            assertEquals(optimisticMessages.map { it.date }, model.messages.map { it.date })
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun questionOpeningBlocksManualSendingOnlyUntilTheOpeningIsEnqueued() = runBlocking {
        val contextRequested = CompletableDeferred<Unit>()
        val contextRecovered = CompletableDeferred<Unit>()
        val runStarted = CompletableDeferred<Unit>()
        val runFinished = CompletableDeferred<Unit>()
        val client = FakeNewsClient(AgentV2ThreadSummary("question-retry-thread", 1)).apply {
            onUpdateHostContext = {
                contextRequested.complete(Unit)
                contextRecovered.await()
            }
            onStartRun = {
                if (sent.size == 1) {
                    runStarted.complete(Unit)
                    runFinished.await()
                }
            }
        }
        val opening = AgentChatOpening(prompt = AgentPromptChatRequest("Question"), client = client)
        val thread = checkNotNull(opening.create())
        val model = newModel(client, thread, opening)
        try {
            withTimeout(1_000) { contextRequested.await() }
            assertTrue(model.hasUnsentOpening)
            assertFalse(model.sendMessage("Before opening"))
            assertEquals(opening.messages, model.messages)
            assertTrue(client.sent.isEmpty())

            contextRecovered.complete(Unit)
            withTimeout(1_000) { runStarted.await() }
            assertFalse(model.hasUnsentOpening)
            client.onMessages = { error("offline") }
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        client.startedRunIds.last(),
                        "server-run",
                        thread.id,
                        "thread_revision_conflict",
                        retryable = true
                    )
                )
            )
            runFinished.complete(Unit)
            withTimeout(1_000) {
                while (model.state != AgentVM.State.ERROR) yield()
            }

            assertFalse(model.hasUnsentOpening)
            client.onMessages = {}
            assertTrue(model.sendMessage("After failure"))
            awaitReady(model)
            assertEquals(
                listOf("Question" to AgentV2EntryPoint(), "After failure" to AgentV2EntryPoint()),
                client.sent
            )
            assertEquals(
                listOf("Question", "After failure"),
                model.messages.filter { it.role == AgentMessageRole.USER }.map { it.text }
            )
        } finally {
            contextRecovered.complete(Unit)
            runFinished.complete(Unit)
            model.onDestroy()
        }
    }

    @Test
    fun reusedEmptyThreadQueuesBothQuestionsWhileTheFirstWaitsForHostContext() = runBlocking {
        val contextRequested = CompletableDeferred<Unit>()
        val contextRecovered = CompletableDeferred<Unit>()
        val runStarted = List(2) { CompletableDeferred<Unit>() }
        val runFinished = List(2) { CompletableDeferred<Unit>() }
        val client = FakeNewsClient(AgentV2ThreadSummary("reused-question-thread", 1)).apply {
            onUpdateHostContext = {
                contextRequested.complete(Unit)
                contextRecovered.await()
            }
            onStartRun = {
                val index = sent.lastIndex
                runStarted[index].complete(Unit)
                runFinished[index].await()
            }
        }
        val firstEntryPoint = AgentV2EntryPoint(kind = "portfolio", accountScope = "all")
        val secondEntryPoint = AgentV2EntryPoint(kind = "search")
        val firstOpening = AgentChatOpening(
            prompt = AgentPromptChatRequest("  First question \n", firstEntryPoint),
            client = client
        )
        val firstThread = checkNotNull(firstOpening.create())
        val model = AgentSession.acquire(firstThread) {
            newModel(client, firstThread, firstOpening)
        }
        var hasOwner = true
        try {
            withTimeout(1_000) { contextRequested.await() }
            assertTrue(client.sent.isEmpty())
            AgentSession.release(model)
            hasOwner = false

            val secondOpening = AgentChatOpening(
                prompt = AgentPromptChatRequest("  Second question \n", secondEntryPoint),
                client = client
            )
            val secondThread = checkNotNull(secondOpening.create())
            assertEquals(firstThread.id, secondThread.id)
            val retained = AgentSession.acquireOpening(
                secondThread,
                secondOpening.messages,
                secondOpening.entryPoint
            )
            hasOwner = true
            assertSame(model, retained)
            val openingMessages = firstOpening.messages + secondOpening.messages
            assertEquals(openingMessages, retained.messages)
            assertEquals(listOf<AgentV2ThreadNewsRequest?>(null, null), client.newsRequests)
            assertTrue(client.sent.isEmpty())

            fun answer(index: Int) {
                val updates = listOf(
                    AgentV2Update.RunStarted(
                        client.startedRunIds.last(),
                        "server-run-$index",
                        firstThread.id,
                        firstThread.revision,
                        "user-sdk-$index"
                    ),
                    AgentV2Update.MessageStarted(
                        client.startedRunIds.last(),
                        "server-run-$index",
                        firstThread.id,
                        "answer-sdk-$index",
                        "markdown"
                    ),
                    AgentV2Update.TextDelta(
                        client.startedRunIds.last(),
                        "server-run-$index",
                        firstThread.id,
                        "answer-sdk-$index",
                        "Answer $index"
                    ),
                    AgentV2Update.MessageCompleted(
                        client.startedRunIds.last(),
                        "server-run-$index",
                        firstThread.id,
                        "answer-sdk-$index",
                        "complete"
                    )
                )
                updates.forEach { retained.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
            }

            contextRecovered.complete(Unit)
            withTimeout(1_000) { runStarted[0].await() }
            assertEquals(listOf("First question" to firstEntryPoint), client.sent)
            assertFalse(runStarted[1].isCompleted)
            assertEquals(openingMessages.map { it.id }, retained.messages.map { it.id })
            assertEquals(openingMessages.map { it.date }, retained.messages.map { it.date })
            answer(0)
            runFinished[0].complete(Unit)

            withTimeout(1_000) { runStarted[1].await() }
            assertEquals(
                listOf("First question", "Answer 0", "Second question", ""),
                retained.messages.map { it.text }
            )
            assertEquals(openingMessages.map { it.id }, retained.messages.map { it.id })
            assertEquals(openingMessages.map { it.date }, retained.messages.map { it.date })
            assertTrue(retained.messages.last().isStreaming)
            answer(1)
            runFinished[1].complete(Unit)
            awaitReady(retained)
            retained.retry()
            yield()

            assertEquals(
                listOf("First question" to firstEntryPoint, "Second question" to secondEntryPoint),
                client.sent
            )
            assertEquals(
                listOf("First question", "Answer 0", "Second question", "Answer 1"),
                retained.messages.map { it.text }
            )
            assertEquals(openingMessages.map { it.id }, retained.messages.map { it.id })
            assertEquals(openingMessages.map { it.date }, retained.messages.map { it.date })
            assertEquals(
                listOf("user-sdk-0", "answer-sdk-0", "user-sdk-1", "answer-sdk-1"),
                retained.messages.map { it.sdkMessageId }
            )
            assertEquals(0, client.messageRequests)
        } finally {
            contextRecovered.complete(Unit)
            runFinished.forEach { it.complete(Unit) }
            if (hasOwner) AgentSession.release(model)
            model.onDestroy()
        }
    }

    @Test
    fun questionWaitsForConsentAndStartsOnlyAfterItIsAccepted() = runBlocking {
        val client = FakeNewsClient(AgentV2ThreadSummary("question-thread", 1)).apply {
            hasConsent = false
        }
        val opening = AgentChatOpening(prompt = AgentPromptChatRequest("Question"), client = client)

        assertNull(opening.create())
        assertTrue(opening.isConsentRequired)
        assertEquals(0, client.acceptedConsentCount)
        assertTrue(client.newsRequests.isEmpty())
        assertTrue(client.sent.isEmpty())

        val thread = checkNotNull(opening.create(shouldAcceptConsent = true))
        assertFalse(opening.isConsentRequired)
        assertEquals(1, client.acceptedConsentCount)
        val model = newModel(client, thread, opening)
        try {
            awaitReady(model)
            assertEquals(listOf("Question" to AgentV2EntryPoint()), client.sent)
            assertEquals(listOf<AgentV2ThreadNewsRequest?>(null), client.newsRequests)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun questionCreationFailureDoesNotSendAndRetryCreatesAgain() = runBlocking {
        val unavailable = IllegalStateException("offline")
        val client = FakeNewsClient(AgentV2ThreadSummary("question-thread", 1)).apply {
            onCreate = { throw unavailable }
        }
        val opening = AgentChatOpening(prompt = AgentPromptChatRequest("Question"), client = client)
        val optimisticMessages = opening.messages.toList()

        assertNull(opening.create())
        assertSame(unavailable, opening.error)
        assertEquals(optimisticMessages.first().id, opening.messages.single().id)
        assertFalse(opening.messages.single().isStreaming)
        assertTrue(client.sent.isEmpty())

        client.onCreate = {}
        val thread = checkNotNull(opening.create())
        assertNull(opening.error)
        assertEquals(optimisticMessages, opening.messages)
        val model = newModel(client, thread, opening)
        try {
            awaitReady(model)
            assertEquals(listOf<AgentV2ThreadNewsRequest?>(null, null), client.newsRequests)
            assertEquals(listOf("Question" to AgentV2EntryPoint()), client.sent)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun cancelledQuestionCreationDoesNotSendOrBecomeACreationError() = runBlocking {
        val client = FakeNewsClient(AgentV2ThreadSummary("question-thread", 1)).apply {
            onCreate = { CompletableDeferred<Unit>().await() }
        }
        val opening = AgentChatOpening(prompt = AgentPromptChatRequest("Question"), client = client)
        val creation = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }
        assertTrue(opening.isCreating)

        creation.cancelAndJoin()

        assertFalse(opening.isCreating)
        assertNull(opening.error)
        assertEquals(2, opening.messages.size)
        assertTrue(client.sent.isEmpty())
    }

    @Test
    fun deletingBeforeCreationStartsNeverCreatesOrAcceptsConsent() = runBlocking {
        val consentReleased = CompletableDeferred<Unit>()
        val client = FakeNewsClient(AgentV2ThreadSummary("question-thread", 1)).apply {
            hasConsent = false
            onConsent = { withContext(NonCancellable) { consentReleased.await() } }
        }
        val opening = AgentChatOpening(prompt = AgentPromptChatRequest("Question"), client = client)
        val creation = async(start = CoroutineStart.UNDISPATCHED) {
            opening.create(shouldAcceptConsent = true)
        }

        opening.deleteChat { fail("Nothing was created, so there is no deletion error") }
        creation.cancel()
        consentReleased.complete(Unit)
        creation.join()

        assertNull(opening.create(shouldAcceptConsent = true))
        assertNull(opening.error)
        assertEquals(0, client.acceptedConsentCount)
        assertTrue(client.newsRequests.isEmpty())
        assertTrue(client.deletedThreads.isEmpty())
        assertTrue(client.sent.isEmpty())
    }

    @Test
    fun deletedOpeningCleansUpItsExistingCreationAfterTheScreenCloses() = runBlocking {
        for (isNews in listOf(false, true)) {
            val thread = if (isNews) {
                newsThread()
            } else {
                AgentV2ThreadSummary(
                    "question-thread",
                    1
                )
            }
            val created = CompletableDeferred<Unit>()
            val deletionStarted = CompletableDeferred<Unit>()
            val deletionFinished = CompletableDeferred<Unit>()
            val deletionFailure = CompletableDeferred<Throwable>()
            val serverError = IllegalStateException("offline")
            val client = FakeNewsClient(thread).apply {
                onCreate = { created.await() }
                onDelete = {
                    deletionStarted.complete(Unit)
                    deletionFinished.await()
                    if (isNews) throw serverError
                }
            }
            val opening = if (isNews) {
                AgentChatOpening(news = AgentNewsChatRequest(42, "en", "News"), client = client)
            } else {
                AgentChatOpening(prompt = AgentPromptChatRequest("Question"), client = client)
            }
            val creation = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }
            assertEquals(1, client.newsRequests.size)
            opening.deleteChat { deletionFailure.complete(it) }
            opening.deleteChat { fail("Deletion must be idempotent") }
            withTimeout(1_000) { creation.cancelAndJoin() }
            assertTrue(client.deletedThreads.isEmpty())
            assertFalse(created.isCompleted)

            created.complete(Unit)
            withTimeout(1_000) { deletionStarted.await() }
            assertEquals(listOf(thread.id), client.deletedThreads)
            assertTrue(client.sent.isEmpty())
            assertNull(opening.error)
            assertNull(opening.create())
            deletionFinished.complete(Unit)
            if (isNews) {
                assertSame(serverError, withTimeout(1_000) { deletionFailure.await() })
            } else {
                yield()
                assertFalse(deletionFailure.isCompleted)
            }
        }
    }

    @Test
    fun failedCreationAfterDeletionClosesSilentlyWithoutSending() = runBlocking {
        val created = CompletableDeferred<Unit>()
        val creationFinished = CompletableDeferred<Unit>()
        val client = FakeNewsClient(AgentV2ThreadSummary("question-thread", 1)).apply {
            onCreate = {
                try {
                    created.await()
                    error("Creation failed")
                } finally {
                    creationFinished.complete(Unit)
                }
            }
        }
        val opening = AgentChatOpening(prompt = AgentPromptChatRequest("Question"), client = client)
        val creation = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }
        opening.deleteChat { fail("A failed creation must not show a delete error") }
        creation.cancelAndJoin()
        created.complete(Unit)
        withTimeout(1_000) { creationFinished.await() }
        yield()

        assertNull(opening.error)
        assertTrue(client.deletedThreads.isEmpty())
        assertTrue(client.sent.isEmpty())
    }

    @Test
    fun deletingPreparedOpeningHoldsItsQuestionUntilTheServerRefusesDeletion() = runBlocking {
        val contextStarted = CompletableDeferred<Job>()
        val contextReleased = CompletableDeferred<Unit>()
        val deletionStarted = CompletableDeferred<Unit>()
        val deletionFinished = CompletableDeferred<Unit>()
        val deletionFailure = CompletableDeferred<Throwable>()
        val serverError = IllegalStateException("offline")
        val thread = AgentV2ThreadSummary("question-thread", 1)
        val client = FakeNewsClient(thread).apply {
            onUpdateHostContext = {
                contextStarted.complete(checkNotNull(currentCoroutineContext()[Job]))
                withContext(NonCancellable) { contextReleased.await() }
            }
            onDelete = {
                deletionStarted.complete(Unit)
                deletionFinished.await()
                throw serverError
            }
        }
        val opening = AgentChatOpening(prompt = AgentPromptChatRequest("Question"), client = client)
        checkNotNull(opening.create())
        val sessions = modelSessions()
        val model = sessions.acquire(thread.id) { newModel(client, thread, opening) }
        try {
            val startup = withTimeout(1_000) { contextStarted.await() }
            model.deleteChat({ deletionFailure.complete(it) }, onSuccess = {})
            model.deleteChat({ fail("Deletion must be idempotent") }, onSuccess = {})
            assertTrue(model.shouldRetainSession)
            sessions.release(thread.id, model)
            assertEquals(listOf(model), sessions.getModels())
            assertFalse(model.sendMessage("Too late"))
            model.acceptOpening(opening.messages, opening.entryPoint)
            model.retry()
            withTimeout(1_000) { deletionStarted.await() }
            assertEquals(listOf(thread.id), client.deletedThreads)
            assertFalse(deletionFailure.isCompleted)

            contextReleased.complete(Unit)
            withTimeout(1_000) { startup.join() }
            assertTrue(client.sent.isEmpty())
            deletionFinished.complete(Unit)
            assertSame(serverError, withTimeout(1_000) { deletionFailure.await() })
            withTimeout(1_000) { while (sessions.getModels().isNotEmpty()) yield() }
            assertEquals(listOf("Question"), client.sent.map { it.first })
        } finally {
            contextReleased.complete(Unit)
            deletionFinished.complete(Unit)
            model.onDestroy()
        }
    }

    @Test
    fun deletingChatHoldsAnUnsentRunUntilDeletionSucceedsOrFails() = runBlocking {
        for (shouldWaitForHostContext in listOf(false, true)) {
            for (shouldDelete in listOf(false, true)) {
                val thread = AgentV2ThreadSummary("empty-thread", 1)
                val deletionStarted = CompletableDeferred<Unit>()
                val deletionMayEnd = CompletableDeferred<Unit>()
                val deletionFailed = CompletableDeferred<Throwable>()
                val contextStarted = CompletableDeferred<Job>()
                val contextReleased = CompletableDeferred<Unit>()
                val client = FakeNewsClient(thread).apply {
                    onDelete = {
                        deletionStarted.complete(Unit)
                        deletionMayEnd.await()
                        if (!shouldDelete) error("Deletion refused")
                    }
                }
                val modelScope =
                    CoroutineScope(coroutineContext + SupervisorJob(coroutineContext[Job]))
                val provider = AgentV2HostContextProvider(client, modelScope) {
                    AgentHostContextSnapshot(null, JSONObject())
                }
                val model = AgentSession.acquire(thread) {
                    AgentVM(
                        client = client,
                        initialThread = thread,
                        scope = modelScope,
                        contextProvider = provider
                    )
                }
                try {
                    awaitReady(model)
                    if (shouldWaitForHostContext) {
                        client.onUpdateHostContext = {
                            contextStarted.complete(checkNotNull(currentCoroutineContext()[Job]))
                            contextReleased.await()
                        }
                        provider.onWalletEvent(WalletEvent.BalanceChanged)
                    }
                    assertTrue(model.sendMessage("Question"))
                    val pendingRun = if (shouldWaitForHostContext) {
                        withTimeout(1_000) { contextStarted.await() }
                    } else {
                        null
                    }
                    assertTrue(model.sendMessage("Queued"))
                    assertTrue(client.sent.isEmpty())
                    AgentSession.deleteChat(model) { deletionFailed.complete(it) }
                    AgentSession.release(model)
                    withTimeout(1_000) { deletionStarted.await() }
                    contextReleased.complete(Unit)
                    withTimeout(1_000) { pendingRun?.join() }
                    assertTrue(
                        "Question sent during deletion (shouldWaitForHostContext=$shouldWaitForHostContext)",
                        client.sent.isEmpty()
                    )

                    deletionMayEnd.complete(Unit)
                    if (!shouldDelete) withTimeout(1_000) { deletionFailed.await() }
                    withTimeout(1_000) {
                        while (AgentSession.findLoadedModel(thread.id) != null) yield()
                    }
                    assertEquals(
                        if (shouldDelete) emptyList() else listOf("Question", "Queued"),
                        client.sent.map { it.first }
                    )
                    assertEquals(listOf(thread.id), client.deletedThreads)
                } finally {
                    contextReleased.complete(Unit)
                    deletionMayEnd.complete(Unit)
                    AgentSession.dropDeletedChat(thread.id)
                    model.onDestroy()
                }
            }
        }
    }

    @Test
    fun newsOpensBeforeCreationAndLoadsTheSavedPostWithoutSending() = runBlocking {
        val created = CompletableDeferred<Unit>()
        val runStarted = CompletableDeferred<Unit>()
        val runFinished = CompletableDeferred<Unit>()
        val thread = newsThread().copy(messageCount = 1)
        val followup = AgentV2FollowUp("news-followup", "suggested_prompt", "Why does this matter?")
        val savedPost = AgentV2PersistedMessage(
            "post",
            thread.id,
            "assistant",
            "complete",
            content = AgentV2MessageContent.Markdown("**Server headline**\n\nNews body"),
            createdAt = "2026-10-20T00:00:00Z",
            followups = listOf(followup),
            newsPost = true
        )
        val client = FakeNewsClient(thread, listOf(savedPost)).apply {
            onCreate = { created.await() }
            onStartRun = {
                runStarted.complete(Unit)
                runFinished.await()
            }
        }
        val request = AgentNewsChatRequest(
            42,
            "en",
            "Feed headline",
            body = "Full **feed** body",
            sources = listOf(AgentV2NewsFeedItem.Source("Source", "https://example.com/news"))
        )
        val opening = AgentChatOpening(news = request, client = client)
        val preview = request.newsPostCard()
        assertEquals(request.body, preview.body)
        assertEquals(request.sources, preview.sources)
        assertTrue(opening.messages.isEmpty())
        val creation = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }

        assertFalse(creation.isCompleted)
        assertTrue(opening.isCreating)
        assertTrue(opening.messages.isEmpty())
        assertEquals(listOf(AgentV2ThreadNewsRequest(42, "en")), client.newsRequests)
        assertTrue(client.sent.isEmpty())

        created.complete(Unit)
        val createdThread = checkNotNull(creation.await())
        assertEquals(thread.news?.headline, createdThread.news?.headline)
        assertEquals(request.body, createdThread.news?.body)
        assertEquals(request.sources, createdThread.news?.sources)
        val model = newModel(client, createdThread, opening)
        try {
            awaitReady(model)
            assertEquals(1, model.messages.size)
            val post = model.messages.single()
            assertTrue(post.newsPost)
            assertFalse(post.isStreaming)
            assertEquals(listOf(followup), model.visibleFollowups(post.id))
            assertTrue(model.visibleHints.isEmpty())
            assertFalse(model.hasUnsentOpening)
            assertEquals(request.body, model.currentThread.news?.body)
            assertEquals(request.sources, model.currentThread.news?.sources)
            repeat(2) {
                model.acceptOpening(opening.messages, opening.entryPoint)
                model.retry()
            }
            yield()
            assertEquals(1, client.messageRequests)
            assertTrue(client.hintRequests.isEmpty())
            assertTrue(client.sent.isEmpty())
            assertTrue(model.sendFollowup(post.id, followup.id))
            assertTrue(model.visibleFollowups(post.id).isEmpty())
            assertEquals(
                followup.text,
                model.messages.first {
                    it.role == AgentMessageRole.USER
                }.text
            )
            withTimeout(1_000) { runStarted.await() }
            assertEquals(listOf(followup.text to null), client.sent)
            assertEquals(
                listOf(AgentV2FollowUpReference(savedPost.id, followup.id)),
                client.sentFollowups
            )
            listOf(
                AgentV2Update.RunStarted(
                    client.startedRunIds.last(),
                    "server-run",
                    thread.id,
                    thread.revision,
                    "question"
                ),
                AgentV2Update.MessageStarted(
                    client.startedRunIds.last(),
                    "server-run",
                    thread.id,
                    "answer",
                    "markdown"
                ),
                AgentV2Update.TextDelta(
                    client.startedRunIds.last(),
                    "server-run",
                    thread.id,
                    "answer",
                    "News analysis"
                ),
                AgentV2Update.MessageCompleted(
                    client.startedRunIds.last(),
                    "server-run",
                    thread.id,
                    "answer",
                    "complete"
                )
            ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
            runFinished.complete(Unit)
            awaitReady(model)
            assertEquals("News analysis", model.messages.last().text)
            assertTrue(model.visibleFollowups(post.id).isEmpty())
            assertTrue(model.visibleHints.isEmpty())
            assertTrue(client.hintRequests.isEmpty())
        } finally {
            runFinished.complete(Unit)
            model.onDestroy()
        }
    }

    @Test
    fun newsReadsItsPostBeforeConsentAndSendsASuggestionOnlyOnceAllowed() = runBlocking {
        val runStarted = CompletableDeferred<Unit>()
        val thread = newsThread().copy(messageCount = 1)
        val followup = AgentV2FollowUp("news-followup", "suggested_prompt", "Why does this matter?")
        val savedPost = AgentV2PersistedMessage(
            "post",
            thread.id,
            "assistant",
            "complete",
            content = AgentV2MessageContent.Markdown("**Server headline**\n\nNews body"),
            createdAt = "2026-10-20T00:00:00Z",
            followups = listOf(followup),
            newsPost = true
        )
        val client = FakeNewsClient(thread, listOf(savedPost)).apply {
            hasConsent = false
            onStartRun = { runStarted.complete(Unit) }
        }
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "Feed headline"),
            client = client
        )

        val createdThread = checkNotNull(opening.create())
        assertFalse(opening.isConsentRequired)
        assertEquals(listOf(AgentV2ThreadNewsRequest(42, "en")), client.newsRequests)
        val model = newModel(client, createdThread, opening)
        try {
            awaitReady(model)
            assertEquals(false, model.hasConsent)
            assertFalse(model.isThreadStarted)
            val post = model.messages.single()
            assertTrue(post.newsPost)
            assertEquals(listOf(followup), model.visibleFollowups(post.id))
            assertEquals(0, client.acceptedConsentCount)
            assertTrue(client.sent.isEmpty())

            // The consent sheet stores the consent, then hands it to the chat
            client.acceptConsent()
            model.acceptConsent()
            assertEquals(true, model.hasConsent)
            assertEquals(AgentVM.State.READY, model.state)
            assertFalse(model.isThreadStarted)
            assertTrue(model.sendFollowup(post.id, followup.id))
            // The question counts at once, before the list learns of it
            assertTrue(model.isThreadStarted)
            withTimeout(1_000) { runStarted.await() }
            assertEquals(listOf(followup.text to null), client.sent)
            assertEquals(1, client.acceptedConsentCount)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun emptyNewsThreadUsesPreviewAndQueuesFirstQuestionAsAnOrdinaryAppend() = runBlocking {
        val historyRequested = CompletableDeferred<Unit>()
        val historyLoaded = CompletableDeferred<Unit>()
        val client = FakeNewsClient(newsThread().copy(news = null)).apply {
            onMessages = {
                historyRequested.complete(Unit)
                historyLoaded.await()
            }
        }
        val request = AgentNewsChatRequest(42, "en", "Feed headline", body = "Full news body")
        val opening = AgentChatOpening(news = request, client = client)
        val thread = checkNotNull(opening.create())
        assertEquals(request.newsPostCard(), thread.news)
        val model = newModel(client, thread, opening)
        try {
            withTimeout(1_000) { historyRequested.await() }
            assertEquals(AgentVM.State.LOADING, model.state)
            assertTrue(model.messages.isEmpty())
            assertTrue(model.visibleHints.isEmpty())
            assertTrue(client.hintRequests.isEmpty())
            assertFalse(model.hasUnsentOpening)
            assertTrue(client.sent.isEmpty())
            assertTrue(model.sendMessage("  Why does this matter? \n"))
            assertTrue(client.sent.isEmpty())
            historyLoaded.complete(Unit)
            awaitReady(model)
            assertEquals(listOf("Why does this matter?" to null), client.sent)
            assertTrue(model.visibleHints.isEmpty())
            assertTrue(client.hintRequests.isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun existingNewsThreadLoadsHistoryWithoutSending() = runBlocking {
        val existingMessage = AgentV2PersistedMessage(
            "message",
            "news-thread",
            "user",
            "complete",
            content = AgentV2MessageContent.Markdown(checkNotNull(newsThread().news).headline),
            createdAt = "2026-10-20T00:00:00Z"
        )
        val client = FakeNewsClient(newsThread().copy(messageCount = 1), listOf(existingMessage))
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "Feed headline"),
            client = client
        )
        assertTrue(opening.messages.isEmpty())

        val thread = checkNotNull(opening.create())
        val model = newModel(client, thread, opening)
        try {
            awaitReady(model)
            assertEquals(
                existingMessage.content,
                AgentV2MessageContent.Markdown(model.messages.single().text)
            )
            assertEquals(1, client.messageRequests)
            assertTrue(model.visibleFollowups(existingMessage.id).isEmpty())
            assertTrue(model.visibleHints.isEmpty())
            yield()
            assertTrue(client.hintRequests.isEmpty())
            assertTrue(client.sent.isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun emptyOrdinaryThreadLoadsAndShowsStarterHints() = runBlocking {
        val thread = AgentV2ThreadSummary("empty-thread", 1)
        val client = FakeNewsClient(thread)
        val model = newModel(client, thread)
        try {
            awaitReady(model)
            withTimeout(1_000) {
                while (model.visibleHints.isEmpty()) yield()
            }
            assertEquals(listOf("en"), client.hintRequests)
            // Contact Support follows the server's hints
            assertEquals(
                listOf("learn.staking", AGENT_SUPPORT_HINT_ID),
                model.visibleHints.map { it.id }
            )
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun discussionReusesTheLiveSessionWithoutCreatingOrReloadingTheThread() = runBlocking {
        val thread = newsThread().copy(
            id = "retained-discussion",
            title = "Agent title",
            icon = "📰",
            messageCount = 1
        )
        val existingMessage = AgentV2PersistedMessage(
            "message",
            thread.id,
            "user",
            "complete",
            content = AgentV2MessageContent.Markdown("Existing question"),
            createdAt = "2026-10-20T00:00:00Z"
        )
        val client = FakeNewsClient(thread, listOf(existingMessage))
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "Feed headline", "💬", thread.id),
            client = client
        )
        val owners = mutableListOf<AgentVM>()
        try {
            assertTrue(opening.messages.isEmpty())
            val model = checkNotNull(
                opening.acquireDiscussion { summary ->
                    AgentSession.acquire(summary) { newModel(client, summary) }
                }
            ).also(owners::add)
            awaitReady(model)
            assertEquals("Existing question", model.messages.single().text)
            assertEquals(thread.title, model.currentThread.title)
            assertEquals(thread.icon, model.currentThread.icon)
            AgentSession.acquire(model.currentThread) {
                error("The feed owner must reuse the discussion session")
            }.also(owners::add)
            val renamedThread = thread.copy(title = "Current title", icon = "🔎")
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(AgentV2Update.ThreadChanged(thread.id, renamedThread))
            )
            val currentMessages = model.messages.toList()
            AgentSession.release(model)
            owners.removeAt(0)

            val reopened = checkNotNull(
                opening.acquireDiscussion { summary ->
                    AgentSession.acquire(summary) {
                        error("Reopening must preserve the live session")
                    }
                }
            ).also(owners::add)

            assertSame(model, reopened)
            assertEquals(renamedThread.title, reopened.currentThread.title)
            assertEquals(renamedThread.icon, reopened.currentThread.icon)
            assertEquals(currentMessages, reopened.messages)
            assertEquals(1, client.messageRequests)
            assertTrue(client.newsRequests.isEmpty())
            assertTrue(client.sent.isEmpty())
        } finally {
            owners.forEach(AgentSession::release)
        }
    }

    @Test
    fun missingDiscussionIsRecreatedWithoutSending() = runBlocking {
        val oldThreadId = "deleted-discussion"
        val client = FakeNewsClient(newsThread()).apply {
            onMessages = { threadId ->
                if (threadId == oldThreadId) {
                    throw AgentV2OperationException(
                        AgentV2MutationError("thread_not_found", retryable = false)
                    )
                }
            }
        }
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "Feed headline", threadId = oldThreadId),
            client = client
        )
        val owners = mutableListOf<AgentVM>()
        try {
            val missing = checkNotNull(
                opening.acquireDiscussion { summary ->
                    AgentSession.acquire(summary) { newModel(client, summary) }
                }
            ).also(owners::add)
            withTimeout(1_000) {
                while (missing.state != AgentVM.State.ERROR) yield()
            }
            assertEquals("thread_not_found", missing.startupErrorCode)
            assertTrue(client.newsRequests.isEmpty())
            assertTrue(client.sent.isEmpty())
            assertTrue(opening.recreateMissingDiscussion(missing.startupErrorCode))
            assertNull(opening.acquireDiscussion())
            assertTrue(opening.messages.isEmpty())
            AgentSession.release(missing)
            owners.removeAt(0)

            val thread = checkNotNull(opening.create())
            val recreated = AgentSession.acquire(thread) {
                newModel(client, thread, opening)
            }.also(owners::add)
            awaitReady(recreated)

            assertEquals(listOf(AgentV2ThreadNewsRequest(42, "en")), client.newsRequests)
            assertEquals(2, client.messageRequests)
            assertTrue(recreated.messages.isEmpty())
            assertTrue(client.sent.isEmpty())
        } finally {
            owners.forEach(AgentSession::release)
        }
    }

    @Test
    fun newsHistoryFailureUsesReadErrorCopyAndRetriesWithoutSending() = runBlocking {
        val thread = newsThread()
        var failureCode = "action_unsupported"
        val client = FakeNewsClient(thread).apply {
            onMessages = {
                throw AgentV2OperationException(
                    AgentV2MutationError(failureCode, retryable = true)
                )
            }
        }
        val model = newModel(client, thread)
        try {
            withTimeout(1_000) {
                while (model.state != AgentVM.State.ERROR) yield()
            }
            assertEquals("action_unsupported", model.startupErrorCode)
            assertEquals(
                LocaleController.getString("Failed to load chat"),
                model.messages.last().text
            )
            assertTrue(model.messages.last().isFailure)

            failureCode = "network_error"
            checkNotNull(model.failureRetry).invoke()
            withTimeout(1_000) {
                while (model.state != AgentVM.State.ERROR) yield()
            }
            assertEquals("network_error", model.startupErrorCode)
            assertEquals(
                LocaleController.getString("\$agent_connection_lost"),
                model.messages.last().text
            )

            client.onMessages = {}
            checkNotNull(model.failureRetry).invoke()
            awaitReady(model)
            assertEquals(3, client.messageRequests)
            assertNull(model.startupErrorCode)
            assertTrue(client.newsRequests.isEmpty())
            assertTrue(client.sent.isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun newsCreationFailureAndRetryNeverCreateStreamingMessagesOrSend() = runBlocking {
        val unavailable = IllegalStateException("news_unavailable")
        val client = FakeNewsClient(newsThread()).apply { onCreate = { throw unavailable } }
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "Feed headline"),
            client = client
        )

        assertNull(opening.create())
        assertSame(unavailable, opening.error)
        assertTrue(opening.messages.isEmpty())
        assertTrue(client.sent.isEmpty())

        val retried = CompletableDeferred<Unit>()
        client.onCreate = { retried.await() }
        val retry = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }
        assertFalse(retry.isCompleted)
        assertNull(opening.error)
        assertTrue(opening.messages.isEmpty())
        retried.complete(Unit)

        val thread = checkNotNull(retry.await())
        val model = newModel(client, thread, opening)
        try {
            awaitReady(model)
            assertTrue(opening.messages.isEmpty())
            assertTrue(model.messages.isEmpty())
            assertEquals(2, client.newsRequests.size)
            assertTrue(client.sent.isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun newsReopenedDuringClearNeverSendsAfterClearCompletes() = runBlocking {
        val thread = newsThread()
        val clearApplied = CompletableDeferred<Unit>()
        val clearResponse = CompletableDeferred<Unit>()
        val client = FakeNewsClient(thread).apply {
            onClear = {
                clearApplied.complete(Unit)
                clearResponse.await()
            }
        }
        val sessions = modelSessions()
        val model = sessions.acquire(thread.id) { newModel(client, thread) }
        try {
            awaitReady(model)
            model.clearChat()
            withTimeout(1_000) { clearApplied.await() }
            assertEquals(AgentVM.State.CLEARING, model.state)
            sessions.release(thread.id, model)

            val opening = AgentChatOpening(
                news = AgentNewsChatRequest(42, "en", "Feed headline"),
                client = client
            )
            val reopenedThread = checkNotNull(opening.create())
            val retained = sessions.acquire(reopenedThread.id) {
                error("The clearing session must be retained")
            }
            assertSame(model, retained)
            repeat(2) { retained.acceptOpening(opening.messages, opening.entryPoint) }
            assertTrue(retained.messages.isEmpty())
            assertTrue(client.sent.isEmpty())

            clearResponse.complete(Unit)
            awaitReady(retained)
            retained.retry()
            yield()
            assertEquals(thread.revision + 1, retained.currentThread.revision)
            assertEquals(thread.news, retained.currentThread.news)
            assertTrue(retained.messages.isEmpty())
            assertTrue(retained.visibleHints.isEmpty())
            assertTrue(client.hintRequests.isEmpty())
            assertTrue(client.sent.isEmpty())
            sessions.release(reopenedThread.id, retained)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun failedNewsHydrationCanBeRetriedWithoutSending() = runBlocking {
        val client = FakeNewsClient(newsThread()).apply {
            onMessages = { error("offline") }
        }
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "Feed headline"),
            client = client
        )
        val thread = checkNotNull(opening.create())
        val model = newModel(client, thread, opening)
        try {
            withTimeout(1_000) {
                while (model.state != AgentVM.State.ERROR) yield()
            }
            assertTrue(model.messages.all { it.role == AgentMessageRole.SYSTEM && !it.isStreaming })
            assertTrue(client.sent.isEmpty())
            client.onMessages = {}
            model.retry()
            awaitReady(model)
            model.retry()
            yield()
            assertEquals(2, client.messageRequests)
            assertFalse(model.hasUnsentOpening)
            assertTrue(model.messages.all { it.role == AgentMessageRole.SYSTEM && !it.isStreaming })
            assertTrue(client.sent.isEmpty())
        } finally {
            model.onDestroy()
        }

        for (isDigest in listOf(false, true)) {
            val supportClient = FakeNewsClient(createDiscussionThread(isDigest)).apply {
                onMessages = {
                    if (isDigest) {
                        throw AgentV2OperationException(
                            AgentV2MutationError("thread_not_found", retryable = false)
                        )
                    }
                    error("offline")
                }
            }
            val supportOpening = createDeferredDiscussionOpening(supportClient, isDigest)
            supportOpening.readConsent()
            assertTrue(supportOpening.stageSupportRequest())
            val supportMessageId = supportOpening.messages.single().id
            val supportThread = checkNotNull(supportOpening.create())
            val supportModel = newModel(supportClient, supportThread, supportOpening)
            val question = AgentMessage(role = AgentMessageRole.USER, text = "Ordinary question")
            supportModel.acceptOpening(listOf(question), AgentV2EntryPoint())
            try {
                withTimeout(1_000) {
                    while (supportModel.state != AgentVM.State.ERROR) yield()
                }
                val hasFailedSupportMessage = supportModel.messages.any {
                    it.id == supportMessageId
                }
                if (isDigest) {
                    assertTrue(
                        supportOpening.recreateMissingDiscussion(supportModel.startupErrorCode)
                    )
                    assertNull(supportOpening.create())
                    assertTrue(supportOpening.messages.isEmpty())
                }
                supportClient.onMessages = {}
                supportModel.retry()
                awaitReady(supportModel)
                yield()
                assertEquals(listOf(question.text to null), supportClient.sent)
                assertFalse(hasFailedSupportMessage)
                assertEquals(
                    listOf(question.id),
                    supportModel.messages.filter { it.role == AgentMessageRole.USER }.map { it.id }
                )
                assertFalse(supportModel.hasUnsentOpening)
            } finally {
                supportModel.onDestroy()
            }
        }
    }

    @Test
    fun clearDiscardsAnOlderHistoryPageThatArrivesAfterItCompletes() = runBlocking {
        val thread = AgentV2ThreadSummary("chat", revision = 2, title = "Current title")
        val page = CompletableDeferred<AgentV2ThreadHydration>()
        val requested = CompletableDeferred<Job>()
        val latest = AgentV2PersistedMessage(
            "latest",
            thread.id,
            "user",
            "complete",
            content = AgentV2MessageContent.Markdown("Latest question"),
            createdAt = "2026-10-20T00:00:00Z"
        )
        val client = object : AgentV2Client by FakeNewsClient(thread) {
            override suspend fun messages(
                threadId: String,
                cursor: String?,
                limit: Int
            ): AgentV2ThreadHydration {
                if (cursor == null) {
                    return AgentV2ThreadHydration(thread, listOf(latest), "older")
                }
                assertEquals("older", cursor)
                requested.complete(currentCoroutineContext()[Job]!!)
                return withContext(NonCancellable) { page.await() }
            }
        }
        val model = newModel(client, thread)
        try {
            awaitReady(model)
            model.loadOlderMessages()
            val historyJob = withTimeout(1_000) { requested.await() }

            model.clearChat()
            awaitReady(model)
            val clearedThread = model.currentThread
            assertTrue(model.messages.isEmpty())
            assertNull(model.historyCursor)

            page.complete(
                AgentV2ThreadHydration(
                    thread.copy(title = "Outdated title"),
                    listOf(
                        latest.copy(
                            id = "older",
                            content = AgentV2MessageContent.Markdown("Old question")
                        )
                    ),
                    "old-cursor"
                )
            )
            withTimeout(1_000) { historyJob.join() }

            assertTrue(model.messages.isEmpty())
            assertNull(model.historyCursor)
            assertEquals(clearedThread, model.currentThread)
        } finally {
            page.complete(AgentV2ThreadHydration(thread, emptyList()))
            model.onDestroy()
        }
    }

    @Test
    fun newsDiscussionOffersAProblemReportBeforeItsThreadAndSendsAHeldReportOnce() = runBlocking {
        val created = CompletableDeferred<Unit>()
        val client = FakeNewsClient(newsThread()).apply {
            onCreate = { created.await() }
            isProblemReportAvailable = true
        }
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "News"),
            client = client
        )
        val creation = async { opening.create() }
        opening.readConsent()
        withTimeout(1_000) {
            while (!opening.isCreating) yield()
        }
        // The thread is still being created, and the server hasn't been asked whether it takes reports
        assertTrue(opening.canReportProblem)
        val results = mutableListOf<Boolean>()
        opening.reportProblem("Wrong summary") { results += it }
        yield()
        assertTrue(results.isEmpty())

        created.complete(Unit)
        val thread = checkNotNull(creation.await())
        val model = newModel(client, thread, opening)
        try {
            opening.releaseHeldReports { comment, onResult ->
                model.reportProblem(null, comment, onResult)
            }
            opening.releaseHeldReports { _, _ -> fail("A held report is handed over once") }
            withTimeout(1_000) {
                while (results.isEmpty()) yield()
            }
            assertEquals(listOf(true), results)
            assertEquals(listOf(thread.id to "Wrong summary"), client.reports)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun failedNewsDiscussionFailsItsHeldProblemReport() = runBlocking {
        val created = CompletableDeferred<Unit>()
        val client = FakeNewsClient(newsThread()).apply {
            onCreate = {
                created.await()
                error("offline")
            }
        }
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "News"),
            client = client
        )
        val creation = async { opening.create() }
        opening.readConsent()
        withTimeout(1_000) {
            while (!opening.isCreating) yield()
        }
        val results = mutableListOf<Boolean>()
        opening.reportProblem("Wrong summary") { results += it }

        created.complete(Unit)
        assertNull(creation.await())
        assertEquals(listOf(false), results)
        assertFalse(opening.canReportProblem)
        assertTrue(client.reports.isEmpty())
    }

    @Test
    fun chatOpeningOffersAProblemReportFromItsFirstFrameWithTheConsentTheAppKnows() = runBlocking {
        val client = FakeNewsClient(newsThread()).apply {
            isConsentKnownGiven = true
            hasConsent = false
        }
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "News"),
            client = client
        )
        assertTrue(opening.canReportProblem)
        // The opening's own read decides
        opening.readConsent()
        assertFalse(opening.canReportProblem)
    }

    @Test
    fun newsDiscussionOffersNoProblemReportBeforeConsent() = runBlocking {
        val client = FakeNewsClient(newsThread()).apply { hasConsent = false }
        val opening = AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "News"),
            client = client
        )
        opening.readConsent()
        assertFalse(opening.canReportProblem)
    }

    private fun verifyDeferredHeaderSupport(isDigest: Boolean) = runBlocking {
        val created = CompletableDeferred<Unit>()
        val historyRequested = CompletableDeferred<Unit>()
        val historyLoaded = CompletableDeferred<Unit>()
        val runStarted = CompletableDeferred<Unit>()
        val thread = createDiscussionThread(isDigest).copy(messageCount = 1)
        val post = AgentV2PersistedMessage(
            "post",
            thread.id,
            "assistant",
            "complete",
            content = AgentV2MessageContent.Markdown("Post context"),
            createdAt = "2026-10-20T00:00:00Z",
            newsPost = true
        )
        val client = FakeNewsClient(thread, listOf(post)).apply {
            hasConsent = false
            onCreate = { created.await() }
            onMessages = {
                historyRequested.complete(Unit)
                historyLoaded.await()
            }
            onStartRun = { runStarted.complete(Unit) }
        }
        val opening = createDeferredDiscussionOpening(client, isDigest)
        opening.readConsent()
        assertFalse(opening.canRequestSupport)
        client.hasConsent = true
        opening.readConsent()
        assertNull(opening.create())
        assertTrue(opening.canRequestSupport)
        opening.onBridgeUpdate(
            ApiUpdate.ApiUpdateAgentV2(
                AgentV2Update.UserQuotaChanged(
                    AgentV2UserQuota(10, 10, 0, "2099-01-01T00:00:00Z")
                )
            )
        )
        assertFalse(opening.canSubmitDiscussionMessage)
        assertTrue(opening.stageSupportRequest())
        assertFalse(opening.canRequestSupport)
        assertFalse(opening.stageSupportRequest())
        val creation = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }
        assertNull(opening.create())
        assertEquals(
            listOf(AgentV2ThreadNewsRequest(42, "en").takeUnless { isDigest }),
            client.newsRequests
        )
        assertEquals(
            listOf(AgentV2ThreadDigestRequest(DIGEST_ID).takeIf { isDigest }),
            client.digestRequests
        )
        created.complete(Unit)
        val createdThread = checkNotNull(creation.await())
        assertEquals(createdThread, opening.create())
        val model = newModel(client, createdThread, opening)
        try {
            withTimeout(1_000) { historyRequested.await() }
            assertFalse(model.canRequestSupport)
            assertTrue(client.sent.isEmpty())
            historyLoaded.complete(Unit)
            withTimeout(1_000) { runStarted.await() }
            awaitReady(model)
            model.retry()
            yield()
            assertEquals(
                listOf(
                    getAgentSupportRequestText() to
                        AgentV2EntryPoint.supportRequest(AgentV2SupportRequestSource.HEADER)
                ),
                client.sent
            )
            assertEquals(listOf<AgentV2FollowUpReference?>(null), client.sentFollowups)
            assertEquals("Post context", model.messages.single { it.newsPost }.text)
            assertEquals(1, model.messages.count { it.role == AgentMessageRole.USER })
            assertEquals(1, client.newsRequests.size)
        } finally {
            historyLoaded.complete(Unit)
            model.onDestroy()
        }

        val supportThread = createdThread.copy(support = AgentV2ThreadSupport("waiting"))
        val supportClient = FakeNewsClient(supportThread, listOf(post))
        val supportModel = newModel(supportClient, supportThread, opening)
        try {
            awaitReady(supportModel)
            yield()
            assertTrue(supportClient.sent.isEmpty())
            assertTrue(supportModel.messages.none { it.role == AgentMessageRole.USER })
            assertFalse(supportModel.hasUnsentOpening)
        } finally {
            supportModel.onDestroy()
        }

        val failedClient = FakeNewsClient(thread).apply {
            onCreate = { error("Creation failed") }
        }
        val failedOpening = createDeferredDiscussionOpening(failedClient, isDigest)
        failedOpening.readConsent()
        assertTrue(failedOpening.stageSupportRequest())
        assertNull(failedOpening.create())
        assertTrue(failedOpening.messages.isEmpty())
        assertFalse(failedOpening.hasStagedMessage)
        assertTrue(failedClient.sent.isEmpty())
        assertNull(failedOpening.create())
        assertEquals(1, failedClient.newsRequests.size)
    }

    private fun verifyDeferredHeaderSupportWalletChanges(shouldSwitchDuringHydration: Boolean) =
        testDeferredDiscussions { isDigest ->
            val originalAccountId = AccountStore.activeAccountId
            try {
                for (shouldReturnToWallet in listOf(false, true)) {
                    AccountStore.updateActiveAccount("wallet-a")
                    val created = CompletableDeferred<Unit>()
                    val historyRequested = CompletableDeferred<Unit>()
                    val historyLoaded = CompletableDeferred<Unit>()
                    val client = FakeNewsClient(createDiscussionThread(isDigest)).apply {
                        onCreate = { created.await() }
                        onMessages = {
                            historyRequested.complete(Unit)
                            historyLoaded.await()
                        }
                    }
                    val opening = createDeferredDiscussionOpening(client, isDigest)
                    opening.readConsent()
                    assertTrue(opening.stageSupportRequest())
                    val creation = async(start = CoroutineStart.UNDISPATCHED) { opening.create() }
                    var model: AgentVM? = null
                    try {
                        if (shouldSwitchDuringHydration) {
                            created.complete(Unit)
                            model = newModel(client, checkNotNull(creation.await()), opening)
                            withTimeout(1_000) { historyRequested.await() }
                        }
                        WalletCore.notifyEvent(WalletEvent.AccountWillChange(fromHome = false))
                        AccountStore.updateActiveAccount("wallet-b")
                        WalletCore.notifyEvent(WalletEvent.AccountChanged())
                        if (shouldReturnToWallet) {
                            WalletCore.notifyEvent(WalletEvent.AccountWillChange(fromHome = false))
                            AccountStore.updateActiveAccount("wallet-a")
                            WalletCore.notifyEvent(WalletEvent.AccountChanged())
                        }
                        if (!shouldSwitchDuringHydration) {
                            created.complete(Unit)
                            model = newModel(client, checkNotNull(creation.await()), opening)
                        }
                        withTimeout(1_000) { historyRequested.await() }
                        historyLoaded.complete(Unit)
                        awaitReady(checkNotNull(model))
                        yield()
                        assertTrue(client.sent.isEmpty())
                        assertTrue(model.messages.none { it.role == AgentMessageRole.USER })
                        assertFalse(model.hasUnsentOpening)
                    } finally {
                        created.complete(Unit)
                        historyLoaded.complete(Unit)
                        model?.onDestroy()
                    }
                }
            } finally {
                AccountStore.updateActiveAccount(originalAccountId)
            }
        }

    private fun testDeferredDiscussions(test: suspend CoroutineScope.(Boolean) -> Unit) =
        runBlocking {
            for (isDigest in listOf(false, true)) test(isDigest)
        }

    private fun createDeferredDiscussionOpening(client: AgentV2Client, isDigest: Boolean) =
        AgentChatOpening(
            news = AgentNewsChatRequest(42, "en", "Feed headline", shouldDeferCreation = true)
                .takeUnless { isDigest },
            client = client,
            digestId = DIGEST_ID.takeIf { isDigest },
            shouldDeferCreation = isDigest
        )

    private fun createDiscussionThread(isDigest: Boolean) = if (isDigest) {
        newsThread().copy(
            news = null,
            digest = AgentV2ThreadDigestCard(
                DIGEST_ID,
                "2026-11-08T18:00:00.000Z",
                1,
                listOf(AgentV2NewsDigestHeadline(42, "Headline"))
            )
        )
    } else {
        newsThread()
    }

    private fun CoroutineScope.newModel(
        client: AgentV2Client,
        thread: AgentV2ThreadSummary,
        opening: AgentChatOpening? = null
    ): AgentVM {
        val modelScope = CoroutineScope(coroutineContext + SupervisorJob(coroutineContext[Job]))
        return AgentVM(
            client = client,
            initialThread = thread,
            initialMessages = opening?.messages.orEmpty(),
            initialOpeningEntryPoint = opening?.entryPoint?.takeIf {
                opening.messages.isNotEmpty()
            },
            initialOpeningFollowupText = opening?.followupText,
            initialOpeningAuthority = opening?.messageAuthority,
            cachedHistories = AgentCachedHistories(this) { null },
            scope = modelScope,
            contextProvider = AgentV2HostContextProvider(client, modelScope) {
                AgentHostContextSnapshot(AccountStore.activeAccountId, JSONObject())
            }
        )
    }

    private fun modelSessions() = AgentThreadSessions<AgentVM>(
        shouldRetain = { it.shouldRetainSession },
        setIdleHandler = { model, handler -> model.onSessionIdle = handler },
        destroy = { it.onDestroy() }
    )

    private suspend fun awaitReady(model: AgentVM) = withTimeout(1_000) {
        while (model.state != AgentVM.State.READY) {
            assertFalse("Model startup failed", model.state == AgentVM.State.ERROR)
            yield()
        }
    }

    private fun newsThread() = AgentV2ThreadSummary(
        "news-thread",
        revision = 1,
        news = AgentV2ThreadNewsCard(
            42,
            headline = "  Server headline differs from the feed \n",
            publishedAt = "2026-10-20T00:00:00Z"
        )
    )

    private class FakeNewsClient(
        private val thread: AgentV2ThreadSummary,
        private val history: List<AgentV2PersistedMessage> = emptyList()
    ) : AgentV2Client by LiveAgentV2Client() {
        val newsRequests = mutableListOf<AgentV2ThreadNewsRequest?>()
        val digestRequests = mutableListOf<AgentV2ThreadDigestRequest?>()
        val hintRequests = mutableListOf<String?>()
        val sent = mutableListOf<Pair<String, AgentV2EntryPoint?>>()
        val sentFollowups = mutableListOf<AgentV2FollowUpReference?>()
        val sentRevisions = mutableListOf<Int>()
        val deletedThreads = mutableListOf<String>()
        var onConsent: suspend () -> Unit = {}
        var onCreate: suspend () -> Unit = {}
        var onDelete: suspend () -> Unit = {}
        var onMessages: suspend (String) -> Unit = {}
        var onUpdateHostContext: suspend () -> Unit = {}
        var onClear: suspend () -> Unit = {}
        var onStartRun: suspend () -> Unit = {}
        var onLoadAvailability: suspend () -> Unit = {}
        var onLoadUserQuota: suspend () -> Unit = {}
        var availabilityRequests = 0
            private set
        var quotaRequests = 0
            private set
        val startedRunIds = mutableListOf<String>()
        var hasConsent = true
        var acceptedConsentCount = 0
            private set
        var messageRequests = 0
            private set
        var isProblemReportAvailable = false
        val reports = mutableListOf<Pair<String, String?>>()
        override var isConsentKnownGiven = false

        override suspend fun consent(): Boolean {
            onConsent()
            return hasConsent
        }
        override suspend fun acceptConsent() {
            acceptedConsentCount++
            hasConsent = true
        }
        override suspend fun updateHostContext(context: JSONObject?) = onUpdateHostContext()
        override suspend fun loadAvailability() {
            availabilityRequests++
            onLoadAvailability()
        }
        override suspend fun loadUserQuota() {
            quotaRequests++
            onLoadUserQuota()
        }
        override suspend fun problemReportAvailability() = isProblemReportAvailable
        override suspend fun reportProblem(threadId: String, messageId: String?, comment: String?) {
            reports += threadId to comment
        }

        override suspend fun hints(langCode: String?): AgentV2HintsResponse {
            hintRequests += langCode
            return AgentV2HintsResponse(3, "catalog", listOf(AgentV2StarterHint("learn.staking")))
        }

        override suspend fun createThread(
            news: AgentV2ThreadNewsRequest?,
            digest: AgentV2ThreadDigestRequest?
        ): AgentV2ThreadCreateResponse {
            newsRequests += news
            digestRequests += digest
            onCreate()
            return AgentV2ThreadCreateResponse(thread, created = false)
        }

        override suspend fun deleteThread(threadId: String): AgentV2ThreadDeleteResponse {
            assertEquals(thread.id, threadId)
            deletedThreads += threadId
            onDelete()
            return AgentV2ThreadDeleteResponse(threadId, duplicate = false)
        }

        override suspend fun messages(
            threadId: String,
            cursor: String?,
            limit: Int
        ): AgentV2ThreadHydration {
            messageRequests++
            onMessages(threadId)
            assertEquals(thread.id, threadId)
            return AgentV2ThreadHydration(thread, history)
        }

        override suspend fun getCachedMessages(threadId: String): AgentV2CachedMessages? = null

        override suspend fun clearThread(threadId: String, revision: Int): AgentV2ThreadResponse {
            assertEquals(thread.id, threadId)
            onClear()
            return AgentV2ThreadResponse(
                thread.copy(revision = revision + 1, messageCount = 0, news = null)
            )
        }

        override suspend fun startRun(
            clientRunId: String,
            threadId: String?,
            revision: Int,
            text: String,
            entryPoint: AgentV2EntryPoint?,
            followupOf: AgentV2FollowUpReference?,
            targetUserMessageId: String?,
            targetAssistantMessageId: String?
        ): AgentV2RunResult {
            assertEquals(thread.id, threadId)
            if (AgentV2EntryPoint.isSupportRequest(entryPoint)) {
                assertNull(targetUserMessageId)
                assertNull(targetAssistantMessageId)
            }
            sent += text to entryPoint
            sentFollowups += followupOf
            sentRevisions += revision
            startedRunIds += clientRunId
            onStartRun()
            return AgentV2RunResult(clientRunId, state = "completed")
        }
    }

    companion object {
        private const val DIGEST_ID = "en:2026-11-08T18:00:00.000Z"
        private var previousLanguage: WLanguage? = null

        @JvmStatic
        @BeforeClass
        fun initializeEmptyWalletStorage() {
            LocaleController::class.java.getDeclaredField("_activeLanguage").apply {
                isAccessible = true
                previousLanguage = get(null) as WLanguage?
                set(null, WLanguage.ENGLISH)
            }
            val storage = Proxy.newProxyInstance(
                IGlobalStorageProvider::class.java.classLoader,
                arrayOf(IGlobalStorageProvider::class.java)
            ) { _, method, _ ->
                when (method.name) {
                    "contains" -> false

                    "keysIn" -> emptyArray<String>()

                    "getInt", "getString", "getBool", "getDict", "getArray",
                    "incrementDoNotSynchronize", "decrementDoNotSynchronize",
                    "set", "setEmptyObject", "setEmptyObjects", "remove" -> null

                    else -> error("Unexpected wallet storage call: ${method.name}")
                }
            } as IGlobalStorageProvider
            WGlobalStorage.init(storage)
        }

        @JvmStatic
        @AfterClass
        fun restoreLanguage() {
            LocaleController::class.java.getDeclaredField("_activeLanguage").apply {
                isAccessible = true
                set(null, previousLanguage)
            }
        }
    }
}
