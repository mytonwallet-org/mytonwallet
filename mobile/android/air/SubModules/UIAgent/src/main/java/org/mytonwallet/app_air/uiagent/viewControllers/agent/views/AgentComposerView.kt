package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatEditText
import androidx.core.widget.doAfterTextChanged
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.emoji.EmojiHelper
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.scaleIn
import org.mytonwallet.app_air.uicomponents.widgets.scaleOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class AgentComposerView(context: Context, private val blurRootView: ViewGroup? = null) :
    WFrameLayout(context),
    WThemedView {

    var onSend: ((String) -> Boolean)? = null
    var onDraftCleared: (() -> Unit)? = null

    private val inputBackground = WFrameLayout(context)
    var onHeightChanged: (() -> Unit)? = null

    val inputBottomInset: Int
        get() = paddingBottom + 2 * WGlassView.GLASS_PADDING_DP.dp

    private val editText = AppCompatEditText(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, adaptiveFontSize())
        typeface = WFont.Regular.typeface
        hint = LocaleController.getString("Ask anything")
        maxLines = 5
        inputType = EditorInfo.TYPE_CLASS_TEXT or
            EditorInfo.TYPE_TEXT_FLAG_CAP_SENTENCES or
            EditorInfo.TYPE_TEXT_FLAG_MULTI_LINE
        imeOptions = EditorInfo.IME_ACTION_SEND
        background = null
        setPaddingRelative(16.dp, 10.dp, 16.dp, 10.dp)
    }

    private val sendButton = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER
        isClickable = true
        isFocusable = true
        scaleX = 0f
        scaleY = 0f
    }

    private var isSendEnabled = false
    private var isSubmissionEnabled = true
    private var lastHeight = 0
    private var isApplyingEmoji = false
    private var inputGlass: WGlassView? = null

    init {
        layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        setPaddingDp(16, 8, 16, 8)
        clipChildren = false
        clipToPadding = false

        inputBackground.minimumHeight = 48.dp
        inputBackground.addView(
            editText,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.TOP
                topMargin = 2.5f.dp.roundToInt()
            }
        )

        sendButton.layoutParams = LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.END or Gravity.BOTTOM
            marginEnd = 4.dp
            bottomMargin = 4.dp
        }
        inputBackground.addView(sendButton)

        addView(inputBackground, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        inputGlass = WGlassView.attachTo(
            inputBackground,
            24f.dp,
            GlassProviders.composer(WColor.SearchFieldBackground),
            blurRootView
        )

        editText.doAfterTextChanged { editable ->
            if (!isApplyingEmoji && editable != null) {
                isApplyingEmoji = true
                EmojiHelper.replaceEmojiInPlace(editable, editText)
                isApplyingEmoji = false
            }
            updateSendButtonState()
            if (editable.isNullOrEmpty()) onDraftCleared?.invoke()
        }

        sendButton.setOnClickListener { trySend() }

        editText.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                trySend()
                true
            } else {
                false
            }
        }

        editText.setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN &&
                !event.isShiftPressed
            ) {
                trySend()
                true
            } else {
                false
            }
        }

        updateTheme()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (height != lastHeight) {
            lastHeight = height
            onHeightChanged?.invoke()
        }
    }

    fun setDraftText(text: String) {
        editText.setText(text)
        editText.setSelection(editText.length())
        editText.requestFocus()
        editText.post { editText.showKeyboard() }
    }

    private fun trySend() {
        val text = editText.text?.toString()?.trim() ?: return
        if (text.isNotEmpty() && onSend?.invoke(text) == true) {
            editText.text?.clear()
        }
    }

    private fun updateSendButtonState() {
        val hasText = !editText.text.isNullOrBlank()
        isSendEnabled = isSubmissionEnabled && hasText
        applySendButtonTheme()
    }

    private var paddingAnimator: ValueAnimator? = null

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
        if (sendButton.isEnabled == isSendEnabled) return
        sendButton.isEnabled = isSendEnabled
        sendButton.isClickable = isSendEnabled
        if (isSendEnabled) {
            sendButton.scaleIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        } else {
            sendButton.scaleOut(AnimationConstants.SUPER_QUICK_ANIMATION)
        }
        animateInputPadding()
    }

    private fun animateInputPadding() {
        paddingAnimator?.cancel()
        val targetPadding = if (isSendEnabled) 52.dp else 16.dp
        paddingAnimator = ValueAnimator.ofInt(editText.paddingEnd, targetPadding).apply {
            duration = if (WGlobalStorage.getAreAnimationsActive()) {
                AnimationConstants.SUPER_QUICK_ANIMATION
            } else {
                0L
            }
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                editText.setPaddingRelative(
                    editText.paddingStart,
                    editText.paddingTop,
                    animation.animatedValue as Int,
                    editText.paddingBottom
                )
            }
            start()
        }
    }

    fun setSubmissionEnabled(enabled: Boolean) {
        if (isSubmissionEnabled == enabled) return
        isSubmissionEnabled = enabled
        updateSendButtonState()
    }

    override fun updateTheme() {
        editText.setHintTextColor(WColor.SecondaryText.color)
        editText.setTextColor(WColor.PrimaryText.color)
        editText.highlightColor = WColor.Tint.color and 0x40FFFFFF

        inputBackground.setBackgroundColor(
            Color.TRANSPARENT,
            24f.dp,
            clipToBounds = true
        )
        inputGlass?.updateTheme()

        applySendButtonTheme()
    }
}
