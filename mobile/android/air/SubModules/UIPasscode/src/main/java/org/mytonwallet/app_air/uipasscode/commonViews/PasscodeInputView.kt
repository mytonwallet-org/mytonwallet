package org.mytonwallet.app_air.uipasscode.commonViews;

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.pulseView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.shakeView
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class PasscodeInputView(
    context: Context,
    val delegate: WeakReference<Delegate>?,
    val forceLightScreen: Boolean = false,
    val forceDarkScreen: Boolean = false,
    val margins: Int = 16,
    val showKeyboardOnFocus: Boolean,
) : WFrameLayout(context), View.OnKeyListener, WThemedView {

    interface Delegate {
        fun didChangePasscode(passcode: String)
        fun didEnterPasscode(passcode: String)
    }

    var passcode = ""
        set(value) {
            field = value
            updateTheme()
        }

    init {
        isFocusableInTouchMode = true
        isFocusable = true
        setOnKeyListener(this)
    }

    override fun onCheckIsTextEditor(): Boolean {
        return true
    }

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = EditorInfo.TYPE_CLASS_NUMBER
        return PasscodeInputConnection(this, false)
    }

    private var configured = false
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (configured)
            return
        configured = true
        setupViews()
    }

    override fun requestFocus(direction: Int, previouslyFocusedRect: Rect?): Boolean {
        super.requestFocus(direction, previouslyFocusedRect)
        if (showKeyboardOnFocus)
            showKeyboard()
        return true
    }

    private val circleViews = ArrayList<WView>()
    var passLength = 4
        set(value) {
            field = value
            circleViews.forEachIndexed { index, circleView ->
                circleView.visibility = if (index < value) VISIBLE else GONE
            }
        }

    private val roundDrawable = RoundProgressDrawable(12.dp, 0.5f.dp).apply {
        color = WColor.Green.color
    }

    private val progressView = AppCompatImageView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(14.dp, 14.dp)
        setPadding(2.dp)
        setImageDrawable(roundDrawable)
        scaleType = ImageView.ScaleType.CENTER_INSIDE
        alpha = 0f
    }

    private fun setupViews() {
        for (i in 0..5) {
            val v = WView(context)
            val lp = LayoutParams(14.dp, 14.dp).apply {
                if (LocaleController.isRTL) {
                    rightMargin = 4.dp + i * (14 + margins).dp
                    leftMargin = 4.dp
                } else {
                    leftMargin = 4.dp + i * (14 + margins).dp
                    rightMargin = 4.dp
                }
                topMargin = 4.dp
                bottomMargin = 4.dp
            }
            addView(v, lp)
            circleViews.add(v)
            v.visibility = if (i < passLength) VISIBLE else GONE
        }

        updateTheme()
    }

    override fun onKey(v: View?, keyCode: Int, event: KeyEvent?): Boolean {
        if (event?.action == KeyEvent.ACTION_DOWN) {
            when (keyCode) {
                in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> {
                    if (passcode.length < passLength) {
                        passcode += (keyCode - KeyEvent.KEYCODE_0).toString()
                        if (passcode.length == passLength) {
                            delegate?.get()?.didEnterPasscode(passcode)
                        } else {
                            delegate?.get()?.didChangePasscode(passcode)
                        }
                        return true
                    }
                }

                KeyEvent.KEYCODE_DEL -> {
                    if (passcode.isNotEmpty()) {
                        passcode = passcode.substring(0, passcode.length - 1)
                        delegate?.get()?.didChangePasscode(passcode)
                        return true
                    }
                }
            }
        }
        return false
    }

    override fun updateTheme() {
        val primaryText = if (forceLightScreen) Color.WHITE else
            if (forceDarkScreen) Color.BLACK else WColor.Tint.color
        val secondaryText =
            if (!forceDarkScreen && (forceLightScreen || ThemeManager.isDark))
                Color.WHITE.colorWithAlpha(85) else Color.BLACK.colorWithAlpha(85)
        circleViews.forEachIndexed { index, wView ->
            if (index < passcode.length) {
                if (wView.currentBackgroundColor != primaryText)
                    wView.pulseView()
                wView.animateBackgroundColor(
                    primaryText,
                    8f.dp,
                    primaryText,
                    1.dp
                )
            } else {
                wView.animateBackgroundColor(
                    Color.TRANSPARENT,
                    8f.dp,
                    secondaryText,
                    1.dp
                )
            }
        }
    }

    fun resetInput() {
        passcode = ""
        shakeView()
        Haptics.play(this, HapticType.ERROR)
    }

    var isShowingIndicator = false
    fun showIndicator(animateToGreen: Boolean = true) {
        if (isShowingIndicator)
            return
        if (!animateToGreen) {
            roundDrawable.color = if (forceLightScreen) Color.WHITE else WColor.Tint.color
        }
        isShowingIndicator = true
        circleViews.forEach {
            if (animateToGreen) {
                if (it.currentBackgroundColor != WColor.Tint.color) {
                    it.setBackgroundColor(WColor.Green.color, 8f.dp)
                }
            }
            it.pulseView()
        }
        Handler(Looper.getMainLooper()).postDelayed({
            if (!isShowingIndicator)
                return@postDelayed
            animateCirclesToCenter(animateToGreen) {
                if (!isShowingIndicator)
                    return@animateCirclesToCenter
                addView(
                    progressView,
                    LayoutParams(14.dp, 14.dp).apply {
                        gravity = Gravity.CENTER
                    }
                )
                circleViews.forEach {
                    it.fadeOut()
                }
                progressView.fadeIn()
            }
        }, AnimationConstants.VERY_QUICK_ANIMATION)
    }

    fun hideIndicator() {
        if (!isShowingIndicator) return

        isShowingIndicator = false
        (progressView.parent as? ViewGroup)?.removeView(progressView)

        circleViews.forEachIndexed { i, view ->
            view.apply {
                scaleX = 1f
                scaleY = 1f
                alpha = 1f
                layoutParams = (layoutParams as LayoutParams).apply {
                    if (LocaleController.isRTL) {
                        rightMargin = 4.dp + i * (14 + margins).dp
                        leftMargin = 4.dp
                    } else {
                        leftMargin = 4.dp + i * (14 + margins).dp
                        rightMargin = 4.dp
                    }
                    gravity = Gravity.NO_GRAVITY
                }
                visibility = if (i < passLength) VISIBLE else GONE
            }
        }
    }

    private fun animateCirclesToCenter(animateToGreen: Boolean, onComplete: () -> Unit) {
        val centerX = width / 2

        circleViews.forEachIndexed { index, view ->
            val targetTranslation = centerX - view.x - 8f.dp

            view.animate()
                .translationX(targetTranslation)
                .scaleX(0.8f)
                .scaleY(0.8f)
                .alpha(0.5f)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .setInterpolator(WInterpolator.emphasized)
                .withEndAction {
                    view.translationX = 0f
                    view.layoutParams = (view.layoutParams as LayoutParams).apply {
                        rightMargin = 4.dp
                        leftMargin = 4.dp
                        gravity = Gravity.CENTER
                    }

                    if (index == circleViews.lastIndex) {
                        onComplete()
                    }
                }

            if (animateToGreen)
                view.animateBackgroundColor(WColor.Green.color, 8f.dp)
        }
    }
}

class PasscodeInputConnection(targetView: View, fullEditor: Boolean) :
    BaseInputConnection(targetView, fullEditor) {
    override fun sendKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_DEL) {
            return super.sendKeyEvent(event)
        }
        return super.sendKeyEvent(event)
    }

    override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
        if (beforeLength == 1 && afterLength == 0) {
            return sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL)) &&
                sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
        }
        return super.deleteSurroundingText(beforeLength, afterLength)
    }
}
