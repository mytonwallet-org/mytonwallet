package org.mytonwallet.app_air.uiagent.agentV2

import android.net.Uri
import org.mytonwallet.app_air.walletbasecontext.APP_SCHEME
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction

internal fun buildAgentActionUrl(action: AgentV2ResolvedAction): String? = when (action) {
    is AgentV2ResolvedAction.OpenReceive -> Uri.Builder()
        .scheme(APP_SCHEME)
        .authority("receive")
        .appendQueryParameter("chain", action.chain)
        .build()
        .toString()

    is AgentV2ResolvedAction.SendForm -> Uri.parse(action.url).takeIf {
        it.scheme == "mtw" && it.host == "send"
    }?.let { uri ->
        // Send fills the maximum it computes for `amount=all` only from an agent link
        if (action.isMaxAmount) {
            uri.buildUpon().appendQueryParameter("amount", "all").build().toString()
        } else {
            action.url
        }
    }

    is AgentV2ResolvedAction.OpenStaking -> {
        val stakeAmount = action.amount
        val amount = when (stakeAmount?.kind) {
            "exact" -> stakeAmount.value ?: return null
            "all" -> "all"
            null -> null
            else -> return null
        }
        Uri.Builder()
            .scheme(APP_SCHEME)
            .authority("stake")
            .appendQueryParameter("asset", action.tokenSlug)
            .apply { if (amount != null) appendQueryParameter("amount", amount) }
            .build()
            .toString()
    }

    is AgentV2ResolvedAction.OpenSwap -> {
        if (action.tokenInSlug?.isBlank() == true || action.tokenOutSlug?.isBlank() == true) {
            return null
        }
        val amount = action.amount?.let {
            it.toDoubleOrNull()?.takeIf { value -> value.isFinite() && value > 0 }
                ?: return null
        }
        val amountParameter = when (action.amountSide) {
            "source" -> if (amount != null &&
                action.tokenInSlug != null
            ) {
                "amountIn"
            } else {
                return null
            }

            "destination" -> if (amount != null &&
                action.tokenOutSlug != null
            ) {
                "amountOut"
            } else {
                return null
            }

            null -> if (amount == null) null else return null

            else -> return null
        }
        Uri.Builder()
            .scheme(APP_SCHEME)
            .authority("swap")
            .apply {
                action.tokenInSlug?.let { appendQueryParameter("in", it) }
                action.tokenOutSlug?.let { appendQueryParameter("out", it) }
                if (amountParameter !=
                    null
                ) {
                    appendQueryParameter(amountParameter, amount.toString())
                }
            }
            .build()
            .toString()
    }

    is AgentV2ResolvedAction.OpenDapp, is AgentV2ResolvedAction.Inactive -> null
}
