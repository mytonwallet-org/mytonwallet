package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.ProgressBar
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isGone
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.agentUnavailableText
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

class AgentNewChatVC(context: Context) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG get() = Companion.TAG
    override val ignoreSideGuttering = true

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val client = LiveAgentV2Client()
    private val loader = AgentNewChatLoader(
        client::consent,
        client::acceptConsent,
        { client.createThread().thread }
    )
    private var request: Job? = null
    private var preparedChat: AgentPreparedChat? = null
    private var hasStarted = false
    private var shouldAcceptConsentOnRetry = false
    private val progress by lazy {
        ProgressBar(context).apply { id = UIComponentsR.id.agent_new_chat_progress }
    }
    private val errorLabel by lazy {
        WLabel(context).apply {
            id = UIComponentsR.id.agent_new_chat_error
            gravity = Gravity.CENTER
            setStyle(16f)
            text = agentUnavailableText()
        }
    }
    private val retryButton by lazy {
        WButton(context, WButton.Type.SECONDARY).apply {
            id = UIComponentsR.id.agent_new_chat_retry
            text = LocaleController.getString("Retry")
            setOnClickListener { load(shouldAcceptConsentOnRetry) }
        }
    }
    private val errorView by lazy {
        LinearLayout(context).apply {
            id = View.generateViewId()
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(24.dp, 0, 24.dp, 0)
            isGone = true
            addView(errorLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(
                retryButton,
                LinearLayout.LayoutParams(MATCH_PARENT, 50.dp).apply { topMargin = 16.dp }
            )
        }
    }

    override fun setupViews() {
        super.setupViews()
        setNavTitle(LocaleController.getString("New Chat"))
        setupNavBar(true)
        navigationBar?.setTitleGravity(Gravity.CENTER)
        navigationBar?.titleLabel?.setStyle(TITLE_SIZE, WFont.Medium)
        view.addView(errorView, ConstraintLayout.LayoutParams(0, 0))
        view.addView(progress, ConstraintLayout.LayoutParams(40.dp, 40.dp))
        view.setConstraints {
            allEdges(errorView)
            toCenterX(progress)
            toCenterY(progress)
        }
        updateTheme()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        if (preparedChat != null) {
            presentChat()
        } else if (!hasStarted) {
            hasStarted = true
            load()
        }
    }

    private fun load(shouldAcceptConsent: Boolean = false) {
        if (request?.isActive == true) return
        shouldAcceptConsentOnRetry = shouldAcceptConsent
        progress.isGone = false
        errorView.isGone = true
        request = scope.launch {
            try {
                preparedChat = loader.load(shouldAcceptConsent)
                if (preparedChat == null) {
                    // The Agent asks for consent before it starts the chat
                    AgentConsentSheetVC.present(
                        this@AgentNewChatVC,
                        onAllowed = { load(shouldAcceptConsent = true) },
                        onDeclined = { leaveDeclinedChat() }
                    )
                } else {
                    presentChat()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                errorLabel.text = agentUnavailableText()
                errorView.isGone = false
            } finally {
                progress.isGone = true
            }
        }
    }

    private fun presentChat() {
        val chat = preparedChat ?: return
        val navigation = navigationController ?: return
        if (navigation.isDisappeared || navigation.viewControllers.lastOrNull() !== this) return
        navigation.push(
            AgentVC(context, checkNotNull(chat.thread)),
            animated = false
        ) {
            navigation.removeViewController(this)
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        if (window?.isWideLayout == true) topReversedCornerView?.setBlurAlpha(1f)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(
            if (window?.isWideLayout == true) {
                WColor.SecondaryBackground.color
            } else {
                agentChatBackgroundColor
            }
        )
        errorLabel.setTextColor(WColor.SecondaryText)
        retryButton.updateTheme()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private companion object {
        const val TAG = "AgentNewChat"
        const val TITLE_SIZE = 20f
    }
}

/**
 * A feed preview waits for its first message; other discussions open at once, and ordinary chats ask for consent
 */
internal class AgentNewChatLoader(
    private val consent: suspend () -> Boolean,
    private val acceptConsent: suspend () -> Unit,
    private val createThread: suspend (AgentV2ThreadNewsRequest?) -> AgentV2ThreadSummary,
    private val news: AgentV2ThreadNewsRequest? = null,
    private val hasDiscussion: Boolean = false,
    private val shouldDeferCreation: Boolean = false
) {
    suspend fun load(
        shouldAcceptConsent: Boolean = false,
        hasMessage: Boolean = false
    ): AgentPreparedChat? {
        if (shouldDeferCreation && !hasMessage) return AgentPreparedChat(null)
        if (news == null && !hasDiscussion && !consent()) {
            if (!shouldAcceptConsent) return null
            acceptConsent()
        }
        return AgentPreparedChat(createThread(news))
    }
}

internal data class AgentPreparedChat(val thread: AgentV2ThreadSummary?)
