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
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ProblemReportResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
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
    fun decodesDefaultThreadOperationErrorsThroughTheActualApiMethod() {
        val resultAdapter = moshi.adapter<AgentV2MutationResult<AgentV2ThreadResponse>>(
            ApiMethod.AgentV2.GetDefaultThread().type
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
