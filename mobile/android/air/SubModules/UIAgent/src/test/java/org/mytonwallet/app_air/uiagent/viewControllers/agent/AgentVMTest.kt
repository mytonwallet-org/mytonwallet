package org.mytonwallet.app_air.uiagent.viewControllers.agent

import java.lang.reflect.Proxy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
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
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.resolveAgentThreadTitle
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUpReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2HintsResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class AgentVMTest {
    @Test
    fun opensTheRequestedThreadWithoutLoadingTheDefaultConversation() = runBlocking {
        val selectedThread = AgentV2ThreadSummary("selected", 2)
        val hydration = AgentV2ThreadHydration(selectedThread.copy(revision = 3), emptyList())
        val requestedIds = mutableListOf<String>()

        val result = hydrateAgentThread(
            selectedThread,
            loadMessages = { threadId ->
                requestedIds += threadId
                hydration
            }
        )

        assertSame(hydration, result)
        assertEquals(listOf("selected"), requestedIds)
    }

    @Test
    fun refusesHistoryFromAnotherThread() = runBlocking {
        try {
            hydrateAgentThread(
                AgentV2ThreadSummary("selected", 1),
                loadMessages = {
                    AgentV2ThreadHydration(AgentV2ThreadSummary("other", 1), emptyList())
                }
            )
            fail("A different conversation must not be rendered in the selected thread")
        } catch (error: IllegalStateException) {
            assertEquals("Unexpected Agent thread", error.message)
        }
    }

    @Test
    fun showsTheLatestThreadTitleWithTheFirstQuestionAsFallback() {
        val thread =
            AgentV2ThreadSummary(
                "thread",
                1,
                title = "My title",
                icon = "💎",
                hasCustomTitle = true
            )
        assertEquals("My title", resolveAgentThreadTitle(thread, "First question", "New Chat"))
        assertEquals(
            "Agent title",
            resolveAgentThreadTitle(
                thread.copy(title = "Agent title", hasCustomTitle = null),
                "First question",
                "New Chat"
            )
        )
        assertEquals(
            "First question",
            resolveAgentThreadTitle(
                thread.copy(title = null, hasCustomTitle = null),
                "First question",
                "New Chat"
            )
        )
        assertEquals(
            "New Chat",
            resolveAgentThreadTitle(AgentV2ThreadSummary("empty", 1), null, "New Chat")
        )
    }

    @Test
    fun regenerationKeepsThePromptAndRemovesOnlyTheSelectedAnswerAndItsTail() {
        val prompt = AgentMessage(role = AgentMessageRole.USER, text = "Question")
        val answer = AgentMessage(
            id = "local-answer",
            sdkMessageId = "server-answer",
            role = AgentMessageRole.ASSISTANT,
            text = "Answer"
        )
        val laterPrompt = AgentMessage(role = AgentMessageRole.USER, text = "Later")
        val messages = listOf(prompt, answer, laterPrompt)
        assertEquals(listOf(prompt), agentMessagesBeforeRegeneration(messages, answer.id))
        assertEquals(
            listOf(prompt),
            agentMessagesBeforeRegeneration(messages, answer.sdkMessageId!!)
        )
        assertEquals(
            listOf(prompt, laterPrompt),
            agentMessagesBeforeRegeneration(messages, answer.id, listOf(laterPrompt))
        )
        assertNull(agentMessagesBeforeRegeneration(messages, prompt.id))
        assertNull(agentMessagesBeforeRegeneration(messages, "missing"))
    }

    @Test
    fun reportsOnlyTheServerIdOfAnAnswer() {
        val boundAnswer = AgentMessage(
            id = "local-bound",
            sdkMessageId = "server-answer",
            role = AgentMessageRole.ASSISTANT,
            text = "Answer"
        )
        val unboundAnswer = AgentMessage(
            id = "local-unbound",
            role = AgentMessageRole.ASSISTANT,
            text = "Answer"
        )
        val messages = listOf(boundAnswer, unboundAnswer)

        assertEquals("server-answer", resolveAgentReportMessageId(messages, boundAnswer.id))
        assertNull(resolveAgentReportMessageId(messages, unboundAnswer.id))
    }

    @Test
    fun editRemovesTheOriginalPromptAndItsConversationTail() {
        val earlier = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Earlier")
        val original = AgentMessage(
            id = "local-question",
            sdkMessageId = "server-question",
            role = AgentMessageRole.USER,
            text = "Original"
        )
        val answer = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Old answer")
        val later = AgentMessage(role = AgentMessageRole.USER, text = "Later question")
        val messages = listOf(earlier, original, answer, later)

        assertEquals(listOf(earlier), agentMessagesBeforeEdit(messages, original.id))
        assertEquals(listOf(earlier), agentMessagesBeforeEdit(messages, original.sdkMessageId!!))
        assertEquals(
            emptyList<AgentMessage>(),
            agentMessagesBeforeEdit(listOf(original), original.id)
        )
    }

    @Test
    fun editCannotTruncateAnAnswerOrAMissingTarget() {
        val answer = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Answer")
        assertNull(agentMessagesBeforeEdit(listOf(answer), answer.id))
        assertNull(agentMessagesBeforeEdit(listOf(answer), "missing"))
    }

    @Test
    fun retryAfterQuotaReplacesTheRegeneratedAnswer() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client)
        client.onStartRun = {
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        "client-run",
                        threadId = client.thread.id,
                        code = "user_quota_exhausted",
                        retryable = true
                    )
                )
            )
            AgentV2RunResult("client-run", state = "failed")
        }
        client.onRetryRun = { clientRunId ->
            assertEquals("client-run", clientRunId)
            listOf(
                AgentV2Update.RunStarted(clientRunId, "run", client.thread.id, 2),
                AgentV2Update.TextDelta(
                    clientRunId,
                    "run",
                    client.thread.id,
                    "new-answer",
                    "New answer"
                ),
                AgentV2Update.MessageCompleted(
                    clientRunId,
                    "run",
                    client.thread.id,
                    "new-answer",
                    "complete"
                )
            ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
            AgentV2RunResult(clientRunId, "run", state = "completed")
        }
        try {
            awaitReady(model)
            assertTrue(model.regenerateMessage("answer"))
            awaitReady(model)
            assertEquals(
                listOf("Old answer"),
                model.messages.filter {
                    it.role ==
                        AgentMessageRole.ASSISTANT
                }.map { it.text }
            )

            checkNotNull(model.failureRetry).invoke()
            awaitReady(model)

            assertEquals(
                listOf("New answer"),
                model.messages.filter {
                    it.role ==
                        AgentMessageRole.ASSISTANT
                }.map { it.text }
            )
            assertEquals(
                listOf("Original question"),
                model.messages.filter {
                    it.role ==
                        AgentMessageRole.USER
                }.map { it.text }
            )
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun retryAfterQuotaReloadsTheEditedHistoryOnSuccessAndFailure() = runBlocking {
        for (shouldFail in listOf(false, true)) {
            val client = FakeClient(history())
            val model = newModel(client)
            client.onStartRun = {
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            "client-run",
                            threadId = client.thread.id,
                            code = "user_quota_exhausted",
                            retryable = true
                        )
                    )
                )
                AgentV2RunResult("client-run", state = "failed")
            }
            client.onRetryRun = { clientRunId ->
                assertEquals("client-run", clientRunId)
                client.history = history("Edited question", "New answer")
                listOf(
                    AgentV2Update.RunStarted(
                        clientRunId,
                        "run",
                        client.thread.id,
                        2,
                        "edited-question"
                    ),
                    AgentV2Update.TextDelta(
                        clientRunId,
                        "run",
                        client.thread.id,
                        "new-answer",
                        "New answer"
                    )
                ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        if (shouldFail) {
                            AgentV2Update.RunFailed(
                                clientRunId,
                                "run",
                                client.thread.id,
                                "rate_limited",
                                retryable = true
                            )
                        } else {
                            AgentV2Update.MessageCompleted(
                                clientRunId,
                                "run",
                                client.thread.id,
                                "new-answer",
                                "complete"
                            )
                        }
                    )
                )
                AgentV2RunResult(
                    clientRunId,
                    "run",
                    state = if (shouldFail) "failed" else "completed"
                )
            }
            try {
                awaitReady(model)
                assertTrue(model.editMessage("question", "Edited question"))
                awaitReady(model)
                assertEquals(2, client.messageRequests)
                assertEquals(
                    listOf("Original question"),
                    model.messages.filter {
                        it.role ==
                            AgentMessageRole.USER
                    }.map { it.text }
                )

                checkNotNull(model.failureRetry).invoke()
                awaitReady(model)

                assertEquals(
                    "History must reload after Retry (failed=$shouldFail)",
                    3,
                    client.messageRequests
                )
                assertEquals(
                    listOf("Edited question"),
                    model.messages.filter {
                        it.role ==
                            AgentMessageRole.USER
                    }.map { it.text }
                )
                assertEquals(
                    listOf("New answer"),
                    model.messages.filter {
                        it.role ==
                            AgentMessageRole.ASSISTANT
                    }.map { it.text }
                )
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun firstUnseenMessageFollowsTheSeenCountAcrossOlderPages() = runBlocking {
        // Two older messages are on a page that hasn't loaded
        val client = FakeClient(history(), messageCount = 4)
        val model = newModel(client)
        try {
            awaitReady(model)
            val loadedIds = model.messages.map { it.id }

            assertEquals(4, model.seenMessageCount)
            assertEquals(loadedIds[1], model.findFirstUnseenMessageId(seenMessageCount = 3))
            assertEquals(loadedIds[0], model.findFirstUnseenMessageId(seenMessageCount = 1))
            assertNull(model.findFirstUnseenMessageId(seenMessageCount = 4))
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun rateLimitAfterRunStartedDoesNotOfferRetry() = runBlocking {
        val client = FakeClient(emptyList())
        val model = newModel(client)
        client.onStartRun = {
            listOf(
                AgentV2Update.RunStarted("client-run", "run", client.thread.id, 2, "question"),
                AgentV2Update.RunFailed(
                    "client-run",
                    "run",
                    client.thread.id,
                    "rate_limited",
                    retryable = true
                )
            ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
            AgentV2RunResult("client-run", "run", state = "failed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            awaitReady(model)

            assertNull(model.failureRetry)
            assertFalse(model.isInputBlockedByLimit)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun retryExpiresFiveMinutesAfterResetWithoutSendingOrChangingTheFailedQuestion() = runBlocking {
        val resetAt = 10_000L
        val expiresAt = resetAt + 5 * 60_000L
        var clock = resetAt - 1_000
        var inputLimitChanges = 0
        var retryCalls = 0
        val failedQuestionIds = mutableListOf<String>()
        val client = FakeClient(emptyList())
        val model = newModel(client, now = { clock })
        val delegate = Proxy.newProxyInstance(
            AgentVM.Delegate::class.java.classLoader,
            arrayOf(AgentVM.Delegate::class.java)
        ) { _, method, args ->
            when (method.name) {
                "onInputLimitChanged" -> inputLimitChanges++
                "onOutgoingMessageFailed" -> failedQuestionIds += args[0] as String
            }
            null
        } as AgentVM.Delegate
        model.attach(delegate)
        client.onStartRun = {
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        "client-run",
                        threadId = client.thread.id,
                        code = "user_quota_exhausted",
                        retryable = true,
                        resetAt = resetAt
                    )
                )
            )
            AgentV2RunResult("client-run", state = "failed")
        }
        client.onRetryRun = {
            retryCalls++
            null
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            awaitReady(model)
            val failedMessages = model.messages.toList()
            val question = failedMessages.single { it.role == AgentMessageRole.USER }
            assertEquals(listOf(question.id), failedQuestionIds)
            assertNull(question.sdkMessageId)
            assertTrue(model.isInputBlockedByLimit)
            assertNull(model.failureRetry)

            clock = resetAt
            val staleRetry = checkNotNull(model.failureRetry)
            assertFalse(model.isInputBlockedByLimit)
            clock = expiresAt - 1
            assertTrue(model.failureRetry != null)
            model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(AgentV2Update.UserQuotaChanged()))

            clock = expiresAt
            assertNull(model.failureRetry)
            val changesBeforeTimer = inputLimitChanges
            withTimeout(1_000) {
                while (inputLimitChanges == changesBeforeTimer) yield()
            }
            staleRetry()
            model.retryLimit()
            awaitReady(model)

            assertEquals(0, retryCalls)
            assertEquals(failedMessages, model.messages)
            assertEquals(listOf(question.id), failedQuestionIds)
            assertFalse(model.isInputBlockedByLimit)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun retryWithoutResetExpiresFiveMinutesAfterFailure() = runBlocking {
        for (code in listOf("rate_limited", "user_quota_exhausted")) {
            val failedAt = 10_000L
            var clock = failedAt
            var retryCalls = 0
            val client = FakeClient(emptyList())
            val model = newModel(client, now = { clock })
            client.onStartRun = {
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            "client-run",
                            threadId = client.thread.id,
                            code = code,
                            retryable = true
                        )
                    )
                )
                AgentV2RunResult("client-run", state = "failed")
            }
            client.onRetryRun = {
                retryCalls++
                null
            }
            try {
                awaitReady(model)
                assertTrue(model.sendMessage("Question"))
                awaitReady(model)
                val failedMessages = model.messages.toList()
                val staleRetry = checkNotNull(model.failureRetry)

                clock = failedAt + 5 * 60_000L - 1
                assertTrue(model.failureRetry != null)
                clock++
                assertNull("Retry must expire for $code", model.failureRetry)
                staleRetry()
                model.retryLimit()
                awaitReady(model)

                assertEquals(0, retryCalls)
                assertEquals(failedMessages, model.messages)
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun retryExpiresOneDayAfterFailureEvenWhenTheLimitResetsLater() = runBlocking {
        val failedAt = 10_000L
        val resetAt = failedAt + 2 * 24 * 60 * 60_000L
        var clock = failedAt
        val client = FakeClient(emptyList())
        val model = newModel(client, now = { clock })
        client.onStartRun = {
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        "client-run",
                        threadId = client.thread.id,
                        code = "user_quota_exhausted",
                        retryable = true,
                        resetAt = resetAt
                    )
                )
            )
            AgentV2RunResult("client-run", state = "failed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            awaitReady(model)

            clock = failedAt + 24 * 60 * 60_000L - 1
            model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(AgentV2Update.UserQuotaChanged()))
            assertTrue(model.isInputBlockedByLimit)
            clock++
            model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(AgentV2Update.UserQuotaChanged()))
            assertNull(model.failureRetry)
            assertFalse(model.isInputBlockedByLimit)
        } finally {
            model.onDestroy()
        }
    }

    private fun history(question: String = "Original question", answer: String = "Old answer") =
        listOf(
            AgentV2PersistedMessage(
                "question",
                "thread",
                "user",
                "complete",
                content = AgentV2MessageContent.Markdown(question),
                createdAt = "2026-10-20T00:00:00Z"
            ),
            AgentV2PersistedMessage(
                "answer",
                "thread",
                "assistant",
                "complete",
                content = AgentV2MessageContent.Markdown(answer),
                createdAt = "2026-10-20T00:00:01Z"
            )
        )

    private fun CoroutineScope.newModel(
        client: FakeClient,
        now: () -> Long = System::currentTimeMillis
    ): AgentVM {
        val modelScope = CoroutineScope(coroutineContext + SupervisorJob(coroutineContext[Job]))
        return AgentVM(
            client = client,
            initialThread = client.thread,
            scope = modelScope,
            contextProvider = AgentV2HostContextProvider(client, modelScope) {
                AgentHostContextSnapshot(null, JSONObject())
            },
            now = now
        )
    }

    private suspend fun awaitReady(model: AgentVM) = withTimeout(1_000) {
        while (model.state != AgentVM.State.READY) {
            assertFalse("Model startup failed", model.state == AgentVM.State.ERROR)
            yield()
        }
    }

    private class FakeClient(
        var history: List<AgentV2PersistedMessage>,
        messageCount: Int = history.size
    ) : AgentV2Client by LiveAgentV2Client() {
        val thread = AgentV2ThreadSummary("thread", 1, messageCount = messageCount)
        var messageRequests = 0
            private set
        var onStartRun: suspend () -> AgentV2RunResult = { error("Unexpected run") }
        var onRetryRun: suspend (String) -> AgentV2RunResult? = { error("Unexpected Retry") }

        override suspend fun consent() = true
        override suspend fun updateHostContext(context: JSONObject?) {}
        override suspend fun setChatActive(isActive: Boolean) {}
        override suspend fun problemReportAvailability() = false
        override suspend fun loadAvailability() {}
        override suspend fun loadUserQuota() {}
        override suspend fun hints(langCode: String?) =
            AgentV2HintsResponse(3, "catalog", emptyList())

        override suspend fun messages(
            threadId: String,
            cursor: String?,
            limit: Int
        ): AgentV2ThreadHydration {
            assertEquals(thread.id, threadId)
            messageRequests++
            return AgentV2ThreadHydration(thread, history)
        }

        override suspend fun startRun(
            threadId: String?,
            revision: Int,
            text: String,
            entryPoint: AgentV2EntryPoint?,
            followupOf: AgentV2FollowUpReference?,
            targetUserMessageId: String?,
            targetAssistantMessageId: String?
        ) = onStartRun()

        override suspend fun retryRun(clientRunId: String) = onRetryRun(clientRunId)
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
