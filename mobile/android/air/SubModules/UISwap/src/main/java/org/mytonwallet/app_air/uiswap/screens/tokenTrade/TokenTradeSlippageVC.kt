package org.mytonwallet.app_air.uiswap.screens.tokenTrade

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
import android.text.InputFilter
import android.text.InputType
import android.text.method.DigitsKeyListener
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.SeekBar
import androidx.appcompat.widget.AppCompatEditText
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.ViewCompat
import androidx.core.widget.doAfterTextChanged
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setConstraints
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
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
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 40f)
        gravity = Gravity.END or Gravity.CENTER_VERTICAL
        isSingleLine = true
        inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
        keyListener = DigitsKeyListener.getInstance("0123456789.,")
        filters = arrayOf(
            InputFilter { source, start, end, dest, dstart, dend ->
                val result = dest.replaceRange(dstart, dend, source.subSequence(start, end))
                val parts = result.split('.', ',')
                if (parts.size > 2 || (parts.getOrNull(1)?.length ?: 0) > 1) "" else null
            }
        )
        contentDescription = LocaleController.getString("Slippage")
        doAfterTextChanged { text ->
            if (isUpdatingText) return@doAfterTextChanged
            draft = text?.toString()?.replace(',', '.')?.toFloatOrNull()
                ?.let { (it * 10).roundToInt() / 10f }
            updateState(updateText = false)
        }
    }
    private val percentLabel = WLabel(context).apply {
        setStyle(32f, WFont.Balance)
        text = "%"
    }
    private val valueBox = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.BOTTOM
        setPadding(10.dp, 10.dp, 10.dp, 10.dp)
        addView(valueInput, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(percentLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    private val slider = SeekBar(context).apply {
        id = View.generateViewId()
        max = SLIDER_STEPS
        contentDescription = LocaleController.getString("Slippage")
        setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                draft = valueAt(progress.toFloat() / SLIDER_STEPS)
                valueInput.clearFocus()
                updateState(updateSlider = false)
            }

            override fun onStartTrackingTouch(seekBar: SeekBar) {}
            override fun onStopTrackingTouch(seekBar: SeekBar) {}
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
            for (value in TICKS) {
                canvas.drawCircle(start + track * positionFor(value), height / 2f, 1.5f.dp, paint)
            }
        }
    }

    private val doneButton = WButton(context).apply {
        text = LocaleController.getString("Done")
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

        view.addView(minButton, ConstraintLayout.LayoutParams(WRAP_CONTENT, 26.dp))
        view.addView(valueBox, ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        view.addView(maxButton, ConstraintLayout.LayoutParams(WRAP_CONTENT, 26.dp))
        view.addView(slider, ConstraintLayout.LayoutParams(0, 44.dp))
        view.addView(ticks, ConstraintLayout.LayoutParams(0, 8.dp))
        view.addView(doneButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            navigationBar?.let { topToBottom(valueBox, it, 12f) }
            toCenterX(valueBox)
            toStart(minButton, 30f)
            centerYToCenterY(minButton, valueBox)
            toEnd(maxButton, 30f)
            centerYToCenterY(maxButton, valueBox)
            topToBottom(slider, valueBox, 16f)
            toCenterX(slider, 30f)
            topToBottom(ticks, slider)
            toCenterX(ticks, 30f)
            topToBottom(doneButton, ticks, 32f)
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
        slider.progressTintList = ColorStateList.valueOf(WColor.Tint.color)
        slider.thumbTintList = ColorStateList.valueOf(WColor.Tint.color)
        listOf(minButton, maxButton).forEach {
            it.setTextColor(WColor.PrimaryText.color)
            it.background = GradientDrawable().apply {
                cornerRadius = 13f.dp
                setColor(WColor.SecondaryText.color.colorWithAlpha(31))
            }
        }
        ticks.invalidate()
        updateState(updateText = false, updateSlider = false)
    }

    private fun rangeButton(title: String, value: Float) = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        text = LocaleController.getString(title)
        gravity = Gravity.CENTER
        minWidth = 64.dp
        setPadding(10.dp, 0, 10.dp, 0)
        setOnClickListener {
            valueInput.clearFocus()
            draft = value
            updateState()
        }
    }

    private fun updateState(updateText: Boolean = true, updateSlider: Boolean = true) {
        val value = draft
        if (updateText) {
            isUpdatingText = true
            valueInput.setText(value?.let { format(it) } ?: "")
            isUpdatingText = false
        }
        if (updateSlider) {
            slider.progress = (positionFor(value ?: DEFAULT_VALUE) * SLIDER_STEPS).roundToInt()
        }
        ViewCompat.setStateDescription(slider, format(value ?: DEFAULT_VALUE) + "%")
        valueInput.setTextColor(if (isValid) WColor.PrimaryText.color else WColor.Error.color)
        doneButton.isEnabled = isValid
    }

    companion object {
        private const val MIN_VALUE = 0.1f
        private const val MAX_VALUE = 50f
        private const val DEFAULT_VALUE = 5f
        private const val SLIDER_STEPS = 1000
        private val TICKS = listOf(0.1f, 0.5f, 1f, 5f, 10f, 50f)

        private fun format(value: Float): String =
            if (value % 1f == 0f) value.toInt().toString() else value.toString()

        fun positionFor(value: Float): Float =
            (ln(value.coerceIn(MIN_VALUE, MAX_VALUE) / MIN_VALUE) / ln(MAX_VALUE / MIN_VALUE))

        fun valueAt(position: Float): Float =
            ((MIN_VALUE * (MAX_VALUE / MIN_VALUE).pow(position.coerceIn(0f, 1f))) * 10)
                .roundToInt() / 10f
    }
}
