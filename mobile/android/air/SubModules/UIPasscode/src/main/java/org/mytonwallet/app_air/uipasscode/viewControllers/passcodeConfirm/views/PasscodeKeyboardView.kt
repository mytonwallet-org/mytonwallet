package org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views

import android.annotation.SuppressLint
import android.content.Context
import androidx.core.content.ContextCompat
import androidx.core.view.children
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeInObjectAnimator
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcore.stores.AuthStore
import kotlin.math.min

@SuppressLint("ViewConstructor")
class PasscodeKeyboardView(
    context: Context,
    val light: Boolean?,
    showMotionBackgroundDrawable: Boolean,
    ignoreBiometry: Boolean
) : WFrameLayout(context), WThemedView {
    companion object {
        private const val GAP = 8
        private const val HEIGHT = 80
        private const val MAX_BUTTON_WIDTH = 120
    }

    var listener: PasscodeListener? = null

    interface PasscodeListener {
        fun onBiometricsCheck()
        fun onNumberDelete()
        fun onNumberInput(number: Int)
    }

    private lateinit var deleteButton: PasscodeNumberView

    init {
        for (a in 0..11) {
            addView(
                PasscodeNumberView(
                    context,
                    1 + a / 3,
                    1 + a % 3,
                    light,
                    showMotionBackgroundDrawable
                ).apply {
                    when (a) {
                        11 -> { // backspace
                            deleteButton = this
                            setOnClickListener {
                                Haptics.play(this, HapticType.LIGHT_TAP)
                                listener?.onNumberDelete()
                            }
                        }

                        9 -> { // biometric
                            customDrawable = ContextCompat.getDrawable(
                                context,
                                R.drawable.ic_biometric
                            )
                            setOnClickListener {
                                Haptics.play(this, HapticType.LIGHT_TAP)
                                listener?.onBiometricsCheck()
                            }
                            isGone =
                                ignoreBiometry || !WGlobalStorage.isBiometricActivated() ||
                                    !BiometricHelpers.canAuthenticate(context)
                        }

                        else -> {
                            setOnClickListener {
                                Haptics.play(this, HapticType.LIGHT_TAP)
                                num?.let { listener?.onNumberInput(it) }
                            }
                        }
                    }
                }, LayoutParams(80.dp, 80.dp)
            )
        }
    }

    private var buttonWidth = 0
    private var buttonSize = 0

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)

        val maxButtonWidth =
            min((width - paddingLeft - paddingRight - GAP.dp * 4) / 3, MAX_BUTTON_WIDTH.dp)

        val totalGapHeight = GAP.dp * 3
        val availableHeight = height - paddingTop - paddingBottom - totalGapHeight
        val maxButtonHeight = availableHeight / 4

        buttonWidth = maxButtonWidth
        buttonSize = min(HEIGHT.dp, min(maxButtonWidth, maxButtonHeight))

        val measuredHeight = paddingTop + buttonSize * 4 + GAP.dp * 3 + paddingBottom

        for (i in 0 until childCount) {
            val child = getChildAt(i)
            child.measure(buttonWidth.exactly, buttonSize.exactly)
        }

        setMeasuredDimension(width, measuredHeight)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val o = (measuredWidth - paddingLeft - paddingRight - buttonWidth * 3 - GAP.dp * 2) / 2
        for (i in 0 until childCount) {
            val child = getChildAt(i)

            val bx = i % 3
            val by = i / 3

            val left = paddingLeft + bx * (buttonWidth + GAP.dp) + o
            val top = paddingTop + by * buttonSize + GAP.dp * by

            child.layout(left, top, left + buttonWidth, top + buttonSize)
            (child as? PasscodeNumberView)?.apply {
                updateConstraintsForSize(buttonSize)
                updateBackground()
            }
        }
    }

    var showSignOut: Boolean = AuthStore.getCooldownDate() > System.currentTimeMillis()
    val exitDrawable = ContextCompat.getDrawable(
        context,
        org.mytonwallet.app_air.icons.R.drawable.ic_exit_filled
    )
    val backspaceDrawable = ContextCompat.getDrawable(
        context,
        R.drawable.ic_backspace
    )

    fun updateButtons(isEmpty: Boolean) {
        deleteButton.drawableTint = if (isEmpty && showSignOut) WColor.Error.color else null
        val prevDrawable = deleteButton.customDrawable
        deleteButton.customDrawable =
            if (isEmpty && showSignOut)
                exitDrawable
            else if (!isEmpty)
                backspaceDrawable
            else
                null
        if (prevDrawable != deleteButton.customDrawable)
            deleteButton.updateImage(true)
    }

    fun lockKeypad() {
        children.forEach {
            if (it != deleteButton) {
                it.lockView()
                it.apply {
                    if (isGone)
                        return@apply
                    if (!isAttachedToWindow) {
                        alpha = 0.5f
                    } else {
                        fadeOut(targetAlpha = 0.5f)
                    }
                }
            }
        }
    }

    fun unlockKeypad() {
        children.forEach {
            it.unlockView()
            it.apply {
                if (alpha == 1f)
                    return@apply
                fadeInObjectAnimator()?.start()
            }
        }
    }

    override fun updateTheme() {
        invalidate()
    }
}
