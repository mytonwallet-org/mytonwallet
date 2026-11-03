package org.mytonwallet.app_air.uiswap.screens.tokenTrade

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.os.Build
import android.text.InputFilter
import android.text.InputType
import android.text.method.DigitsKeyListener
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.SeekBar
import androidx.appcompat.widget.AppCompatEditText
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.ViewCompat
import androidx.core.widget.doAfterTextChanged
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setConstraints
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeSlippageScale.MAX_VALUE
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeSlippageScale.MIN_VALUE
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeSlippageScale.POSITIONS
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeSlippageScale.PRESETS
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeSlippageScale.TINT_COLOR
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeSlippageScale.formatSlippage
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeSlippageScale.positionFor
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeSlippageScale.selection
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.stores.AccountStore

@SuppressLint("ViewConstructor")
class TokenTradeSlippageVC(
    context: Context,
    slippage: Float,
    private val onCommit: (Float) -> Unit
) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "TokenTradeSlippage"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false

    override val wrapsContentInCenteredWindow = true

    private var draft: Float? = slippage
    private var isUpdatingText = false

    private val isValid: Boolean
        get() = draft?.let { it > 0f && it <= MAX_VALUE } ?: false

    private val minButton = rangeButton("Min", MIN_VALUE)
    private val maxButton = rangeButton("Max", MAX_VALUE)

    private val valueInput = AppCompatEditText(context).apply {
        background = null
        setPadding(0, 0, 0, 0)
        includeFontPadding = false
        typeface = WFont.Balance.typeface
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            isLocalePreferredLineHeightForMinimumUsed = false
        }
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 40f)
        gravity = Gravity.END or Gravity.CENTER_VERTICAL
        isSingleLine = true
        minWidth = 24.dp
        maxWidth = 100.dp
        hint = "0"
        inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
        keyListener = DigitsKeyListener.getInstance("0123456789.,")
        filters = arrayOf(
            InputFilter { source, start, end, dest, dstart, dend ->
                val result = dest.replaceRange(dstart, dend, source.subSequence(start, end))
                val parts = result.split('.', ',')
                if (parts.size > 2 || (parts.getOrNull(1)?.length ?: 0) > 1) "" else null
            }
        )
        contentDescription = LocaleController.getString("Slippage") + ", %"
        doAfterTextChanged { text ->
            if (isUpdatingText) return@doAfterTextChanged
            draft = text?.toString()?.replace(',', '.')?.toFloatOrNull()
                ?.let { (it * 10).roundToInt() / 10f }
            updateState(updateText = false)
        }
    }
    private val percentLabel = WLabel(context).apply {
        setStyle(32f, WFont.Balance)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            isLocalePreferredLineHeightForMinimumUsed = false
        }
        text = "%"
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val valueBox = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        layoutDirection = View.LAYOUT_DIRECTION_LTR
        minimumWidth = 92.dp
        setPadding(10.dp, 0, 10.dp, 0)
        addView(valueInput, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(percentLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setOnClickListener {
            valueInput.requestFocus()
            valueInput.setSelection(valueInput.text?.length ?: 0)
        }
    }

    private var capturedPreset: Int? = null

    private val slider = object : SeekBar(context) {
        // Inside the sheet, AbsSeekBar defers the pressed state until the touch moves past the slop.
        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (event.actionMasked == MotionEvent.ACTION_DOWN && isEnabled) {
                drawableHotspotChanged(event.x, event.y)
                isPressed = true
            }
            val handled = super.onTouchEvent(event)
            if (event.actionMasked == MotionEvent.ACTION_UP ||
                event.actionMasked == MotionEvent.ACTION_CANCEL
            ) {
                isPressed = false
            }
            return handled
        }
    }.apply {
        id = View.generateViewId()
        max = SLIDER_STEPS
        thumb = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setSize(24.dp, 24.dp)
        }
        setPadding(12.dp, 0, 12.dp, 0)
        contentDescription = LocaleController.getString("Slippage")
        setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                val selection = selectionAt(seekBar, capturedPreset)
                if (selection.presetIndex != null && selection.presetIndex != capturedPreset) {
                    Haptics.play(seekBar, HapticType.SELECTION)
                }
                capturedPreset = selection.presetIndex
                if (selection.presetIndex != null) seekBar.progress = progressFor(selection.value)
                if (draft == selection.value) return
                if (valueInput.hasFocus()) valueInput.hideKeyboard()
                draft = selection.value
                updateState(updateSlider = false)
            }

            override fun onStartTrackingTouch(seekBar: SeekBar) {
                if (valueInput.hasFocus()) valueInput.hideKeyboard()
                if (!isValid) {
                    draft = selectionAt(seekBar, null).value
                    updateState(updateSlider = false)
                }
                capturedPreset = draft?.let { PRESETS.indexOf(it) }?.takeIf { it >= 0 }
            }

            override fun onStopTrackingTouch(seekBar: SeekBar) {
                capturedPreset = null
                draft?.takeIf { isValid }?.let { seekBar.progress = progressFor(it) }
            }
        })
    }

    private val ticks = object : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        init {
            id = generateViewId()
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        override fun onDraw(canvas: Canvas) {
            paint.color = WColor.SecondaryText.color.colorWithAlpha(89)
            val start = slider.paddingStart.toFloat()
            val track = width - slider.paddingStart - slider.paddingEnd
            for (index in PRESETS.indices) {
                val position = POSITIONS[index + 1]
                val x = if (layoutDirection == LAYOUT_DIRECTION_RTL) 1 - position else position
                canvas.drawCircle(start + track * x, height / 2f, 1.5f.dp, paint)
            }
        }
    }

    private val descriptionLabel = WLabel(context).apply {
        setStyle(13f)
        text = LocaleController.getString(
            "Slippage is the difference between the expected and actual trade price caused by price changes during execution."
        )
    }

    private val doneButton = WButton(context).apply {
        text = LocaleController.getString("Done")
        buttonHeight = 52.dp
        customTint = TINT_COLOR
        setOnClickListener {
            val value = draft ?: return@setOnClickListener
            if (!isValid) return@setOnClickListener
            onCommit(value)
            window?.dismissLastNav()
        }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Slippage"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(minButton, ConstraintLayout.LayoutParams(64.dp, 44.dp))
        view.addView(valueBox, ConstraintLayout.LayoutParams(WRAP_CONTENT, 60.dp))
        view.addView(maxButton, ConstraintLayout.LayoutParams(64.dp, 44.dp))
        view.addView(slider, ConstraintLayout.LayoutParams(0, 44.dp))
        view.addView(ticks, ConstraintLayout.LayoutParams(0, 8.dp))
        view.addView(descriptionLabel, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(doneButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            navigationBar?.let { topToBottom(valueBox, it, 12f) }
            toCenterX(valueBox)
            toStart(minButton, 32f)
            centerYToCenterY(minButton, valueBox)
            toEnd(maxButton, 32f)
            centerYToCenterY(maxButton, valueBox)
            topToBottom(slider, valueBox, 16f)
            toCenterX(slider, 20f)
            topToTop(ticks, slider, 28f)
            toCenterX(ticks, 20f)
            topToBottom(descriptionLabel, slider, 16f)
            toCenterX(descriptionLabel, 32f)
            topToBottom(doneButton, descriptionLabel, 18f)
            toCenterX(doneButton, 30f)
            toBottom(doneButton, 28f)
        }

        updateState()
        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setPadding(0, 0, 0, navigationController?.getSystemBars()?.bottom ?: 0)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )
        valueBox.setBackgroundColor(WColor.Background.color, 22f.dp)
        percentLabel.setTextColor(WColor.SecondaryText.color)
        valueInput.setHintTextColor(WColor.SecondaryText.color)
        descriptionLabel.setTextColor(WColor.SecondaryText.color)
        slider.progressTintList = ColorStateList.valueOf(TINT_COLOR)
        slider.thumbTintList = ColorStateList.valueOf(TINT_COLOR)
        ticks.invalidate()
        listOf(minButton, maxButton).forEach {
            it.setTextColor(WColor.PrimaryText.color)
            it.background = InsetDrawable(
                GradientDrawable().apply {
                    cornerRadius = 13f.dp
                    setColor(WColor.SecondaryText.color.colorWithAlpha(31))
                },
                0,
                9.dp,
                0,
                9.dp
            )
        }
        updateState(updateText = false, updateSlider = false)
    }

    private fun rangeButton(title: String, value: Float) = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        text = LocaleController.getString(title)
        gravity = Gravity.CENTER
        contentDescription = "$text, ${formatSlippage(value)}%"
        setOnClickListener {
            if (valueInput.hasFocus()) valueInput.hideKeyboard()
            draft = value
            Haptics.play(this, HapticType.SELECTION)
            updateState()
        }
    }

    private fun updateState(updateText: Boolean = true, updateSlider: Boolean = true) {
        val value = draft
        if (updateText) {
            isUpdatingText = true
            valueInput.setText(value?.let { formatSlippage(it) } ?: "")
            isUpdatingText = false
        }
        if (isValid && value != null) {
            if (updateSlider) slider.progress = progressFor(value)
            ViewCompat.setStateDescription(slider, formatSlippage(value) + "%")
        }
        valueInput.setTextColor(if (isValid) WColor.PrimaryText.color else WColor.Error.color)
        doneButton.isEnabled = isValid
    }

    private fun selectionAt(seekBar: SeekBar, capturedPreset: Int?) = selection(
        seekBar.progress.toFloat() / SLIDER_STEPS,
        (seekBar.width - seekBar.paddingStart - seekBar.paddingEnd).toFloat(),
        capturedPreset
    )

    private fun progressFor(value: Float): Int = (positionFor(value) * SLIDER_STEPS).roundToInt()

    private companion object {
        const val SLIDER_STEPS = 1000
    }
}
