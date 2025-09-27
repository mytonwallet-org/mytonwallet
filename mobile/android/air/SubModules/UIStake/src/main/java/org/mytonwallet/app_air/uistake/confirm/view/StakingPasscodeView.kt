package org.mytonwallet.app_air.uistake.confirm.view

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintSet
import com.google.android.material.progressindicator.CircularProgressIndicator
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticFeedbackHelper
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.shakeView
import org.mytonwallet.app_air.uipasscode.commonViews.PasscodeInputView
import org.mytonwallet.app_air.uipasscode.commonViews.PasscodeNumberView
import org.mytonwallet.app_air.uistake.confirm.ConfirmStakingHeaderView
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MToken
import java.math.BigInteger

@SuppressLint("ViewConstructor")
class StakingPasscodeView(
    val window: WWindow,
    val light: Boolean,
    val animated: Boolean,
    val amountInCrypto: BigInteger,
    val token: MToken,
    showPositiveSignForAmount: Boolean,
    messageString: String,
    val onEnteredPasscode: (passcode: String, callback: (wasCorrect: Boolean) -> Unit) -> Unit
) : WView(window), WThemedView {

    private val title =
        LocaleController.getString(
            (if (WGlobalStorage.isBiometricActivated() && BiometricHelpers.canAuthenticate(window))
                "Enter passcode or use fingerprint" else "Enter Passcode")
        )

    private val passLength = WSecureStorage.getPasscodeLength()

    private val headerView = ConfirmStakingHeaderView(context).apply {
        config(token, amountInCrypto, showPositiveSignForAmount, messageString)
    }
    private val confirmGap = View(context).apply {
        id = generateViewId()
    }

    private val passcodeInputView: PasscodeInputView by lazy {
        val v = PasscodeInputView(context, null, light, margins = 8, showKeyboardOnFocus = false)
        v.isEnabled = false
        v.passLength = passLength
        v
    }

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(15f, WFont.Regular)
        lbl.text = title
        lbl
    }

    private val numPadItems = ArrayList<PasscodeNumberView>()
    private val numPadView: WView by lazy {
        val v = WView(context)
        for (row in 1..4) {
            for (column in 1..3) {
                val numPadItem = PasscodeNumberView(context, row, column, light)
                val isBiometricButton = numPadItem.num == null && column == 1
                numPadItems.add(numPadItem)
                numPadItem.setOnClickListener {
                    doOnNumPadClick?.invoke()
                    if (numPadItem.num != null) {
                        passcodeInputView.passcode += numPadItem.num
                        if (passcodeInputView.passcode.length >= passLength) {
                            checkPasscode(passcodeInputView.passcode)
                        }
                    } else {
                        if (isBiometricButton) {
                            tryBiometrics(true)
                        } else {
                            passcodeInputView.passcode = passcodeInputView.passcode.dropLast(1)
                        }
                    }
                }
                if (isBiometricButton) {
                    numPadItem.visibility =
                        if (WGlobalStorage.isBiometricActivated() &&
                            BiometricHelpers.canAuthenticate(window)
                        ) VISIBLE else INVISIBLE
                }
                v.addView(numPadItem, LayoutParams(80.dp, 80.dp))
            }
        }
        val px192 = (192 + 62).dp
        v.setConstraints {
            numPadItems.forEachIndexed { index, passcodeNumberView ->
                if (index > 2) {
                    topToBottom(passcodeNumberView, numPadItems[index - 3], 8f)
                } else {
                    toTop(passcodeNumberView)
                }
                toCenterX(passcodeNumberView)
                setMargin(passcodeNumberView.id, ConstraintSet.START, ((index % 3) - 1) * px192)
            }
        }
        v
    }

    var doOnNumPadClick: (() -> Unit)? = null

    override fun setupViews() {
        super.setupViews()

        addView(headerView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(confirmGap, ViewGroup.LayoutParams(MATCH_PARENT, 12.dp))

        addView(passcodeInputView)
        addView(titleLabel)
        addView(numPadView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        setConstraints {
            toTop(headerView)

            topToBottom(confirmGap, headerView)
            topToBottom(titleLabel, confirmGap, 26f)
            topToBottom(passcodeInputView, titleLabel, 18.5f)

            toCenterX(headerView)
            toCenterX(passcodeInputView)
            toCenterX(titleLabel)
            toCenterX(numPadView)
            topToBottom(numPadView, passcodeInputView, 75f)
        }

        val startWithBiometrics =
            WGlobalStorage.isBiometricActivated() && BiometricHelpers.canAuthenticate(window)

        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            passcodeInputView.scaleX = 0f
            passcodeInputView.scaleY = 0f
            titleLabel.alpha = 0f
            numPadItems.forEach {
                it.scaleX = 0f
                it.scaleY = 0f
            }
            ValueAnimator.ofInt(0, 800.dp).apply {
                startDelay = AnimationConstants.QUICK_ANIMATION
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
                        titleLabel.alpha = 0f
                    } else if (updatedValue <= 800) {
                        val alpha = (updatedValue - 350) / 450f
                        titleLabel.translationX = (1 - alpha) * 20
                        titleLabel.alpha = alpha
                    }

                    if (!startWithBiometrics) {
                        numPadItems.forEachIndexed { index, passcodeNumberView ->
                            val startTime = 150 + index * 50
                            val endTime = startTime + 250f
                            val value = if (updatedValue <= startTime) {
                                0f
                            } else if (updatedValue >= endTime) {
                                1f
                            } else
                                (updatedValue - startTime) / (endTime - startTime)
                            passcodeNumberView.scaleX = value
                            passcodeNumberView.scaleY = value
                        }
                    }
                }

                start()
            }
        } else {
            if (startWithBiometrics) {
                numPadItems.forEach {
                    it.scaleX = 0f
                    it.scaleY = 0f
                }
            }
        }

        updateTheme()

        if (startWithBiometrics) {
            tryBiometrics(false)
        }
    }

    override fun updateTheme() {
        confirmGap.setBackgroundColor(WColor.SecondaryBackground.color)

        val color = if (light) Color.WHITE else WColor.SecondaryText.color
        window.forceStatusBarLight = light
        window.forceBottomBarLight = light
        titleLabel.setTextColor(color)
    }

    private fun checkPasscode(passcode: String) {
        lockView()
        onEnteredPasscode(passcode) { wasCorrect ->
            if (!wasCorrect) {
                Handler(Looper.getMainLooper()).postDelayed({
                    passcodeInputView.passcode = ""
                    passcodeInputView.shakeView()
                    HapticFeedbackHelper(context).provideErrorFeedback()
                    unlockView()
                }, 500)
            }
        }
    }

    override fun unlockView() {
        super.unlockView()
        passcodeInputView.isEnabled = false
    }

    private fun tryBiometrics(viewIsLoaded: Boolean) {
        if (viewIsLoaded)
            numPadView.fadeOut()
        BiometricHelpers.authenticate(
            window,
            title,
            null,
            null,
            LocaleController.getString("Use PIN"),
            onSuccess = {
                checkPasscode(WSecureStorage.getBiometricPasscode(window) ?: "")
            },
            onCanceled = {
                if (viewIsLoaded) {
                    numPadView.fadeIn()
                } else {
                    if (!WGlobalStorage.getAreAnimationsActive()) {
                        numPadItems.forEach {
                            it.scaleX = 1f
                            it.scaleY = 1f
                        }
                        return@authenticate
                    }
                    ValueAnimator.ofInt(0, 430.dp).apply {
                        startDelay = AnimationConstants.VERY_QUICK_ANIMATION
                        duration = AnimationConstants.VERY_SLOW_ANIMATION
                        addUpdateListener { updatedAnimation ->
                            val updatedValue = updatedAnimation.animatedValue as Int

                            numPadItems.forEachIndexed { index, passcodeNumberView ->
                                val startTime = index * 30
                                val endTime = startTime + 100f
                                val value = if (updatedValue <= startTime) {
                                    0f
                                } else if (updatedValue >= endTime) {
                                    1f
                                } else
                                    (updatedValue - startTime) / (endTime - startTime)
                                passcodeNumberView.scaleX = value
                                passcodeNumberView.scaleY = value
                            }
                        }
                        start()
                    }
                }
            }
        )
    }

    fun showIndicator() {
        passcodeInputView.fadeOut {
            val progressIndicator = CircularProgressIndicator(context).apply {
                id = generateViewId()
                isIndeterminate = true
                setIndicatorColor(titleLabel.currentTextColor)
                indicatorSize = 28.dp
            }
            addView(
                progressIndicator,
                ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
            )
            progressIndicator.elevation = 1000f
            setConstraints {
                edgeToEdge(progressIndicator, passcodeInputView)
            }
        }
    }

}
