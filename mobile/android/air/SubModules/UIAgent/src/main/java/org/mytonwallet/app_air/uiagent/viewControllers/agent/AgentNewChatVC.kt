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
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentConsentView
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
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

    private val consentView by lazy {
        AgentConsentView(context).apply {
            isGone = true
            onAllow = { load(shouldAcceptConsent = true) }
        }
    }
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
        view.addView(consentView, ConstraintLayout.LayoutParams(0, 0))
        view.addView(errorView, ConstraintLayout.LayoutParams(0, 0))
        view.addView(progress, ConstraintLayout.LayoutParams(40.dp, 40.dp))
        view.setConstraints {
            allEdges(consentView)
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
        progress.isGone = !consentView.isGone
        errorView.isGone = true
        consentView.showError(null)
        consentView.setLoading(true)
        request = scope.launch {
            try {
                preparedChat = loader.load(shouldAcceptConsent)
                if (preparedChat == null) {
                    consentView.isGone = false
                } else {
                    presentChat()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                val errorText = agentUnavailableText()
                if (consentView.isGone) {
                    errorLabel.text = errorText
                    errorView.isGone = false
                } else {
                    consentView.showError(errorText)
                }
            } finally {
                progress.isGone = true
                consentView.setLoading(false)
            }
        }
    }

    private fun presentChat() {
        val chat = preparedChat ?: return
        val navigation = navigationController ?: return
        if (navigation.isDisappeared || navigation.viewControllers.lastOrNull() !== this) return
        navigation.push(
            AgentVC(context, chat.thread),
            animated = false
        ) {
            navigation.removeViewController(this)
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        if (window?.isWideLayout == true) topReversedCornerView?.setBlurAlpha(1f)
        val bottom = navigationController?.getSystemBars()?.bottom ?: 0
        val endsAboveBottomBar =
            additionalTabletPadding > 0 && !WGlobalStorage.isGradientNavigationBarActive()
        val gutter = if (additionalTabletPadding > 0) ViewConstants.HORIZONTAL_PADDINGS.dp else 0
        view.setConstraints {
            toStartPx(consentView, additionalTabletPadding + systemBarStartInset + gutter)
            toEndPx(consentView, systemBarEndInset + gutter)
            toBottomPx(consentView, if (endsAboveBottomBar) bottom else 0)
        }
        consentView.updateInsets(
            agentHeaderBottom() + AGENT_LIST_TOP_INSET.dp,
            bottom,
            endsAboveBottomBar
        )
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
        consentView.updateTheme()
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

internal class AgentNewChatLoader(
    private val consent: suspend () -> Boolean,
    private val acceptConsent: suspend () -> Unit,
    private val createThread: suspend (AgentV2ThreadNewsRequest?) -> AgentV2ThreadSummary,
    private val news: AgentV2ThreadNewsRequest? = null
) {
    suspend fun load(shouldAcceptConsent: Boolean = false): AgentPreparedChat? {
        if (!consent()) {
            if (!shouldAcceptConsent) return null
            acceptConsent()
        }
        return AgentPreparedChat(createThread(news))
    }
}

internal data class AgentPreparedChat(val thread: AgentV2ThreadSummary)
