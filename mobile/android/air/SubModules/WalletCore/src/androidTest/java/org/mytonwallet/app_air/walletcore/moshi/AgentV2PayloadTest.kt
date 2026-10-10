package org.mytonwallet.app_air.walletcore.moshi

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AssetRef
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUpReference
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

class AgentV2PayloadTest {
    @Test
    fun commandsPreserveEntryPointsAndOmitAbsentFields() {
        val entryPoints = listOf(
            AgentV2EntryPoint() to """{"kind":"agentTab"}""",
            AgentV2EntryPoint(
                kind = "portfolioChart",
                chartId = "netWorth",
                range = "7d",
                accountScope = "current",
                source = "analyzeIt"
            ) to
                """{"kind":"portfolioChart","chartId":"netWorth","range":"7d","accountScope":"current","source":"analyzeIt"}""",
            AgentV2EntryPoint(kind = "tokenScreen", asset = AgentV2AssetRef("ton", "ton")) to
                """{"kind":"tokenScreen","asset":{"slug":"ton","chain":"ton"}}""",
            AgentV2EntryPoint(kind = "globalSearch", query = "a\"b") to
                """{"kind":"globalSearch","query":"a\"b"}""",
            AgentV2EntryPoint(
                kind = "emptyState",
                surface = "agentTab",
                hintId = "learn.security",
                catalogVersion = "agent-starter-hints-v1"
            ) to
                """{"kind":"emptyState","surface":"agentTab","hintId":"learn.security","catalogVersion":"agent-starter-hints-v1"}""",
            AgentV2EntryPoint(asset = AgentV2AssetRef("token", "ton", "address")) to
                """{"kind":"agentTab","asset":{"slug":"token","chain":"ton","tokenAddress":"address"}}"""
        )
        for ((entryPoint, expected) in entryPoints) {
            for (threadId in listOf(null, "thread")) {
                val arguments = ApiMethod.AgentV2.StartRun(threadId, 7, "hello\nworld", entryPoint)
                    .arguments
                val command = JSONArray(arguments).getJSONObject(0)
                assertEquals(threadId != null, command.has("threadId"))
                assertEquals(threadId, command.opt("threadId"))
                assertEquals(7, command.getInt("expectedThreadRevision"))
                assertEquals("append", command.getJSONObject("input").getString("kind"))
                assertEquals("hello\nworld", command.getJSONObject("input").getString("text"))
                assertEquals(
                    JSONObject(expected).toMap(),
                    command.getJSONObject("entryPoint").toMap()
                )
                assertFalse(command.has("followupOf"))
            }
        }
    }

    @Test
    fun followupCommandsPreserveReferenceAndOmitEntryPoint() {
        val reference = AgentV2FollowUpReference("server-message", "server-followup")
        val command = JSONArray(
            ApiMethod.AgentV2.StartRun(
                "thread",
                7,
                "How does staking work?",
                followupOf = reference
            ).arguments
        ).getJSONObject(0)

        assertEquals(
            mapOf(
                "threadId" to "thread",
                "expectedThreadRevision" to 7,
                "input" to mapOf("kind" to "append", "text" to "How does staking work?"),
                "followupOf" to mapOf(
                    "messageId" to reference.messageId,
                    "followupId" to reference.followupId
                )
            ),
            command.toMap()
        )
    }

    @Test
    fun regenerationTargetsTheAnswerWithoutResendingUserText() {
        val command = JSONArray(
            ApiMethod.AgentV2.StartRun(
                "thread",
                7,
                "Unused",
                targetAssistantMessageId = "server-answer"
            ).arguments
        ).getJSONObject(0)
        assertEquals(
            mapOf(
                "threadId" to "thread",
                "expectedThreadRevision" to 7,
                "input" to mapOf(
                    "kind" to "regenerate",
                    "targetAssistantMessageId" to "server-answer"
                )
            ),
            command.toMap()
        )
        assertThrows(IllegalArgumentException::class.java) {
            ApiMethod.AgentV2.StartRun(
                "thread",
                7,
                "Unused",
                targetUserMessageId = "server-question",
                targetAssistantMessageId = "server-answer"
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            ApiMethod.AgentV2.StartRun(
                "thread",
                7,
                "Unused",
                entryPoint = AgentV2EntryPoint(),
                targetAssistantMessageId = "server-answer"
            )
        }
    }

    @Test
    fun editCommandsPreserveTargetAndOmitAppendOrigins() {
        val command = JSONArray(
            ApiMethod.AgentV2.StartRun(
                "thread",
                7,
                "Edited\nquestion",
                targetUserMessageId = "server-question"
            ).arguments
        ).getJSONObject(0)
        assertEquals(
            mapOf(
                "threadId" to "thread",
                "expectedThreadRevision" to 7,
                "input" to mapOf(
                    "kind" to "edit",
                    "text" to "Edited\nquestion",
                    "targetUserMessageId" to "server-question"
                )
            ),
            command.toMap()
        )
        assertThrows(IllegalArgumentException::class.java) {
            ApiMethod.AgentV2.StartRun(
                "thread",
                7,
                "Edited",
                entryPoint = AgentV2EntryPoint(),
                targetUserMessageId = "server-question"
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            ApiMethod.AgentV2.StartRun(
                "thread",
                7,
                "Edited",
                followupOf = AgentV2FollowUpReference("answer", "followup"),
                targetUserMessageId = "server-question"
            )
        }
    }

    @Test
    fun rejectsConflictingCommandOrigins() {
        assertThrows(IllegalArgumentException::class.java) {
            ApiMethod.AgentV2.StartRun(
                "thread",
                7,
                "How does staking work?",
                AgentV2EntryPoint(),
                AgentV2FollowUpReference("server-message", "server-followup")
            )
        }
    }

    @Test
    fun hostContextPreservesNullAndThePreparedObject() {
        assertEquals("[null]", ApiMethod.AgentV2.UpdateHostContext(null).arguments)
        val context = JSONObject("""{"accounts":[],"activeAccountId":null,"lang":"en"}""")
        val arguments = ApiMethod.AgentV2.UpdateHostContext(context).arguments
        assertEquals(context.toMap(), JSONArray(arguments).getJSONObject(0).toMap())
    }

    private fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { key ->
        when (val value = get(key)) {
            is JSONObject -> value.toMap()
            is JSONArray -> (0 until value.length()).map(value::get)
            else -> value
        }
    }
}
