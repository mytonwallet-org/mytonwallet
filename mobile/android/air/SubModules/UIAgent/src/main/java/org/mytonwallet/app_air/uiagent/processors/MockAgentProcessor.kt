package org.mytonwallet.app_air.uiagent.processors

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

class MockAgentProcessor : AgentProcessor {

    private val replies = listOf(
        "I can help with balances, swaps, staking, and recent activity.",
        "TON is currently trading around \$3.45, up 2.3% in the last 24 hours.",
        "Your main wallet balance is 125.5 TON. Would you like to see a breakdown of your tokens?",
        "Staking rewards are distributed every 18 hours. Your current APY is approximately 4.2%.",
        "I found 3 recent transactions: a swap of 10 TON for USDT, a staking deposit, and an incoming transfer of 5 TON."
    )

    private var replyIndex = 0

    override suspend fun streamMessage(
        userId: String,
        message: String,
        userAddresses: List<AgentUserAddress>,
        onEvent: (AgentStreamEvent) -> Unit,
        onDone: () -> Unit,
        onError: (Exception) -> Unit
    ) {
        withContext(Dispatchers.IO) {
            try {
                delay(300)

                onEvent(AgentStreamEvent.Metadata(type = "question", streaming = true))

                val reply = if (message.contains("?")) {
                    "Short answer: yes. This screen is ready to evolve into a real chat surface once we connect it to the backend."
                } else {
                    replies[replyIndex++ % replies.size]
                }

                val words = reply.split(" ")
                for (word in words) {
                    val chunk = if (word == words.first()) word else " $word"
                    delay(50)
                    onEvent(AgentStreamEvent.Chunk(chunk))
                }

                // Emit deeplinks for some replies
                val idx = (replyIndex - 1).mod(replies.size)
                if (idx == 2 || idx == 4) {
                    val deeplinks = when (idx) {
                        2 -> listOf(
                            AgentResult(
                                type = "action",
                                message = null,
                                deeplinks = listOf(
                                    AgentResultDeeplink("Swap 10 TON → USDT", "ton://swap?from=TON&to=USDT&amount=10"),
                                    AgentResultDeeplink("View Balance", "ton://wallet")
                                ),
                                raw = org.json.JSONObject()
                            )
                        )
                        else -> listOf(
                            AgentResult(
                                type = "action",
                                message = null,
                                deeplinks = listOf(
                                    AgentResultDeeplink("View Transactions", "ton://activity")
                                ),
                                raw = org.json.JSONObject()
                            )
                        )
                    }
                    onEvent(AgentStreamEvent.Results(deeplinks))
                }

                onDone()
            } catch (e: Exception) {
                onError(e)
            }
        }
    }
}
