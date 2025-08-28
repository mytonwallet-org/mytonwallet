package org.mytonwallet.app_air.uipasscode.commonViews;

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class PasscodeInputView(
    context: Context,
    val delegate: WeakReference<Delegate>?,
    val light: Boolean = false,
    val margins: Int = 2
) :
    LinearLayout(context), View.OnKeyListener, WThemedView {

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
        id = generateViewId()
        isFocusableInTouchMode = true
        isFocusable = true
        setOnKeyListener(this)
    }

    override fun onCheckIsTextEditor(): Boolean {
        return true
    }

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = EditorInfo.TYPE_CLASS_NUMBER
        return CustomInputConnection(this, false)
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

    private fun setupViews() {
        for (i in 1..6) {
            val v = WView(context)
            val lp = ConstraintLayout.LayoutParams(16.dp, 16.dp)
            lp.setMargins(
                margins.dp,
                margins.dp,
                margins.dp,
                margins.dp
            )
            addView(v, lp)
            circleViews.add(v)
            v.visibility = if (i <= passLength) VISIBLE else GONE
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
        val primaryText = if (light) Color.WHITE else WColor.PrimaryText.color
        val secondaryText =
            if (light) Color.WHITE.colorWithAlpha(85) else WColor.SecondaryText.color
        circleViews.forEachIndexed { index, wView ->
            if (index < passcode.length)
                wView.animateBackgroundColor(
                    primaryText,
                    8f.dp,
                    primaryText,
                    1.dp
                )
            else
                wView.animateBackgroundColor(
                    Color.TRANSPARENT,
                    8f.dp,
                    secondaryText,
                    1.dp
                )
        }
    }
}

private class CustomInputConnection(targetView: View, fullEditor: Boolean) :
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
