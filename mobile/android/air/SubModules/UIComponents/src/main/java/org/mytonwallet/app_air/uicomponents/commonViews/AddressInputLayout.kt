package org.mytonwallet.app_air.uicomponents.commonViews

import android.R
import android.annotation.SuppressLint
import android.os.Build
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
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.core.widget.addTextChangedListener
import androidx.core.widget.doOnTextChanged
import me.vkryl.android.AnimatorUtils
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getTextFromClipboard
import org.mytonwallet.app_air.uicomponents.extensions.setMarginsDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.extensions.setTextIfDiffer
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.EditTextTint
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ScamLabelSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.autoComplete.WAutoCompleteView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeInAnimatorSet
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.fadeOutAnimatorSet
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
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class AddressInputLayout(
    val viewController: WeakReference<WViewController>,
    val autoCompleteConfig: AutoCompleteConfig = AutoCompleteConfig(),
    onTextEntered: (text: String) -> Unit
) : FrameLayout(viewController.get()!!.context), WThemedView {

    var pasteInterceptor: ((pastedText: String) -> Boolean)? = null

    var focusCallback: ((hasFocus: Boolean) -> Unit)? = null
    var activeChain: MBlockchain = MBlockchain.ton
        set(value) {
            field = value
            autocompleteResult?.let { setAutocompleteResult(it) }
        }

    var showCloseOnTextEditing: Boolean = false
        set(value) {
            field = value
            updateTextFieldPadding()
        }

    var textFieldTopPadding: Int = 8.dp
        set(value) {
            field = value
            updateTextFieldPadding()
        }

    var textFieldBottomPadding: Int = 20.dp
        set(value) {
            field = value
            updateTextFieldPadding()
        }

    companion object {
        const val IS_BUILD_IN_AUTOCOMPLETE_ENABLED = false
    }

    data class AutoCompleteConfig(
        val type: Type = Type.BUILT_IN,
        val accountAddresses: Boolean = true
    ) {
        val isEnabled: Boolean
            get() {
                return when (type) {
                    Type.BUILT_IN -> IS_BUILD_IN_AUTOCOMPLETE_ENABLED
                    Type.EXTERNAL -> true
                    else -> false
                }
            }

        enum class Type {
            /**
             * No auto-completion functionality.
             */
            NONE,

            /**
             * Built-in popup-style auto-completion functionality.
             */
            BUILT_IN,

            /**
             * Any external auto-completion functionality.
             */
            EXTERNAL
        }
    }

    private var isEditable = true

    private val textField = object : AppCompatEditText(context) {
        override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? {
            val ic = super.onCreateInputConnection(outAttrs) ?: return null
            return object : InputConnectionWrapper(ic, true) {
                override fun commitText(txt: CharSequence?, newCursorPosition: Int): Boolean {
                    val appliedText = txt?.toString()
                    if (appliedText != null && appliedText.contains("\n")) {
                        val cleaned = appliedText.replace("\n", "")
                        val committed = if (cleaned.isNotEmpty()) {
                            super.commitText(cleaned, newCursorPosition)
                        } else true

                        post { onTextEntered(getKeyword()) }
                        return committed
                    }

                    val oldText = text?.toString() ?: ""
                    val result = super.commitText(txt, newCursorPosition)

                    if (result && txt != null && txt.length > 1) {
                        val newText = text?.toString() ?: ""
                        if (MBlockchain.isValidAddressOnAnyChain(newText)) {
                            if (newText.length > oldText.length + 1) {
                                post { onTextEntered(getKeyword()) }
                            }
                        }
                    }
                    return result
                }
            }
        }

        override fun onTextContextMenuItem(id: Int): Boolean {
            if (id == R.id.paste || id == R.id.pasteAsPlainText) {
                val pasted = context.getTextFromClipboard()?.trim().orEmpty()
                if (pasted.isNotEmpty() && pasteInterceptor?.invoke(pasted) == true) {
                    return true
                }
                val result = super.onTextContextMenuItem(id)
                if (result && MBlockchain.isValidAddressOnAnyChain(text.toString())) {
                    post { onTextEntered(getKeyword()) }
                }
                return result
            }
            return super.onTextContextMenuItem(id)
        }
    }.apply {
        background = null
        hint = LocaleController.getString("Wallet Address or Domain")
        typeface = WFont.Regular.typeface
        layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        maxLines = 3
        setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN) {
                onTextEntered(getKeyword())
                return@setOnKeyListener true
            }
            false
        }
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        }
        onFocusChangeListener = OnFocusChangeListener { v, hasFocus ->
            focusCallback?.invoke(hasFocus)
            if (autoCompleteConfig.type != AutoCompleteConfig.Type.BUILT_IN || !autoCompleteConfig.isEnabled)
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
            if (!isEditable) return@doOnTextChanged
            if (showCloseOnTextEditing) {
                if (!t.isNullOrEmpty()) {
                    setButtonsVisible(false) {
                        closeButton.fadeInAnimatorSet(AnimationConstants.SUPER_QUICK_ANIMATION)
                    }
                } else {
                    closeButton.fadeOutAnimatorSet(AnimationConstants.SUPER_QUICK_ANIMATION) {
                        setButtonsVisible(true)
                    }
                }
            } else {
                setButtonsVisible(t.isNullOrEmpty())
            }
            if (t.toString().trim() != autocompleteResult?.address(activeChain.name)) {
                autocompleteResult = null
            }
            updateTextFieldPadding()
        }
    }

    private val qrScanImageViewRipple = WRippleDrawable.create(8f.dp)
    val qrScanImageView = AppCompatImageView(context).apply {
        background = qrScanImageViewRipple
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_qr_code_scan_16_24)
        layoutParams = LayoutParams(
            24.dp,
            24.dp,
            Gravity.TOP or if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT
        ).apply {
            if (LocaleController.isRTL) {
                leftMargin = 20.dp
            } else {
                rightMargin = 20.dp
            }
        }
    }

    private val pasteTextViewRipple = WRippleDrawable.create(8f.dp)
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
            if (LocaleController.isRTL) {
                leftMargin = (20 + 24 + 12).dp
            } else {
                rightMargin = (20 + 24 + 12).dp
            }
        }
    }

    var autocompleteResult: AutocompleteResult? = null
        private set

    val autoCompleteView = WAutoCompleteView(context, onSuggest = {
        onSuggestSelected(it)
    }).apply {
        elevation = 4f.dp
    }

    private val overlayLabel = WLabel(context).apply {
        setStyle(16f, WFont.Regular)
        gravity = Gravity.CENTER_VERTICAL
        isGone = true
        setOnClickListener {
            hideOverlayViews()
            textField.requestFocus()
            textField.setSelection(textField.text?.length ?: 0)
            textField.showKeyboard()
        }
    }

    private val scamLabelSpan by lazy {
        ScamLabelSpan(LocaleController.getString("Scam").uppercase())
    }

    private val closeButton: WImageButton by lazy {
        WImageButton(context).apply {
            val closeDrawable =
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.uicomponents.R.drawable.ic_close_filled
                )
            setImageDrawable(closeDrawable)
            isGone = true
            setOnClickListener {
                hideOverlayViews()
                textField.setText("")
                textField.requestFocus()
                textField.showKeyboard()
            }
            layoutParams = LayoutParams(
                WRAP_CONTENT,
                WRAP_CONTENT,
                Gravity.TOP or if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT
            ).apply {
                topMargin = 8.dp
                if (LocaleController.isRTL) {
                    leftMargin = 12.dp
                } else {
                    rightMargin = 12.dp
                }
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
            addView(closeButton, LayoutParams(24.dp, 24.dp).apply {
                gravity = Gravity.END
                setMarginsDp(0, 8, 12, 0)
            })
        }

        pasteTextView.setOnClickListener {
            context.getTextFromClipboard()?.let {
                val pasted = it.trim()
                if (pasted.isNotEmpty() && pasteInterceptor?.invoke(pasted) == true) {
                    return@setOnClickListener
                }
                textField.setTextIfDiffer(it, selectionToEnd = true)
                onTextEntered(getKeyword())
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
        overlayLabel.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        updateOverlayText()
        closeButton.apply {
            setBackgroundColor(WColor.SecondaryBackground.color, 10f.dp)
            updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
        }
    }

    fun insetsUpdated() {
        if (autoCompleteConfig.type != AutoCompleteConfig.Type.BUILT_IN || !autoCompleteConfig.isEnabled)
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
        autoCompleteView.maxYInWindow = totalHeight - keyboardHeight - 16.dp
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

    fun addTextChangedListener(
        onTextChanged: (text: String) -> Unit
    ): TextWatcher {
        return addTextChangedListener(onTextChanged = { text, _, _, _ ->
            onTextChanged(text?.toString().orEmpty())
        })
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

    fun setAddress(savedAddress: MSavedAddress) {
        setAutocompleteResult(AutocompleteResult(savedAddress = savedAddress))
    }

    fun setAccount(account: MAccount) {
        setAutocompleteResult(AutocompleteResult(account = account))
    }

    fun setScamAddress(savedAddress: MSavedAddress) {
        setAutocompleteResult(AutocompleteResult(savedAddress = savedAddress, isScam = true))
    }

    private fun setAutocompleteResult(autocompleteResult: AutocompleteResult) {
        this.autocompleteResult = autocompleteResult
        textField.setText(autocompleteResult.address(activeChain.name))
        updateOverlayText()
        showOverlayViews()
    }

    fun inputFieldHasFocus(): Boolean {
        return textField.hasFocus()
    }

    fun resetInputFieldFocus() {
        textField.clearFocus()
    }

    fun setEditable(isEditable: Boolean) {
        this.isEditable = isEditable
        textField.apply {
            isEnabled = isEditable
            isFocusable = isEditable
            isFocusableInTouchMode = isEditable
            isCursorVisible = isEditable
            setTextIsSelectable(isEditable)
        }
        pasteTextView.apply {
            isVisible = isEditable && textField.text.isNullOrEmpty()
            isEnabled = isEditable
        }
        qrScanImageView.apply {
            isVisible = isEditable && textField.text.isNullOrEmpty()
            isEnabled = isEditable
        }
        closeButton.isEnabled = isEditable
        if (!isEditable) {
            hideOverlayViews()
        }
    }

    @SuppressLint("SetTextI18n")
    private fun onSuggestSelected(savedAddress: MSavedAddress) {
        setAddress(savedAddress)
    }

    private fun findAddressAttempt() {
        if (!IS_BUILD_IN_AUTOCOMPLETE_ENABLED)
            return
        if (autocompleteResult != null)
            return
        val addresses = (AddressStore.addressData?.savedAddresses ?: emptyList()) +
            (AddressStore.addressData?.otherAccountAddresses ?: emptyList())
        addresses.firstOrNull { it.address == getAddress() }?.let {
            onSuggestSelected(it)
        }
    }

    private fun showOverlayViews() {
        overlayLabel.isGone = false
        textField.isGone = true
        if (!isEditable) {
            closeButton.isGone = true
            return
        }
        if (!showCloseOnTextEditing) {
            closeButton.isGone = false
        }
    }

    private fun hideOverlayViews() {
        overlayLabel.isGone = true
        textField.isGone = false
        if (!isEditable) {
            closeButton.isGone = true
            return
        }
        if (!showCloseOnTextEditing) {
            closeButton.isGone = true
        }
    }

    private fun updateOverlayText() {
        val autocompleteResult = autocompleteResult ?: return
        val name = autocompleteResult.name
        val isScam = autocompleteResult.isScam == true
        if (name == null && !isScam) {
            this.autocompleteResult = null
            return
        }
        val address = autocompleteResult.address(activeChain.name)?.formatStartEndAddress()
        if (address == null) {
            this.autocompleteResult = null
            return
        }
        overlayLabel.text = buildSpannedString {
            if (isScam) {
                append(" ", scamLabelSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                append(" ")
            } else {
                inSpans(WTypefaceSpan(WFont.Medium.typeface, WColor.PrimaryText.color)) {
                    append("$name · ")
                }
            }
            inSpans(WTypefaceSpan(WFont.Regular.typeface, WColor.SecondaryText.color)) {
                append(address)
            }.styleDots()
        }
    }

    private fun updateTextFieldPadding() {
        val rightPadding = if (!isEditable) {
            20.dp
        } else if (textField.text.isNullOrEmpty()) {
            val pasteTextWidth =
                pasteTextView.paint.measureText(LocaleController.getString("Paste")).toInt()
            (20.dp + 24.dp + 12.dp + pasteTextWidth + 8.dp)
        } else {
            if (showCloseOnTextEditing) 44.dp else 20.dp
        }

        textField.setPaddingLocalized(
            20.dp,
            textFieldTopPadding,
            rightPadding,
            textFieldBottomPadding
        )
        qrScanImageView.updateLayoutParams<LayoutParams> {
            topMargin = textFieldTopPadding
        }
        pasteTextView.updateLayoutParams<LayoutParams> {
            topMargin = textFieldTopPadding
        }
        closeButton.updateLayoutParams<LayoutParams> {
            topMargin = textFieldTopPadding
        }
        overlayLabel.setPadding(20.dp, textFieldTopPadding, 48.dp, textFieldBottomPadding)
    }

    private fun setButtonsVisible(visible: Boolean, onEnd: (() -> Unit)? = null) {
        if (visible) {
            listOf(pasteTextView, qrScanImageView).fadeIn(
                duration = AnimationConstants.SUPER_QUICK_ANIMATION,
                interpolator = AnimatorUtils.DECELERATE_INTERPOLATOR
            ) { onEnd?.invoke() }
        } else {
            listOf(pasteTextView, qrScanImageView).fadeOut(
                duration = AnimationConstants.SUPER_QUICK_ANIMATION,
                interpolator = AnimatorUtils.DECELERATE_INTERPOLATOR
            ) { onEnd?.invoke() }
        }
    }

    data class AutocompleteResult(
        val account: MAccount? = null,
        val savedAddress: MSavedAddress? = null,
        val isScam: Boolean? = null
    ) {
        val name: String? get() = account?.name ?: savedAddress?.name

        fun address(chain: String = MBlockchain.ton.name): String? {
            return account?.addressByChain[chain] ?: account?.firstAddress ?: savedAddress?.address
        }
    }
}
