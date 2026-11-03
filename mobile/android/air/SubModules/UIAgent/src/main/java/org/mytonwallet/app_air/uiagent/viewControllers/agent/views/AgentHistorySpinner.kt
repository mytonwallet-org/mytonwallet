package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.widget.ProgressBar
import androidx.core.view.isGone
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

internal const val AGENT_HISTORY_LOAD_THRESHOLD = 5

@SuppressLint("ViewConstructor")
internal class AgentHistorySpinner(context: Context) : ProgressBar(context) {
    init {
        id = generateViewId()
        isGone = true
        contentDescription = LocaleController.getString("Loading...")
    }

    fun setLoading(isLoading: Boolean) {
        isGone = !isLoading
    }

    companion object {
        const val SIZE = 24
        const val TOP_GAP = 8
    }
}
