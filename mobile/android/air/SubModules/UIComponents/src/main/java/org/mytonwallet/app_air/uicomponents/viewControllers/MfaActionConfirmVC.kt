package org.mytonwallet.app_air.uicomponents.viewControllers

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.text.SpannableStringBuilder
import android.text.Spannable
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.net.toUri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.TelegramAvatarView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.buildConfirmWithTelegramTitle
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.walletcore.MFA_BOT_URL
import org.mytonwallet.app_air.walletcore.TON_CHAIN
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.buildMfaStartParam
import org.mytonwallet.app_air.walletcore.models.AccountMfa
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import kotlin.math.max

/**
 * Reusable "Confirm with Telegram" screen for any flow that returns an MFA request
 * hash (send, swap, stake/unstake/claim, NFT transfer, dapp transfer, domain ops, …).
 *
 * Polls `fetchMfaRequest` while visible; on confirmation, dismisses the entire
 * navigation stack (matching iOS/`dismissLastNav` behaviour for these flows).
 * Caller may pass an optional [chip] (token + amount + "to" text) shown under the
 * title – primarily used by transfer flows. Other flows can omit it.
 */
@SuppressLint("ViewConstructor")
class MfaActionConfirmVC(
    context: Context,
    private val requestHash: String,
    private val chip: Chip? = null,
    private val forceCloseButton: Boolean = false,
    private val popupConfirmedActivity: Boolean = true,
    private val onConfirmed: ((txHash: String?) -> Unit)? = null,
    private val onFinishOverride: ((txHash: String?) -> Unit)? = null,
) : WViewController(context), WalletCore.EventObserver {
    override val TAG = "MfaActionConfirm"
    override val shouldDisplayBottomBar = true

    /**
     * Optional pill-shaped subtitle under the title.
     * @param leading optional token icon (null hides the icon, useful for non-token flows).
     * @param text formatted text already prepared by the caller (e.g. "10.5 TON to UQk…").
     */
    data class Chip(
        val leading: IApiToken? = null,
        val text: CharSequence,
    )

    companion object {
        private const val AVATAR_SIZE = 72
        private const val AVATAR_OVERLAP = 22
        private const val CHIP_ICON_SIZE = 20

        // After Telegram confirmation we wait briefly for the matching local
        // activity to arrive so we can auto-open TransactionVC like the
        // non-MFA flow does. Fall back to plain dismiss after this window.
        private const val ACTIVITY_WAIT_TIMEOUT_MS = 8_000L
    }

    private var pollingJob: Job? = null
    private var didComplete = false

    private var pendingTxHash: String? = null
    private var pendingAccountId: String? = null
    private var awaitingActivity = false
    private val activityTimeoutHandler = Handler(Looper.getMainLooper())
    private val activityTimeoutRunnable = Runnable {
        if (!awaitingActivity) return@Runnable
        finishMfaConfirm(matchedActivity = null)
    }

    private val walletAvatar = AccountIconView(
        context,
        AccountIconView.Usage.ViewItem(28f.dp),
    ).apply {
        id = View.generateViewId()
        AccountStore.activeAccount?.let { config(it, useTelegramAvatar = false) }
    }

    private val userAvatar: View = buildUserAvatar()

    private val avatarsRow = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        clipChildren = false
        addView(
            walletAvatar,
            LinearLayout.LayoutParams(AVATAR_SIZE.dp, AVATAR_SIZE.dp).apply {
                marginEnd = -AVATAR_OVERLAP.dp
            },
        )
        addView(userAvatar, LinearLayout.LayoutParams(AVATAR_SIZE.dp, AVATAR_SIZE.dp))
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            id = View.generateViewId()
            setStyle(28f, WFont.Medium)
            gravity = Gravity.CENTER
            text = buildConfirmWithTelegramTitle(context)
        }
    }

    private val chipTokenIcon: WCustomImageView? = chip?.leading?.let { token ->
        WCustomImageView(context).apply {
            id = View.generateViewId()
            defaultRounding = Content.Rounding.Round
            defaultPlaceholder = Content.Placeholder.Color(WColor.SecondaryBackground)
            set(Content.of(token, showChain = false))
        }
    }

    private val chipLabel: WLabel? = chip?.let {
        WLabel(context).apply {
            id = View.generateViewId()
            setStyle(17f, WFont.Medium)
            text = it.text
        }
    }

    private val chipView: LinearLayout? = if (chip == null) null else LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        val hasIcon = chipTokenIcon != null
        setPadding(
            if (hasIcon) 8.dp else 14.dp,
            6.dp,
            14.dp,
            6.dp,
        )
        chipTokenIcon?.let { icon ->
            addView(
                icon,
                LinearLayout.LayoutParams(CHIP_ICON_SIZE.dp, CHIP_ICON_SIZE.dp).apply {
                    marginEnd = 6.dp
                },
            )
        }
        chipLabel?.let { lbl ->
            addView(lbl, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
    }

    private val infoIcon = AppCompatImageView(context).apply {
        id = View.generateViewId()
        setImageDrawable(context.getDrawableCompat(R.drawable.ic_tg_security))
    }

    private val infoLabel = WLabel(context).apply {
        id = View.generateViewId()
        setStyle(16f)
        text = buildInfoText()
    }

    private val infoCard = WView(context).apply {
        id = View.generateViewId()
        addView(infoIcon, ConstraintLayout.LayoutParams(30.dp, 30.dp))
        addView(infoLabel, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(infoIcon, 16f)
            toCenterY(infoIcon, 12f)
            startToEnd(infoLabel, infoIcon, 16f)
            toEnd(infoLabel, 16f)
            toTop(infoLabel, 12f)
            toBottom(infoLabel, 12f)
        }
    }

    private val confirmButton: WButton by lazy {
        WButton(context, WButton.Type.PRIMARY).apply {
            text = LocaleController.getString("Confirm")
            setOnClickListener { openTelegram() }
        }
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
        )
        v.addView(avatarsRow, ViewGroup.LayoutParams(WRAP_CONTENT, AVATAR_SIZE.dp))
        v.addView(titleLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        chipView?.let { v.addView(it, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)) }
        v.addView(infoCard, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(avatarsRow, 8f)
            toCenterX(avatarsRow)
            topToBottom(titleLabel, avatarsRow, 22f)
            toCenterX(titleLabel, 8f)
            if (chipView != null) {
                topToBottom(chipView, titleLabel, 16f)
                toCenterX(chipView)
                topToBottom(infoCard, chipView, 24f)
            } else {
                topToBottom(infoCard, titleLabel, 24f)
            }
            toCenterX(infoCard)
            toBottom(infoCard, 16f)
        }
        v.clipChildren = false
        v
    }

    private val scrollView: WScrollView by lazy {
        WScrollView(WeakReference(this)).apply {
            addView(scrollingContentView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            clipChildren = false
        }
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        val isRoot = (navigationController?.viewControllers?.size ?: 0) <= 1
        if (forceCloseButton || isRoot) {
            navigationBar?.addCloseButton()
        }

        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(confirmButton, ConstraintLayout.LayoutParams(0, 50.dp))

        view.setConstraints {
            topToBottom(scrollView, navigationBar!!)
            toCenterX(scrollView)
            bottomToTop(scrollView, confirmButton, 20f)
            toBottomPx(confirmButton, buttonsBottomMargin())
            toStartPx(confirmButton, 16.dp + systemBarStartInset)
            toEndPx(confirmButton, 16.dp + systemBarEndInset)
        }
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        scrollView.setBackgroundColor(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        chipLabel?.setTextColor(WColor.Tint.color)
        chipView?.setBackgroundColor(WColor.Tint.color.colorWithAlpha(26), 100f.dp)
        infoLabel.setTextColor(WColor.PrimaryText.color)
        infoCard.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        startPolling()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        stopPolling()
    }

    override fun onDestroy() {
        stopPolling()
        awaitingActivity = false
        activityTimeoutHandler.removeCallbacks(activityTimeoutRunnable)
        WalletCore.unregisterObserver(this)
        super.onDestroy()
    }

    private fun startPolling() {
        if (pollingJob?.isActive == true) return
        pollingJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive && !didComplete) {
                poll()
                delay(1000L)
            }
        }
    }

    private fun stopPolling() {
        pollingJob?.cancel()
        pollingJob = null
    }

    private suspend fun poll() {
        if (didComplete) return
        try {
            val req = WalletCore.call(ApiMethod.Mfa.FetchMfaRequest(requestHash))
            if (req.isConfirmed) {
                didComplete = true
                stopPolling()
                onMfaConfirmed(req.txHash)
            }
        } catch (t: Throwable) {
            if (shouldStopPolling(t)) {
                didComplete = true
                stopPolling()
                showError(t as? JSWebViewBridge.ApiError, t)
            }
        }
    }

    private fun shouldStopPolling(error: Throwable): Boolean {
        val apiError = error as? JSWebViewBridge.ApiError ?: return false
        return when (apiError.parsed) {
            MBridgeError.SERVER_ERROR,
            MBridgeError.AXIOS_ERROR,
            MBridgeError.PARSE_ERROR,
            MBridgeError.UNKNOWN -> false

            else -> true
        }
    }

    private fun showError(apiError: JSWebViewBridge.ApiError?, error: Throwable) {
        val parsed = apiError?.parsed ?: MBridgeError.UNKNOWN
        showError(parsed)
    }

    private fun onMfaConfirmed(txHash: String?) {
        val hash = txHash?.takeIf { it.isNotBlank() }
        val accountId = AccountStore.activeAccount?.accountId
        if (hash == null || accountId == null) {
            finishMfaConfirm(matchedActivity = null)
            return
        }
        pendingTxHash = hash
        pendingAccountId = accountId
        awaitingActivity = true
        WalletCore.registerObserver(this)
        activityTimeoutHandler.postDelayed(
            activityTimeoutRunnable,
            ACTIVITY_WAIT_TIMEOUT_MS,
        )
    }

    private fun matchesPendingTxHash(activity: MApiTransaction): Boolean {
        val hash = pendingTxHash ?: return false
        if (activity.parsedTxId.hash == hash) return true
        if (activity.externalMsgHashNorm == hash) return true
        return activity.getTxHash() == hash
    }

    private var didFinish = false
    private fun finishMfaConfirm(matchedActivity: MApiTransaction?) {
        if (didFinish) return
        didFinish = true
        awaitingActivity = false
        activityTimeoutHandler.removeCallbacks(activityTimeoutRunnable)
        WalletCore.unregisterObserver(this)
        val accountId = pendingAccountId
        val txHash = pendingTxHash
        pendingTxHash = null
        pendingAccountId = null
        val onFinishOverride = onFinishOverride
        if (onFinishOverride != null) {
            onFinishOverride(txHash)
            return
        }
        navigationController?.window?.dismissLastNav {
            if (popupConfirmedActivity && matchedActivity != null && accountId != null) {
                WalletCore.notifyEvent(
                    WalletEvent.OpenActivity(accountId, matchedActivity)
                )
            }
            onConfirmed?.invoke(txHash)
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (!awaitingActivity) return
        val accountId = pendingAccountId ?: return
        when (walletEvent) {
            is WalletEvent.NewLocalActivities -> {
                if (walletEvent.accountId != null && walletEvent.accountId != accountId) return
                walletEvent.localActivities
                    ?.firstOrNull { matchesPendingTxHash(it) }
                    ?.let { finishMfaConfirm(it) }
            }

            is WalletEvent.ReceivedPendingActivities -> {
                if (walletEvent.accountId != null && walletEvent.accountId != accountId) return
                walletEvent.pendingActivities
                    ?.firstOrNull { matchesPendingTxHash(it) }
                    ?.let { finishMfaConfirm(it) }
            }

            is WalletEvent.ReceivedNewActivities -> {
                if (walletEvent.accountId != null && walletEvent.accountId != accountId) return
                walletEvent.newActivities
                    ?.firstOrNull { matchesPendingTxHash(it) }
                    ?.let { finishMfaConfirm(it) }
            }

            else -> Unit
        }
    }

    private fun openTelegram() {
        val uri = MFA_BOT_URL.toUri()
            .buildUpon()
            .appendQueryParameter("startapp", buildMfaStartParam(requestHash))
            .build()
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching { context.startActivity(intent) }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollingContentView.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0
        )
        view.setConstraints {
            toBottomPx(confirmButton, buttonsBottomMargin())
            toStartPx(confirmButton, 16.dp + systemBarStartInset)
            toEndPx(confirmButton, 16.dp + systemBarEndInset)
        }
    }

    private fun buttonsBottomMargin(): Int {
        return 20.dp + max(
            (navigationController?.bottomInset ?: 0),
            (navigationController?.imeInsetBottom ?: 0),
        )
    }

    private fun buildUserAvatar(): View {
        val mfa = AccountStore.activeAccount?.byChain?.get(TON_CHAIN)?.mfa
        val user: AccountMfa.User = mfa?.user ?: return View(context).apply {
            id = View.generateViewId()
            setBackgroundColor(WColor.SecondaryBackground.color, AVATAR_SIZE.dp / 2f)
        }
        val telegram = TelegramAvatarView(context, user).apply { id = View.generateViewId() }
        val image = WCustomImageView(context).apply {
            id = View.generateViewId()
            defaultRounding = Content.Rounding.Round
            defaultPlaceholder = Content.Placeholder.Color(WColor.Transparent)
            val rasterUrl = user.avatarUrl
            if (rasterUrl != null) set(Content.ofUrl(rasterUrl))
        }
        return FrameLayout(context).apply {
            id = View.generateViewId()
            addView(telegram, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(image, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    private fun buildInfoText(): CharSequence {
        val full = LocaleController.getString(
            "An extra security layer requires confirming actions in Telegram after signing.",
        )
        val highlight = LocaleController.getString("confirming actions in Telegram")
        val idx = full.indexOf(highlight)
        if (idx < 0) return full
        val builder = SpannableStringBuilder(full)
        builder.setSpan(
            StyleSpan(android.graphics.Typeface.BOLD),
            idx,
            idx + highlight.length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
        )
        return builder
    }
}
