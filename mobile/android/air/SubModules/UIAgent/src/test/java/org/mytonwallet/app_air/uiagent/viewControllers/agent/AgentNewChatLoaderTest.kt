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
import kotlinx.coroutines.currentCoroutineContext
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
import org.mytonwallet.app_air.uiagent.agentV2.AgentHostContextSnapshot
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2HostContextProvider
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUpReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2HintsResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationError
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2StarterHint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadCreateResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDeleteResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

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
                        "run",
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
                        "run",
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
                        "run",
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
                        "run",
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
                        "run",
                        "server-run-$index",
                        firstThread.id,
                        firstThread.revision,
                        "user-sdk-$index"
                    ),
                    AgentV2Update.MessageStarted(
                        "run",
                        "server-run-$index",
                        firstThread.id,
                        "answer-sdk-$index",
                        "markdown"
                    ),
                    AgentV2Update.TextDelta(
                        "run",
                        "server-run-$index",
                        firstThread.id,
                        "answer-sdk-$index",
                        "Answer $index"
                    ),
                    AgentV2Update.MessageCompleted(
                        "run",
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
    fun deletingPreparedOpeningBlocksLateStartupAndSurvivesSessionDestruction() = runBlocking {
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
            model.deleteChat { deletionFailure.complete(it) }
            model.deleteChat { fail("Deletion must be idempotent") }
            assertFalse(model.shouldRetainSession)
            sessions.release(thread.id, model)
            assertTrue(sessions.getModels().isEmpty())
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
        } finally {
            contextReleased.complete(Unit)
            deletionFinished.complete(Unit)
            model.onDestroy()
        }
    }

    @Test
    fun deletingChatCancelsUnsentRunBeforeAndAfterHostContextWait() = runBlocking {
        for (waitForHostContext in listOf(false, true)) {
            val thread = AgentV2ThreadSummary("empty-thread", 1)
            val deleted = CompletableDeferred<Unit>()
            val contextStarted = CompletableDeferred<Job>()
            val contextReleased = CompletableDeferred<Unit>()
            val client = FakeNewsClient(thread).apply { onDelete = { deleted.complete(Unit) } }
            val modelScope = CoroutineScope(coroutineContext + SupervisorJob(coroutineContext[Job]))
            val provider = AgentV2HostContextProvider(client, modelScope) {
                AgentHostContextSnapshot(null, JSONObject())
            }
            val model = AgentVM(
                client = client,
                initialThread = thread,
                scope = modelScope,
                contextProvider = provider
            )
            try {
                awaitReady(model)
                if (waitForHostContext) {
                    client.onUpdateHostContext = {
                        contextStarted.complete(checkNotNull(currentCoroutineContext()[Job]))
                        withContext(NonCancellable) { contextReleased.await() }
                    }
                    provider.onWalletEvent(WalletEvent.BalanceChanged)
                }
                assertTrue(model.sendMessage("Question"))
                val pendingRun = if (waitForHostContext) {
                    withTimeout(1_000) { contextStarted.await() }
                } else {
                    null
                }
                assertTrue(client.sent.isEmpty())
                model.deleteChat { fail("Deletion should succeed") }
                model.onDestroy()
                withTimeout(1_000) { deleted.await() }
                contextReleased.complete(Unit)
                withTimeout(1_000) { pendingRun?.join() }
                assertTrue(client.sent.isEmpty())
                assertEquals(listOf(thread.id), client.deletedThreads)
            } finally {
                contextReleased.complete(Unit)
                model.onDestroy()
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
                    "run",
                    "server-run",
                    thread.id,
                    thread.revision,
                    "question"
                ),
                AgentV2Update.MessageStarted("run", "server-run", thread.id, "answer", "markdown"),
                AgentV2Update.TextDelta("run", "server-run", thread.id, "answer", "News analysis"),
                AgentV2Update.MessageCompleted("run", "server-run", thread.id, "answer", "complete")
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
            assertEquals(listOf("learn.staking"), model.visibleHints.map { it.id })
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
            scope = modelScope,
            contextProvider = AgentV2HostContextProvider(client, modelScope) {
                AgentHostContextSnapshot(null, JSONObject())
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
        var hasConsent = true
        var acceptedConsentCount = 0
            private set
        var messageRequests = 0
            private set

        override suspend fun consent(): Boolean {
            onConsent()
            return hasConsent
        }
        override suspend fun acceptConsent() {
            acceptedConsentCount++
            hasConsent = true
        }
        override suspend fun updateHostContext(context: JSONObject?) = onUpdateHostContext()
        override suspend fun problemReportAvailability() = false

        override suspend fun hints(langCode: String?): AgentV2HintsResponse {
            hintRequests += langCode
            return AgentV2HintsResponse(3, "catalog", listOf(AgentV2StarterHint("learn.staking")))
        }

        override suspend fun createThread(
            news: AgentV2ThreadNewsRequest?
        ): AgentV2ThreadCreateResponse {
            newsRequests += news
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

        override suspend fun clearThread(threadId: String, revision: Int): AgentV2ThreadResponse {
            assertEquals(thread.id, threadId)
            onClear()
            return AgentV2ThreadResponse(
                thread.copy(revision = revision + 1, messageCount = 0, news = null)
            )
        }

        override suspend fun startRun(
            threadId: String?,
            revision: Int,
            text: String,
            entryPoint: AgentV2EntryPoint?,
            followupOf: AgentV2FollowUpReference?,
            targetUserMessageId: String?,
            targetAssistantMessageId: String?
        ): AgentV2RunResult {
            assertEquals(thread.id, threadId)
            sent += text to entryPoint
            sentFollowups += followupOf
            sentRevisions += revision
            onStartRun()
            return AgentV2RunResult("run", state = "completed")
        }
    }

    companion object {
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
