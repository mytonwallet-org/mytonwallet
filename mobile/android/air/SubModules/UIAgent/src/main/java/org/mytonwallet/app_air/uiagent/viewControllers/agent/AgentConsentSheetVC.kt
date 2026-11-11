package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.content.Context
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ErrorText
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentConsentView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSpinningTopView
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

/**
 * The Agent's consent, asked in a bottom sheet at the first thing the user does that would send something to it, under
 * the app's sheet header with the Agent's name after its spinning top, the typing row's. A hold grows the top threefold
 * over the header, as everywhere, while the title stays in place. Allow records the consent and closes the sheet, and
 * [onAllowed] then carries out what the user did. Swiping the sheet down, a tap outside it, the close button or Back
 * closes it without consent, and [onDeclined] drops what the user did.
 */
class AgentConsentSheetVC private constructor(
    context: Context,
    private val onAllowed: () -> Unit,
    private val onDeclined: () -> Unit
) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "AgentConsentSheet"

    override val shouldDisplayTopBar = false

    override val wrapsContentInCenteredWindow = true

    private val client: AgentV2Client = LiveAgentV2Client()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var acceptJob: Job? = null
    private var isAllowed = false

    private val consentView = AgentConsentView(context).apply { onAllow = ::allow }
    private val titleLabel = WLabel(context).apply {
        setStyle(TITLE_TEXT_SIZE, WFont.Medium)
        setSingleLine()
        text = LocaleController.getString("Agent")
    }

    private val titleTop = AgentSpinningTopView(context).apply {
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        isTouchInteractive = true
    }

    // The Agent's name with the typing row's top before it, as an icon beside a heading, where the title is
    private val titleView = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(titleTop, LinearLayout.LayoutParams(TITLE_TOP_SIZE.dp, TITLE_TOP_SIZE.dp))
        addView(
            titleLabel,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                marginStart = TITLE_TOP_GAP.dp
            }
        )
    }

    override fun setupViews() {
        super.setupViews()
        setNavTitle(LocaleController.getString("Agent"))
        setupNavBar(true)
        navigationBar?.setTitleView(titleView, animated = false)
        navigationBar?.addCloseButton()
        // The grown top's glass sees the sheet behind it
        titleTop.backdropSource = view
        view.addView(
            consentView,
            ConstraintLayout.LayoutParams(
                ConstraintLayout.LayoutParams.MATCH_CONSTRAINT,
                ConstraintLayout.LayoutParams.WRAP_CONTENT
            )
        )
        view.setConstraints {
            navigationBar?.let { topToBottom(consentView, it) } ?: toTop(consentView)
            toCenterX(consentView)
            toBottom(consentView)
        }
        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bars = navigationController?.getSystemBars()
        consentView.setBottomInset(bars?.bottom ?: 0)
        // The sheet, its header included, stops short of the status bar, as the window rests a taller one
        val windowHeight = window?.windowView?.height ?: 0
        consentView.maxContentHeight = (
            windowHeight - (bars?.top ?: 0) - SHEET_TOP_GAP.dp - WNavigationBar.DEFAULT_HEIGHT.dp
            ).coerceAtLeast(0)
        view.setConstraints {
            toStartPx(consentView, systemBarStartInset)
            toEndPx(consentView, systemBarEndInset)
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(agentChatBackgroundColor, ViewConstants.BLOCK_RADIUS.dp, 0f)
        titleLabel.setTextColor(WColor.PrimaryText)
        consentView.updateTheme()
    }

    private fun allow() {
        if (acceptJob?.isActive == true) return
        consentView.setLoading(true)
        consentView.showError(null)
        acceptJob = scope.launch {
            try {
                client.acceptConsent()
                isAllowed = true
                window?.dismissLastNav { onAllowed() } ?: onAllowed()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                val code = (error as? AgentV2OperationException)?.error?.code ?: error.message
                consentView.showError(agentV2ErrorText(code))
            } finally {
                consentView.setLoading(false)
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        if (!isAllowed) onDeclined()
        super.onDestroy()
    }

    companion object {
        // The gap the window keeps above a sheet as tall as it, in dp
        private const val SHEET_TOP_GAP = 20

        // How long the sheet waits for the keyboard to go before it shows anyway
        private const val KEYBOARD_HIDE_TIMEOUT_MS = 600L

        // The header's title, as the app's sheets show it, after the typing row's 24 dp top, 6 dp before it
        private const val TITLE_TEXT_SIZE = 22f
        private const val TITLE_TOP_SIZE = 24
        private const val TITLE_TOP_GAP = 6

        /**
         * Shows the sheet over [from]'s window; nothing shows when [from] has no window. An open keyboard goes first,
         * and the sheet rises once the window has let it go, where it rests without it. The field keeps its focus, for
         * [onDeclined] to give the keyboard back to.
         */
        fun present(from: WViewController, onAllowed: () -> Unit, onDeclined: () -> Unit = {}) {
            val window = from.window ?: return
            if (!isAgentKeyboardShown(window)) {
                show(window, from, onAllowed, onDeclined)
                return
            }
            from.view.hideKeyboard(clearFocus = false)
            val deadline = SystemClock.uptimeMillis() + KEYBOARD_HIDE_TIMEOUT_MS
            window.windowView.postOnAnimation(object : Runnable {
                override fun run() {
                    when {
                        from.isDestroyed -> onDeclined()

                        isAgentKeyboardShown(window) && SystemClock.uptimeMillis() < deadline ->
                            window.windowView.postOnAnimation(this)

                        else -> show(window, from, onAllowed, onDeclined)
                    }
                }
            })
        }

        private fun show(
            window: WWindow,
            from: WViewController,
            onAllowed: () -> Unit,
            onDeclined: () -> Unit
        ) {
            val navigation = WNavigationController(
                window,
                WNavigationController.PresentationConfig(
                    style = WNavigationController.PresentationStyle.BottomSheet
                )
            )
            navigation.setRoot(AgentConsentSheetVC(from.context, onAllowed, onDeclined))
            window.present(navigation)
        }
    }
}

/** Whether the soft keyboard shows over [window], a floating one included */
internal fun isAgentKeyboardShown(window: WWindow): Boolean =
    (window.imeInsets?.bottom ?: 0) > 0 || ViewCompat.getRootWindowInsets(window.windowView)
        ?.isVisible(WindowInsetsCompat.Type.ime()) == true

/** Takes a chat off its stack once the user closes the consent sheet without allowing the Agent */
internal fun WViewController.leaveDeclinedChat() {
    val navigation = navigationController ?: return
    if (navigation.viewControllers.size > 1 && navigation.viewControllers.lastOrNull() === this) {
        navigation.pop()
    }
}
