package org.mytonwallet.app_air.uicomponents.commonViews

import android.R
import android.annotation.SuppressLint
import android.os.Build
import android.text.SpannableString
import android.text.Spanned
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputConnectionWrapper
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatEditText
import androidx.appcompat.widget.AppCompatImageView
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.widget.addTextChangedListener
import androidx.core.widget.doOnTextChanged
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getTextFromClipboard
import org.mytonwallet.app_air.uicomponents.extensions.resize
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.extensions.setTextIfDiffer
import org.mytonwallet.app_air.uicomponents.helpers.EditTextTint
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.autoComplete.WAutoCompleteView
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.theme.colorStateList
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class AddressInputLayout(
    val viewController: WeakReference<WViewController>,
    val autoCompleteConfig: AutoCompleteConfig = AutoCompleteConfig(),
    onTextEntered: () -> Unit
) : FrameLayout(viewController.get()!!.context), WThemedView {

    companion object {
        const val IS_AUTOCOMPLETE_ENABLED = false
    }

    data class AutoCompleteConfig(
        private val enabled: Boolean = true,
        val accountAddresses: Boolean = true
    ) {
        val isEnabled: Boolean
            get() {
                return IS_AUTOCOMPLETE_ENABLED && enabled
            }
    }

    private val buttonsVisible = BoolAnimator(
        220L,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        true
    ) { state, value, changed, _ ->
        pasteTextView.alpha = value
        qrScanImageView.alpha = value
        if (changed) {
            pasteTextView.isEnabled = state == BoolAnimator.State.TRUE
            pasteTextView.isVisible = state != BoolAnimator.State.FALSE
            qrScanImageView.isEnabled = state == BoolAnimator.State.TRUE
            qrScanImageView.isVisible = state != BoolAnimator.State.FALSE
        }
    }

    private val textField = object : AppCompatEditText(context) {
        override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? {
            val ic = super.onCreateInputConnection(outAttrs) ?: return null
            return object : InputConnectionWrapper(ic, true) {
                override fun commitText(txt: CharSequence?, newCursorPosition: Int): Boolean {
                    val oldText = text?.toString() ?: ""
                    val result = super.commitText(txt, newCursorPosition)

                    if (result && txt != null && txt.length > 1) {
                        val newText = text?.toString() ?: ""
                        if (MBlockchain.Companion.isValidAddressOnAnyChain(newText)) {
                            if (newText.length > oldText.length + 1) {
                                post { onTextEntered() }
                            }
                        }
                    }
                    return result
                }
            }
        }

        override fun onTextContextMenuItem(id: Int): Boolean {
            if (id == R.id.paste || id == R.id.pasteAsPlainText) {
                val result = super.onTextContextMenuItem(id)
                if (result && MBlockchain.Companion.isValidAddressOnAnyChain(text.toString())) {
                    post { onTextEntered() }
                }
                return result
            }
            return super.onTextContextMenuItem(id)
        }
    }.apply {
        background = null
        hint =
            LocaleController.getString("Wallet Address or Domain")
        typeface = WFont.Regular.typeface
        layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        maxLines = 3
        setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN) {
                onTextEntered()
                return@setOnKeyListener true
            }
            false
        }
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        }
        onFocusChangeListener = OnFocusChangeListener { v, hasFocus ->
            if (!autoCompleteConfig.isEnabled)
                return@OnFocusChangeListener
            if (hasFocus) {
                hideOverlayViews()
                if (autoCompleteView.parent == null)
                    viewController.get()?.view?.addView(
                        autoCompleteView,
                        LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                    )
                autoCompleteView.attachToAddressInput(this@AddressInputLayout, autoCompleteConfig)
            } else {
                if (autoCompleteView.parent != null)
                    viewController.get()?.view?.removeView(autoCompleteView)
                autoCompleteView.attachToAddressInput(null, autoCompleteConfig)
                findAddressAttempt()
            }
        }
        doOnTextChanged { t, _, _, _ ->
            buttonsVisible.animatedValue = t.isNullOrEmpty()
            if (t.toString().trim() != selectedAddress?.address) {
                selectedAddress = null
            }
            updateTextFieldPadding()
        }
    }

    private val qrScanImageViewRipple = WRippleDrawable.Companion.create(8f.dp)
    val qrScanImageView = AppCompatImageView(context).apply {
        background = qrScanImageViewRipple
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_qr_code_scan_16_24)
        layoutParams = LayoutParams(
            24.dp,
            24.dp,
            Gravity.TOP or if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT
        ).apply {
            topMargin = 8.dp
            if (LocaleController.isRTL) {
                leftMargin = 20.dp
            } else {
                rightMargin = 20.dp
            }
        }
    }

    private val pasteTextViewRipple = WRippleDrawable.Companion.create(8f.dp)
    val pasteTextView = AppCompatTextView(context).apply {
        background = pasteTextViewRipple
        setPaddingDp(4, 0, 4, 0)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)

        text = LocaleController.getString("Paste")
        typeface = WFont.Regular.typeface
        layoutParams = LayoutParams(
            WRAP_CONTENT,
            WRAP_CONTENT,
            Gravity.TOP or if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT
        ).apply {
            topMargin = 8.dp
            if (LocaleController.isRTL) {
                leftMargin = (20 + 24 + 12).dp
            } else {
                rightMargin = (20 + 24 + 12).dp
            }
        }
    }

    private var selectedAddress: MSavedAddress? = null
    val autoCompleteView = WAutoCompleteView(context, onSuggest = {
        onSuggestSelected(it)
    }).apply {
        elevation = 4f.dp
    }

    private val overlayLabel = WLabel(context).apply {
        setStyle(16f)
        gravity = Gravity.CENTER_VERTICAL
        setPaddingDp(20, 8, 48, 20)
        isGone = true
        setOnClickListener {
            hideOverlayViews()
            textField.requestFocus()
            textField.setSelection(textField.text?.length ?: 0)
            textField.showKeyboard()
        }
    }

    private val closeButton: WImageButton by lazy {
        WImageButton(context).apply {
            val closeDrawable =
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.uicomponents.R.drawable.ic_close
                )?.resize(context, 16.dp, 16.dp)
            setImageDrawable(closeDrawable)
            isGone = true
            setOnClickListener {
                hideOverlayViews()
                textField.setText("")
                textField.requestFocus()
                textField.showKeyboard()
            }
        }
    }

    private var afterQrScannedListener: ((String) -> Unit)? = null
    fun doAfterQrCodeScanned(listener: ((String) -> Unit)?) {
        afterQrScannedListener = listener
    }

    init {
        addView(textField)
        addView(qrScanImageView)
        addView(pasteTextView)
        if (autoCompleteConfig.isEnabled) {
            addView(overlayLabel, LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(closeButton, LayoutParams(20.dp, 20.dp).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                marginEnd = 20.dp
                bottomMargin = 6.dp
            })
        }

        pasteTextView.setOnClickListener {
            context.getTextFromClipboard()?.let {
                textField.setTextIfDiffer(it, selectionToEnd = true)
                onTextEntered()
            }
        }

        WalletContextManager.delegate?.bindQrCodeButton(
            context,
            qrScanImageView,
            {
                setText(it)
                clearFocus()
                hideKeyboard()
                afterQrScannedListener?.invoke(it)
            }
        )

        updateTextFieldPadding()
        updateTheme()
    }

    override val isTinted = true
    override fun updateTheme() {
        qrScanImageViewRipple.rippleColor = WColor.TintRipple.color
        pasteTextViewRipple.rippleColor = WColor.TintRipple.color
        qrScanImageView.imageTintList = WColor.Tint.colorStateList
        pasteTextView.setTextColor(WColor.Tint.color)
        textField.setTextColor(WColor.PrimaryText.color)
        textField.setHintTextColor(WColor.SecondaryText.color)
        textField.highlightColor = WColor.Tint.color.colorWithAlpha(51)
        EditTextTint.applyColor(textField, WColor.Tint.color)
        overlayLabel.setBackgroundColor(WColor.Background.color, ViewConstants.BIG_RADIUS.dp)
        updateOverlayText()
        closeButton.apply {
            setBackgroundColor(WColor.SecondaryBackground.color, 10f.dp)
            updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
        }
    }

    fun insetsUpdated() {
        if (!autoCompleteConfig.isEnabled)
            return
        val viewController = viewController.get() ?: return
        val keyboardHeight = viewController.window?.imeInsets?.bottom ?: return
        if (keyboardHeight == 0) {
            autoCompleteView.attachToAddressInput(null, autoCompleteConfig)
            return
        }
        autoCompleteView.attachToAddressInput(this, autoCompleteConfig)
        val totalHeight =
            ((viewController.navigationController?.parent as? ViewGroup)?.height ?: 0)
        val location = IntArray(2)
        viewController.view.getLocationInWindow(location)
        autoCompleteView.maxYInWindow =
            totalHeight - keyboardHeight - 16.dp
    }

    fun getKeyword(): String {
        return textField.text.toString().trim()
    }

    fun getAddress(): String {
        return getKeyword()
    }

    fun addTextChangedListener(textWatcher: TextWatcher) {
        textField.addTextChangedListener(textWatcher)
    }

    fun addTextChangedListener(
        onTextChanged: (
            text: CharSequence?,
            start: Int,
            before: Int,
            count: Int
        ) -> Unit
    ): TextWatcher {
        return textField.addTextChangedListener(onTextChanged = onTextChanged)
    }

    fun removeTextChangedListener(watcher: TextWatcher?) {
        textField.removeTextChangedListener(watcher)
    }

    fun doOnTextChanged(
        action: (
            text: CharSequence?,
            start: Int,
            before: Int,
            count: Int
        ) -> Unit
    ) {
        textField.doOnTextChanged(action)
    }

    fun setHint(text: String) {
        textField.hint = text
    }

    fun setText(text: String) {
        textField.setText(text)
        hideOverlayViews()
    }

    @SuppressLint("SetTextI18n")
    private fun onSuggestSelected(savedAddress: MSavedAddress) {
        selectedAddress = savedAddress
        textField.setText(savedAddress.address)
        updateOverlayText()
        hideKeyboard()
        showOverlayViews()
    }

    private fun findAddressAttempt() {
        if (!IS_AUTOCOMPLETE_ENABLED)
            return
        if (selectedAddress != null)
            return
        val addresses = (AddressStore.addressData?.savedAddresses ?: emptyList()) +
            (AddressStore.addressData?.otherAccountAddresses ?: emptyList())
        addresses.firstOrNull { it.address == getAddress() }?.let {
            selectedAddress = it
            setText(it.address)
            updateOverlayText()
            hideKeyboard()
            showOverlayViews()
        }
    }

    private fun showOverlayViews() {
        overlayLabel.isGone = false
        closeButton.isGone = false
        textField.isGone = true
    }

    private fun hideOverlayViews() {
        overlayLabel.isGone = true
        closeButton.isGone = true
        textField.isGone = false
    }

    private fun updateOverlayText() {
        val selectedAddress = selectedAddress ?: return
        val name = selectedAddress.name
        val address = selectedAddress.address.formatStartEndAddress()
        val fullText = "$name • $address"

        val spannable = SpannableString(fullText)

        spannable.setSpan(
            WTypefaceSpan(WFont.Medium.typeface, WColor.PrimaryText.color),
            0,
            name.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )

        val bulletStart = name.length
        val bulletEnd = bulletStart + 2
        spannable.setSpan(
            WTypefaceSpan(WFont.Regular.typeface, WColor.SecondaryText.color),
            bulletStart,
            bulletEnd,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )

        overlayLabel.text = spannable
    }

    private fun updateTextFieldPadding() {
        val rightPadding = if (textField.text.isNullOrEmpty()) {
            val pasteTextWidth =
                pasteTextView.paint.measureText(LocaleController.getString("Paste")).toInt()
            (20.dp + 24.dp + 12.dp + pasteTextWidth + 8.dp)
        } else {
            20.dp
        }

        textField.setPaddingLocalized(20.dp, 8.dp, rightPadding, 20.dp)
    }
}
