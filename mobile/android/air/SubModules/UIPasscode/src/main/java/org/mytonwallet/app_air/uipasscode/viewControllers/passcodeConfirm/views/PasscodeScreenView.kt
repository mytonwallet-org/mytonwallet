package org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatTextView
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.animation.doOnEnd
import androidx.core.content.ContextCompat
import androidx.core.view.children
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.Runnable
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.commonViews.PasscodeInputView
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.NftAccentColors
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class PasscodeScreenView(
    private val containerVC: WViewController,
    private val passcodeViewState: PasscodeViewState,
    ignoreBiometry: Boolean
) : WView(containerVC.context), WThemedView,
    PasscodeKeyboardView.PasscodeListener {

    companion object {
        const val TOP_HEADER_MAX_HEIGHT_RATIO = 0.25f
        const val ANIMATE_PINPAD = false
    }

    val allowBiometry =
        WGlobalStorage.isBiometricActivated() && BiometricHelpers.canAuthenticate(context) && !ignoreBiometry
    private val passcodeLength = WSecureStorage.getPasscodeLength()

    private val showAnimation = WGlobalStorage.getAreAnimationsActive() &&
        passcodeViewState is PasscodeViewState.Default &&
        passcodeViewState.animated

    private val subtitle = when (passcodeViewState) {
        is PasscodeViewState.Default -> {
            passcodeViewState.subtitle
        }

        is PasscodeViewState.CustomHeader -> {
            if (allowBiometry)
                LocaleController.getString("Enter passcode or use fingerprint")
            else
                LocaleController.getString("Enter Passcode")
        }
    }

    private val gapDrawable = SeparatorBackgroundDrawable().apply {
        backgroundWColor = WColor.SecondaryBackground
        isTop = true
    }

    private val topImageView = WImageView(context)

    private val titleTextView = AppCompatTextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 32f)
        typeface = WFont.SemiBold.typeface
        gravity = Gravity.CENTER
    }

    private val subTitleTextView = WLabel(context).apply {
        setStyle(16f)
        text = subtitle
        gravity = Gravity.CENTER
    }

    private val passcodeInputView = PasscodeInputView(
        context,
        null,
        forceLightScreen = if (passcodeViewState is PasscodeViewState.Default) passcodeViewState.light == true else false,
        forceDarkScreen = if (passcodeViewState is PasscodeViewState.Default && passcodeViewState.isUnlockScreen)
            NftAccentColors.veryBrightColors.contains(WColor.Tint.color) else false,
        margins = 8,
        showKeyboardOnFocus = false
    ).apply {
        passLength = passcodeLength
    }
    private val gapView1: WBaseView by lazy {
        WBaseView(context)
    }
    private val gapView2 = WBaseView(context)
    private val passcodeKeyboardView = PasscodeKeyboardView(
        context,
        light = if (passcodeViewState is PasscodeViewState.Default) passcodeViewState.light else null,
        showMotionBackgroundDrawable = passcodeViewState is PasscodeViewState.Default && passcodeViewState.showMotionBackgroundDrawable,
        ignoreBiometry = ignoreBiometry
    ).apply {
        setPadding(
            0,
            0,
            0,
            4.dp + (containerVC.navigationController?.getSystemBars()?.bottom ?: 0)
        )
    }

    val topLinearLayout = object : LinearLayout(context) {
        var desiredHeight: Int = 0
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)

            if (desiredHeight == 0)
                desiredHeight = measuredHeight
            if (measuredHeight < desiredHeight) {
                clipChildren = false
                clipToPadding = false
                val child = children.firstOrNull() as? ViewGroup
                child?.apply {
                    pivotX = measuredWidth / 2f
                    pivotY = (desiredHeight - measuredHeight) / 4f
                    clipChildren = false
                    clipToPadding = false
                    val scale = measuredHeight / desiredHeight.toFloat()
                    scaleX = scale
                    scaleY = scale
                }
            }
        }
    }.apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
    }
    private val bottomLayout = WView(context)

    private var isConfigured = false
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()

        if (isConfigured) {
            return
        }
        isConfigured = true

        passcodeKeyboardView.listener = this

        setupContent()

        updateTheme()
        if (showAnimation) animateViews()
        passcodeKeyboardView.updateButtons(isEmpty = true)
    }

    private fun setupContent() {
        addView(topLinearLayout, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            bottomLayout,
            LayoutParams(
                MATCH_PARENT,
                if (passcodeViewState is PasscodeViewState.Default) WRAP_CONTENT else 0
            )
        )

        if (passcodeViewState is PasscodeViewState.Default) {
            setupAsDefaultPasscodeView()
        } else if (passcodeViewState is PasscodeViewState.CustomHeader) {
            setupAsCustomHeader()
        }
    }

    private fun setupAsDefaultPasscodeView() {
        val defaultState = passcodeViewState as PasscodeViewState.Default

        addView(gapView1, LayoutParams(WRAP_CONTENT, 0))
        addView(gapView2, LayoutParams(WRAP_CONTENT, 0))

        if (showAnimation) {
            if (ANIMATE_PINPAD) {
                passcodeKeyboardView.apply {
                    alpha = 0f
                    scaleX = 0f
                    scaleY = 0f
                }
            }
            passcodeInputView.apply {
                scaleX = 0f
                scaleY = 0f
            }
            titleTextView.alpha = 0f
            subTitleTextView.alpha = 0f
        }

        titleTextView.text = defaultState.title

        val showNavBar = defaultState.showNavBar
        val topInset = if (!showNavBar) {
            containerVC.navigationController?.getSystemBars()?.top ?: 0
        } else {
            0
        }

        val parentHeight = (containerVC.navigationController?.parent as? ViewGroup)?.height ?: 0
        val scaleFactor =
            if (parentHeight <= 2280) 0.2f + max(0, parentHeight - 1280) / 1000 else 1f

        val topImageMargin = (16.dp * scaleFactor).roundToInt() + topInset
        val titleMarginTop = (30.dp * scaleFactor).roundToInt()
        val inputMarginTop = (28.dp * scaleFactor).roundToInt()

        topLinearLayout.apply {
            addView(
                topImageView,
                LinearLayout.LayoutParams(48.dp, 48.dp).apply {
                    gravity = Gravity.CENTER
                    topMargin = topImageMargin
                }
            )
            addView(
                titleTextView,
                LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    leftMargin = 20.dp
                    topMargin = titleMarginTop
                    rightMargin = 20.dp
                }
            )
            addView(
                subTitleTextView,
                LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    topMargin = 14.dp
                    leftMargin = 20.dp
                    rightMargin = 20.dp
                }
            )
            addView(
                passcodeInputView,
                LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = Gravity.CENTER
                    topMargin = inputMarginTop
                    bottomMargin = 12.dp
                }
            )
        }

        bottomLayout.addView(passcodeKeyboardView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        setConstraints {
            toTop(gapView1)
            topToBottom(topLinearLayout, gapView1)
            topToBottom(gapView2, topLinearLayout)
            topToBottom(bottomLayout, gapView2)
            toBottom(bottomLayout)
            createVerticalChain(
                ConstraintSet.PARENT_ID, ConstraintSet.TOP,
                ConstraintSet.PARENT_ID, ConstraintSet.BOTTOM,
                intArrayOf(gapView1.id, topLinearLayout.id, gapView2.id, bottomLayout.id),
                null,
                ConstraintSet.CHAIN_PACKED
            )
        }
    }

    private fun setupAsCustomHeader() {
        addView(gapView2, LayoutParams(WRAP_CONTENT, ViewConstants.GAP.dp))
        bottomLayout.addView(
            subTitleTextView,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        bottomLayout.addView(
            passcodeInputView,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        bottomLayout.addView(passcodeKeyboardView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        bottomLayout.setConstraints {
            constrainedHeight(passcodeKeyboardView.id, true)
            setVerticalBias(subTitleTextView.id, 0f)
            setVerticalBias(passcodeInputView.id, 0f)
            setVerticalBias(passcodeKeyboardView.id, 1f)
            toTop(subTitleTextView, 24f)
            topToBottom(passcodeInputView, subTitleTextView, 16.5f)
            toCenterX(passcodeInputView)
            topToBottom(passcodeKeyboardView, passcodeInputView, 12f)
            toBottom(passcodeKeyboardView)
        }
        setConstraints {
            constrainMaxHeight(
                topLinearLayout.id,
                ((containerVC.navigationController!!.parent as View).height * TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
            )
            toTop(topLinearLayout)
            topToBottom(gapView2, topLinearLayout)
            topToBottom(bottomLayout, gapView2)
            toBottom(bottomLayout)
            createVerticalChain(
                ConstraintSet.PARENT_ID, ConstraintSet.TOP,
                ConstraintSet.PARENT_ID, ConstraintSet.BOTTOM,
                intArrayOf(topLinearLayout.id, gapView2.id, bottomLayout.id),
                null,
                ConstraintSet.CHAIN_SPREAD_INSIDE
            )
        }
    }

    private fun animateViews() {
        ValueAnimator.ofInt(0, 800.dp).apply {
            startDelay = 0
            duration = AnimationConstants.VERY_VERY_SLOW_ANIMATION

            addUpdateListener { updatedAnimation ->
                val updatedValue = updatedAnimation.animatedValue as Int

                if (updatedValue < 400) {
                    passcodeInputView.scaleX = updatedValue / 400f
                    passcodeInputView.scaleY = updatedValue / 400f
                } else {
                    passcodeInputView.scaleX = 1f
                    passcodeInputView.scaleY = 1f
                }

                if (updatedValue < 350) {
                    titleTextView.alpha = 0f
                    subTitleTextView.alpha = 0f
                } else if (updatedValue <= 800) {
                    val alpha = (updatedValue - 350) / 450f
                    titleTextView.translationX = (1 - alpha) * 20
                    subTitleTextView.translationX = titleTextView.translationX
                    titleTextView.alpha = alpha
                    subTitleTextView.alpha = alpha
                }
            }
            doOnEnd {
                passcodeInputView.scaleX = 1f
                passcodeInputView.scaleY = 1f
                titleTextView.translationX = 0f
                subTitleTextView.translationX = 0f
                titleTextView.alpha = 1f
                subTitleTextView.alpha = 1f
            }

            start()
        }
    }

    override fun updateTheme() {
        if (passcodeViewState !is PasscodeViewState.Default) {
            topLinearLayout.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.TOOLBAR_RADIUS.dp,
                ViewConstants.BLOCK_RADIUS.dp,
            )
            bottomLayout.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp,
                ViewConstants.TOOLBAR_RADIUS.dp
            )
        } else if (!passcodeViewState.showMotionBackgroundDrawable) {
            containerVC.view.setBackgroundColor(WColor.Background.color)
        }
        if (passcodeViewState is PasscodeViewState.Default) {
            val color =
                if (passcodeViewState.light ?: ThemeManager.isDark) Color.WHITE else Color.BLACK
            containerVC.window?.forceStatusBarLight = passcodeViewState.light
            containerVC.window?.forceBottomBarLight = passcodeViewState.light
            val lockDrawable =
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.uipasscode.R.drawable.ic_lock
                )?.apply {
                    setTint(color)
                }
            topImageView.setImageDrawable(lockDrawable)
            titleTextView.setTextColor(color)
            subTitleTextView.setTextColor(color)
        } else if (passcodeViewState is PasscodeViewState.CustomHeader) {
            subTitleTextView.setTextColor(WColor.SecondaryText.color)
            gapDrawable.invalidateSelf()
        }
    }

    var delegate: Delegate? = null

    interface Delegate {
        fun onEnterPasscode(
            passcode: String,
            callback: (wasCorrect: Boolean, cooldownDate: Long?) -> Unit
        )

        fun signOutPressed() {}
    }

    override fun onBiometricsCheck() {
        if (isLoading.value || inBiometry.value) {
            return
        }

        tryBiometrics()
    }

    override fun onNumberDelete() {
        if (isLoading.value || inBiometry.value) {
            return
        }

        if (passcodeInputView.passcode.isEmpty()) {
            if ((passcodeViewState as? PasscodeViewState.Default)?.isUnlockScreen == true) {
                delegate?.signOutPressed()
            }
            return
        }
        passcodeInputView.passcode = passcodeInputView.passcode.dropLast(1)
        passcodeKeyboardView.updateButtons(passcodeInputView.passcode.isEmpty())
    }

    override fun onNumberInput(number: Int) {
        if (isLoading.value || inBiometry.value) {
            return
        }

        doOnNumPadClick?.invoke()
        passcodeInputView.passcode += number
        passcodeKeyboardView.updateButtons(passcodeInputView.passcode.isEmpty())
        if (passcodeInputView.passcode.length >= passcodeLength) {
            checkPasscode(passcodeInputView.passcode)
        }
    }

    var doOnNumPadClick: (() -> Unit)? = null


    /* * */

    var inBiometry = BoolAnimator(
        AnimationConstants.SLOW_ANIMATION,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        initialValue = showAnimation
    ) { _, value, _, _ ->
        if (ANIMATE_PINPAD) {
            passcodeKeyboardView.alpha = 1f - value
            passcodeKeyboardView.scaleX = 1f - value * 0.25f
            passcodeKeyboardView.scaleY = 1f - value * 0.25f
        }
    }

    fun tryBiometrics() {
        Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "tryBiometrics: Attempting biometric authentication")
        inBiometry.animatedValue = true

        BiometricHelpers.authenticate(
            context as FragmentActivity,
            if (passcodeViewState is PasscodeViewState.Default) passcodeViewState.title else subtitle,
            null,
            null,
            LocaleController.getString("Use PIN"),
            onSuccess = {
                Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "tryBiometrics: Biometric success")
                passcodeInputView.passcode = "----" // To fill passcode input view
                checkPasscode(WSecureStorage.getBiometricPasscode(containerVC.window!!) ?: "")
            },
            onCanceled = {
                Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "tryBiometrics: Biometric canceled")
                inBiometry.animatedValue = false
            }
        )
    }


    /* * */

    private var isLoading = BoolAnimator(
        220L,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        initialValue = false
    ) { _, _, _, _ -> }

    private fun checkPasscode(passcode: String) {
        if (isLoading.value) {
            inBiometry.animatedValue = false
            return
        }

        Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "checkPasscode: Verifying passcode")
        isLoading.animatedValue = true
        delegate!!.onEnterPasscode(passcode) { correct, cooldownDate ->
            isLoading.animatedValue = false
            if (correct) {
                Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "checkPasscode: Passcode correct")
            } else {
                Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "checkPasscode: Passcode incorrect hasCooldown=${cooldownDate != null}")
                inBiometry.animatedValue = false
                passcodeInputView.resetInput()
                if ((passcodeViewState as? PasscodeViewState.Default)?.isUnlockScreen == true && cooldownDate != null)
                    passcodeKeyboardView.showSignOut = true
                passcodeKeyboardView.updateButtons(isEmpty = true)

                setupCooldown(cooldownDate)
            }
        }
    }

    fun showIndicator(animateToGreen: Boolean = true) {
        passcodeInputView.showIndicator(animateToGreen)
    }

    fun clearPasscode() {
        passcodeInputView.hideIndicator()
        passcodeInputView.passcode = ""
        passcodeKeyboardView.updateButtons(isEmpty = true)
    }

    // Rate Limit //////////
    private var cooldownHandler: Handler? = null
    private var cooldownRunnable: Runnable? = null

    fun setupCooldown(cooldownEndTime: Long?) {
        clearCooldown()

        val remainingMillis = cooldownEndTime?.let { it - System.currentTimeMillis() } ?: 0

        if (remainingMillis > 0) {
            Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "setupCooldown: Cooldown active remainingMs=$remainingMillis")
            passcodeKeyboardView.lockKeypad()
            startCooldownTimer(cooldownEndTime!!)
        } else {
            resetToNormalState()
        }
    }

    fun clearCooldown() {
        cooldownRunnable?.let { runnable ->
            cooldownHandler?.removeCallbacks(runnable)
        }
        cooldownHandler = null
        cooldownRunnable = null
    }

    private fun startCooldownTimer(cooldownEndTime: Long) {
        cooldownHandler = Handler(Looper.getMainLooper())

        cooldownRunnable = object : Runnable {
            override fun run() {
                val remainingMillis = cooldownEndTime - System.currentTimeMillis()

                if (remainingMillis > 0) {
                    updateCooldownDisplay(remainingMillis)
                    cooldownHandler?.postDelayed(this, 1000)
                } else {
                    onCooldownFinished()
                }
            }
        }

        cooldownRunnable?.let { cooldownHandler?.post(it) }
    }

    private fun updateCooldownDisplay(remainingMillis: Long) {
        val totalSeconds = (remainingMillis + 999) / 1000
        var hours = totalSeconds / 3600
        var minutes = (totalSeconds % 3600) / 60
        var seconds = totalSeconds % 60
        if (hours == 1L && minutes == 0L) {
            hours = 0L
            minutes = 60L
        } else if (minutes == 1L && seconds == 0L) {
            minutes = 0
            seconds = 60
        }

        val message = when {
            hours > 0 -> {
                val hourText = LocaleController.getPlural(hours.toInt(), "hour")
                val minuteText = LocaleController.getPlural(minutes.toInt(), "minute")
                if (minutes > 0) {
                    LocaleController.getFormattedString(
                        "Try again in %1$@ and %2$@",
                        listOf(hourText, minuteText)
                    )
                } else {
                    LocaleController.getFormattedString(
                        "Try again in %1$@",
                        listOf(hourText)
                    )
                }
            }

            minutes > 0 -> {
                val minuteText = LocaleController.getPlural(minutes.toInt(), "minute")
                val secondText = LocaleController.getPlural(seconds.toInt(), "second")
                if (seconds > 0) {
                    LocaleController.getFormattedString(
                        "Try again in %1$@ and %2$@",
                        listOf(minuteText, secondText)
                    )
                } else {
                    LocaleController.getFormattedString(
                        "Try again in %1$@",
                        listOf(minuteText)
                    )
                }
            }

            else -> {
                val secondText = LocaleController.getPlural(seconds.toInt(), "second")
                LocaleController.getFormattedString("Try again in %1$@", listOf(secondText))
            }
        }

        subTitleTextView.text = message
    }

    private fun onCooldownFinished() {
        resetToNormalState()
        clearCooldown()
    }

    private fun resetToNormalState() {
        passcodeKeyboardView.unlockKeypad()
        subTitleTextView.text = subtitle
    }

}
