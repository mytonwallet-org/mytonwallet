package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.animation.ValueAnimator
import android.graphics.drawable.GradientDrawable
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatEditText
import androidx.core.widget.doAfterTextChanged
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.emoji.EmojiHelper
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.scaleIn
import org.mytonwallet.app_air.uicomponents.widgets.scaleOut
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class AgentComposerView(context: Context) : WFrameLayout(context), WThemedView {

    var onSend: ((String) -> Unit)? = null
    var onHintsToggle: (() -> Unit)? = null

    private val inputBackground = WFrameLayout(context)
    var onHeightChanged: (() -> Unit)? = null

    private val editText = AppCompatEditText(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = WFont.Regular.typeface
        hint = LocaleController.getString("Ask anything")
        maxLines = 5
        inputType = EditorInfo.TYPE_CLASS_TEXT or
            EditorInfo.TYPE_TEXT_FLAG_CAP_SENTENCES or
            EditorInfo.TYPE_TEXT_FLAG_MULTI_LINE
        imeOptions = EditorInfo.IME_ACTION_SEND
        background = null
        setPaddingDp(16, 10, 52, 10)
    }

    private val hintsBgDrawable = GradientDrawable().apply {
        cornerRadius = 12f.dp
    }
    private val hintsRipple = WRippleDrawable.create(12f.dp)
    private val hintsButton = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER
        isClickable = true
        isFocusable = true
        foreground = hintsRipple
        setImageResource(R.drawable.ic_suggestions)
    }

    private val sendButton = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER
        isClickable = true
        isFocusable = true
        scaleX = 0f
        scaleY = 0f
    }

    private var isSendEnabled = false
    private var hintsActive = false
    private var lastHeight = 0
    private var isApplyingEmoji = false

    init {
        layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        setPaddingDp(16, 8, 16, 8)
        clipChildren = false
        clipToPadding = false

        inputBackground.minimumHeight = 48.dp
        inputBackground.addView(editText, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            gravity = Gravity.TOP
            topMargin = 2.5f.dp.roundToInt()
        })

        hintsButton.layoutParams = LayoutParams(32.dp, 32.dp).apply {
            gravity = Gravity.END or Gravity.BOTTOM
            marginEnd = 12.dp
            bottomMargin = 8.dp
        }
        inputBackground.addView(hintsButton)

        sendButton.layoutParams = LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.END or Gravity.BOTTOM
            marginEnd = 4.dp
            bottomMargin = 4.dp
        }
        inputBackground.addView(sendButton)

        addView(inputBackground, LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        editText.doAfterTextChanged { editable ->
            if (!isApplyingEmoji && editable != null) {
                isApplyingEmoji = true
                EmojiHelper.replaceEmojiInPlace(editable, editText)
                isApplyingEmoji = false
            }
            updateSendButtonState()
            post {
                if (height != lastHeight) {
                    lastHeight = height
                    onHeightChanged?.invoke()
                }
            }
        }

        hintsButton.setOnClickListener {
            onHintsToggle?.invoke()
        }
        sendButton.setOnClickListener { trySend() }

        editText.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                trySend()
                true
            } else false
        }

        editText.setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN && !event.isShiftPressed) {
                trySend()
                true
            } else false
        }

        updateTheme()
    }

    private fun trySend() {
        val text = editText.text?.toString()?.trim() ?: return
        if (text.isNotEmpty()) {
            onSend?.invoke(text)
            editText.text?.clear()
        }
    }

    fun clearDraft() {
        editText.text?.clear()
    }

    val draftText: String?
        get() = editText.text?.toString()

    private fun updateSendButtonState() {
        val hasText = !editText.text.isNullOrBlank()
        isSendEnabled = hasText
        applySendButtonTheme()
    }

    private var hintsAnimator: ValueAnimator? = null

    private fun applySendButtonTheme() {
        val sendDrawable = GradientDrawable().apply {
            cornerRadius = 20f.dp
            if (isSendEnabled) {
                setColor(WColor.Tint.color)
            } else {
                setColor(WColor.SearchFieldBackground.color)
            }
        }
        sendButton.background = sendDrawable

        sendButton.setImageResource(R.drawable.ic_send)
        if (sendButton.isEnabled == isSendEnabled)
            return
        sendButton.isEnabled = isSendEnabled
        if (isSendEnabled) {
            sendButton.scaleIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        } else {
            sendButton.scaleOut(AnimationConstants.SUPER_QUICK_ANIMATION)
        }
        animateHintsButton(isSendEnabled)
    }

    private fun animateHintsButton(sendVisible: Boolean) {
        val targetTranslationX = if (sendVisible) (-44f).dp else 0f

        hintsAnimator?.cancel()
        hintsAnimator =
            ValueAnimator.ofFloat(hintsButton.translationX, targetTranslationX).apply {
                duration = AnimationConstants.SUPER_QUICK_ANIMATION
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener { animation ->
                    hintsButton.translationX = animation.animatedValue as Float
                    val fraction = animation.animatedFraction
                    val padding = if (sendVisible) {
                        (52.dp + fraction * (88.dp - 52.dp)).toInt()
                    } else {
                        (88.dp - fraction * (88.dp - 52.dp)).toInt()
                    }
                    editText.setPadding(
                        editText.paddingLeft,
                        editText.paddingTop,
                        padding,
                        editText.paddingBottom
                    )
                }
                start()
            }
    }

    fun setHintsActive(active: Boolean) {
        if (hintsActive == active) return
        hintsActive = active
        applyHintsButtonTheme()
    }

    fun setHintsAvailable(available: Boolean) {
        hintsButton.isClickable = available
        hintsButton.isFocusable = available
    }

    private fun applyHintsButtonTheme() {
        if (hintsActive) {
            hintsButton.setImageResource(R.drawable.ic_suggestions_close)
            hintsButton.setColorFilter(WColor.SecondaryText.color)
        } else {
            hintsButton.setImageResource(R.drawable.ic_suggestions)
            hintsButton.setColorFilter(WColor.SecondaryText.color)
        }
    }

    override fun updateTheme() {
        editText.setHintTextColor(WColor.SecondaryText.color)
        editText.setTextColor(WColor.PrimaryText.color)
        editText.highlightColor = WColor.Tint.color and 0x40FFFFFF

        val bgDrawable = GradientDrawable().apply {
            cornerRadius = 24f.dp
            setColor(WColor.Background.color)
        }
        inputBackground.background = bgDrawable
        inputBackground.elevation = 2f.dp

        applyHintsButtonTheme()
        hintsRipple.rippleColor = WColor.BackgroundRipple.color

        applySendButtonTheme()
    }
}
