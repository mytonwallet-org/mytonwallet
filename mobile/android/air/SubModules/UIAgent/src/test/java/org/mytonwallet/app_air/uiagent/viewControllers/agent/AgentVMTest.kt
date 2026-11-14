package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.content.Context
import android.content.ContextWrapper
import java.lang.reflect.Proxy
import java.util.Date
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
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
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ErrorText
import org.mytonwallet.app_air.uiagent.agentV2.getAgentSupportRequestText
import org.mytonwallet.app_air.uiagent.agentV2.resolveAgentThreadTitle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.formatAgentChatTime
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerButton
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.resolveAgentComposerButton
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadListClient
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadListModel
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadReadState
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.LiveAgentThreadListClient
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Action
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ActionPresentation
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerFeedbackResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Availability
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2CachedMessages
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUpReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2HintsResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationError
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2OperatorAuthor
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2SupportRequestSource
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDeleteResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSupport
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2UserQuota
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class AgentVMTest {
    @Test
    fun supportConflictRefreshesTheRevisionAndResendsTheSameBubbleOnce() = runBlocking {
        for (state in listOf("waiting", "operator")) {
            val client = FakeClient(emptyList()).apply {
                thread = thread.copy(support = AgentV2ThreadSupport(state))
            }
            val model = newModel(client)
            val failures = mutableListOf<String>()
            val delegate = Proxy.newProxyInstance(
                AgentVM.Delegate::class.java.classLoader,
                arrayOf(AgentVM.Delegate::class.java)
            ) { _, method, _ ->
                if (method.name in listOf("onOutgoingMessageFailed", "onError")) {
                    failures += method.name
                }
                null
            } as AgentVM.Delegate
            model.attach(delegate)
            client.onStartRun = { clientRunId ->
                if (client.startedTexts.size == 1) {
                    client.thread = client.thread.copy(revision = 2)
                    model.onBridgeUpdate(
                        ApiUpdate.ApiUpdateAgentV2(
                            AgentV2Update.RunFailed(
                                clientRunId,
                                threadId = client.thread.id,
                                code = "thread_revision_conflict",
                                retryable = true
                            )
                        )
                    )
                    AgentV2RunResult(
                        clientRunId,
                        inputMessageId = "rejected-input",
                        state = "failed"
                    )
                } else {
                    listOf(
                        AgentV2Update.RunStarted(
                            clientRunId,
                            "run",
                            client.thread.id,
                            3,
                            "saved-input"
                        ),
                        AgentV2Update.MessageCompleted(
                            clientRunId,
                            "run",
                            client.thread.id,
                            "saved-input",
                            "delivered_to_support"
                        )
                    ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
                    AgentV2RunResult(clientRunId, "run", "saved-input", "completed")
                }
            }
            try {
                awaitReady(model)
                assertTrue(model.sendMessage("Please help"))
                val messageId = model.messages.first { it.role == AgentMessageRole.USER }.id
                awaitReady(model)

                val question = model.messages.single()
                assertEquals(messageId, question.id)
                assertEquals("saved-input", question.sdkMessageId)
                assertEquals(listOf("Please help", "Please help"), client.startedTexts)
                assertEquals(listOf(1, 2), client.startedRevisions)
                assertEquals(1, client.startedRunIds.distinct().size)
                assertEquals(2, client.messageRequests)
                assertTrue(failures.isEmpty())
            } finally {
                model.detach(delegate)
                model.onDestroy()
            }
        }
    }

    @Test
    fun supportConflictReportsTheOriginalFailureWhenItsRefreshFails() = runBlocking {
        val client = FakeClient(emptyList()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator"))
        }
        val model = newModel(client)
        client.onStartRun = { clientRunId ->
            client.messagesError = IllegalStateException("Unavailable")
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        clientRunId,
                        threadId = client.thread.id,
                        code = "thread_revision_conflict",
                        retryable = true
                    )
                )
            )
            AgentV2RunResult(clientRunId, state = "failed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Please help"))
            withTimeout(1_000) { while (model.state != AgentVM.State.ERROR) yield() }

            assertEquals(listOf("Please help"), client.startedTexts)
            assertEquals(3, client.messageRequests)
            assertTrue(
                model.messages.any {
                    it.text == agentV2ErrorText("thread_revision_conflict")
                }
            )
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun supportConflictDoesNotResendASecondConflictOrAnotherFailure() = runBlocking {
        for (code in listOf("thread_revision_conflict", "internal_error")) {
            val client = FakeClient(emptyList()).apply {
                thread = thread.copy(support = AgentV2ThreadSupport("waiting"))
            }
            val model = newModel(client)
            client.onStartRun = { clientRunId ->
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            clientRunId,
                            threadId = client.thread.id,
                            code = if (client.startedTexts.size ==
                                1
                            ) {
                                "thread_revision_conflict"
                            } else {
                                code
                            },
                            retryable = true
                        )
                    )
                )
                AgentV2RunResult(clientRunId, state = "failed")
            }
            try {
                awaitReady(model)
                assertTrue(model.sendMessage("Please help"))
                awaitReady(model)

                assertEquals(listOf("Please help", "Please help"), client.startedTexts)
                assertEquals(agentV2ErrorText(code), model.messages.single { it.isFailure }.text)
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun stoppingOrLeavingDuringSupportConflictRefreshPreventsResending() = runBlocking {
        for (action in listOf("stop", "leave")) {
            val client = FakeClient(emptyList()).apply {
                thread = thread.copy(support = AgentV2ThreadSupport("operator"))
            }
            val model = newModel(client, waitForSupportPoll = { awaitCancellation() })
            val delegate = createPollingDelegate()
            val refreshStarted = CompletableDeferred<Unit>()
            val refreshCancelled = CompletableDeferred<Unit>()
            model.attach(delegate)
            model.setActive(delegate, true)
            client.onStartRun = { clientRunId ->
                client.onMessagePage = { _, _ ->
                    refreshStarted.complete(Unit)
                    try {
                        awaitCancellation()
                    } finally {
                        client.onMessagePage = null
                        client.thread = client.thread.copy(revision = 2, messageCount = 2)
                        client.history = history()
                        refreshCancelled.complete(Unit)
                    }
                }
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            clientRunId,
                            threadId = client.thread.id,
                            code = "thread_revision_conflict",
                            retryable = true
                        )
                    )
                )
                AgentV2RunResult(clientRunId, state = "failed")
            }
            try {
                awaitReady(model)
                assertTrue(model.sendMessage("Please help"))
                withTimeout(1_000) { refreshStarted.await() }
                if (action == "stop") model.stopAnswer() else model.setActive(delegate, false)
                withTimeout(1_000) { refreshCancelled.await() }
                awaitReady(model)

                assertEquals(listOf("Please help"), client.startedTexts)
                assertEquals(action == "leave", model.messages.any { it.isFailure })
                if (action == "leave") {
                    assertEquals(2, model.currentThread.revision)
                    assertTrue(model.messages.any { it.sdkMessageId == "answer" })
                }
            } finally {
                model.detach(delegate)
                model.onDestroy()
            }
        }
    }

    @Test
    fun supportConflictReportsItsErrorWhenPagingSupersedesItsRefresh() = runBlocking {
        val client = FakeClient(history()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator"))
            nextCursor = "older"
        }
        val model = newModel(client)
        val refreshStarted = CompletableDeferred<Unit>()
        client.onStartRun = { clientRunId ->
            client.onMessagePage = { cursor, _ ->
                if (cursor == null && !refreshStarted.isCompleted) {
                    refreshStarted.complete(Unit)
                    awaitCancellation()
                } else if (cursor == null) {
                    AgentV2ThreadHydration(client.thread, client.history)
                } else {
                    assertEquals("older", cursor)
                    client.thread = client.thread.copy(revision = 2)
                    client.history = history(answer = "Updated answer")
                    AgentV2ThreadHydration(client.thread, emptyList())
                }
            }
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        clientRunId,
                        threadId = client.thread.id,
                        code = "thread_revision_conflict",
                        retryable = true
                    )
                )
            )
            AgentV2RunResult(clientRunId, state = "failed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Please help"))
            withTimeout(1_000) { refreshStarted.await() }
            model.loadOlderMessages()
            awaitReady(model)
            withTimeout(1_000) { while (model.isLoadingOlderMessages) yield() }

            assertEquals(listOf("Please help"), client.startedTexts)
            assertEquals(4, client.messageRequests)
            assertEquals(2, model.currentThread.revision)
            assertEquals(
                "Updated answer",
                model.messages.single {
                    it.sdkMessageId == "answer"
                }.text
            )
            assertEquals(
                agentV2ErrorText("thread_revision_conflict"),
                model.messages.single { it.isFailure }.text
            )
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun ordinaryAppendEditAndRegenerationDoNotResendAfterARevisionConflict() = runBlocking {
        for (operation in listOf("append", "edit", "regenerate")) {
            val client = FakeClient(history())
            val model = newModel(client)
            client.onStartRun = { clientRunId ->
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            clientRunId,
                            threadId = client.thread.id,
                            code = "thread_revision_conflict",
                            retryable = true
                        )
                    )
                )
                AgentV2RunResult(clientRunId, state = "failed")
            }
            try {
                awaitReady(model)
                assertTrue(
                    when (operation) {
                        "append" -> model.sendMessage("Question")
                        "edit" -> model.editMessage("question", "Edited question")
                        else -> model.regenerateMessage("answer")
                    }
                )
                awaitReady(model)

                assertEquals(1, client.startedRunIds.size)
                assertEquals(2, client.messageRequests)
                assertEquals(
                    agentV2ErrorText("thread_revision_conflict"),
                    model.messages.single { it.isFailure }.text
                )
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun deliveredToSupportKeepsTheSavedQuestionWithoutAnAnswerOrFailure() = runBlocking {
        val client = FakeClient(emptyList())
        val model = newModel(client)
        val failures = mutableListOf<String>()
        val delegate = Proxy.newProxyInstance(
            AgentVM.Delegate::class.java.classLoader,
            arrayOf(AgentVM.Delegate::class.java)
        ) { _, method, _ ->
            if (method.name in listOf("onOutgoingMessageFailed", "onError")) {
                failures += method.name
            }
            null
        } as AgentVM.Delegate
        model.attach(delegate)
        client.onStartRun = { clientRunId ->
            listOf(
                AgentV2Update.RunStarted(clientRunId, "run", client.thread.id, 2),
                AgentV2Update.MessageCompleted(
                    clientRunId,
                    "run",
                    client.thread.id,
                    "saved-question",
                    "delivered_to_support"
                )
            ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
            AgentV2RunResult(clientRunId, "run", state = "completed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Please help"))
            awaitReady(model)

            val question = model.messages.single()
            assertEquals(AgentMessageRole.USER, question.role)
            assertEquals("Please help", question.text)
            assertEquals("saved-question", question.sdkMessageId)
            assertFalse(question.isStreaming)
            assertTrue(failures.isEmpty())
            assertNull(model.failureRetry)
        } finally {
            model.detach(delegate)
            model.onDestroy()
        }
    }

    @Test
    fun supportHydrationAndUpdatesHideAgentActionsUntilSupportCloses() = runBlocking {
        val followup = AgentV2FollowUp("next", "suggested_prompt", "More")
        val messages = history().map { message ->
            if (message.role == "assistant") message.copy(followups = listOf(followup)) else message
        } + listOf("Alex", "Sam").mapIndexed { index, name ->
            AgentV2PersistedMessage(
                id = "joined-$index",
                threadId = "thread",
                role = "event",
                status = "complete",
                createdAt = "2026-10-20T00:00:0${index + 2}Z",
                code = "operator_joined",
                author = AgentV2OperatorAuthor("operator-$index", name)
            )
        }
        val client = FakeClient(messages).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("waiting"))
        }
        val model = newModel(client)
        try {
            awaitReady(model)
            assertEquals(AgentVM.SupportState.Waiting, model.supportState)
            for (state in listOf("waiting", "operator")) {
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.ThreadChanged(
                            client.thread.id,
                            client.thread.copy(support = AgentV2ThreadSupport(state))
                        )
                    )
                )
                if (state == "operator") {
                    assertEquals(AgentVM.SupportState.Operator("Sam"), model.supportState)
                }
                assertFalse(model.canEditMessage("question"))
                assertFalse(model.canRegenerateMessage("answer"))
                assertFalse(model.editMessage("question", "Edited question"))
                assertFalse(model.regenerateMessage("answer"))
                assertTrue(model.visibleFollowups("answer").isEmpty())
                assertFalse(model.sendFollowup("answer", "next"))
            }
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.ThreadChanged(
                        client.thread.id,
                        client.thread.copy(support = AgentV2ThreadSupport("closed"))
                    )
                )
            )
            assertEquals(AgentVM.SupportState.Closed, model.supportState)
            assertTrue(model.canEditMessage("question"))
            assertTrue(model.canRegenerateMessage("answer"))
            assertEquals(listOf(followup), model.visibleFollowups("answer"))
            assertTrue(client.startedRunIds.isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun supportKeepsHistoryLoadRetryAvailable() = runBlocking {
        for (state in listOf("waiting", "operator")) {
            val client = FakeClient(history()).apply {
                thread = thread.copy(support = AgentV2ThreadSupport(state))
                messagesError = IllegalStateException("Unavailable")
            }
            val model = newModel(client)
            try {
                withTimeout(1_000) { while (model.state != AgentVM.State.ERROR) yield() }
                val retry = checkNotNull(model.failureRetry)

                client.messagesError = null
                retry()
                awaitReady(model)

                assertEquals(2, client.messageRequests)
                assertEquals(
                    listOf("Original question", "Old answer"),
                    model.messages.filter { it.role != AgentMessageRole.SYSTEM }.map { it.text }
                )
                assertTrue(client.startedRunIds.isEmpty())
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun supportHidesAnOlderFailureRetryAndRejectsItsSavedActionUntilClosed() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client)
        var retryCalls = 0
        client.onStartRun = { clientRunId ->
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        clientRunId,
                        threadId = client.thread.id,
                        code = "user_quota_exhausted",
                        retryable = true
                    )
                )
            )
            AgentV2RunResult(clientRunId, state = "failed")
        }
        client.onRetryRun = {
            retryCalls++
            null
        }
        try {
            awaitReady(model)
            assertEquals(AgentVM.SupportState.None, model.supportState)
            assertTrue(model.sendMessage("Question"))
            awaitReady(model)
            val staleRetry = checkNotNull(model.failureRetry)
            assertEquals(
                agentV2ErrorText("user_quota_exhausted"),
                model.messages.last { it.isFailure }.text
            )
            val failedMessages = model.messages.toList()
            for (state in listOf("waiting", "operator")) {
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.ThreadChanged(
                            client.thread.id,
                            client.thread.copy(support = AgentV2ThreadSupport(state))
                        )
                    )
                )
                assertNull(model.failureRetry)
                staleRetry()
                model.retryLimit()
                yield()
                assertEquals(0, retryCalls)
                assertEquals(failedMessages, model.messages)
            }
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.ThreadChanged(
                        client.thread.id,
                        client.thread.copy(support = AgentV2ThreadSupport("closed"))
                    )
                )
            )
            assertTrue(model.failureRetry != null)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun closingUpdateDuringHydrationKeepsTheFinalSupportReadPending() = runBlocking {
        val ticks = Channel<Unit>()
        val firstRead = CompletableDeferred<Unit>()
        val finishFirstRead = CompletableDeferred<Unit>()
        val refreshed = CompletableDeferred<Unit>()
        val client = FakeClient(history()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("waiting"))
        }
        val initialHydration = AgentV2ThreadHydration(client.thread, client.history)
        client.onMessagePage = { _, _ ->
            if (client.messageRequests == 1) {
                firstRead.complete(Unit)
                finishFirstRead.await()
                initialHydration
            } else {
                AgentV2ThreadHydration(client.thread, client.history)
            }
        }
        val model = newModel(client, waitForSupportPoll = { ticks.receive() })
        val delegate = createPollingDelegate(onRefreshed = { refreshed.complete(Unit) })
        model.attach(delegate)
        model.setActive(delegate, true)
        try {
            withTimeout(1_000) { firstRead.await() }
            val reply = AgentV2PersistedMessage(
                "final-reply",
                "thread",
                "operator",
                "complete",
                createdAt = "2026-10-20T00:00:02Z",
                text = "Final reply",
                author = AgentV2OperatorAuthor("operator", "Sam")
            )
            val closed = reply.copy(
                id = "closed",
                role = "event",
                createdAt = "2026-10-20T00:00:03Z",
                text = null,
                author = null,
                code = "support_closed",
                reason = "operator"
            )
            client.thread = client.thread.copy(
                revision = 2,
                messageCount = 3,
                support = AgentV2ThreadSupport("closed", reply.createdAt)
            )
            client.history += listOf(reply, closed)
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.ThreadChanged(client.thread.id, client.thread)
                )
            )
            withTimeout(1_000) { while (model.currentThread.revision != 2) yield() }
            finishFirstRead.complete(Unit)
            awaitReady(model)
            withTimeout(1_000) { refreshed.await() }

            assertEquals(2, client.messageRequests)
            assertEquals(AgentVM.SupportState.Closed, model.supportState)
            assertEquals(
                listOf("question", "answer", "final-reply", "closed"),
                model.messages.map { it.sdkMessageId }
            )
            assertEquals(reply.createdAt, model.loadedOperatorMessageAt)
            assertFalse(ticks.trySend(Unit).isSuccess)
        } finally {
            model.detach(delegate)
            model.onDestroy()
            ticks.close()
        }
    }

    @Test
    fun supportPollingFollowsHydrationVisibilityForegroundAndRunOwnership() = runBlocking {
        val ticks = Channel<Unit>()
        var pollWaits = 0
        var refreshes = 0
        val startupRead = CompletableDeferred<Unit>()
        val client = FakeClient(history()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("waiting"))
            onMessagePage = { _, _ ->
                startupRead.await()
                AgentV2ThreadHydration(thread, history)
            }
        }
        val model = newModel(client, waitForSupportPoll = {
            pollWaits++
            ticks.receive()
        })
        val delegate = createPollingDelegate(onRefreshed = { refreshes++ })
        suspend fun awaitRequests(count: Int) = withTimeout(1_000) {
            while (client.messageRequests < count) yield()
        }
        suspend fun awaitTimer(after: Int) = withTimeout(1_000) {
            while (pollWaits <= after) yield()
        }
        suspend fun awaitRefresh(count: Int) = withTimeout(1_000) {
            while (refreshes < count) yield()
        }
        model.attach(delegate)
        model.setActive(delegate, true)
        try {
            awaitRequests(1)
            assertEquals(0, pollWaits)
            client.onMessagePage = null
            startupRead.complete(Unit)
            awaitReady(model)
            awaitRequests(1)
            awaitTimer(0)
            assertEquals(1, client.messageRequests)

            var requests = client.messageRequests
            model.setActive(delegate, false)
            yield()
            assertFalse(ticks.trySend(Unit).isSuccess)
            assertEquals(requests, client.messageRequests)

            var waits = pollWaits
            model.setActive(delegate, true)
            awaitRequests(++requests)
            awaitRefresh(1)
            awaitTimer(waits)
            model.onWalletEvent(WalletEvent.AppBackground)
            yield()
            assertFalse(ticks.trySend(Unit).isSuccess)
            assertEquals(requests, client.messageRequests)

            waits = pollWaits
            model.onWalletEvent(WalletEvent.AppForeground)
            awaitRequests(++requests)
            awaitRefresh(2)
            awaitTimer(waits)
            val runStarted = CompletableDeferred<Unit>()
            val finishRun = CompletableDeferred<Unit>()
            client.onStartRun = { clientRunId ->
                runStarted.complete(Unit)
                finishRun.await()
                client.thread = client.thread.copy(revision = 2, messageCount = 3)
                client.history += persistedMessage("sent", "user", "Help", "2026-10-20T00:00:02Z")
                listOf(
                    AgentV2Update.RunStarted(clientRunId, "run", client.thread.id, 2),
                    AgentV2Update.MessageCompleted(
                        clientRunId,
                        "run",
                        client.thread.id,
                        "sent",
                        "delivered_to_support"
                    )
                ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
                AgentV2RunResult(clientRunId, "run", state = "completed")
            }
            assertTrue(model.sendMessage("Help"))
            withTimeout(1_000) { runStarted.await() }
            assertFalse(ticks.trySend(Unit).isSuccess)
            assertEquals(requests, client.messageRequests)

            waits = pollWaits
            finishRun.complete(Unit)
            awaitReady(model)
            awaitRequests(++requests)
            awaitRefresh(3)
            awaitTimer(waits)
            client.thread = client.thread.copy(support = null)
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.ThreadChanged(client.thread.id, client.thread)
                )
            )
            yield()
            assertFalse(ticks.trySend(Unit).isSuccess)
        } finally {
            model.detach(delegate)
            model.onDestroy()
            ticks.close()
        }
    }

    @Test
    fun aBoundUserMessageDoesNotHideTheGapBeforeItFromSupportRefresh() = runBlocking {
        val client = FakeClient(history()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("waiting"))
        }
        val model = newModel(client, waitForSupportPoll = { awaitCancellation() })
        val refreshed = CompletableDeferred<Unit>()
        val delegate = createPollingDelegate(onRefreshed = { refreshed.complete(Unit) })
        model.attach(delegate)
        client.onStartRun = { clientRunId ->
            listOf(
                AgentV2Update.RunStarted(clientRunId, "run", client.thread.id, 2, "later"),
                AgentV2Update.MessageCompleted(
                    clientRunId,
                    "run",
                    client.thread.id,
                    "later",
                    "delivered_to_support"
                )
            ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
            AgentV2RunResult(clientRunId, "run", "later", "completed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Later"))
            val localId = model.messages.last { it.role == AgentMessageRole.USER }.id
            awaitReady(model)

            val later = persistedMessage("later", "user", "Later", "2026-10-20T00:00:04Z")
            val lateReply = AgentV2PersistedMessage(
                "late",
                "thread",
                "operator",
                "complete",
                createdAt = "2026-10-20T00:00:03Z",
                text = "Earlier reply",
                author = AgentV2OperatorAuthor("operator", "Sam")
            )
            val newestReply = lateReply.copy(id = "newest", createdAt = "2026-10-20T00:00:05Z")
            client.thread = client.thread.copy(
                revision = 3,
                messageCount = 5,
                support = AgentV2ThreadSupport("operator", newestReply.createdAt)
            )
            val cursors = mutableListOf<String?>()
            client.onMessagePage = { cursor, _ ->
                cursors += cursor
                when (cursor) {
                    null -> AgentV2ThreadHydration(
                        client.thread,
                        listOf(later, newestReply),
                        "missing"
                    )

                    "missing" -> AgentV2ThreadHydration(
                        client.thread,
                        listOf(history().last(), lateReply)
                    )

                    else -> error("Unexpected cursor")
                }
            }
            model.setActive(delegate, true)
            withTimeout(1_000) { refreshed.await() }

            assertEquals(listOf(null, "missing"), cursors)
            assertEquals(
                listOf("question", "answer", "late", "later", "newest"),
                model.messages.map {
                    it.sdkMessageId
                }
            )
            assertEquals(localId, model.messages.single { it.sdkMessageId == "later" }.id)
        } finally {
            model.detach(delegate)
            model.onDestroy()
        }
    }

    @Test
    fun supportRefreshInsertsMissingPagesBeforeKnownMessagesAndKeepsLoadedHistory() = runBlocking {
        val ticks = Channel<Unit>()
        var pollWaits = 0
        var refreshes = 0
        val laterQuestion = persistedMessage("later", "user", "Later", "2026-10-20T00:00:06Z")
        val client = FakeClient(history() + laterQuestion, messageCount = 5).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator"))
            nextCursor = "older"
        }
        val model = newModel(client, waitForSupportPoll = {
            pollWaits++
            ticks.receive()
        })
        val delegate = createPollingDelegate(onRefreshed = { refreshes++ })
        suspend fun awaitTimer(after: Int) = withTimeout(1_000) {
            while (pollWaits <= after) yield()
        }
        suspend fun awaitRefresh(count: Int) = withTimeout(1_000) {
            while (refreshes < count) yield()
        }
        model.attach(delegate)
        try {
            awaitReady(model)
            model.setActive(delegate, true)
            awaitRefresh(1)
            awaitTimer(0)
            val position = AgentVM.ScrollPosition(AgentVM.ScrollAnchor.Message("answer"), 24)
            model.updateScrollPosition(delegate, position)
            val readOlder = CompletableDeferred<Unit>()
            val finishOlder = CompletableDeferred<Unit>()
            val oldMessages = listOf(
                persistedMessage("old-question", "user", "Older", "2026-10-19T00:00:00Z"),
                persistedMessage("old-answer", "assistant", "Older answer", "2026-10-19T00:00:01Z")
            )
            client.onMessagePage = { cursor, _ ->
                assertEquals("older", cursor)
                readOlder.complete(Unit)
                finishOlder.await()
                AgentV2ThreadHydration(client.thread, oldMessages, "oldest")
            }
            model.loadOlderMessages()
            withTimeout(1_000) { readOlder.await() }
            assertFalse(ticks.trySend(Unit).isSuccess)
            val waits = pollWaits
            finishOlder.complete(Unit)
            awaitTimer(waits)
            val oldPresentationIds = model.messages.associate { it.sdkMessageId to it.id }
            val event = AgentV2PersistedMessage(
                "requested",
                "thread",
                "event",
                "complete",
                createdAt = "2026-10-20T00:00:02Z",
                code = "support_requested"
            )
            val operator = AgentV2OperatorAuthor("operator", "Sam")
            val lateReply = AgentV2PersistedMessage(
                "late",
                "thread",
                "operator",
                "complete",
                createdAt = "2026-10-20T00:00:04Z",
                text = "Reply before the later question",
                author = operator
            )
            val newestReply = lateReply.copy(
                id = "newest",
                createdAt = "2026-10-20T00:00:07Z",
                text = "Newest reply"
            )
            client.thread = client.thread.copy(
                revision = 3,
                messageCount = 7,
                support = AgentV2ThreadSupport("operator", newestReply.createdAt)
            )
            val cursors = mutableListOf<String?>()
            client.onMessagePage = { cursor, _ ->
                cursors += cursor
                when (cursor) {
                    null -> AgentV2ThreadHydration(client.thread, listOf(newestReply), "missing")

                    "missing" -> AgentV2ThreadHydration(
                        client.thread,
                        listOf(history().last(), event, lateReply, laterQuestion),
                        "older"
                    )

                    else -> error("Unexpected cursor")
                }
            }
            withTimeout(1_000) { ticks.send(Unit) }
            awaitRefresh(2)
            assertEquals(listOf(null, "missing"), cursors)
            val expectedIds = listOf(
                "old-question",
                "old-answer",
                "question",
                "answer",
                "requested",
                "late",
                "later",
                "newest"
            )
            assertEquals(expectedIds, model.messages.map { it.sdkMessageId })
            oldPresentationIds.forEach { (sdkId, id) ->
                assertEquals(id, model.messages.single { it.sdkMessageId == sdkId }.id)
            }
            assertEquals("oldest", model.historyCursor)
            assertEquals(position, model.scrollPosition)
            assertEquals(newestReply.createdAt, model.loadedOperatorMessageAt)
            assertEquals(7, model.seenMessageCount)
            assertEquals("late", model.findFirstUnseenMessageId(4))

            cursors.clear()
            withTimeout(1_000) { ticks.send(Unit) }
            awaitRefresh(3)
            assertEquals(listOf<String?>(null), cursors)
            assertEquals(expectedIds, model.messages.map { it.sdkMessageId })
            assertEquals(position, model.scrollPosition)
        } finally {
            model.detach(delegate)
            model.onDestroy()
            ticks.close()
        }
    }

    @Test
    fun repliesRefreshedIntoAReopenedSupportChatShowFromTheFirstUnreadOne() = runBlocking {
        val operator = AgentV2OperatorAuthor("operator", "Sam")
        fun reply(id: String, createdAt: String) = AgentV2PersistedMessage(
            id,
            "thread",
            "operator",
            "complete",
            createdAt = createdAt,
            text = "Reply $id",
            author = operator
        )
        val firstReply = reply("op1", "2026-10-20T00:00:02Z")
        val client = FakeClient(history() + firstReply).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator", firstReply.createdAt))
        }
        val model = newModel(client, waitForSupportPoll = { awaitCancellation() })
        val refreshes = Channel<Unit>(Channel.UNLIMITED)
        val delegate = createPollingDelegate(onRefreshed = { refreshes.trySend(Unit) })
        val readState = AgentThreadReadState(read = { null }, write = {})
        fun timeline(dividerMessageId: String?) = model.messages.flatMap {
            val item = AgentTimelineItem.Message(it)
            if (it.id ==
                dividerMessageId
            ) {
                listOf(AgentTimelineItem.UnreadDivider, item)
            } else {
                listOf(item)
            }
        }
        model.attach(delegate)
        try {
            awaitReady(model)
            model.setActive(delegate, true)
            withTimeout(1_000) { refreshes.receive() }
            readState.onChatAppeared(client.thread.id)
            readState.markSupportSeen(client.thread.id, model.loadedOperatorMessageAt)
            model.setActive(delegate, false)
            readState.onChatDisappeared(client.thread.id, model.seenMessageCount)

            // Two replies come while the chat is in the list
            val laterReplies = listOf(
                reply("op2", "2026-10-20T00:00:03Z"),
                reply("op3", "2026-10-20T00:00:04Z")
            )
            client.history += laterReplies
            client.thread = client.thread.copy(
                revision = 2,
                messageCount = 5,
                support = AgentV2ThreadSupport("operator", laterReplies.last().createdAt)
            )
            model.refreshThreadIfNeeded(client.thread)

            // Opened again, the chat shows what it holds and waits for the replies
            val opening = AgentUnreadOpening(
                client.thread,
                hasOpening = false,
                isSummaryCached = false,
                readState = readState
            )
            assertNull(opening.resolveSeenMessageCount(model))
            val shown = timeline(null)
            model.setActive(delegate, true)
            withTimeout(1_000) { refreshes.receive() }

            val seen = checkNotNull(opening.resolveSeenMessageCount(model))
            val refreshed = timeline(model.findFirstUnseenMessageId(seen))
            val dividerIndex = checkNotNull(refreshed.findArrivingUnreadDividerIndex(shown))
            assertEquals(
                "op2",
                (refreshed[dividerIndex + 1] as AgentTimelineItem.Message).message.sdkMessageId
            )
            // A later refresh leaves the divider where the user scrolled from it
            assertNull(refreshed.findArrivingUnreadDividerIndex(refreshed))
        } finally {
            model.detach(delegate)
            model.onDestroy()
            refreshes.close()
        }
    }

    @Test
    fun aSupportRefreshKeepsTheChatsCopyAtItsNewestPage() = runBlocking {
        var refreshes = 0
        val client = FakeClient(history()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator"))
        }
        val histories = AgentCachedHistories(this) { null }
        val model = newModel(
            client,
            cachedHistories = histories,
            waitForSupportPoll = { awaitCancellation() }
        )
        val delegate = createPollingDelegate(onRefreshed = { refreshes++ })
        model.attach(delegate)
        try {
            awaitReady(model)
            model.setActive(delegate, true)
            withTimeout(1_000) { while (refreshes < 1) yield() }

            val reply = AgentV2PersistedMessage(
                "reply",
                "thread",
                "operator",
                "complete",
                createdAt = "2026-10-20T00:00:02Z",
                text = "Hi",
                author = AgentV2OperatorAuthor("operator", "Sam")
            )
            client.history += reply
            client.thread = client.thread.copy(
                revision = 2,
                messageCount = 3,
                support = AgentV2ThreadSupport("operator", reply.createdAt)
            )
            model.refreshThreadIfNeeded(client.thread)
            withTimeout(1_000) { while (refreshes < 2) yield() }

            // A chat opened again later starts from the copy, which keeps the reply
            val copy = checkNotNull(histories.get(client.thread.id))
            assertEquals(listOf("question", "answer", "reply"), copy.messages.map { it.id })
            assertEquals(client.thread, copy.thread)
        } finally {
            model.detach(delegate)
            model.onDestroy()
        }
    }

    @Test
    fun aFailedReadAfterSupportClosesIsRetriedWhenTheChatShowsAgain() = runBlocking {
        var refreshes = 0
        val client = FakeClient(history()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator"))
        }
        val model = newModel(client, waitForSupportPoll = { awaitCancellation() })
        val delegate = createPollingDelegate(onRefreshed = { refreshes++ })
        suspend fun awaitRefresh(count: Int) = withTimeout(1_000) {
            while (refreshes < count) yield()
        }
        model.attach(delegate)
        try {
            awaitReady(model)
            model.setActive(delegate, true)
            awaitRefresh(1)

            val closed = AgentV2PersistedMessage(
                "closed",
                "thread",
                "event",
                "complete",
                createdAt = "2026-10-20T00:00:03Z",
                code = "support_closed",
                reason = "operator"
            )
            client.history += closed
            client.thread = client.thread.copy(
                revision = 2,
                support = AgentV2ThreadSupport("closed")
            )
            val requests = client.messageRequests
            val failedRead = CompletableDeferred<Unit>()
            client.onMessagePage = { _, _ ->
                failedRead.complete(Unit)
                throw IllegalStateException("Unavailable")
            }
            model.refreshThreadIfNeeded(client.thread)
            withTimeout(1_000) { failedRead.await() }
            yield()
            // The failure waits for the chat to show again rather than reading in a loop
            assertEquals(requests + 1, client.messageRequests)
            assertEquals(AgentVM.SupportState.Closed, model.supportState)
            assertFalse(model.messages.any { it.sdkMessageId == "closed" })

            client.onMessagePage = null
            model.setActive(delegate, false)
            model.setActive(delegate, true)
            awaitRefresh(2)
            assertEquals(requests + 2, client.messageRequests)
            assertEquals("closed", model.messages.last().sdkMessageId)

            // Once merged, the final read isn't repeated
            model.setActive(delegate, false)
            model.setActive(delegate, true)
            model.onWalletEvent(WalletEvent.AppForeground)
            yield()
            assertEquals(requests + 2, client.messageRequests)
        } finally {
            model.detach(delegate)
            model.onDestroy()
        }
    }

    @Test
    fun aThreadUpdateAfterAFailedFinalReadKeepsTheUnloadedReplyUnseen() = runBlocking {
        var refreshes = 0
        val operator = AgentV2OperatorAuthor("operator", "Sam")
        val client = FakeClient(history()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator"))
        }
        val model = newModel(client, waitForSupportPoll = { awaitCancellation() })
        val delegate = createPollingDelegate(onRefreshed = { refreshes++ })
        suspend fun awaitRefresh(count: Int) = withTimeout(1_000) {
            while (refreshes < count) yield()
        }
        model.attach(delegate)
        try {
            awaitReady(model)
            model.setActive(delegate, true)
            awaitRefresh(1)
            val seen = checkNotNull(model.seenMessageCount)

            // The operator answers and closes the request; the read of that history fails
            val reply = AgentV2PersistedMessage(
                "op2",
                "thread",
                "operator",
                "complete",
                createdAt = "2026-10-20T00:00:02Z",
                text = "Done",
                author = operator
            )
            val closed = AgentV2PersistedMessage(
                "closed",
                "thread",
                "event",
                "complete",
                createdAt = "2026-10-20T00:00:03Z",
                code = "support_closed",
                reason = "operator"
            )
            client.history += listOf(reply, closed)
            client.thread = client.thread.copy(
                revision = 2,
                messageCount = 3,
                support = AgentV2ThreadSupport("closed", reply.createdAt)
            )
            val failedRead = CompletableDeferred<Unit>()
            client.onMessagePage = { _, _ ->
                failedRead.complete(Unit)
                throw IllegalStateException("Unavailable")
            }
            model.refreshThreadIfNeeded(client.thread)
            withTimeout(1_000) { failedRead.await() }
            yield()
            model.setActive(delegate, false)

            // Pinning the chat from the list brings the server's summary while reads still fail
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.ThreadChanged(
                        client.thread.id,
                        client.thread.copy(isPinned = true)
                    )
                )
            )
            assertFalse(model.hasLoadedNewestMessages)
            assertNull(model.findFirstUnseenMessageId(seen))

            client.onMessagePage = null
            model.setActive(delegate, true)
            awaitRefresh(2)
            assertTrue(model.hasLoadedNewestMessages)
            assertEquals(
                model.messages.single { it.sdkMessageId == "op2" }.id,
                model.findFirstUnseenMessageId(seen)
            )
        } finally {
            model.detach(delegate)
            model.onDestroy()
        }
    }

    @Test
    fun supportRefreshRetriesSilentlyAndLoadsTheFinalPageAfterSupportCloses() = runBlocking {
        val ticks = Channel<Unit>()
        var refreshes = 0
        var errors = 0
        val client = FakeClient(history()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator"))
        }
        val model = newModel(client, waitForSupportPoll = {
            ticks.receive()
        })
        val delegate = createPollingDelegate(onRefreshed = { refreshes++ }) { errors++ }
        suspend fun awaitRefresh(count: Int) = withTimeout(1_000) {
            while (refreshes < count) yield()
        }
        model.attach(delegate)
        try {
            awaitReady(model)
            model.setActive(delegate, true)
            awaitRefresh(1)
            val messages = model.messages.toList()
            val failedRead = CompletableDeferred<Unit>()
            client.onMessagePage = { _, _ ->
                failedRead.complete(Unit)
                throw IllegalStateException("Unavailable")
            }
            withTimeout(1_000) { ticks.send(Unit) }
            withTimeout(1_000) { failedRead.await() }
            yield()
            assertEquals(AgentVM.State.READY, model.state)
            assertEquals(messages, model.messages)
            assertEquals(0, errors)

            client.onMessagePage = null
            val reply = AgentV2PersistedMessage(
                "reply",
                "thread",
                "operator",
                "complete",
                createdAt = "2026-10-20T00:00:02Z",
                text = "Help",
                author = AgentV2OperatorAuthor("operator", "Sam")
            )
            client.history += reply
            client.thread = client.thread.copy(
                revision = 2,
                messageCount = 3,
                support = AgentV2ThreadSupport("operator", reply.createdAt)
            )
            withTimeout(1_000) { ticks.send(Unit) }
            awaitRefresh(2)
            assertEquals("reply", model.messages.last().sdkMessageId)
            assertEquals(reply.createdAt, model.loadedOperatorMessageAt)

            val closed = reply.copy(
                id = "closed",
                role = "event",
                createdAt = "2026-10-20T00:00:03Z",
                text = null,
                author = null,
                code = "support_closed",
                reason = "operator"
            )
            client.history += closed
            client.thread = client.thread.copy(
                revision = 3,
                messageCount = 3,
                support = AgentV2ThreadSupport("closed", reply.createdAt)
            )
            val requests = client.messageRequests
            val closingRead = CompletableDeferred<Unit>()
            client.onMessagePage = { _, _ ->
                closingRead.complete(Unit)
                awaitCancellation()
            }
            model.refreshThreadIfNeeded(client.thread)
            withTimeout(1_000) { closingRead.await() }
            model.onWalletEvent(WalletEvent.AppBackground)
            model.setActive(delegate, false)
            yield()
            assertEquals(requests + 1, client.messageRequests)
            assertFalse(model.messages.any { it.sdkMessageId == "closed" })
            client.onMessagePage = null
            model.setActive(delegate, true)
            yield()
            assertEquals(requests + 1, client.messageRequests)
            model.onWalletEvent(WalletEvent.AppForeground)
            awaitRefresh(3)
            assertEquals(requests + 2, client.messageRequests)
            assertEquals("closed", model.messages.last().sdkMessageId)
            assertEquals(AgentVM.SupportState.Closed, model.supportState)
            assertFalse(ticks.trySend(Unit).isSuccess)
            assertEquals(3, model.seenMessageCount)
            assertEquals(0, errors)
        } finally {
            model.detach(delegate)
            model.onDestroy()
            ticks.close()
        }
    }

    @Test
    fun supportMetadataAndOlderClosureRefreshLatestMessages() = runBlocking {
        val ticks = Channel<Unit>()
        var refreshes = 0
        val initialReply = AgentV2PersistedMessage(
            "initial-reply",
            "thread",
            "operator",
            "complete",
            createdAt = "2026-10-20T00:00:02Z",
            text = "Initial reply",
            author = AgentV2OperatorAuthor("operator", "Sam")
        )
        val client = FakeClient(history() + initialReply, messageCount = 4).apply {
            thread =
                thread.copy(support = AgentV2ThreadSupport("operator", initialReply.createdAt))
            nextCursor = "older"
        }
        val model = newModel(client, waitForSupportPoll = {
            ticks.receive()
        })
        val delegate = createPollingDelegate(onRefreshed = { refreshes++ })
        suspend fun awaitRefresh(count: Int) = withTimeout(1_000) {
            while (refreshes < count) yield()
        }
        model.attach(delegate)
        try {
            awaitReady(model)
            model.setActive(delegate, true)
            awaitRefresh(1)
            assertEquals(initialReply.createdAt, model.loadedOperatorMessageAt)
            val liveReply = initialReply.copy(
                id = "live-reply",
                createdAt = "2026-10-20T00:00:03Z",
                text = "Live reply"
            )
            client.thread = client.thread.copy(
                revision = 2,
                messageCount = 5,
                support = AgentV2ThreadSupport("operator", liveReply.createdAt)
            )
            client.history += liveReply
            val liveRead = CompletableDeferred<Unit>()
            val finishLiveRead = CompletableDeferred<Unit>()
            client.onMessagePage = { cursor, _ ->
                assertNull(cursor)
                liveRead.complete(Unit)
                finishLiveRead.await()
                AgentV2ThreadHydration(client.thread, client.history, "older")
            }
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.ThreadChanged(client.thread.id, client.thread)
                )
            )
            withTimeout(1_000) { liveRead.await() }
            assertEquals(initialReply.createdAt, model.loadedOperatorMessageAt)
            finishLiveRead.complete(Unit)
            awaitRefresh(2)
            assertEquals(liveReply.createdAt, model.loadedOperatorMessageAt)

            val finalReply = liveReply.copy(
                id = "final-reply",
                createdAt = "2026-10-20T00:00:04Z",
                text = "Final reply"
            )
            val closed = finalReply.copy(
                id = "closed",
                role = "event",
                createdAt = "2026-10-20T00:00:05Z",
                text = null,
                author = null,
                code = "support_closed",
                reason = "inactivity"
            )
            client.thread = client.thread.copy(
                revision = 3,
                messageCount = 6,
                support = AgentV2ThreadSupport("closed", finalReply.createdAt)
            )
            client.history += listOf(finalReply, closed)
            val finalRead = CompletableDeferred<Unit>()
            val finishFinalRead = CompletableDeferred<Unit>()
            client.onMessagePage = { cursor, _ ->
                if (cursor == "older") {
                    AgentV2ThreadHydration(
                        client.thread,
                        listOf(persistedMessage("old", "user", "Older", "2026-10-19T00:00:00Z"))
                    )
                } else {
                    assertNull(cursor)
                    finalRead.complete(Unit)
                    finishFinalRead.await()
                    AgentV2ThreadHydration(client.thread, client.history, "older")
                }
            }
            val requests = client.messageRequests
            model.loadOlderMessages()
            withTimeout(1_000) { finalRead.await() }
            assertEquals(AgentVM.SupportState.Closed, model.supportState)
            assertEquals(liveReply.createdAt, model.loadedOperatorMessageAt)
            finishFinalRead.complete(Unit)
            awaitRefresh(3)
            assertEquals(requests + 2, client.messageRequests)
            assertEquals(finalReply.createdAt, model.loadedOperatorMessageAt)
            assertEquals("old", model.messages.first().sdkMessageId)
            assertFalse(ticks.trySend(Unit).isSuccess)
        } finally {
            model.detach(delegate)
            model.onDestroy()
            ticks.close()
        }
    }

    @Test
    fun supportRefreshReadsAtMostTenPagesWithoutAnExistingMessage() = runBlocking {
        val client = FakeClient(history()).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator"))
        }
        val model = newModel(client, waitForSupportPoll = { awaitCancellation() })
        val delegate = createPollingDelegate()
        val cursors = mutableListOf<String?>()
        try {
            awaitReady(model)
            client.onMessagePage = { cursor, _ ->
                cursors += cursor
                val page = cursor?.toInt() ?: 0
                AgentV2ThreadHydration(
                    client.thread.copy(revision = 2, messageCount = 14),
                    listOf(
                        AgentV2PersistedMessage(
                            id = "new-${10 - page}",
                            threadId = client.thread.id,
                            role = "operator",
                            status = "complete",
                            createdAt = "2026-10-21T00:00:00Z",
                            text = "Reply ${10 - page}",
                            author = AgentV2OperatorAuthor("operator", "Alex")
                        )
                    ),
                    nextCursor = (page + 1).toString()
                )
            }
            model.setActive(delegate, true)
            withTimeout(1_000) {
                while (model.messages.none { it.sdkMessageId == "new-10" }) yield()
            }
            yield()
            assertEquals(listOf(null) + (1..9).map { it.toString() }, cursors)
            assertEquals(
                listOf("question", "answer") + (1..10).map { "new-$it" },
                model.messages.map { it.sdkMessageId }
            )
        } finally {
            model.onDestroy()
        }
    }

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
    fun theEmptyFieldOffersStopOnlyWhileTheAgentAnswers() {
        assertEquals(
            AgentComposerButton.STOP,
            resolveAgentComposerButton(false, isAnswering = true)
        )
        assertEquals(AgentComposerButton.SEND, resolveAgentComposerButton(true, isAnswering = true))
        assertEquals(
            AgentComposerButton.SEND,
            resolveAgentComposerButton(true, isAnswering = false)
        )
        assertEquals(
            AgentComposerButton.MICROPHONE,
            resolveAgentComposerButton(false, isAnswering = false)
        )
    }

    @Test
    fun stopKeepsTheShownAnswerFreesTheChatAndSendsTheQueuedQuestion() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client)
        val threadId = client.thread.id
        val queuedRunFinished = CompletableDeferred<Unit>()
        fun deliver(vararg updates: AgentV2Update) =
            updates.forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
        suspend fun awaitStarts(count: Int) = withTimeout(1_000) {
            while (client.startedTexts.size < count) yield()
        }
        fun shownAnswers() = model.messages
            .filter { it.role == AgentMessageRole.ASSISTANT && !it.isStreaming }
        client.onStartRun = { clientRunId ->
            when (client.startedTexts.size) {
                // The answer's content has ended and it is rated and has suggestions, but its run goes on
                1 -> deliver(
                    AgentV2Update.RunStarted(clientRunId, "run-1", threadId, 2),
                    AgentV2Update.TextDelta(clientRunId, "run-1", threadId, "partial", "Partial"),
                    AgentV2Update.MessageCompleted(
                        clientRunId,
                        "run-1",
                        threadId,
                        "partial",
                        "complete"
                    ),
                    AgentV2Update.FollowupsAvailable(
                        clientRunId,
                        "run-1",
                        threadId,
                        "partial",
                        listOf(AgentV2FollowUp("next", "suggested_prompt", "More"))
                    )
                )

                3 -> queuedRunFinished.await()

                else -> Unit
            }
            if (client.startedTexts.size != 3) awaitCancellation()
            AgentV2RunResult(clientRunId, "run-3", state = "completed")
        }
        // The SDK's stop is still on its way while the chat goes on
        client.onStopRun = { awaitCancellation() }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            awaitStarts(1)
            assertTrue(shownAnswers().last().isComplete)

            model.stopAnswer()
            model.stopAnswer()

            assertEquals(listOf(threadId), client.stopRequests)
            assertEquals(AgentVM.State.READY, model.state)
            val partial = shownAnswers().last()
            assertEquals("Partial", partial.text)
            assertTrue(partial.followups.isEmpty())
            assertFalse(partial.isComplete)

            // Stopped before the SDK reports its run, an answer that has shown nothing leaves no row, and the queued
            // question goes at once
            assertTrue(model.sendMessage("Second"))
            awaitStarts(2)
            assertTrue(model.sendMessage("Queued"))
            // The repeated tap doesn't stop the queued question the first one sent
            model.stopAnswer()
            model.stopAnswer()
            assertEquals(listOf(threadId, threadId), client.stopRequests)
            assertEquals(AgentVM.State.RUNNING, model.state)
            awaitStarts(3)
            assertEquals(listOf("Question", "Second", "Queued"), client.startedTexts)
            assertEquals(listOf("Old answer", "Partial"), shownAnswers().map { it.text })

            // The stopped run's updates that were already on their way don't reach the queued question's answer
            val (_, stoppedRunId, queuedRunId) = client.startedRunIds
            deliver(
                AgentV2Update.RunStarted(stoppedRunId, "run-2", threadId, 3),
                AgentV2Update.TextDelta(stoppedRunId, "run-2", threadId, "stale", "Stale"),
                AgentV2Update.RunStarted(queuedRunId, "run-3", threadId, 3),
                AgentV2Update.TextDelta(queuedRunId, "run-3", threadId, "queued", "Queued answer"),
                AgentV2Update.MessageCompleted(queuedRunId, "run-3", threadId, "queued", "complete")
            )
            queuedRunFinished.complete(Unit)
            awaitReady(model)
            assertTrue(model.messages.none { it.text == "Stale" })
            assertEquals(
                listOf("Old answer", "Partial", "Queued answer"),
                shownAnswers().map { it.text }
            )
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun stopKeepsAnEmptyAnswersRowAMomentUntilTheNextQuestion() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client, stoppedAnswerDurationMs = 200L)
        suspend fun awaitStarts(count: Int) = withTimeout(1_000) {
            while (client.startedTexts.size < count) yield()
        }
        fun stoppingAnswers() = model.messages.filter { it.isStopping }
        client.onStartRun = { awaitCancellation() }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            awaitStarts(1)

            model.stopAnswer()

            // The row stays, no longer streaming, while the indicator takes the Stop, and then goes
            assertEquals(AgentVM.State.READY, model.state)
            val stopping = stoppingAnswers().single()
            assertFalse(stopping.isStreaming)
            assertTrue(stopping.hasVisibleBubble)
            withTimeout(1_000) {
                while (stoppingAnswers().isNotEmpty()) delay(10)
            }
            assertTrue(model.messages.none { it.id == stopping.id })

            // The next question takes its place at once
            assertTrue(model.sendMessage("Second"))
            awaitStarts(2)
            model.stopAnswer()
            assertEquals(1, stoppingAnswers().size)
            assertTrue(model.sendMessage("Third"))
            awaitStarts(3)
            assertTrue(stoppingAnswers().isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun stoppedAnswerKeepsItsTextUntilTheServerHoldsAsMuch() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client)
        val threadId = client.thread.id
        fun deliver(vararg updates: AgentV2Update) =
            updates.forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
        fun shownAnswers() = model.messages.filter { it.role == AgentMessageRole.ASSISTANT }
            .map { it.text }
        fun savedHistory(answer: String?) = history() + listOfNotNull(
            AgentV2PersistedMessage(
                "asked",
                threadId,
                "user",
                "complete",
                content = AgentV2MessageContent.Markdown("Question"),
                createdAt = "2026-10-20T00:00:02Z"
            ),
            answer?.let {
                AgentV2PersistedMessage(
                    "partial",
                    threadId,
                    "assistant",
                    "cancelled",
                    content = AgentV2MessageContent.Markdown(it),
                    createdAt = "2026-10-20T00:00:03Z"
                )
            }
        )
        suspend fun readHistoryAgain(revision: Int) {
            val requests = client.messageRequests
            model.refreshThreadIfNeeded(client.thread.copy(revision = revision))
            withTimeout(1_000) { while (client.messageRequests == requests) yield() }
            awaitReady(model)
            yield()
        }
        client.onStartRun = { clientRunId ->
            deliver(
                AgentV2Update.RunStarted(clientRunId, "run-1", threadId, 2),
                AgentV2Update.TextDelta(clientRunId, "run-1", threadId, "partial", "Shown so far")
            )
            awaitCancellation()
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            withTimeout(1_000) { while (client.startedTexts.isEmpty()) yield() }
            val requestsBeforeStop = client.messageRequests
            model.stopAnswer()

            // The server keeps the cancelled answer without what streamed and reports the thread changed
            client.history = savedHistory("")
            deliver(AgentV2Update.ThreadChanged(threadId, client.thread.copy(revision = 3)))
            yield()

            // The chat doesn't read its history again after a stop, so the shown text stays
            assertEquals(requestsBeforeStop, client.messageRequests)
            assertEquals(listOf("Old answer", "Shown so far"), shownAnswers())

            // A later read that leaves the answer out, or holds less of its text, keeps the shown text
            readHistoryAgain(4)
            assertEquals(listOf("Old answer", "Shown so far"), shownAnswers())
            client.history = savedHistory("Shown")
            readHistoryAgain(5)
            assertEquals(listOf("Old answer", "Shown so far"), shownAnswers())

            // Once the server holds as much, its answer shows, and from then on the server's text is the one shown
            client.history = savedHistory("Shown so far, and the rest")
            readHistoryAgain(6)
            assertEquals(listOf("Old answer", "Shown so far, and the rest"), shownAnswers())
            client.history = savedHistory("Shown")
            readHistoryAgain(7)
            assertEquals(listOf("Old answer", "Shown"), shownAnswers())
        } finally {
            model.onDestroy()
        }
    }

    /**
     * A stopped answer an edit or a regeneration would replace stays until the server admits the run: after a rejected
     * run a history read keeps its shown text, and after an admitted one the read shows the server's answer
     */
    @Test
    fun stoppedAnswerIsRetiredOnlyOnceTheReplacingRunIsAdmitted() = runBlocking {
        for (isEdit in listOf(false, true)) {
            for (isAdmitted in listOf(false, true)) {
                checkStoppedAnswerAfterReplacingRun(isEdit, isAdmitted)
            }
        }
    }

    private suspend fun CoroutineScope.checkStoppedAnswerAfterReplacingRun(
        isEdit: Boolean,
        isAdmitted: Boolean
    ) {
        val case = "${if (isEdit) "edit" else "regeneration"}, admitted: $isAdmitted"
        val client = FakeClient(history())
        val model = newModel(client)
        val threadId = client.thread.id
        fun deliver(vararg updates: AgentV2Update) =
            updates.forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
        fun stoppedAnswerText() = model.messages.firstOrNull { it.sdkMessageId == "partial" }?.text
        fun savedHistory(answer: String) = history() + listOf(
            AgentV2PersistedMessage(
                "asked",
                threadId,
                "user",
                "complete",
                content = AgentV2MessageContent.Markdown("Question"),
                createdAt = "2026-10-20T00:00:02Z"
            ),
            AgentV2PersistedMessage(
                "partial",
                threadId,
                "assistant",
                "cancelled",
                content = AgentV2MessageContent.Markdown(answer),
                createdAt = "2026-10-20T00:00:03Z"
            )
        )
        suspend fun readHistoryAgain(revision: Int) {
            val requests = client.messageRequests
            model.refreshThreadIfNeeded(client.thread.copy(revision = revision))
            withTimeout(1_000) { while (client.messageRequests == requests) yield() }
            awaitReady(model)
            yield()
        }
        client.onStartRun = { clientRunId ->
            deliver(
                AgentV2Update.RunStarted(clientRunId, "run-1", threadId, 2),
                AgentV2Update.TextDelta(clientRunId, "run-1", threadId, "partial", "Shown so far")
            )
            awaitCancellation()
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            withTimeout(1_000) { while (client.startedTexts.isEmpty()) yield() }
            model.stopAnswer()
            client.history = savedHistory("")
            readHistoryAgain(3)
            assertEquals(case, "Shown so far", stoppedAnswerText())

            // Both server copies hold less text than the user saw: the stopped answer's after a rejected run, the new
            // answer after an admitted one
            client.history = savedHistory(if (isAdmitted) "New" else "Shown")
            client.onStartRun = { clientRunId ->
                if (!isAdmitted) error("Rejected")
                deliver(AgentV2Update.RunStarted(clientRunId, "run-2", threadId, 4))
                AgentV2RunResult(clientRunId, "run-2", state = "completed")
            }
            val runs = client.startedTexts.size
            val isStarted = if (isEdit) {
                val question = model.messages.first { it.sdkMessageId == "asked" }
                model.editMessage(question.id, "Question again")
            } else {
                model.regenerateMessage("partial")
            }
            assertTrue(case, isStarted)
            withTimeout(1_000) { while (client.startedTexts.size == runs) yield() }
            withTimeout(1_000) { while (model.state == AgentVM.State.RUNNING) yield() }
            readHistoryAgain(5)

            assertEquals(case, if (isAdmitted) "New" else "Shown so far", stoppedAnswerText())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun inactiveClosedChatRefreshKeepsCanonicalHistoryWhileMappingActions() = runBlocking {
        val client = FakeClient(
            history() + listOf(
                persistedMessage("tail-question", "user", "Tail question", "2026-10-20T00:00:02Z"),
                persistedMessage("tail-answer", "assistant", "Tail answer", "2026-10-20T00:00:03Z")
            )
        ).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("closed"))
        }
        val model = newModel(client, waitForSupportPoll = { awaitCancellation() })
        val delegate = createPollingDelegate()
        val actionRead = CompletableDeferred<Unit>()
        val finishActionRead = CompletableDeferred<Unit>()
        model.attach(delegate)
        try {
            awaitReady(model)
            client.history = listOf(
                client.history.first(),
                persistedMessage("new-answer", "assistant", "New answer", "2026-10-20T00:00:04Z")
                    .copy(actions = listOf(AgentV2Action("send", "send", "Send")))
            )
            client.thread = client.thread.copy(revision = 2, messageCount = 2)
            client.onActionPresentationOf = { messageId, actionId ->
                assertEquals("new-answer", messageId)
                assertEquals("send", actionId)
                actionRead.complete(Unit)
                finishActionRead.await()
                AgentV2ActionPresentation.Send("active")
            }
            model.refreshThreadIfNeeded(client.thread)
            withTimeout(1_000) { actionRead.await() }
            finishActionRead.complete(Unit)
            withTimeout(1_000) {
                while (model.messages.none { it.sdkMessageId == "new-answer" }) yield()
            }
            model.setActive(delegate, true)
            yield()

            assertEquals(listOf("question", "new-answer"), model.messages.map { it.sdkMessageId })
            assertEquals(listOf("Original question", "New answer"), model.messages.map { it.text })
            assertEquals(2, client.messageRequests)
            assertTrue(client.startedRunIds.isEmpty())
        } finally {
            model.detach(delegate)
            model.onDestroy()
        }
    }

    @Test
    fun closedSupportKeptChatRefreshRemovesTheReplacedAnswerAndTail() = runBlocking {
        val client = FakeClient(
            history() + listOf(
                persistedMessage("tail-question", "user", "Tail question", "2026-10-20T00:00:02Z"),
                persistedMessage("tail-answer", "assistant", "Tail answer", "2026-10-20T00:00:03Z")
            )
        ).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("closed"))
        }
        var pollWaits = 0
        val model = newModel(client, waitForSupportPoll = {
            pollWaits++
            awaitCancellation()
        })
        val delegate = createPollingDelegate()
        model.attach(delegate)
        try {
            awaitReady(model)
            model.setActive(delegate, true)
            client.history = listOf(
                client.history.first(),
                persistedMessage("new-answer", "assistant", "New answer", "2026-10-20T00:00:04Z")
            )
            client.thread = client.thread.copy(revision = 2, messageCount = 2)
            val lastOperatorMessageAt = "2026-10-20T00:00:05Z"
            client.onMessagePage = { _, _ ->
                val snapshot = client.thread
                if (client.messageRequests == 2) {
                    client.thread = snapshot.copy(
                        support = AgentV2ThreadSupport("closed", lastOperatorMessageAt)
                    )
                    model.onBridgeUpdate(
                        ApiUpdate.ApiUpdateAgentV2(
                            AgentV2Update.ThreadChanged(client.thread.id, client.thread)
                        )
                    )
                }
                AgentV2ThreadHydration(snapshot, client.history)
            }
            model.refreshThreadIfNeeded(client.thread)
            withTimeout(1_000) {
                while (model.loadedOperatorMessageAt != lastOperatorMessageAt) yield()
            }

            assertEquals(listOf("question", "new-answer"), model.messages.map { it.sdkMessageId })
            assertEquals(listOf("Original question", "New answer"), model.messages.map { it.text })
            assertEquals(3, client.messageRequests)
            assertTrue(client.startedRunIds.isEmpty())
            assertEquals(0, pollWaits)
        } finally {
            model.detach(delegate)
            model.onDestroy()
        }
    }

    /**
     * A kept chat refreshing takes the server's newest page and its cursor: the older pages it had loaded leave and
     * come back in order by scrolling, a message the server removed goes, and of the rest only a message not stored yet
     * and a stopped answer newer than the page stay, in their places by time
     */
    @Test
    fun keptChatRefreshTakesTheNewestPageInOrder() = runBlocking {
        val olderPage = listOf(
            persistedMessage("q1", "user", "First", "2026-10-20T00:00:00Z"),
            persistedMessage("a1", "assistant", "First answer", "2026-10-20T00:00:01Z")
        )
        val client = FakeClient(
            listOf(
                persistedMessage("q2", "user", "Second", "2026-10-20T00:00:02Z"),
                persistedMessage("a2", "assistant", "Second answer", "2026-10-20T00:00:03Z")
            )
        ).apply {
            nextCursor = "older"
            olderPages = mapOf("older" to AgentV2ThreadHydration(thread, olderPage))
        }
        val model = newModel(client)
        val threadId = client.thread.id
        fun deliver(vararg updates: AgentV2Update) =
            updates.forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
        fun shownTexts() = model.messages.map { it.text }
        suspend fun loadOlderMessages() {
            val requests = client.messageRequests
            model.loadOlderMessages()
            withTimeout(1_000) { while (client.messageRequests == requests) yield() }
            repeat(20) { yield() }
        }
        client.onStartRun = { clientRunId ->
            deliver(
                AgentV2Update.RunStarted(clientRunId, "run-1", threadId, 2, inputMessageId = "q3"),
                AgentV2Update.TextDelta(clientRunId, "run-1", threadId, "a3", "Shown so far")
            )
            awaitCancellation()
        }
        try {
            awaitReady(model)
            loadOlderMessages()
            assertEquals(listOf("First", "First answer", "Second", "Second answer"), shownTexts())
            assertTrue(model.sendMessage("Third"))
            withTimeout(1_000) { while (client.startedTexts.isEmpty()) yield() }
            model.stopAnswer()
            awaitReady(model)
            client.onStartRun = { error("Unavailable") }
            assertTrue(model.sendMessage("Not stored"))
            withTimeout(1_000) { while (model.state == AgentVM.State.RUNNING) yield() }
            val unsent = model.messages.last { it.role == AgentMessageRole.USER }
            assertNull(unsent.sdkMessageId)

            // Elsewhere the second answer was asked again; the stopped answer was saved empty, so the page leaves it out
            client.history = listOf(
                persistedMessage("q2", "user", "Second", "2026-10-20T00:00:02Z"),
                persistedMessage("a2b", "assistant", "Second answer again", "2026-10-20T00:00:04Z"),
                persistedMessage("q3", "user", "Third", "2026-10-20T00:00:05Z"),
                persistedMessage(
                    "a3",
                    "assistant",
                    "",
                    "2026-10-20T00:00:06Z",
                    status = "cancelled"
                )
            )
            val requests = client.messageRequests
            model.refreshThreadIfNeeded(client.thread.copy(revision = 5))
            withTimeout(1_000) { while (client.messageRequests == requests) yield() }
            awaitReady(model)
            repeat(20) { yield() }

            val refreshed = model.messages.filter { it.role != AgentMessageRole.SYSTEM }
            assertEquals(
                listOf("Second", "Second answer again", "Third", "Shown so far", "Not stored"),
                refreshed.map { it.text }
            )
            assertEquals(unsent.id, refreshed.last().id)
            loadOlderMessages()
            assertEquals(
                listOf(
                    "First",
                    "First answer",
                    "Second",
                    "Second answer again",
                    "Third",
                    "Shown so far",
                    "Not stored"
                ),
                model.messages.filter { it.role != AgentMessageRole.SYSTEM }.map { it.text }
            )
        } finally {
            model.onDestroy()
        }
    }

    /**
     * A stopped answer older than a kept chat's refreshed page comes back with its shown text when its page loads,
     * once, though the server saved it empty or left it out
     */
    @Test
    fun stoppedAnswerComesBackWithItsOlderPage() = runBlocking {
        for (isLeftOut in listOf(false, true)) {
            checkStoppedAnswerComesBackWithItsOlderPage(isLeftOut)
        }
    }

    private suspend fun CoroutineScope.checkStoppedAnswerComesBackWithItsOlderPage(
        isLeftOut: Boolean
    ) {
        val case = if (isLeftOut) "left out" else "saved empty"
        val client = FakeClient(history())
        val model = newModel(client)
        val threadId = client.thread.id
        client.onStartRun = { clientRunId ->
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunStarted(
                        clientRunId,
                        "run-1",
                        threadId,
                        2,
                        inputMessageId = "q3"
                    )
                )
            )
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.TextDelta(clientRunId, "run-1", threadId, "a3", "Shown so far")
                )
            )
            awaitCancellation()
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Third"))
            withTimeout(1_000) { while (client.startedTexts.isEmpty()) yield() }
            model.stopAnswer()
            awaitReady(model)

            // Newer messages push the stopped answer to an older page
            client.history = listOf(
                persistedMessage("q4", "user", "Later question", "2099-01-01T00:00:00Z"),
                persistedMessage("a4", "assistant", "Later answer", "2099-01-01T00:00:01Z")
            )
            client.nextCursor = "older"
            client.olderPages = mapOf(
                "older" to AgentV2ThreadHydration(
                    client.thread,
                    history() + listOfNotNull(
                        persistedMessage("q3", "user", "Third", "2026-10-20T00:00:02Z"),
                        persistedMessage(
                            "a3",
                            "assistant",
                            "",
                            "2026-10-20T00:00:03Z",
                            status = "cancelled"
                        ).takeUnless { isLeftOut }
                    )
                )
            )
            val requests = client.messageRequests
            model.refreshThreadIfNeeded(client.thread.copy(revision = 5))
            withTimeout(1_000) { while (client.messageRequests == requests) yield() }
            awaitReady(model)
            assertEquals(
                case,
                listOf("Later question", "Later answer"),
                model.messages.map { it.text }
            )

            model.loadOlderMessages()
            withTimeout(1_000) { while (client.messageRequests == requests + 1) yield() }
            repeat(20) { yield() }

            assertEquals(
                case,
                listOf(
                    "Original question",
                    "Old answer",
                    "Third",
                    "Shown so far",
                    "Later question",
                    "Later answer"
                ),
                model.messages.map { it.text }
            )
        } finally {
            model.onDestroy()
        }
    }

    /** A load other than a kept chat's refresh keeps the stored messages its page lacks, after the page */
    @Test
    fun loadAfterAFailureKeepsTheMessagesItsPageLacks() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client)
        client.onStartRun = { error("Unavailable") }
        try {
            awaitReady(model)
            // The edit fails, and so does the history read after it, which leaves the chat failed
            client.messagesError = IllegalStateException("Unavailable")
            assertTrue(model.editMessage("question", "Edited question"))
            withTimeout(1_000) { while (model.state != AgentVM.State.ERROR) yield() }

            client.messagesError = null
            client.history = listOf(
                persistedMessage("q2", "user", "Newer question", "2026-10-20T00:00:02Z"),
                persistedMessage("a2", "assistant", "Newer answer", "2026-10-20T00:00:03Z")
            )
            model.retry()
            awaitReady(model)

            assertEquals(
                listOf("Newer question", "Newer answer", "Original question", "Old answer"),
                model.messages.filter { it.role != AgentMessageRole.SYSTEM }.map { it.text }
            )
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun stoppedRegenerationShowsTheAnswerItWouldReplace() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client)
        val failedQuestionIds = mutableListOf<String>()
        val delegate = Proxy.newProxyInstance(
            AgentVM.Delegate::class.java.classLoader,
            arrayOf(AgentVM.Delegate::class.java)
        ) { _, method, args ->
            if (method.name == "onOutgoingMessageFailed") failedQuestionIds += args[0] as String
            null
        } as AgentVM.Delegate
        model.attach(delegate)
        client.onStartRun = { awaitCancellation() }
        client.onStopRun = { awaitCancellation() }
        try {
            awaitReady(model)
            assertTrue(model.regenerateMessage("answer"))
            withTimeout(1_000) {
                while (client.startedTexts.isEmpty()) yield()
            }

            model.stopAnswer()

            // The chat gives back the rows it hid for the new answer, as after a failed regeneration
            assertEquals(listOf("answer"), failedQuestionIds)
            assertEquals(
                listOf("Original question", "Old answer"),
                model.messages.map { it.text }
            )
            assertTrue(model.canRegenerateMessage("answer"))
        } finally {
            model.detach(delegate)
            model.onDestroy()
        }
    }

    /**
     * A question sent right after Regenerate, before the server admits the new answer, queues
     * behind it: the new answer takes the old one's place above it, and it goes once that ends
     */
    @Test
    fun aQuestionSentDuringARegenerationQueuesBelowTheNewAnswer() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client)
        val threadId = client.thread.id
        val mayAdmit = CompletableDeferred<Unit>()
        val answerMayEnd = CompletableDeferred<Unit>()
        client.onStartRun = { clientRunId ->
            if (client.startedTexts.size == 1) {
                mayAdmit.await()
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunStarted(clientRunId, "run-1", threadId, 2)
                    )
                )
                answerMayEnd.await()
            }
            AgentV2RunResult(clientRunId, "run-${client.startedTexts.size}", state = "completed")
        }
        try {
            awaitReady(model)
            assertTrue(model.regenerateMessage("answer"))
            withTimeout(1_000) {
                while (client.startedTexts.isEmpty()) yield()
            }

            assertTrue(model.sendMessage("Queued"))
            val queued = model.messages.last()
            assertTrue(model.isMessageQueued(queued.id))
            assertEquals(listOf("Old answer"), client.startedTexts)

            mayAdmit.complete(Unit)
            withTimeout(1_000) {
                while (model.messages.any { it.text == "Old answer" }) yield()
            }
            assertEquals(
                listOf(AgentMessageRole.USER, AgentMessageRole.ASSISTANT, AgentMessageRole.USER),
                model.messages.map { it.role }
            )
            assertEquals(queued.id, model.messages.last().id)

            answerMayEnd.complete(Unit)
            withTimeout(1_000) {
                while (client.startedTexts.size < 2) yield()
            }
            awaitReady(model)
            assertEquals(listOf("Old answer", "Queued"), client.startedTexts)
            assertFalse(model.isMessageQueued(queued.id))
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun retryAfterQuotaReplacesTheRegeneratedAnswer() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client)
        client.onStartRun = { clientRunId ->
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        clientRunId,
                        threadId = client.thread.id,
                        code = "user_quota_exhausted",
                        retryable = true
                    )
                )
            )
            AgentV2RunResult(clientRunId, state = "failed")
        }
        client.onRetryRun = { clientRunId ->
            assertEquals(client.startedRunIds.last(), clientRunId)
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
            val histories = AgentCachedHistories(this) { null }
            val model = newModel(client, cachedHistories = histories)
            client.onStartRun = { clientRunId ->
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            clientRunId,
                            threadId = client.thread.id,
                            code = "user_quota_exhausted",
                            retryable = true
                        )
                    )
                )
                AgentV2RunResult(clientRunId, state = "failed")
            }
            client.onRetryRun = { clientRunId ->
                assertEquals(client.startedRunIds.last(), clientRunId)
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

                // The reloaded history is the copy a chat opened later shows at once
                client.onMessages = { awaitCancellation() }
                val reopened = newModel(
                    client,
                    canShowCachedMessages = true,
                    cachedHistories = histories
                )
                try {
                    assertEquals(
                        listOf("Edited question", "New answer"),
                        reopened.messages.map { it.text }
                    )
                } finally {
                    reopened.onDestroy()
                }
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun aQuestionDeliveredToSupportCountsAsSeenWhenTheChatIsLeft() = runBlocking {
        val operator = AgentV2OperatorAuthor("operator", "Sam")
        fun event(id: String, code: String, createdAt: String) = AgentV2PersistedMessage(
            id,
            "thread",
            "event",
            "complete",
            createdAt = createdAt,
            code = code,
            author = operator.takeIf { code == "operator_joined" }
        )
        fun reply(id: String, createdAt: String) = AgentV2PersistedMessage(
            id,
            "thread",
            "operator",
            "complete",
            createdAt = createdAt,
            text = "Operator reply",
            author = operator
        )
        val firstReply = reply("op1", "2026-10-20T00:00:04Z")
        val client = FakeClient(
            history() + listOf(
                event("requested", "support_requested", "2026-10-20T00:00:02Z"),
                event("joined", "operator_joined", "2026-10-20T00:00:03Z"),
                firstReply
            ),
            messageCount = 3
        ).apply {
            thread = thread.copy(support = AgentV2ThreadSupport("operator", firstReply.createdAt))
        }
        val model = newModel(client, waitForSupportPoll = { awaitCancellation() })
        val refreshes = Channel<Unit>(Channel.UNLIMITED)
        val delegate = createPollingDelegate(onRefreshed = { refreshes.trySend(Unit) })
        val readState = AgentThreadReadState(read = { null }, write = {})
        client.onStartRun = { clientRunId ->
            // The server saves the question, sends the thread with it counted, and ends the run without an answer
            client.thread = client.thread.copy(revision = 2, messageCount = 4)
            client.history += persistedMessage("sent", "user", "Thanks", "2026-10-20T00:00:05Z")
            listOf(
                AgentV2Update.RunStarted(clientRunId, "run", client.thread.id, 2, "sent"),
                AgentV2Update.ThreadChanged(client.thread.id, client.thread),
                AgentV2Update.MessageCompleted(
                    clientRunId,
                    "run",
                    client.thread.id,
                    "sent",
                    "delivered_to_support"
                )
            ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
            AgentV2RunResult(clientRunId, "run", "sent", "completed")
        }
        model.attach(delegate)
        model.setActive(delegate, true)
        try {
            awaitReady(model)
            readState.onChatAppeared(client.thread.id)
            assertTrue(model.sendMessage("Thanks"))
            awaitReady(model)
            withTimeout(1_000) { refreshes.receive() }

            readState.markSupportSeen(client.thread.id, model.loadedOperatorMessageAt)
            model.setActive(delegate, false)
            readState.onChatDisappeared(client.thread.id, model.seenMessageCount)
            assertFalse(readState.isUnread(client.thread))

            // The operator answers while the chat is in the list, which passes the chat its summary
            val secondReply = reply("op2", "2026-10-20T00:00:06Z")
            client.history += secondReply
            client.thread = client.thread.copy(
                revision = 3,
                messageCount = 5,
                support = AgentV2ThreadSupport("operator", secondReply.createdAt)
            )
            model.refreshThreadIfNeeded(client.thread)
            // Pinning it there brings the server's summary as a thread update too
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.ThreadChanged(
                        client.thread.id,
                        client.thread.copy(isPinned = true)
                    )
                )
            )
            val seen = readState.getSeenMessageCountIfUnread(client.thread)
            assertEquals(4, seen)

            // Opened again, the chat shows what it has before the reply loads; nothing it shows is new yet
            assertFalse(model.hasLoadedNewestMessages)
            assertNull(model.findFirstUnseenMessageId(seen!!))
            assertEquals(4, model.seenMessageCount)
            model.setActive(delegate, true)
            withTimeout(1_000) { refreshes.receive() }

            assertTrue(model.hasLoadedNewestMessages)
            assertEquals(
                model.messages.single { it.sdkMessageId == "op2" }.id,
                model.findFirstUnseenMessageId(seen)
            )
        } finally {
            model.detach(delegate)
            model.onDestroy()
            refreshes.close()
        }
    }

    @Test
    fun historyReloadOfAMissingThreadDropsItsCopy() = runBlocking {
        val client = FakeClient(history())
        val histories = AgentCachedHistories(this) { null }
        val model = newModel(client, cachedHistories = histories)
        try {
            awaitReady(model)
            assertTrue(histories.get(client.thread.id) != null)

            // The thread was deleted on another device
            val missing = AgentV2OperationException(AgentV2MutationError("thread_not_found", false))
            client.onStartRun = { throw missing }
            client.onMessages = { throw missing }
            assertTrue(model.editMessage("question", "Edited question"))
            withTimeout(1_000) {
                while (client.messageRequests < 2) yield()
            }
            yield()

            assertNull(histories.get(client.thread.id))
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun chatOpenedFromACachedRowLearnsFromItsLoadedThreadThatItIsUnread() = runBlocking {
        for (isSummaryCached in listOf(true, false)) {
            // The user left while the answer streamed, and the app was killed before it completed
            val readState = AgentThreadReadState(read = { null }, write = {})
            val stale = AgentV2ThreadSummary("thread", 1, messageCount = 1)
            readState.onChatAppeared(stale.id)
            readState.onChatDisappeared(stale.id, seenMessageCount = 1)
            val client = FakeClient(history())
            client.thread = stale
            val freshHistory = CompletableDeferred<AgentV2ThreadHydration>()
            client.onMessages = { freshHistory.await() }
            val histories = AgentCachedHistories(this) { null }
            histories.storeLoadedPage(stale, history().take(1), hasOlder = false)
            val opening = AgentUnreadOpening(
                stale,
                hasOpening = false,
                isSummaryCached = isSummaryCached,
                readState = readState
            )
            val model = newModel(
                client,
                canShowCachedMessages = opening.canShowCachedMessages,
                cachedHistories = histories
            )
            try {
                assertTrue(model.isCachedMessage("question"))
                assertEquals(isSummaryCached, opening.isAwaitingLoadedThread)
                assertNull(opening.resolveSeenMessageCount(model))

                freshHistory.complete(
                    AgentV2ThreadHydration(stale.copy(revision = 2, messageCount = 2), history())
                )
                awaitReady(model)

                val seen = opening.resolveSeenMessageCount(model)
                assertFalse(opening.isAwaitingLoadedThread)
                if (isSummaryCached) {
                    assertEquals(1, seen)
                    assertEquals("answer", model.findFirstUnseenMessageId(checkNotNull(seen)))
                } else {
                    assertNull(seen)
                }
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun walletResetAfterTheBridgeIsRecreatedClearsTheCopies() = runBlocking {
        var bridge: Any? = Any()
        val histories = AgentCachedHistories(this, getBridge = { bridge }) { null }
        val thread = AgentV2ThreadSummary("bridge-thread", 1, messageCount = 2)
        histories.storeLoadedPage(thread, history(), hasOlder = false)
        WalletCore.notifyEvent(WalletEvent.AccountsReset)
        assertNull(histories.get(thread.id))

        // The window closed and reopened: the new bridge starts without observers and misses the reset
        histories.storeLoadedPage(thread, history(), hasOlder = false)
        WalletCore.destroyBridge()
        bridge = Any()
        WalletCore.notifyEvent(WalletEvent.AccountsReset)
        assertNull(histories.get(thread.id))

        // Used again, the store hears the next reset
        histories.storeLoadedPage(thread, history(), hasOlder = false)
        WalletCore.notifyEvent(WalletEvent.AccountsReset)
        assertNull(histories.get(thread.id))
    }

    @Test
    fun walletResetClearsTheSharedCopiesWithoutTheList() {
        val histories = AgentSession.cachedHistories
        val thread = AgentV2ThreadSummary("reset-thread", 1, messageCount = 2)
        histories.storeLoadedPage(thread, history(), hasOlder = false)
        assertTrue(histories.get(thread.id) != null)

        WalletCore.notifyEvent(WalletEvent.AccountsReset)

        assertNull(histories.get(thread.id))
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
        client.onStartRun = { clientRunId ->
            listOf(
                AgentV2Update.RunStarted(clientRunId, "run", client.thread.id, 2, "question"),
                AgentV2Update.RunFailed(
                    clientRunId,
                    "run",
                    client.thread.id,
                    "rate_limited",
                    retryable = true
                )
            ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
            AgentV2RunResult(clientRunId, "run", state = "failed")
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
    fun aLimitHoldsTheQueueAndTheQuestionItHeldBackGoesFirstOnRetry() = runBlocking {
        val resetAt = 10_000L
        var clock = resetAt - 1_000
        val client = FakeClient(emptyList())
        val model = newModel(client, now = { clock })
        val questionMayFail = CompletableDeferred<Unit>()
        val retriedRunIds = mutableListOf<String>()
        client.onStartRun = { clientRunId ->
            if (client.startedTexts.size == 1) {
                questionMayFail.await()
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            clientRunId,
                            threadId = client.thread.id,
                            code = "user_quota_exhausted",
                            retryable = true,
                            resetAt = resetAt
                        )
                    )
                )
                AgentV2RunResult(clientRunId, state = "failed")
            } else {
                AgentV2RunResult(clientRunId, "run-queued", state = "completed")
            }
        }
        client.onRetryRun = { clientRunId ->
            retriedRunIds += clientRunId
            AgentV2RunResult(clientRunId, "run-retried", state = "completed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            withTimeout(1_000) {
                while (client.startedTexts.isEmpty()) yield()
            }
            assertTrue(model.sendMessage("Queued"))
            questionMayFail.complete(Unit)
            awaitReady(model)

            // The queued question waits rather than meeting the same limit
            assertEquals(listOf("Question"), client.startedTexts)
            assertTrue(model.isInputBlockedByLimit)
            assertNull(model.failureRetry)

            // Once the limit resets, Retry sends the question it held back before the queued one
            clock = resetAt
            checkNotNull(model.failureRetry).invoke()
            withTimeout(1_000) {
                while (client.startedTexts.size < 2) yield()
            }
            awaitReady(model)
            assertEquals(listOf(client.startedRunIds.first()), retriedRunIds)
            assertEquals(listOf("Question", "Queued"), client.startedTexts)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun aWalletSwitchFailsTheQueuedQuestionsAndRetryQueuesThemForTheNewWallet() = runBlocking {
        val client = FakeClient(emptyList())
        lateinit var contextProvider: AgentV2HostContextProvider
        val model = newModel(client, onContextProvider = { contextProvider = it })
        val answerMayEnd = CompletableDeferred<Unit>()
        client.onStartRun = { clientRunId ->
            if (client.startedTexts.size == 1) answerMayEnd.await()
            AgentV2RunResult(clientRunId, "run-${client.startedTexts.size}", state = "completed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            withTimeout(1_000) {
                while (client.startedTexts.isEmpty()) yield()
            }
            assertTrue(model.sendMessage("Queued"))

            contextProvider.onWalletEvent(WalletEvent.AccountWillChange(fromHome = false))
            // The wallet may stay the same until the change ends
            assertTrue(model.messages.none { it.isFailure })
            AccountStore.updateActiveAccount("other")
            contextProvider.onWalletEvent(WalletEvent.AccountChanged())
            // The queued question stays, as a failed send, with the failure after it
            val queued = model.messages.single { it.text == "Queued" }
            val failure = model.messages.last()
            assertTrue(failure.isFailure)
            assertEquals(queued.id, model.messages[model.messages.size - 2].id)
            assertTrue(model.failureRetry != null)

            // It isn't sent for the new wallet once the answer ends
            answerMayEnd.complete(Unit)
            awaitReady(model)
            assertEquals(listOf("Question"), client.startedTexts)

            // Retry queues it again for the new wallet, which sends it
            checkNotNull(model.failureRetry).invoke()
            withTimeout(1_000) {
                while (client.startedTexts.size < 2) yield()
            }
            awaitReady(model)
            assertEquals(listOf("Question", "Queued"), client.startedTexts)
            assertTrue(model.messages.none { it.id == failure.id })
            assertEquals(1, model.messages.count { it.text == "Queued" })
        } finally {
            AccountStore.updateActiveAccount(null)
            model.onDestroy()
        }
    }

    /**
     * The authority published again for the same wallet, as when a switch is aborted or the
     * wallet's chains update, keeps the queue and the question a limit held back, without a failure
     */
    @Test
    fun aRepublishForTheSameWalletKeepsTheQueueAndTheHeldQuestion() = runBlocking {
        val resetAt = 10_000L
        var clock = resetAt - 100
        val client = FakeClient(emptyList())
        lateinit var contextProvider: AgentV2HostContextProvider
        val model = newModel(client, now = { clock }, onContextProvider = { contextProvider = it })
        try {
            queueBehindLimit(model, client, resetAt)
            val shownMessages = model.messages.toList()

            contextProvider.onWalletEvent(WalletEvent.AccountWillChange(fromHome = false))
            contextProvider.onWalletEvent(WalletEvent.AccountChangeAborted)
            contextProvider.onWalletEvent(WalletEvent.ByChainUpdated("account"))
            repeat(20) { yield() }
            assertEquals(shownMessages, model.messages)

            // Both go once the limit resets, the queued one under the new authority
            clock = resetAt
            withTimeout(1_000) {
                while (client.startedTexts.size < 2) yield()
            }
            awaitReady(model)
            assertEquals(listOf(client.startedRunIds.first()), client.retriedRunIds)
            assertEquals(listOf("Question", "Queued"), client.startedTexts)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun aLeftChatSendsTheQueueALimitHoldsOnceItResetsAndThenLetsGo() = runBlocking {
        val resetAt = 10_000L
        var clock = resetAt - 100
        val client = FakeClient(emptyList())
        val destroyed = mutableListOf<AgentVM>()
        val sessions = leftChatSessions(destroyed)
        val model = sessions.acquire(client.thread.id) { newModel(client, now = { clock }) }
        try {
            queueBehindLimit(model, client, resetAt)

            sessions.release(client.thread.id, model)
            assertTrue(destroyed.isEmpty())

            clock = resetAt
            withTimeout(1_000) {
                while (destroyed.isEmpty()) yield()
            }
            assertEquals(listOf(client.startedRunIds.first()), client.retriedRunIds)
            assertEquals(listOf("Question", "Queued"), client.startedTexts)
            assertEquals(listOf(model), destroyed)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun aChatKeepsItsQueueUntilDeletionSucceedsAndResumesItOnFailure() = runBlocking {
        assertQueueWaitsForDeletion(isFromList = false)
    }

    @Test
    fun aThreadListDeletionKeepsTheQueueUntilTheServerConfirmsIt() = runBlocking {
        assertQueueWaitsForDeletion(isFromList = true)
    }

    @Test
    fun aFailedListDeletionKeepsTheQueueHeldUntilTheChatDeletionSettles() = runBlocking {
        val client = FakeClient(emptyList())
        val answerMayEnd = CompletableDeferred<Unit>()
        val deletionStarted = CompletableDeferred<Unit>()
        val deletionMayEnd = CompletableDeferred<Unit>()
        val chatDeletionFailed = CompletableDeferred<Throwable>()
        val listDeletionFailed = CompletableDeferred<Unit>()
        client.onStartRun = { clientRunId ->
            if (client.startedTexts.size == 1) answerMayEnd.await()
            AgentV2RunResult(clientRunId, state = "completed")
        }
        client.onDeleteThread = {
            deletionStarted.complete(Unit)
            deletionMayEnd.await()
            error("Deletion refused")
        }
        val listClient = object : AgentThreadListClient by LiveAgentThreadListClient() {
            override suspend fun delete(id: String): AgentV2ThreadDeleteResponse =
                error("Deletion refused")
        }
        val listModel = AgentThreadListModel(this, client = listClient)
        val model = AgentSession.acquire(client.thread) { newModel(client) }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            withTimeout(1_000) { while (client.startedTexts.isEmpty()) yield() }
            assertTrue(model.sendMessage("Queued"))
            AgentSession.deleteChat(model) { chatDeletionFailed.complete(it) }
            AgentSession.release(model)
            withTimeout(1_000) { deletionStarted.await() }
            answerMayEnd.complete(Unit)
            awaitReady(model)

            assertTrue(listModel.delete(client.thread) { listDeletionFailed.complete(Unit) })
            withTimeout(1_000) { listDeletionFailed.await() }
            yield()

            assertEquals(listOf("Question"), client.startedTexts)
            assertSame(model, AgentSession.findLoadedModel(client.thread.id))
            deletionMayEnd.complete(Unit)
            withTimeout(1_000) {
                chatDeletionFailed.await()
                while (AgentSession.findLoadedModel(client.thread.id) != null) yield()
            }
            assertEquals(listOf("Question", "Queued"), client.startedTexts)
        } finally {
            answerMayEnd.complete(Unit)
            deletionMayEnd.complete(Unit)
            AgentSession.dropDeletedChat(client.thread.id)
            model.onDestroy()
        }
    }

    @Test
    fun cancellingAThreadListDeletionDoesNotResumeItsQueue() = runBlocking {
        val resetAt = 10_000L
        var clock = resetAt - 100
        val client = FakeClient(emptyList())
        val deletionStarted = CompletableDeferred<Unit>()
        client.onDeleteThread = {
            deletionStarted.complete(Unit)
            awaitCancellation()
        }
        val listLifetime = Job()
        val listScope = CoroutineScope(coroutineContext + listLifetime)
        val listClient = object : AgentThreadListClient by LiveAgentThreadListClient() {
            override suspend fun delete(id: String) = client.deleteThread(id)
        }
        val listModel = AgentThreadListModel(listScope, client = listClient)
        val model = AgentSession.acquire(client.thread) { newModel(client, now = { clock }) }
        try {
            queueBehindLimit(model, client, resetAt)
            assertTrue(listModel.delete(client.thread))
            AgentSession.release(model)
            withTimeout(1_000) { deletionStarted.await() }

            listLifetime.cancelAndJoin()
            clock = resetAt
            delay(150)

            assertEquals(listOf("Question"), client.startedTexts)
            assertTrue(client.retriedRunIds.isEmpty())
            assertNull(AgentSession.findLoadedModel(client.thread.id))
        } finally {
            listLifetime.cancel()
            AgentSession.dropDeletedChat(client.thread.id)
            model.onDestroy()
        }
    }

    @Test
    fun accountsResetReleasesAnOpeningThatIsWaitingForWalletAuthority() = runBlocking {
        val client = FakeClient(emptyList())
        lateinit var contextProvider: AgentV2HostContextProvider
        val destroyed = mutableListOf<AgentVM>()
        val sessions = leftChatSessions(destroyed)
        val model = sessions.acquire(client.thread.id) {
            newModel(client, onContextProvider = { contextProvider = it })
        }
        try {
            awaitReady(model)
            contextProvider.onWalletEvent(WalletEvent.AccountWillChange(fromHome = false))
            assertNull(contextProvider.captureMessageAuthority())
            model.acceptOpening(
                listOf(
                    AgentMessage(
                        role = AgentMessageRole.USER,
                        text = "Opening",
                        isStreaming = true
                    ),
                    AgentMessage(role = AgentMessageRole.ASSISTANT, text = "", isStreaming = true)
                ),
                AgentV2EntryPoint()
            )
            sessions.release(client.thread.id, model)
            assertTrue(destroyed.isEmpty())

            WalletCore.notifyEvent(WalletEvent.AccountsReset)

            assertEquals(listOf(model), destroyed)
            assertTrue(sessions.getModels().isEmpty())
            AccountStore.updateActiveAccount("other")
            contextProvider.onWalletEvent(WalletEvent.AccountChanged())
            yield()
            assertTrue(client.startedTexts.isEmpty())
        } finally {
            AccountStore.updateActiveAccount(null)
            model.onDestroy()
        }
    }

    @Test
    fun aLeftChatLetsGoWhenAccountsResetWithQuestionsQueued() = runBlocking {
        val resetAt = 10_000L
        var clock = resetAt - 100
        AccountStore.updateActiveAccount("account")
        val client = FakeClient(emptyList())
        val destroyed = mutableListOf<AgentVM>()
        val sessions = leftChatSessions(destroyed)
        val model = sessions.acquire(client.thread.id) { newModel(client, now = { clock }) }
        try {
            queueBehindLimit(model, client, resetAt)
            val queued = model.messages.last()
            sessions.release(client.thread.id, model)
            assertTrue(destroyed.isEmpty())

            AccountStore.updateActiveAccount(null)
            WalletCore.notifyEvent(WalletEvent.AccountsReset)

            assertFalse(model.isMessageQueued(queued.id))
            assertEquals(listOf(model), destroyed)
            assertTrue(sessions.getModels().isEmpty())
            clock = resetAt
            delay(150)
            assertEquals(listOf("Question"), client.startedTexts)
            assertTrue(client.retriedRunIds.isEmpty())
        } finally {
            AccountStore.updateActiveAccount(null)
            model.onDestroy()
        }
    }

    @Test
    fun aLeftChatLetsGoOnceAWalletSwitchFailsTheQueueALimitHolds() = runBlocking {
        val resetAt = 10_000L
        val client = FakeClient(emptyList())
        lateinit var contextProvider: AgentV2HostContextProvider
        val destroyed = mutableListOf<AgentVM>()
        val sessions = leftChatSessions(destroyed)
        val model = sessions.acquire(client.thread.id) {
            newModel(client, now = { resetAt - 100 }, onContextProvider = { contextProvider = it })
        }
        try {
            queueBehindLimit(model, client, resetAt)
            sessions.release(client.thread.id, model)
            assertTrue(destroyed.isEmpty())

            // The queue waits while the wallet may stay the same
            contextProvider.onWalletEvent(WalletEvent.AccountWillChange(fromHome = false))
            assertTrue(destroyed.isEmpty())
            AccountStore.updateActiveAccount("other")
            contextProvider.onWalletEvent(WalletEvent.AccountChanged())

            assertEquals(listOf(model), destroyed)
            assertEquals(listOf("Question"), client.startedTexts)
            assertTrue(client.retriedRunIds.isEmpty())
        } finally {
            AccountStore.updateActiveAccount(null)
            model.onDestroy()
        }
    }

    @Test
    fun keptChatRefreshKeepsTheQueueALimitHoldsLast() = runBlocking {
        val resetAt = 10_000L
        var clock = resetAt - 100
        val client = FakeClient(history())
        val model = newModel(client, now = { clock })
        try {
            queueBehindLimit(model, client, resetAt)
            val queued = model.messages.last()
            assertEquals("Queued", queued.text)

            val requests = client.messageRequests
            model.refreshThreadIfNeeded(client.thread.copy(revision = 5))
            withTimeout(1_000) {
                while (client.messageRequests == requests) yield()
            }
            repeat(20) { yield() }

            // The held question's failure, though later than the queued question, stays above it
            assertEquals(queued.id, model.messages.last().id)
            assertTrue(model.messages[model.messages.size - 2].isFailure)

            clock = resetAt
            withTimeout(1_000) {
                while (client.startedTexts.size < 2) yield()
            }
            awaitReady(model)
            assertEquals(listOf(client.startedRunIds.first()), client.retriedRunIds)
            assertEquals(listOf("Question", "Queued"), client.startedTexts)
        } finally {
            model.onDestroy()
        }
    }

    /** At the reset, the question a limit held back goes alone, as the same run, then the queue */
    @Test
    fun aLimitResetSendsTheHeldQuestionAloneBeforeTheQueue() = runBlocking {
        val resetAt = 10_000L
        var clock = resetAt - 100
        val client = FakeClient(emptyList())
        val model = newModel(client, now = { clock })
        try {
            queueBehindLimit(model, client, resetAt)
            val retryMayEnd = CompletableDeferred<Unit>()
            client.onRetryRun = { clientRunId ->
                retryMayEnd.await()
                AgentV2RunResult(clientRunId, "run-retried", state = "completed")
            }

            clock = resetAt
            withTimeout(1_000) {
                while (client.retriedRunIds.isEmpty()) yield()
            }
            repeat(20) { yield() }
            assertEquals(client.startedRunIds, client.retriedRunIds)
            assertEquals(listOf("Question"), client.startedTexts)
            assertTrue(model.messages.none { it.isFailure })

            retryMayEnd.complete(Unit)
            withTimeout(1_000) {
                while (client.startedTexts.size < 2) yield()
            }
            awaitReady(model)
            assertEquals(listOf("Question", "Queued"), client.startedTexts)
            assertEquals(1, client.retriedRunIds.size)
        } finally {
            model.onDestroy()
        }
    }

    /** With nothing queued behind it, a question a limit held back waits for Retry at the reset */
    @Test
    fun aLimitResetLeavesAHeldQuestionWithoutAQueueToRetry() = runBlocking {
        val resetAt = 4_102_444_800_000L
        var clock = resetAt - 100
        var inputLimitChanges = 0
        val client = FakeClient(emptyList())
        val model = newModel(client, now = { clock })
        val dictionary = LocaleController::class.java.getDeclaredField("dictionary").apply {
            isAccessible = true
        }
        val previousDictionary = dictionary.get(null)
        val context = ApplicationContextHolder.applicationContext
        val delegate = Proxy.newProxyInstance(
            AgentVM.Delegate::class.java.classLoader,
            arrayOf(AgentVM.Delegate::class.java)
        ) { _, method, _ ->
            if (method.name == "onInputLimitChanged") inputLimitChanges++
            null
        } as AgentVM.Delegate
        model.attach(delegate)
        client.onStartRun = { clientRunId ->
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        clientRunId,
                        threadId = client.thread.id,
                        code = "user_quota_exhausted",
                        retryable = true,
                        resetAt = resetAt
                    )
                )
            )
            AgentV2RunResult(clientRunId, state = "failed")
        }
        try {
            dictionary.set(
                null,
                mapOf(
                    "\$agent_daily_limit_resets_at" to
                        "Daily agent limit reached. Resets at %time%.",
                    "\$agent_daily_limit_reached" to "Daily agent limit reached"
                )
            )
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            awaitReady(model)
            assertTrue(model.isInputBlockedByLimit)
            val failure = model.messages.single { it.isFailure }
            assertEquals(
                "Daily agent limit reached. Resets at ${formatAgentChatTime(
                    context,
                    Date(resetAt)
                )}.",
                failure.text
            )

            clock = resetAt
            val changesBeforeReset = inputLimitChanges
            withTimeout(1_000) {
                while (inputLimitChanges == changesBeforeReset) yield()
            }
            repeat(20) { yield() }
            assertTrue(client.retriedRunIds.isEmpty())
            assertTrue(model.failureRetry != null)
            assertEquals(
                "Daily agent limit reached",
                model.messages.single { it.id == failure.id }.text
            )
        } finally {
            model.detach(delegate)
            model.onDestroy()
            dictionary.set(null, previousDictionary)
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
        client.onStartRun = { clientRunId ->
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        clientRunId,
                        threadId = client.thread.id,
                        code = "user_quota_exhausted",
                        retryable = true,
                        resetAt = resetAt
                    )
                )
            )
            AgentV2RunResult(clientRunId, state = "failed")
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
            model.detach(delegate)
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
            client.onStartRun = { clientRunId ->
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            clientRunId,
                            threadId = client.thread.id,
                            code = code,
                            retryable = true
                        )
                    )
                )
                AgentV2RunResult(clientRunId, state = "failed")
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
    fun ratingReportsItsSaveOnlyWhenTheServerKeepsTheLatestRating() = runBlocking {
        val client = FakeClient(history())
        val model = newModel(client)
        val results = mutableListOf<String>()
        fun rate(feedback: AgentAnswerFeedback?) = model.rateMessage(
            "answer",
            feedback,
            onSaved = { results += "saved $feedback" },
            onFailure = { results += "failed $feedback" }
        )
        suspend fun awaitResults(count: Int) = withTimeout(1_000) {
            while (results.size < count) yield()
        }
        try {
            awaitReady(model)
            client.onSetFeedback = { AgentV2AnswerFeedbackResponse(it) }
            rate(AgentAnswerFeedback.LIKE)
            awaitResults(1)
            assertEquals(listOf("saved LIKE"), results)

            client.onSetFeedback = { error("Offline") }
            rate(AgentAnswerFeedback.DISLIKE)
            awaitResults(2)
            assertEquals("failed DISLIKE", results.last())

            // A rating changed before its save settles reports only the latest one
            val release = CompletableDeferred<Unit>()
            client.onSetFeedback = {
                release.await()
                AgentV2AnswerFeedbackResponse(it)
            }
            rate(null)
            rate(AgentAnswerFeedback.DISLIKE)
            yield()
            release.complete(Unit)
            awaitResults(3)
            yield()
            assertEquals(listOf("saved LIKE", "failed DISLIKE", "saved DISLIKE"), results)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun ratesAnOperatorReplyAsAnAnswer() = runBlocking {
        val reply = AgentV2PersistedMessage(
            "reply",
            "thread",
            "operator",
            "complete",
            createdAt = "2026-10-20T00:00:02Z",
            text = "Hello",
            author = AgentV2OperatorAuthor("operator", "Alex")
        )
        val client = FakeClient(history() + reply)
        val model = newModel(client)
        var isSaved = false
        try {
            awaitReady(model)
            client.onSetFeedback = { AgentV2AnswerFeedbackResponse(it) }
            model.rateMessage(
                "reply",
                AgentAnswerFeedback.LIKE,
                onSaved = { isSaved = true },
                onFailure = {}
            )
            withTimeout(1_000) { while (!isSaved) yield() }

            assertEquals(1, client.feedbackRequests)
            assertEquals(
                AgentAnswerFeedback.LIKE,
                model.messages.single { it.sdkMessageId == "reply" }.feedback
            )
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun retryExpiresOneDayAfterFailureEvenWhenTheLimitResetsLater() = runBlocking {
        val failedAt = 10_000L
        val resetAt = failedAt + 2 * 24 * 60 * 60_000L
        var clock = failedAt
        val client = FakeClient(emptyList())
        val model = newModel(client, now = { clock })
        client.onStartRun = { clientRunId ->
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        clientRunId,
                        threadId = client.thread.id,
                        code = "user_quota_exhausted",
                        retryable = true,
                        resetAt = resetAt
                    )
                )
            )
            AgentV2RunResult(clientRunId, state = "failed")
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

    @Test
    fun cachedHistoryShowsWithNothingToActOnUntilTheHistoryReplacesIt() = runBlocking {
        val client = FakeClient(history())
        val freshHistory = CompletableDeferred<AgentV2ThreadHydration>()
        client.onMessages = { freshHistory.await() }
        client.onCachedMessages = { cachedHistory(client.thread) }
        client.onProblemReportAvailability = { true }
        val model = newModel(client, canShowCachedMessages = true)
        val delegate = Proxy.newProxyInstance(
            AgentVM.Delegate::class.java.classLoader,
            arrayOf(AgentVM.Delegate::class.java)
        ) { _, _, _ -> null } as AgentVM.Delegate
        model.attach(delegate)
        model.setActive(delegate, true)
        try {
            awaitMessages(model)

            assertEquals(AgentVM.State.LOADING, model.state)
            assertEquals(listOf("question", "answer", "stale"), model.messages.map { it.id })
            val cachedAnswer = model.messages[1]
            assertEquals("Cached answer", cachedAnswer.text)
            assertEquals(listOf(AgentDeeplink("Send", actionId = "send")), cachedAnswer.deeplinks)
            assertTrue(model.isCachedMessage("answer"))
            assertTrue(model.publishesAnswerLinks)
            assertEquals(
                listOf(AgentV2FollowUp("more", "question", "Tell me more")),
                cachedAnswer.followups
            )
            assertFalse(cachedAnswer.isComplete)
            assertEquals(0, client.actionPresentationRequests)
            assertFalse(model.canEditMessage("question"))
            assertFalse(model.canRegenerateMessage("answer"))
            assertFalse(model.canReportProblem)
            assertTrue(model.isSupportRequestVisible)
            assertFalse(model.canRequestSupport)
            model.rateMessage("answer", AgentAnswerFeedback.LIKE, onSaved = {}, onFailure = {})
            model.performAction("answer", "send")
            model.loadOlderMessages()
            yield()
            assertEquals(0, client.feedbackRequests)
            assertEquals(0, client.resolveRequests)
            assertEquals(listOf<String?>(null), client.messageCursors)

            // The history's actions load their presentations while the copy still shows
            val presentation = CompletableDeferred<AgentV2ActionPresentation>()
            client.onActionPresentation = { presentation.await() }
            freshHistory.complete(
                AgentV2ThreadHydration(
                    client.thread,
                    client.history.map {
                        it.copy(actions = listOf(AgentV2Action("send", "send", "Send")))
                    },
                    nextCursor = "older"
                )
            )
            withTimeout(1_000) {
                while (client.actionPresentationRequests == 0) yield()
            }
            model.loadOlderMessages()
            yield()
            assertEquals(listOf<String?>(null), client.messageCursors)
            presentation.complete(AgentV2ActionPresentation.Send("active"))
            awaitReady(model)

            assertEquals(listOf("question", "answer"), model.messages.map { it.id })
            assertEquals("Old answer", model.messages[1].text)
            assertTrue(model.messages[1].isComplete)
            assertFalse(model.isCachedMessage("answer"))
            assertTrue(model.canRegenerateMessage("answer"))
            assertTrue(model.canReportProblem)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun cachedSuggestionsSendNothingUntilTheHistoryReplacesThem() = runBlocking {
        val followups = listOf(AgentV2FollowUp("more", "question", "Tell me more"))
        val client = FakeClient(
            history().map { if (it.role == "assistant") it.copy(followups = followups) else it }
        )
        val freshHistory = CompletableDeferred<Unit>()
        client.onMessages = {
            freshHistory.await()
            AgentV2ThreadHydration(client.thread, client.history, null)
        }
        // The copy ends with the answer its suggestions belong to
        client.onCachedMessages = {
            cachedHistory(client.thread).let { it.copy(messages = it.messages.dropLast(1)) }
        }
        client.onStartRun = { awaitCancellation() }
        val model = newModel(client, canShowCachedMessages = true)
        try {
            awaitMessages(model)
            assertTrue(model.isCachedMessage("answer"))
            assertEquals(followups, model.visibleFollowups("answer"))

            assertFalse(model.sendFollowup("answer", "more"))
            yield()
            assertTrue(client.startedTexts.isEmpty())
            assertEquals(listOf("question", "answer"), model.messages.map { it.id })

            freshHistory.complete(Unit)
            awaitReady(model)
            assertFalse(model.isCachedMessage("answer"))
            assertTrue(model.sendFollowup("answer", "more"))
            withTimeout(1_000) {
                while (client.startedTexts.isEmpty()) yield()
            }
            assertEquals(listOf("Tell me more"), client.startedTexts)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun cachedHistoryArrivingAfterTheHistoryRequestEndedIsNotShown() = runBlocking {
        val client = FakeClient(
            history().map { it.copy(actions = listOf(AgentV2Action("send", "send", "Send"))) }
        )
        val cache = CompletableDeferred<AgentV2CachedMessages?>()
        val presentation = CompletableDeferred<AgentV2ActionPresentation>()
        client.onCachedMessages = { cache.await() }
        // The history is mapped after its request ends, while its actions' presentations load
        client.onActionPresentation = { presentation.await() }
        val model = newModel(client, canShowCachedMessages = true)
        try {
            withTimeout(1_000) {
                while (client.actionPresentationRequests == 0) yield()
            }

            cache.complete(cachedHistory(client.thread))
            yield()
            yield()

            assertTrue(model.messages.isEmpty())
            presentation.complete(AgentV2ActionPresentation.Send("active"))
            awaitReady(model)
            assertEquals(listOf("question", "answer"), model.messages.map { it.id })
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun failedHistoryKeepsTheCachedCopyAndAMissingThreadDropsIt() = runBlocking {
        for (code in listOf("network_error", "thread_not_found")) {
            val client = FakeClient(history())
            val freshHistory = CompletableDeferred<AgentV2ThreadHydration>()
            client.onMessages = { freshHistory.await() }
            client.onCachedMessages = { cachedHistory(client.thread) }
            val model = newModel(client, canShowCachedMessages = true)
            try {
                awaitMessages(model)

                freshHistory.completeExceptionally(
                    AgentV2OperationException(AgentV2MutationError(code, retryable = true))
                )
                withTimeout(1_000) {
                    while (model.state != AgentVM.State.ERROR) yield()
                }

                assertEquals(code, model.startupErrorCode)
                assertTrue(model.failureRetry != null)
                val cachedIds = model.messages.filter { it.sdkMessageId != null }.map { it.id }
                if (code == "thread_not_found") {
                    assertTrue(cachedIds.isEmpty())
                } else {
                    assertEquals(listOf("question", "answer", "stale"), cachedIds)
                    assertFalse(model.canRegenerateMessage("answer"))
                    assertEquals(0, client.actionPresentationRequests)
                }
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun failedHistoryHidesTheCachedSuggestionsUntilRetryLoadsTheHistory() = runBlocking {
        val followups = listOf(AgentV2FollowUp("next", "question", "What next"))
        val client = FakeClient(
            history().map { if (it.role == "assistant") it.copy(followups = followups) else it }
        )
        val firstHistory = CompletableDeferred<AgentV2ThreadHydration>()
        client.onMessages = { firstHistory.await() }
        // The copy ends with the answer its suggestions belong to
        client.onCachedMessages = {
            cachedHistory(client.thread).let { it.copy(messages = it.messages.dropLast(1)) }
        }
        val model = newModel(client, canShowCachedMessages = true)
        try {
            awaitMessages(model)
            assertTrue(model.visibleFollowups("answer").isNotEmpty())

            firstHistory.completeExceptionally(
                AgentV2OperationException(AgentV2MutationError("network_error", retryable = true))
            )
            withTimeout(1_000) {
                while (model.state != AgentVM.State.ERROR) yield()
            }
            assertTrue(model.isCachedMessage("answer"))
            assertTrue(model.messages.all { it.followups.isEmpty() })

            client.onMessages = { AgentV2ThreadHydration(client.thread, client.history, null) }
            model.retry()
            awaitReady(model)
            assertFalse(model.isCachedMessage("answer"))
            assertEquals(followups, model.visibleFollowups("answer"))
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun cachedHistoryShowsOnlyInAnEmptyOpenedThread() = runBlocking {
        val opening = listOf(
            AgentMessage(role = AgentMessageRole.USER, text = "Question", isStreaming = true),
            AgentMessage(role = AgentMessageRole.ASSISTANT, text = "", isStreaming = true)
        )
        val news = AgentV2ThreadNewsCard(1, headline = "News", publishedAt = "2026-10-20T00:00:00Z")
        val cases = listOf<Pair<String, CoroutineScope.(FakeClient) -> AgentVM>>(
            "not opened by its id" to {
                newModel(
                    it,
                    canShowCachedMessages = canShowAgentCachedMessages(
                        it.thread,
                        hasOpening = true,
                        readState = AgentThreadReadState(read = { null }, write = {})
                    )
                )
            },
            "opened at its first unread message" to {
                val readState = AgentThreadReadState(read = { null }, write = {})
                readState.onChatAppeared(it.thread.id)
                readState.onChatDisappeared(it.thread.id, seenMessageCount = 1)
                readState.onAnswerCompleted(it.thread.id)
                readState.observe(listOf(it.thread), answeringThreadIds = emptySet())
                assertEquals(1, readState.getSeenMessageCountIfUnread(it.thread))
                newModel(
                    it,
                    canShowCachedMessages = canShowAgentCachedMessages(
                        it.thread,
                        hasOpening = false,
                        readState = readState
                    )
                )
            },
            "a news discussion" to {
                it.thread = it.thread.copy(news = news)
                newModel(it, canShowCachedMessages = true)
            },
            "a new chat" to {
                newModel(
                    it,
                    canShowCachedMessages = true,
                    initialMessages = opening,
                    initialOpeningEntryPoint = AgentV2EntryPoint()
                )
            }
        )
        for ((case, makeModel) in cases) {
            val client = FakeClient(history())
            val freshHistory = CompletableDeferred<AgentV2ThreadHydration>()
            client.onMessages = { freshHistory.await() }
            client.onCachedMessages = { cachedHistory(client.thread) }
            val model = makeModel(client)
            try {
                withTimeout(1_000) {
                    while (client.messageRequests == 0) yield()
                }
                yield()
                assertEquals(case, 0, client.cachedMessageRequests)
            } finally {
                model.onDestroy()
            }
        }

        // A question asked while the copy loads, an unreadable copy and a closed chat show no copy
        val raceCases = listOf<Pair<String, suspend (AgentVM) -> AgentV2CachedMessages?>>(
            "a question" to { model ->
                assertTrue(model.sendMessage("New question"))
                null
            },
            "a failure" to { throw IllegalStateException("Bridge failed") },
            "a closed chat" to { model ->
                model.onDestroy()
                null
            }
        )
        for ((case, beforeCache) in raceCases) {
            val client = FakeClient(history())
            val freshHistory = CompletableDeferred<AgentV2ThreadHydration>()
            val cacheRequested = CompletableDeferred<Unit>()
            val cache = CompletableDeferred<AgentV2CachedMessages?>()
            client.onMessages = { freshHistory.await() }
            client.onCachedMessages = {
                cacheRequested.complete(Unit)
                cache.await()
            }
            val uncaughtErrors = mutableListOf<Throwable>()
            val model = newModel(
                client,
                canShowCachedMessages = true,
                exceptionHandler = CoroutineExceptionHandler { _, error -> uncaughtErrors += error }
            )
            try {
                withTimeout(1_000) { cacheRequested.await() }
                val shownBefore = model.messages.toList()
                runCatching { beforeCache(model) }
                    .onSuccess { cache.complete(cachedHistory(client.thread)) }
                    .onFailure { cache.completeExceptionally(it) }
                yield()
                yield()
                assertTrue(case, model.messages.none { it.id == "stale" })
                assertTrue(case, uncaughtErrors.isEmpty())
                if (case == "a question") {
                    assertEquals(case, listOf("New question"), model.messages.map { it.text })
                } else {
                    assertEquals(case, shownBefore, model.messages)
                }
            } finally {
                freshHistory.complete(AgentV2ThreadHydration(client.thread, client.history))
                model.onDestroy()
            }
        }
    }

    @Test
    fun chatWithItsCopyInMemoryOpensWithItInTheFirstFrame() = runBlocking {
        val client = FakeClient(history())
        val freshHistory = CompletableDeferred<AgentV2ThreadHydration>()
        client.onMessages = { freshHistory.await() }
        val histories = AgentCachedHistories(this) { null }
        val cached = cachedHistory(client.thread)
        histories.storeLoadedPage(cached.thread, cached.messages, cached.hasOlder)

        val model = newModel(client, canShowCachedMessages = true, cachedHistories = histories)

        // Before anything suspends, as the screen draws its first frame
        assertEquals(listOf("question", "answer", "stale"), model.messages.map { it.id })
        assertTrue(model.isCachedMessage("answer"))
        assertEquals(AgentVM.State.LOADING, model.state)
        assertFalse(shouldShowAgentMessagesSkeleton(model, hasOpening = false))
        try {
            withTimeout(1_000) {
                while (client.messageRequests == 0) yield()
            }
            model.performAction("answer", "send")
            model.loadOlderMessages()
            yield()
            assertEquals(0, client.cachedMessageRequests)
            assertEquals(0, client.actionPresentationRequests)
            assertEquals(0, client.resolveRequests)
            assertFalse(model.canRegenerateMessage("answer"))
            assertEquals(listOf<String?>(null), client.messageCursors)

            freshHistory.complete(
                AgentV2ThreadHydration(client.thread, client.history, nextCursor = "older")
            )
            awaitReady(model)

            assertEquals(listOf("question", "answer"), model.messages.map { it.id })
            assertFalse(model.isCachedMessage("answer"))
            val stored = checkNotNull(histories.get(client.thread.id))
            assertEquals(listOf("question", "answer"), stored.messages.map { it.id })
            assertTrue(stored.hasOlder)

            model.clearChat()
            awaitReady(model)
            assertNull(histories.get(client.thread.id))
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun chatOpenedWithItsCopyKeepsItOnFailureAndDropsItForAMissingThread() = runBlocking {
        for (code in listOf("network_error", "thread_not_found")) {
            val client = FakeClient(history())
            client.onMessages = {
                throw AgentV2OperationException(AgentV2MutationError(code, retryable = true))
            }
            val histories = AgentCachedHistories(this) { null }
            val cached = cachedHistory(client.thread)
            histories.storeLoadedPage(cached.thread, cached.messages, cached.hasOlder)
            val model = newModel(client, canShowCachedMessages = true, cachedHistories = histories)
            try {
                withTimeout(1_000) {
                    while (model.state != AgentVM.State.ERROR) yield()
                }

                assertTrue(model.failureRetry != null)
                val cachedIds = model.messages.filter { it.sdkMessageId != null }.map { it.id }
                if (code == "thread_not_found") {
                    assertTrue(cachedIds.isEmpty())
                    assertNull(histories.get(client.thread.id))
                } else {
                    assertEquals(listOf("question", "answer", "stale"), cachedIds)
                    assertFalse(model.canRegenerateMessage("answer"))
                    assertTrue(histories.get(client.thread.id) != null)
                }
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun chatThatJustGotAnAnswerOpensWithoutItsCopies() = runBlocking {
        val client = FakeClient(history())
        client.onMessages = { awaitCancellation() }
        client.onCachedMessages = { cachedHistory(client.thread) }
        val histories = AgentCachedHistories(this) { null }
        val cached = cachedHistory(client.thread)
        histories.storeLoadedPage(cached.thread, cached.messages, cached.hasOlder)
        // The answer completed off screen before the summary counts it: unread without a first unread message
        val readState = AgentThreadReadState(read = { null }, write = {})
        readState.onChatAppeared(client.thread.id)
        readState.onChatDisappeared(client.thread.id, seenMessageCount = client.thread.messageCount)
        readState.onAnswerCompleted(client.thread.id)
        assertTrue(readState.isUnread(client.thread))
        assertNull(readState.getSeenMessageCountIfUnread(client.thread))

        val model = newModel(
            client,
            canShowCachedMessages = canShowAgentCachedMessages(
                client.thread,
                hasOpening = false,
                readState = readState
            ),
            cachedHistories = histories
        )
        try {
            assertTrue(model.messages.isEmpty())
            assertTrue(shouldShowAgentMessagesSkeleton(model, hasOpening = false))
            withTimeout(1_000) {
                while (client.messageRequests == 0) yield()
            }
            yield()
            yield()
            assertEquals(0, client.cachedMessageRequests)
            assertTrue(model.messages.isEmpty())
            assertTrue(shouldShowAgentMessagesSkeleton(model, hasOpening = false))
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun recentlyClosedChatReopenedWithACachedCopyKeepsItsLoadedHistory() = runBlocking {
        val client = FakeClient(history())
        val histories = AgentCachedHistories(this) { null }
        val sessions = AgentThreadSessions<AgentVM>(
            shouldRetain = { it.shouldRetainSession },
            setIdleHandler = { model, handler -> model.onSessionIdle = handler },
            destroy = { it.onDestroy() },
            recentLimit = 8,
            canKeep = { it.canStayLoaded }
        )

        // As `AgentSession.acquire` opens a thread by its id
        fun open() = sessions.acquire(client.thread.id, keepsRecent = true) {
            newModel(client, canShowCachedMessages = true, cachedHistories = histories)
        }.also { it.refreshThreadIfNeeded(client.thread) }
        val model = open()
        try {
            awaitReady(model)
            sessions.release(client.thread.id, model)

            // A newer summary and a different copy of the thread wait in memory and in the SDK
            val cached = cachedHistory(client.thread)
            histories.storeLoadedPage(cached.thread, cached.messages, cached.hasOlder)
            client.onCachedMessages = { cached }
            client.thread = client.thread.copy(revision = 2)
            val freshHistory = CompletableDeferred<AgentV2ThreadHydration>()
            client.onMessages = { freshHistory.await() }
            val reopened = open()
            withTimeout(1_000) {
                while (client.messageRequests < 2) yield()
            }
            yield()

            assertSame(model, reopened)
            assertEquals(
                listOf("Original question", "Old answer"),
                reopened.messages.map {
                    it.text
                }
            )
            assertTrue(reopened.messages.none { reopened.isCachedMessage(it.id) })
            assertEquals(0, client.cachedMessageRequests)
            assertTrue(freshHistory.complete(AgentV2ThreadHydration(client.thread, client.history)))
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun warmChatWithoutConsentDropsItsCopy() = runBlocking {
        val client = FakeClient(history())
        client.hasConsent = false
        val histories = AgentCachedHistories(this) { null }
        val cached = cachedHistory(client.thread)
        histories.storeLoadedPage(cached.thread, cached.messages, cached.hasOlder)
        val model = newModel(client, canShowCachedMessages = true, cachedHistories = histories)
        try {
            assertTrue(model.isCachedMessage("answer"))

            withTimeout(1_000) {
                while (model.state != AgentVM.State.CONSENT_REQUIRED) yield()
            }

            assertTrue(model.messages.none { model.isCachedMessage(it.id) })
            assertTrue(model.messages.isEmpty())
            assertNull(histories.get(client.thread.id))
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun walletResetDropsTheCopyAnOpenChatShows() = runBlocking {
        val client = FakeClient(history())
        client.onMessages = { awaitCancellation() }
        val histories = AgentCachedHistories(this) { null }
        val cached = cachedHistory(client.thread)
        histories.storeLoadedPage(cached.thread, cached.messages, cached.hasOlder)
        val model = newModel(client, canShowCachedMessages = true, cachedHistories = histories)
        try {
            withTimeout(1_000) {
                while (client.messageRequests == 0) yield()
            }
            assertTrue(model.isCachedMessage("answer"))

            WalletCore.notifyEvent(WalletEvent.AccountsReset)

            assertTrue(model.messages.none { model.isCachedMessage(it.id) })
            assertTrue(model.messages.isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun walletResetDuringTheCacheReadShowsNoCopy() = runBlocking {
        val client = FakeClient(history())
        client.onMessages = { awaitCancellation() }
        val cache = CompletableDeferred<AgentV2CachedMessages?>()
        client.onCachedMessages = { cache.await() }
        val model = newModel(client, canShowCachedMessages = true)
        try {
            withTimeout(1_000) {
                while (client.cachedMessageRequests == 0) yield()
            }

            WalletCore.notifyEvent(WalletEvent.AccountsReset)
            cache.complete(cachedHistory(client.thread))
            yield()
            yield()

            assertTrue(model.messages.isEmpty())
            assertFalse(model.isCachedMessage("answer"))
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun chatOpensWithoutACopyInMemoryAsBefore() = runBlocking {
        val news = AgentV2ThreadNewsCard(1, headline = "News", publishedAt = "2026-10-20T00:00:00Z")
        val opening = listOf(
            AgentMessage(role = AgentMessageRole.USER, text = "Question", isStreaming = true),
            AgentMessage(role = AgentMessageRole.ASSISTANT, text = "", isStreaming = true)
        )
        val cases = listOf<
            Triple<
                String,
                Boolean,
                CoroutineScope.(
                    FakeClient,
                    AgentCachedHistories
                ) -> AgentVM
                >
            >(
            Triple("without a copy", false) { client, _ ->
                newModel(client, canShowCachedMessages = true)
            },
            Triple("opened at its first unread message", true) { client, histories ->
                val readState = AgentThreadReadState(read = { null }, write = {})
                readState.onChatAppeared(client.thread.id)
                readState.onChatDisappeared(client.thread.id, seenMessageCount = 1)
                newModel(
                    client,
                    canShowCachedMessages = canShowAgentCachedMessages(
                        client.thread,
                        hasOpening = false,
                        readState = readState
                    ),
                    cachedHistories = histories
                )
            },
            Triple("a news discussion", true) { client, histories ->
                client.thread = client.thread.copy(news = news)
                newModel(client, canShowCachedMessages = true, cachedHistories = histories)
            },
            Triple("a digest discussion", true) { client, histories ->
                client.thread = client.thread.copy(
                    digest = AgentV2ThreadDigestCard(
                        "digest",
                        "2026-10-20T00:00:00Z",
                        0,
                        emptyList()
                    )
                )
                newModel(client, canShowCachedMessages = true, cachedHistories = histories)
            },
            Triple("a new chat", true) { client, histories ->
                newModel(
                    client,
                    canShowCachedMessages = true,
                    initialMessages = opening,
                    initialOpeningEntryPoint = AgentV2EntryPoint(),
                    cachedHistories = histories
                )
            }
        )
        for ((case, hasCopy, makeModel) in cases) {
            val client = FakeClient(history())
            client.onMessages = { awaitCancellation() }
            val histories = AgentCachedHistories(this) { null }
            if (hasCopy) {
                val cached = cachedHistory(client.thread)
                histories.storeLoadedPage(cached.thread, cached.messages, cached.hasOlder)
            }
            val model = makeModel(client, histories)
            try {
                assertTrue(case, model.messages.none { model.isCachedMessage(it.id) })
                assertEquals(
                    case,
                    case != "a new chat",
                    shouldShowAgentMessagesSkeleton(model, hasOpening = case == "a new chat")
                )
            } finally {
                model.onDestroy()
            }
        }
    }

    private fun cachedHistory(thread: AgentV2ThreadSummary) = AgentV2CachedMessages(
        thread,
        history(answer = "Cached answer").map { message ->
            if (message.role != "assistant") return@map message
            message.copy(
                content = AgentV2MessageContent.Markdown(
                    "Cached answer",
                    links = listOf(AgentV2AnswerLink(0, 6, "https://mytonwallet.io"))
                ),
                actions = listOf(AgentV2Action("send", "send", "Send")),
                followups = listOf(AgentV2FollowUp("more", "question", "Tell me more"))
            )
        } + AgentV2PersistedMessage(
            "stale",
            thread.id,
            "user",
            "complete",
            content = AgentV2MessageContent.Markdown("Deleted question"),
            createdAt = "2026-10-20T00:00:02Z"
        ),
        hasOlder = true
    )

    private fun persistedMessage(
        id: String,
        role: String,
        text: String,
        createdAt: String,
        status: String = "complete"
    ) = AgentV2PersistedMessage(
        id,
        "thread",
        role,
        status,
        content = AgentV2MessageContent.Markdown(text),
        createdAt = createdAt
    )

    @Test
    fun supportRequestIsOfferedOutsideSupportAndWaitsOnlyForARunOrARateLimit() = runBlocking {
        var clock = 1_000L
        val client = FakeClient(emptyList())
        val model = newModel(client, now = { clock })
        val runMayEnd = CompletableDeferred<Unit>()
        client.onStartRun = { clientRunId ->
            if (client.startedTexts.size == 1) {
                runMayEnd.await()
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            clientRunId,
                            threadId = client.thread.id,
                            code = "rate_limited",
                            retryable = true,
                            resetAt = 5_000L
                        )
                    )
                )
            }
            AgentV2RunResult(clientRunId, state = "failed")
        }
        val news = newModel(FakeClient(emptyList(), news = NEWS_CARD))
        val digest = newModel(
            FakeClient(emptyList()).apply {
                thread = thread.copy(
                    digest = AgentV2ThreadDigestCard(
                        "digest",
                        "2026-10-20T00:00:00Z",
                        0,
                        emptyList()
                    )
                )
            }
        )
        try {
            awaitReady(model)
            assertTrue(model.isSupportRequestVisible)
            assertTrue(model.canRequestSupport)

            // The daily quota and the Agent's capacity hold back questions, not a support request
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(AgentV2Update.UserQuotaChanged(EXHAUSTED_QUOTA))
            )
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.AvailabilityChanged(
                        AgentV2Availability("capacity_exhausted", resetAt = 5_000L)
                    )
                )
            )
            assertTrue(model.isInputBlockedByLimit)
            assertTrue(model.canRequestSupport)
            model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(AgentV2Update.UserQuotaChanged()))
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.AvailabilityChanged(AgentV2Availability("available"))
                )
            )

            // A run under way, and then its rate limit's wait, hold it back
            assertTrue(model.sendMessage("Question"))
            assertFalse(model.canRequestSupport)
            assertFalse(model.requestSupport(AgentV2SupportRequestSource.HEADER))
            val supportOpening = AgentMessage(
                role = AgentMessageRole.USER,
                text = getAgentSupportRequestText()
            )
            model.acceptOpening(
                listOf(supportOpening),
                AgentV2EntryPoint.supportRequest(AgentV2SupportRequestSource.HEADER)
            )
            assertTrue(model.messages.none { it.id == supportOpening.id })
            runMayEnd.complete(Unit)
            awaitReady(model)
            assertTrue(model.isSupportRequestVisible)
            assertFalse(model.canRequestSupport)
            assertFalse(model.requestSupport(AgentV2SupportRequestSource.HEADER))
            clock = 5_000L
            assertTrue(model.canRequestSupport)
            assertEquals(listOf("Question"), client.startedTexts)

            // Clearing holds it back
            model.clearChat()
            assertFalse(model.canRequestSupport)
            awaitReady(model)
            assertTrue(model.canRequestSupport)

            // Support that has the chat hides it
            for (state in listOf("waiting", "operator")) {
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.ThreadChanged(
                            client.thread.id,
                            model.currentThread.copy(support = AgentV2ThreadSupport(state))
                        )
                    )
                )
                assertFalse(model.isSupportRequestVisible)
                assertFalse(model.canRequestSupport)
            }
            // A news or digest discussion offers it like any other chat
            for (discussion in listOf(news, digest)) {
                awaitReady(discussion)
                assertTrue(discussion.isSupportRequestVisible)
                assertTrue(discussion.canRequestSupport)
            }
        } finally {
            model.onDestroy()
            news.onDestroy()
            digest.onDestroy()
        }
    }

    @Test
    fun supportRequestWaitsForConsent() = runBlocking {
        val client = FakeClient(emptyList()).apply { hasConsent = false }
        val model = newModel(client)
        try {
            withTimeout(1_000) { while (model.state != AgentVM.State.CONSENT_REQUIRED) yield() }
            assertTrue(model.isSupportRequestVisible)
            assertFalse(model.canRequestSupport)
            assertFalse(model.requestSupport(AgentV2SupportRequestSource.HEADER))
            assertTrue(client.startedTexts.isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun supportRequestSendsItsMessageFromEachSource() = runBlocking {
        val entryPoints = listOf(
            UIComponentsR.id.agent_support_button to AgentV2SupportRequestSource.HEADER,
            UIComponentsR.id.agent_support_hint to AgentV2SupportRequestSource.STARTER_HINT
        )
        for ((entryPointId, expectedSource) in entryPoints) {
            val source = getAgentSupportRequestSource(entryPointId)
            assertEquals(expectedSource, source)
            val client = FakeClient(emptyList())
            client.onStartRun =
                { clientRunId -> AgentV2RunResult(clientRunId, "run", state = "completed") }
            val text = getAgentSupportRequestText()
            val entryPoint = AgentV2EntryPoint.supportRequest(source)
            // A new chat from the starter hint opens with the request, which the daily quota doesn't hold back
            val model = if (source == AgentV2SupportRequestSource.STARTER_HINT) {
                newModel(
                    client,
                    initialMessages = listOf(
                        AgentMessage(role = AgentMessageRole.USER, text = text)
                    ),
                    initialOpeningEntryPoint = entryPoint
                ).also {
                    it.onBridgeUpdate(
                        ApiUpdate.ApiUpdateAgentV2(AgentV2Update.UserQuotaChanged(EXHAUSTED_QUOTA))
                    )
                }
            } else {
                newModel(client)
            }
            try {
                awaitReady(model)
                if (source != AgentV2SupportRequestSource.STARTER_HINT) {
                    // Cancel sends nothing; Call does
                    lateinit var call: () -> Unit
                    var cancel: (() -> Unit)? = null
                    AgentSupportRequestConfirmation(hasConsent = true) {
                        model.requestSupport(source)
                    }.present { _, _, action, onAction, cancelTitle, onCancel ->
                        assertEquals("\$agent_support_confirm_action", action)
                        assertEquals("Cancel", cancelTitle)
                        call = onAction
                        cancel = onCancel
                    }
                    cancel?.invoke()
                    yield()
                    assertTrue(client.startedTexts.isEmpty())
                    call()
                }
                withTimeout(1_000) { while (client.startedTexts.isEmpty()) yield() }
                awaitReady(model)

                assertEquals(listOf(text), client.startedTexts)
                assertEquals(listOf<AgentV2EntryPoint?>(entryPoint), client.startedEntryPoints)
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun confirmationSendsNothingOnceSupportCanNoLongerBeCalled() = runBlocking {
        val client = FakeClient(emptyList())
        val runMayEnd = CompletableDeferred<Unit>()
        client.onStartRun = { clientRunId ->
            runMayEnd.await()
            AgentV2RunResult(clientRunId, "run", state = "completed")
        }
        val model = newModel(client)
        try {
            awaitReady(model)
            lateinit var call: () -> Unit
            AgentSupportRequestConfirmation(hasConsent = true) {
                model.requestSupport(AgentV2SupportRequestSource.HEADER)
            }.present { _, _, _, onAction, _, _ -> call = onAction }
            assertTrue(model.sendMessage("Question"))
            call()
            runMayEnd.complete(Unit)
            awaitReady(model)

            assertEquals(listOf("Question"), client.startedTexts)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun confirmationNamesTheWalletAddressesOnlyWithConsentAndAWallet() {
        fun text(hasConsent: Boolean) = AgentSupportRequestConfirmation(hasConsent) {}.text
        val noWallet = "\$agent_support_confirm_text_no_wallet"
        assertEquals(noWallet, text(hasConsent = true))
        AccountStore.updateActiveAccount("account")
        try {
            assertEquals("\$agent_support_confirm_text", text(hasConsent = true))
            assertEquals(noWallet, text(hasConsent = false))
        } finally {
            AccountStore.updateActiveAccount(null)
        }
    }

    @Test
    fun failedSupportRequestLeavesRetryToTheQuestionALimitHeld() = runBlocking {
        val resetAt = 10_000L
        var clock = resetAt - 1_000
        val client = FakeClient(emptyList())
        val model = newModel(client, now = { clock })
        client.onRetryRun =
            { clientRunId -> AgentV2RunResult(clientRunId, "run-retried", state = "completed") }
        client.onStartRun = { clientRunId ->
            val isQuestion = client.startedTexts.size == 1
            val code = if (isQuestion) "user_quota_exhausted" else "support_escalation_rate_limited"
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        clientRunId,
                        threadId = client.thread.id,
                        code = code,
                        retryable = code == "user_quota_exhausted",
                        resetAt = resetAt.takeIf { code == "user_quota_exhausted" }
                    )
                )
            )
            AgentV2RunResult(clientRunId, state = "failed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            awaitReady(model)
            assertTrue(model.isInputBlockedByLimit)

            assertTrue(model.requestSupport(AgentV2SupportRequestSource.HEADER))
            awaitReady(model)
            val (heldFailure, request, failure) = model.messages.takeLast(3)
            assertTrue(failure.isFailure)
            assertEquals("\$agent_support_rate_limited", failure.text)
            assertEquals(getAgentSupportRequestText(), request.text)

            // Once the quota resets, Retry shows under the held question's failure, above the failed request
            clock = resetAt
            assertTrue(heldFailure.isFailure)
            val rowIds = model.messages.map { it.id } + null
            assertEquals(
                model.messages.indexOf(heldFailure),
                model.findFailureRetryRowIndex(rowIds)
            )
            checkNotNull(model.failureRetry).invoke()
            awaitReady(model)
            assertEquals(listOf(client.startedRunIds.first()), client.retriedRunIds)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun rateLimitedSupportRequestKeepsTheCooldownAndTheHeldQuestionsRetry() = runBlocking {
        val quotaResetAt = 5_000L
        val cooldownEnd = 10_000L
        var clock = 1_000L
        val client = FakeClient(emptyList())
        val model = newModel(client, now = { clock })
        client.onRetryRun =
            { clientRunId -> AgentV2RunResult(clientRunId, "run-retried", state = "completed") }
        client.onStartRun = { clientRunId ->
            val isQuestion = client.startedTexts.size == 1
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.RunFailed(
                        clientRunId,
                        threadId = client.thread.id,
                        code = if (isQuestion) "user_quota_exhausted" else "rate_limited",
                        retryable = true,
                        resetAt = if (isQuestion) quotaResetAt else cooldownEnd
                    )
                )
            )
            AgentV2RunResult(clientRunId, state = "failed")
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            awaitReady(model)
            assertTrue(model.requestSupport(AgentV2SupportRequestSource.HEADER))
            awaitReady(model)
            val heldFailure = model.messages[1]
            assertEquals(agentV2ErrorText("rate_limited"), model.messages.last().text)

            // The quota has reset, the server's cooldown hasn't: nothing goes, Retry included
            clock = quotaResetAt
            assertFalse(model.canRequestSupport)
            assertTrue(model.isInputBlockedByLimit)
            assertNull(model.failureRetry)

            // After the cooldown, Retry sends the held question, never the support request
            clock = cooldownEnd
            assertTrue(model.canRequestSupport)
            assertFalse(model.isInputBlockedByLimit)
            assertEquals(
                model.messages.indexOf(heldFailure),
                model.findFailureRetryRowIndex(model.messages.map { it.id })
            )
            checkNotNull(model.failureRetry).invoke()
            awaitReady(model)
            assertEquals(listOf(client.startedRunIds.first()), client.retriedRunIds)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun emptyChatsSupportHintOpensTheChatSupportHasOrCallsSupportHere() = runBlocking {
        val supportThread = AgentV2ThreadSummary(
            "support",
            1,
            lastActivityAt = "2026-10-20T00:00:00Z",
            support = AgentV2ThreadSupport("waiting")
        )
        val lists = listOf(
            listOf(AgentV2ThreadListItem(supportThread)),
            emptyList(),
            null
        )
        for (threads in lists) {
            val list = CompletableDeferred<AgentV2ThreadListResponse>()
            var listRequests = 0
            val client = FakeClient(emptyList()).apply {
                onListThreads = {
                    listRequests++
                    list.await()
                }
                onStartRun =
                    { clientRunId -> AgentV2RunResult(clientRunId, "run", state = "completed") }
            }
            val model = newModel(client)
            val opened = mutableListOf<String>()
            try {
                awaitReady(model)
                withTimeout(1_000) { while (model.visibleHints.isEmpty()) yield() }
                assertEquals(AGENT_SUPPORT_HINT_ID, model.visibleHints.last().id)

                // The hint waits for the server's chats, which the chat reads as it shows the hint
                withTimeout(1_000) { while (listRequests == 0) yield() }
                assertFalse(model.canRequestSupportFromStarterHint)
                model.requestSupportFromStarterHint { opened += it.id }
                if (threads == null) {
                    list.completeExceptionally(IllegalStateException("Unavailable"))
                } else {
                    list.complete(AgentV2ThreadListResponse(threads))
                }
                repeat(3) { yield() }
                assertEquals(threads != null, model.canRequestSupportFromStarterHint)
                assertTrue(opened.isEmpty())
                assertTrue(client.startedEntryPoints.isEmpty())

                model.requestSupportFromStarterHint { opened += it.id }
                awaitReady(model)
                assertEquals(1, listRequests)

                when {
                    threads == null -> {
                        assertTrue(opened.isEmpty())
                        assertTrue(client.startedEntryPoints.isEmpty())
                    }

                    threads.isNotEmpty() -> {
                        assertEquals(listOf("support"), opened)
                        assertTrue(client.startedEntryPoints.isEmpty())
                    }

                    else -> {
                        assertTrue(opened.isEmpty())
                        assertEquals(
                            listOf<AgentV2EntryPoint?>(
                                AgentV2EntryPoint.supportRequest(
                                    AgentV2SupportRequestSource.STARTER_HINT
                                )
                            ),
                            client.startedEntryPoints
                        )
                    }
                }
            } finally {
                model.onDestroy()
            }
        }
    }

    @Test
    fun admittedSupportRequestQueuesTheQuestionALimitHeldAfterIt() = runBlocking {
        val client = FakeClient(emptyList())
        val model = newModel(client)
        client.onStartRun = { clientRunId ->
            when (client.startedTexts.size) {
                1 -> {
                    model.onBridgeUpdate(
                        ApiUpdate.ApiUpdateAgentV2(
                            AgentV2Update.RunFailed(
                                clientRunId,
                                threadId = client.thread.id,
                                code = "user_quota_exhausted",
                                retryable = true,
                                resetAt = System.currentTimeMillis() + 60_000
                            )
                        )
                    )
                    AgentV2RunResult(clientRunId, state = "failed")
                }

                2 -> {
                    listOf(
                        AgentV2Update.RunStarted(
                            clientRunId,
                            "support-run",
                            client.thread.id,
                            2,
                            "request"
                        ),
                        AgentV2Update.ThreadChanged(
                            client.thread.id,
                            client.thread.copy(
                                revision = 2,
                                support = AgentV2ThreadSupport("waiting")
                            )
                        )
                    ).forEach { model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(it)) }
                    AgentV2RunResult(clientRunId, "support-run", "request", state = "completed")
                }

                else -> AgentV2RunResult(clientRunId, "operator-run", state = "completed")
            }
        }
        try {
            awaitReady(model)
            assertTrue(model.sendMessage("Question"))
            awaitReady(model)
            assertTrue(model.requestSupport(AgentV2SupportRequestSource.HEADER))
            withTimeout(1_000) { while (client.startedTexts.size < 3) yield() }
            awaitReady(model)

            // The quota holds back nothing that goes to an operator
            assertEquals(
                listOf("Question", getAgentSupportRequestText(), "Question"),
                client.startedTexts
            )
            assertEquals(
                listOf(getAgentSupportRequestText(), "Question"),
                model.messages.filter { it.role == AgentMessageRole.USER }.map { it.text }
            )
            assertTrue(model.messages.none { it.isFailure })
            assertTrue(client.retriedRunIds.isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun quotaAndCapacityDoNotBlockTheComposerWhileSupportHasTheChat() = runBlocking {
        val client = FakeClient(emptyList())
        val model = newModel(client)
        try {
            awaitReady(model)
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(AgentV2Update.UserQuotaChanged(EXHAUSTED_QUOTA))
            )
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.AvailabilityChanged(
                        AgentV2Availability(
                            "capacity_exhausted",
                            resetAt = System.currentTimeMillis() + 60_000
                        )
                    )
                )
            )
            assertTrue(model.isInputBlockedByLimit)
            for ((state, isBlocked) in listOf(
                "waiting" to false,
                "operator" to false,
                "closed" to true
            )) {
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.ThreadChanged(
                            client.thread.id,
                            client.thread.copy(support = AgentV2ThreadSupport(state))
                        )
                    )
                )
                assertEquals(isBlocked, model.isInputBlockedByLimit)
            }
            // The capacity alone, without the quota
            model.onBridgeUpdate(ApiUpdate.ApiUpdateAgentV2(AgentV2Update.UserQuotaChanged()))
            assertTrue(model.isInputBlockedByLimit)
            model.onBridgeUpdate(
                ApiUpdate.ApiUpdateAgentV2(
                    AgentV2Update.ThreadChanged(
                        client.thread.id,
                        client.thread.copy(support = AgentV2ThreadSupport("waiting"))
                    )
                )
            )
            assertFalse(model.isInputBlockedByLimit)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun supportRequestWaitsWhileOlderHistoryLoads() = runBlocking {
        val olderPage = CompletableDeferred<AgentV2ThreadHydration>()
        val client = FakeClient(history()).apply {
            onMessagePage = { cursor, _ ->
                if (cursor ==
                    null
                ) {
                    AgentV2ThreadHydration(thread, history, "older")
                } else {
                    olderPage.await()
                }
            }
        }
        val model = newModel(client)
        try {
            awaitReady(model)
            assertTrue(model.canRequestSupport)

            model.loadOlderMessages()
            assertTrue(model.isLoadingOlderMessages)
            assertFalse(model.canRequestSupport)
            assertFalse(model.requestSupport(AgentV2SupportRequestSource.HEADER))

            olderPage.complete(AgentV2ThreadHydration(client.thread, emptyList()))
            withTimeout(1_000) { while (model.isLoadingOlderMessages) yield() }
            assertTrue(model.canRequestSupport)
            assertTrue(client.startedTexts.isEmpty())
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

    @Test
    fun offersProblemReportsBeforeTheServerAnswersAndSendsAHeldReportOnce() = runBlocking {
        val availability = CompletableDeferred<Boolean>()
        val client = FakeClient(emptyList()).apply {
            onProblemReportAvailability = { availability.await() }
        }
        val model = newModel(client)
        try {
            awaitReady(model)
            // The server's check hasn't answered
            assertTrue(model.canReportProblem)
            val results = mutableListOf<Boolean>()
            model.reportProblem(null, "Wrong answer") { results += it }
            repeat(20) { yield() }
            assertTrue("Held until the server's check answers", client.reports.isEmpty())

            availability.complete(true)
            withTimeout(1_000) {
                while (results.isEmpty()) yield()
            }
            assertEquals(listOf(true), results)
            assertEquals(listOf(client.thread.id to "Wrong answer"), client.reports)
            assertTrue(model.canReportProblem)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun serverTakingNoReportsTakesTheProblemReportAway() = runBlocking {
        val client = FakeClient(emptyList())
        val model = newModel(client)
        try {
            awaitReady(model)
            withTimeout(1_000) {
                while (model.canReportProblem) yield()
            }
            val results = mutableListOf<Boolean>()
            model.reportProblem(null, "Wrong answer") { results += it }
            withTimeout(1_000) {
                while (results.isEmpty()) yield()
            }
            assertEquals(listOf(false), results)
            assertTrue(client.reports.isEmpty())
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun offersNoProblemReportBeforeConsent() = runBlocking {
        val client = FakeClient(emptyList()).apply {
            hasConsent = false
            onProblemReportAvailability = { true }
        }
        val model = newModel(client)
        try {
            withTimeout(1_000) {
                while (model.state != AgentVM.State.CONSENT_REQUIRED) yield()
            }
            assertFalse(model.canReportProblem)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun keptNewsDiscussionSendsWithoutTheSheetOnceTheAgentIsAllowedElsewhere() = runBlocking {
        val client = FakeClient(emptyList(), news = NEWS_CARD).apply {
            hasConsent = false
            onProblemReportAvailability = { true }
            onStartRun = { clientRunId ->
                AgentV2RunResult(clientRunId, "run", state = "completed")
            }
        }
        val model = newModel(client)
        try {
            awaitReady(model)
            assertEquals(false, model.hasConsent)
            assertFalse(model.canReportProblem)

            // The user allows the Agent from the chat list while `AgentSession` keeps the discussion's model
            client.hasConsent = true
            var asked = 0
            var isSent = false
            val gate = createDiscussionConsentGate(
                model = { model },
                askForConsent = { _, _ -> asked++ }
            )
            gate.request { isSent = model.sendMessage("What does this mean?") }

            assertEquals(0, asked)
            assertTrue(isSent)
            assertEquals(true, model.hasConsent)
            withTimeout(1_000) {
                while (!model.canReportProblem || client.startedTexts.isEmpty()) yield()
            }
            assertEquals(listOf("What does this mean?"), client.startedTexts)
        } finally {
            model.onDestroy()
        }
    }

    @Test
    fun accountsResetForgetsTheKnownConsent() {
        LiveAgentV2Client::class.java.getDeclaredField("isConsentGiven").apply {
            isAccessible = true
            setBoolean(null, true)
        }
        assertTrue(LiveAgentV2Client().isConsentKnownGiven)

        LiveAgentV2Client.forgetKnownConsent()

        assertFalse(LiveAgentV2Client().isConsentKnownGiven)
    }

    private fun createPollingDelegate(
        onRefreshed: () -> Unit = {},
        onError: () -> Unit = {}
    ): AgentVM.Delegate = Proxy.newProxyInstance(
        AgentVM.Delegate::class.java.classLoader,
        arrayOf(AgentVM.Delegate::class.java)
    ) { _, method, _ ->
        if (method.name == "onError") onError()
        if (method.name == "onMessagesRefreshed") onRefreshed()
        null
    } as AgentVM.Delegate

    private fun CoroutineScope.newModel(
        client: FakeClient,
        now: () -> Long = System::currentTimeMillis,
        canShowCachedMessages: Boolean = false,
        initialMessages: List<AgentMessage> = emptyList(),
        initialOpeningEntryPoint: AgentV2EntryPoint? = null,
        exceptionHandler: CoroutineExceptionHandler? = null,
        cachedHistories: AgentCachedHistories = AgentCachedHistories(this) { null },
        stoppedAnswerDurationMs: Long = 0L,
        waitForSupportPoll: suspend () -> Unit = { delay(15_000) },
        onContextProvider: (AgentV2HostContextProvider) -> Unit = {}
    ): AgentVM {
        val modelScope = CoroutineScope(
            coroutineContext + SupervisorJob(coroutineContext[Job]) +
                (exceptionHandler ?: EmptyCoroutineContext)
        )
        val contextProvider = AgentV2HostContextProvider(client, modelScope) {
            AgentHostContextSnapshot(AccountStore.activeAccountId, JSONObject())
        }
        onContextProvider(contextProvider)
        return AgentVM(
            client = client,
            initialThread = client.thread,
            initialMessages = initialMessages,
            initialOpeningEntryPoint = initialOpeningEntryPoint,
            canShowCachedMessages = canShowCachedMessages,
            cachedHistories = cachedHistories,
            scope = modelScope,
            contextProvider = contextProvider,
            now = now,
            stoppedAnswerDurationMs = { stoppedAnswerDurationMs },
            waitForSupportPoll = waitForSupportPoll
        )
    }

    private suspend fun awaitMessages(model: AgentVM) = withTimeout(1_000) {
        while (model.messages.isEmpty()) yield()
    }

    private suspend fun awaitReady(model: AgentVM) = withTimeout(1_000) {
        while (model.state != AgentVM.State.READY) {
            assertFalse("Model startup failed", model.state == AgentVM.State.ERROR)
            yield()
        }
    }

    private suspend fun CoroutineScope.assertQueueWaitsForDeletion(isFromList: Boolean) {
        for (shouldDelete in listOf(false, true)) {
            val resetAt = 10_000L
            var clock = resetAt - 100
            val client = FakeClient(emptyList())
            val deletionStarted = CompletableDeferred<Unit>()
            val deletionMayEnd = CompletableDeferred<Unit>()
            val deletionFailed = CompletableDeferred<Throwable>()
            client.onDeleteThread = {
                deletionStarted.complete(Unit)
                deletionMayEnd.await()
                if (!shouldDelete) error("Deletion refused")
            }
            val model = AgentSession.acquire(client.thread) { newModel(client, now = { clock }) }
            try {
                queueBehindLimit(model, client, resetAt)
                val queued = model.messages.last()
                if (isFromList) {
                    val listClient = object : AgentThreadListClient by LiveAgentThreadListClient() {
                        override suspend fun delete(id: String) = client.deleteThread(id)
                    }
                    val listModel = AgentThreadListModel(this, client = listClient)
                    assertTrue(
                        listModel.delete(client.thread) {
                            deletionFailed.complete(IllegalStateException("Deletion refused"))
                        }
                    )
                } else {
                    AgentSession.deleteChat(model) { deletionFailed.complete(it) }
                }
                AgentSession.release(model)
                withTimeout(1_000) { deletionStarted.await() }

                assertTrue(model.isMessageQueued(queued.id))
                assertSame(model, AgentSession.findLoadedModel(client.thread.id))
                clock = resetAt
                delay(150)
                assertEquals(listOf("Question"), client.startedTexts)
                assertTrue(client.retriedRunIds.isEmpty())

                deletionMayEnd.complete(Unit)
                if (!shouldDelete) {
                    withTimeout(1_000) {
                        deletionFailed.await()
                        while (client.startedTexts.size < 2) yield()
                    }
                    awaitReady(model)
                    assertEquals(listOf("Question", "Queued"), client.startedTexts)
                }
                withTimeout(1_000) {
                    while (AgentSession.findLoadedModel(client.thread.id) != null) yield()
                }
                assertFalse(model.isMessageQueued(queued.id))
                if (shouldDelete) {
                    assertEquals(listOf("Question"), client.startedTexts)
                    assertTrue(client.retriedRunIds.isEmpty())
                }
            } finally {
                deletionMayEnd.complete(Unit)
                AgentSession.dropDeletedChat(client.thread.id)
                model.onDestroy()
            }
        }
    }

    /**
     * Sends a question that a quota resetting at [resetAt] holds back, after queueing another
     * behind it while it runs, and returns once the chat is ready with the queue held. The held
     * question's retry and the questions sent after it complete.
     */
    private suspend fun queueBehindLimit(model: AgentVM, client: FakeClient, resetAt: Long) {
        val questionMayFail = CompletableDeferred<Unit>()
        client.onRetryRun = { clientRunId ->
            AgentV2RunResult(clientRunId, "run-retried", state = "completed")
        }
        client.onStartRun = { clientRunId ->
            if (client.startedTexts.size == 1) {
                questionMayFail.await()
                model.onBridgeUpdate(
                    ApiUpdate.ApiUpdateAgentV2(
                        AgentV2Update.RunFailed(
                            clientRunId,
                            threadId = client.thread.id,
                            code = "user_quota_exhausted",
                            retryable = true,
                            resetAt = resetAt
                        )
                    )
                )
                AgentV2RunResult(clientRunId, state = "failed")
            } else {
                AgentV2RunResult(clientRunId, "run-queued", state = "completed")
            }
        }
        awaitReady(model)
        assertTrue(model.sendMessage("Question"))
        withTimeout(1_000) {
            while (client.startedTexts.isEmpty()) yield()
        }
        assertTrue(model.sendMessage("Queued"))
        // The held question's failure comes later than the queued question
        delay(5)
        questionMayFail.complete(Unit)
        awaitReady(model)
        assertTrue(model.isInputBlockedByLimit)
        assertEquals(listOf("Question"), client.startedTexts)
    }

    // No left chat stays loaded for reopening, as when it is no longer among the latest ones
    private fun leftChatSessions(destroyed: MutableList<AgentVM>) = AgentThreadSessions<AgentVM>(
        shouldRetain = { it.shouldRetainSession },
        setIdleHandler = { model, handler -> model.onSessionIdle = handler },
        destroy = { model ->
            destroyed += model
            model.onDestroy()
        }
    )

    private class FakeClient(
        var history: List<AgentV2PersistedMessage>,
        messageCount: Int = history.size,
        news: AgentV2ThreadNewsCard? = null
    ) : AgentV2Client by LiveAgentV2Client() {
        var thread = AgentV2ThreadSummary("thread", 1, messageCount = messageCount, news = news)
        var messageRequests = 0
            private set
        val messageCursors = mutableListOf<String?>()
        var onMessages: suspend () -> AgentV2ThreadHydration = {
            AgentV2ThreadHydration(thread, history, nextCursor)
        }
        var cachedMessageRequests = 0
            private set
        var onCachedMessages: suspend () -> AgentV2CachedMessages? = { null }
        var actionPresentationRequests = 0
            private set
        var onActionPresentation: suspend () -> AgentV2ActionPresentation = {
            error("Unexpected action presentation")
        }
        var resolveRequests = 0
            private set
        var feedbackRequests = 0
            private set
        val startedTexts = mutableListOf<String>()
        val stopRequests = mutableListOf<String>()
        var onStopRun: suspend () -> Unit = {}
        var onDeleteThread: suspend () -> Unit = { error("Unexpected deletion") }
        val startedRunIds = mutableListOf<String>()
        val startedRevisions = mutableListOf<Int>()
        val startedEntryPoints = mutableListOf<AgentV2EntryPoint?>()
        var onStartRun: suspend (String) -> AgentV2RunResult = { error("Unexpected run") }
        var onRetryRun: suspend (String) -> AgentV2RunResult? = { error("Unexpected Retry") }
        var onSetFeedback: suspend (String?) -> AgentV2AnswerFeedbackResponse = {
            error("Unexpected feedback")
        }
        var onActionPresentationOf: (suspend (String, String) -> AgentV2ActionPresentation)? = null
        var hasConsent = true
        var onListThreads: suspend () -> AgentV2ThreadListResponse = { error("Unexpected list") }
        var onProblemReportAvailability: suspend () -> Boolean = { false }
        val reports = mutableListOf<Pair<String, String?>>()

        override suspend fun consent() = hasConsent
        override suspend fun listThreads(cursor: String?, limit: Int?, query: String?) =
            onListThreads()
        override suspend fun updateHostContext(context: JSONObject?) {}
        override suspend fun setChatActive(isActive: Boolean) {}
        override suspend fun problemReportAvailability() = onProblemReportAvailability()
        override suspend fun reportProblem(threadId: String, messageId: String?, comment: String?) {
            reports += threadId to comment
        }
        override suspend fun loadAvailability() {}
        override suspend fun loadUserQuota() {}
        override suspend fun hints(langCode: String?) =
            AgentV2HintsResponse(3, "catalog", emptyList())

        var nextCursor: String? = null
        var olderPages: Map<String, AgentV2ThreadHydration> = emptyMap()
        var messagesError: Throwable? = null
        var onMessagePage: (suspend (String?, Int) -> AgentV2ThreadHydration)? = null

        override suspend fun messages(
            threadId: String,
            cursor: String?,
            limit: Int
        ): AgentV2ThreadHydration {
            assertEquals(thread.id, threadId)
            messageRequests++
            messageCursors += cursor
            onMessagePage?.let { return it(cursor, limit) }
            messagesError?.let { throw it }
            cursor?.let { return olderPages.getValue(it) }
            return onMessages()
        }

        override suspend fun getCachedMessages(threadId: String): AgentV2CachedMessages? {
            assertEquals(thread.id, threadId)
            cachedMessageRequests++
            return onCachedMessages()
        }

        override suspend fun actionPresentation(
            messageId: String,
            actionId: String
        ): AgentV2ActionPresentation {
            actionPresentationRequests++
            onActionPresentationOf?.let { return it(messageId, actionId) }
            return onActionPresentation()
        }

        override suspend fun resolveAction(
            messageId: String,
            actionId: String
        ): AgentV2ResolvedAction {
            resolveRequests++
            error("Unexpected action")
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
            startedTexts += text
            startedRunIds += clientRunId
            startedRevisions += revision
            startedEntryPoints += entryPoint
            return onStartRun(clientRunId)
        }

        override suspend fun stopRun(threadId: String) {
            stopRequests += threadId
            onStopRun()
        }

        override suspend fun deleteThread(threadId: String): AgentV2ThreadDeleteResponse {
            assertEquals(thread.id, threadId)
            onDeleteThread()
            return AgentV2ThreadDeleteResponse(threadId, duplicate = false)
        }

        val retriedRunIds = mutableListOf<String>()

        override suspend fun retryRun(clientRunId: String): AgentV2RunResult? {
            retriedRunIds += clientRunId
            return onRetryRun(clientRunId)
        }

        override suspend fun clearThread(threadId: String, revision: Int) =
            AgentV2ThreadResponse(thread.copy(revision = revision + 1, messageCount = 0))

        override suspend fun setMessageFeedback(
            threadId: String,
            messageId: String,
            feedback: String?
        ): AgentV2AnswerFeedbackResponse {
            feedbackRequests++
            return onSetFeedback(feedback)
        }
    }

    companion object {
        private val EXHAUSTED_QUOTA = AgentV2UserQuota(20, 20, 0, "2100-01-01T00:00:00Z")
        private val NEWS_CARD = AgentV2ThreadNewsCard(
            eventId = 7,
            headline = "Headline",
            publishedAt = "2026-10-20T00:00:00Z"
        )
        private var previousLanguage: WLanguage? = null
        private var previousApplicationContext: Context? = null

        @JvmStatic
        @BeforeClass
        fun initializeEmptyWalletStorage() {
            ApplicationContextHolder::class.java.getDeclaredField("applicationContext").apply {
                isAccessible = true
                previousApplicationContext = get(null) as Context?
                set(null, ContextWrapper(null))
            }
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
            ApplicationContextHolder::class.java.getDeclaredField("applicationContext").apply {
                isAccessible = true
                set(null, previousApplicationContext)
            }
            LocaleController::class.java.getDeclaredField("_activeLanguage").apply {
                isAccessible = true
                set(null, previousLanguage)
            }
        }
    }
}
