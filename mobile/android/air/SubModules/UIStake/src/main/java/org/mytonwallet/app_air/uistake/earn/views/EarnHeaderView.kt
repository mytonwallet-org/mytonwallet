package org.mytonwallet.app_air.uistake.earn.views

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.text.SpannableStringBuilder
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WLinearLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uistake.earn.EarnVC
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class EarnHeaderView(
    viewController: WeakReference<EarnVC>,
    var onAddStakeClick: (() -> Unit)?,
    var onUnstakeClick: (() -> Unit)?,
) : WLinearLayout(viewController.get()!!.context), WThemedView, SkeletonContainer {

    private var updateHandler: Handler? = null
    private var updateRunnable: Runnable? = null
    private var currentStakingState: StakingState? = null

    companion object {
        val AMOUNT_SKELETON_RADIUS = 24f.dp
        val MESSAGE_SKELETON_RADIUS = 12f.dp
    }

    private val sizeSpan = RelativeSizeSpan(28f / 36f)
    private val colorSpan = WForegroundColorSpan()

    private val separatorBackgroundDrawable: SeparatorBackgroundDrawable by lazy {
        SeparatorBackgroundDrawable().apply {
            backgroundWColor = WColor.Background
        }
    }

    private val amountTextView = WSensitiveDataContainer(
        WLabel(context),
        WSensitiveDataContainer.MaskConfig(16, 4, Gravity.CENTER, protectContentLayoutSize = false)
    ).apply {
        id = generateViewId()
        layoutParams = LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        textAlignment = TEXT_ALIGNMENT_CENTER
        contentView.apply {
            typeface = WFont.NunitoExtraBold.typeface
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 44f)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 36f)
        }
        setOnClickListener {
            if (WGlobalStorage.getIsSensitiveDataProtectionOn())
                WGlobalStorage.toggleSensitiveDataHidden()
        }
    }

    private val amountSkeletonView = WBaseView(context).apply {
        layoutParams = LayoutParams(120.dp, 36.dp)
        visibility = GONE
    }

    private val messageLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.Regular)
            gravity = Gravity.CENTER
        }
    }

    private val messageSkeletonView = WBaseView(context).apply {
        layoutParams = LayoutParams(180.dp, 20.dp)
        visibility = GONE
    }

    private val addStakeButton: WButton by lazy {
        val wButton = WButton(context, WButton.Type.PRIMARY)
        wButton.text = LocaleController.getString("Add stake")
        wButton.setOnClickListener {
            onAddStakeClick?.invoke()
        }
        wButton
    }

    private val unstakeButton: WButton by lazy {
        val wButton = WButton(context, WButton.Type.PRIMARY).apply {
            text = LocaleController.getString("\$unstake_action")
            isEnabled = AccountStore.activeAccount?.accountType != MAccount.AccountType.VIEW
            setOnClickListener {
                onUnstakeClick?.invoke()
            }
        }
        wButton
    }

    private val innerContainer = WView(context).apply {
        id = generateViewId()

        val buttonMarginTopDp = 43.5f
        val buttonMarginSideDp = 20f
        val buttonMarginBottomDp = 20.5f
        val addStakeButtonLp = ConstraintLayout.LayoutParams(
            ConstraintLayout.LayoutParams.MATCH_CONSTRAINT,
            WRAP_CONTENT
        ).apply {
            goneEndMargin = buttonMarginSideDp.toInt().dp
        }
        addView(amountSkeletonView)
        addView(messageSkeletonView)
        addView(amountTextView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(
            messageLabel,
            LayoutParams(ConstraintLayout.LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT)
        )
        addView(addStakeButton, addStakeButtonLp)
        addView(
            unstakeButton,
            LayoutParams(ConstraintLayout.LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT)
        )

        setPadding(
            0,
            WNavigationBar.DEFAULT_HEIGHT.dp +
                (viewController.get()?.navigationController?.getSystemBars()?.top ?: 0),
            0,
            0
        )

        setConstraints {
            toStart(amountTextView)
            toEnd(amountTextView)
            edgeToEdge(amountSkeletonView, amountTextView)

            topToBottom(messageLabel, amountTextView, 5f)
            toCenterX(messageLabel, ViewConstants.HORIZONTAL_PADDINGS + 8f)
            edgeToEdge(messageSkeletonView, messageLabel)

            topToBottom(addStakeButton, messageLabel, buttonMarginTopDp)
            toStart(addStakeButton, buttonMarginSideDp)
            endToStart(addStakeButton, unstakeButton, 5f)
            toBottom(addStakeButton, buttonMarginBottomDp)

            topToBottom(unstakeButton, messageLabel, buttonMarginTopDp)
            toEnd(unstakeButton, buttonMarginSideDp)
            startToEnd(unstakeButton, addStakeButton, 5f)
            toBottom(unstakeButton, buttonMarginBottomDp)
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (innerContainer.parent == null)
            addView(innerContainer, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        updateTheme()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopUpdateTimer()
    }

    override fun updateTheme() {
        if (ThemeManager.uiMode.hasRoundedCorners) {
            setBackgroundColor(WColor.SecondaryBackground.color)
        } else {
            background = separatorBackgroundDrawable
            separatorBackgroundDrawable.invalidateSelf()
        }
        amountTextView.contentView.setTextColor(WColor.PrimaryText.color)
        colorSpan.color = WColor.SecondaryText.color
        messageLabel.setTextColor(WColor.SecondaryText.color)
        amountSkeletonView.setBackgroundColor(
            if (ThemeManager.uiMode.hasRoundedCorners) WColor.SecondaryText.color
            else WColor.SecondaryBackground.color,
            AMOUNT_SKELETON_RADIUS
        )
        messageSkeletonView.setBackgroundColor(
            if (ThemeManager.uiMode.hasRoundedCorners) WColor.SecondaryText.color
            else WColor.SecondaryBackground.color,
            MESSAGE_SKELETON_RADIUS
        )
    }

    fun hideInnerViews() {
        amountTextView.visibility = INVISIBLE
        messageLabel.visibility = INVISIBLE
        addStakeButton.visibility = INVISIBLE
        unstakeButton.visibility = GONE
        amountSkeletonView.visibility = VISIBLE
        messageSkeletonView.visibility = VISIBLE

        // Alpha
        addStakeButton.alpha = 0f
        unstakeButton.alpha = 0f
    }

    fun showInnerViews(shouldShowUnstakeButton: Boolean) {
        amountTextView.visibility = VISIBLE
        messageLabel.visibility = VISIBLE
        addStakeButton.visibility = VISIBLE
        changeUnstakeButtonVisibility(shouldShowUnstakeButton)
        if (amountSkeletonView.visibility != GONE) {
            amountSkeletonView.fadeOut(onCompletion = {
                amountSkeletonView.visibility = GONE
            })
            messageSkeletonView.fadeOut(onCompletion = {
                messageSkeletonView.visibility = GONE
            })
        }

        if (addStakeButton.alpha == 1f)
            return
        Handler(Looper.getMainLooper()).postDelayed({
            addStakeButton.fadeIn(duration = AnimationConstants.SLOW_ANIMATION)
            if (shouldShowUnstakeButton)
                unstakeButton.fadeIn(duration = AnimationConstants.SLOW_ANIMATION)
        }, 100)
    }

    @SuppressLint("SetTextI18n")
    fun setStakingBalance(balance: String, tokenSymbol: String) {
        amountTextView.contentView.text = "$balance $tokenSymbol".let {
            val ssb = SpannableStringBuilder(it)
            CoinUtils.setSpanToFractionalPart(ssb, sizeSpan)
            CoinUtils.setSpanToSymbolPart(ssb, colorSpan)
            ssb
        }
    }

    fun setSubtitle(stakingState: StakingState?) {
        currentStakingState = stakingState

        val inProgressWithdraw = stakingState?.getRequestedAmount()
            ?.let {
                if (!stakingState.isUnstakeRequestAmountUnlocked)
                    formatWithdrawText(stakingState)
                else
                    null
            }

        messageLabel.text = buildString {
            append(LocaleController.getString("Your staking balance"))
            inProgressWithdraw?.let { append("\n\n").append(it) }
        }.toProcessedSpannableStringBuilder()

        if (inProgressWithdraw != null) {
            startUpdateTimer()
        } else {
            stopUpdateTimer()
        }
    }

    private fun formatWithdrawText(stakingState: StakingState): String {
        return LocaleController.getStringWithKeyValues(
            "\$unstaking_when_receive_with_amount",
            listOf(
                "%amount%" to "**${(stakingState.getRequestedAmount() ?: "")}**",
                "%time%" to "**${(stakingState.getRemainingToEndTimeString() ?: "")}**"
            )
        )
    }

    private fun startUpdateTimer() {
        stopUpdateTimer()

        updateHandler = Handler(Looper.getMainLooper())
        updateRunnable = object : Runnable {
            override fun run() {
                updateMessageLabel()
                updateHandler?.postDelayed(this, 1000)
            }
        }
        updateHandler?.postDelayed(updateRunnable!!, 1000)
    }

    private fun stopUpdateTimer() {
        updateRunnable?.let { updateHandler?.removeCallbacks(it) }
        updateHandler = null
        updateRunnable = null
    }

    @SuppressLint("SetTextI18n")
    private fun updateMessageLabel() {
        currentStakingState?.getRequestedAmount()?.let {
            val inProgressWithdraw = formatWithdrawText(currentStakingState!!)
            messageLabel.text = (LocaleController.getString("Your staking balance") +
                "\n\n$inProgressWithdraw").toProcessedSpannableStringBuilder()
        }
    }

    fun changeAddStakeButtonEnable(shouldBeEnabled: Boolean) {
        addStakeButton.isEnabled =
            shouldBeEnabled && AccountStore.activeAccount?.accountType != MAccount.AccountType.VIEW
    }

    fun changeUnstakeButtonVisibility(shouldShow: Boolean) {
        unstakeButton.visibility = if (shouldShow) VISIBLE else GONE
        if (currentStakingState?.isUnstakeRequestAmountUnlocked == true) {
            unstakeButton.text =
                LocaleController.getStringWithKeyValues(
                    "\$unstake_asset",
                    listOf(
                        Pair("%symbol%", currentStakingState?.getRequestedAmount() ?: "")
                    )
                )
        } else {
            unstakeButton.text = LocaleController.getString("\$unstake_action")
        }
    }

    override fun getChildViewMap(): HashMap<View, Float> = hashMapOf(
        (amountSkeletonView to AMOUNT_SKELETON_RADIUS),
        (messageSkeletonView to MESSAGE_SKELETON_RADIUS)
    )

    fun onDestroy() {
        stopUpdateTimer()
        onAddStakeClick = null
        onUnstakeClick = null
    }
}
