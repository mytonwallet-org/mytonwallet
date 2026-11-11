package org.mytonwallet.app_air.uifutures.viewControllers.futuresOpen

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.os.Build
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
import androidx.core.widget.doAfterTextChanged
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPriceString
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

/** Picks the leverage for a new position, previewing its liquidation price */
@SuppressLint("ViewConstructor")
class FuturesLeverageVC(
    context: Context,
    private val maxLeverage: Int,
    leverage: Int,
    private val priceTitle: String,
    private val markPrice: Double,
    estimate: Estimate?,
    private val loadEstimate: (suspend (Int) -> Estimate?)?,
    private val onDone: (Int) -> Unit
) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "FuturesLeverage"

    override val shouldDisplayTopBar = false

    override val wrapsContentInCenteredWindow = true

    private var leverage = leverage.coerceIn(1, maxLeverage)

    /** The typed leverage; `null` or out of range until the field holds a valid one. */
    private var draft: Int? = this.leverage
    private var isUpdatingText = false

    private val isValid: Boolean
        get() = draft?.let { it in 1..maxLeverage } ?: false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var estimateJob: Job? = null
    private val estimates = mutableMapOf<Int, Estimate>().apply {
        // A leverage above the market maximum is shown clamped, and its estimate does not apply
        if (estimate != null && leverage == this@FuturesLeverageVC.leverage) put(leverage, estimate)
    }

    private val minButton = rangeButton("Min") { setLeverage(1) }
    private val maxButton = rangeButton("Max") { setLeverage(maxLeverage) }

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
        hint = "1"
        inputType = InputType.TYPE_CLASS_NUMBER
        keyListener = DigitsKeyListener.getInstance("0123456789")
        contentDescription = LocaleController.getString("Leverage")
        doAfterTextChanged { text ->
            if (isUpdatingText) return@doAfterTextChanged
            draft = text?.toString()?.toIntOrNull()
            if (isValid) {
                setLeverage(draft!!, updateText = false)
            } else {
                estimateJob?.cancel()
                updateValueState()
            }
        }
    }
    private val unitLabel = WLabel(context).apply {
        setStyle(40f, WFont.Balance)
        includeFontPadding = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            isLocalePreferredLineHeightForMinimumUsed = false
        }
        text = "x"
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
        addView(unitLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setOnClickListener {
            valueInput.requestFocus()
            valueInput.setSelection(valueInput.text?.length ?: 0)
            valueInput.showKeyboard()
        }
    }

    private val slider = object : SeekBar(context) {
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
        max = maxLeverage - 1
        thumb = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setSize(24.dp, 24.dp)
        }
        setPadding(12.dp, 0, 12.dp, 0)
        contentDescription = LocaleController.getString("Leverage")
        setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                val value = progress + 1
                if (value == draft) return
                if (valueInput.hasFocus()) valueInput.hideKeyboard()
                Haptics.play(seekBar, HapticType.SELECTION)
                setLeverage(value, updateSlider = false)
            }

            override fun onStartTrackingTouch(seekBar: SeekBar) {
                if (valueInput.hasFocus()) valueInput.hideKeyboard()
                if (!isValid) setLeverage(seekBar.progress + 1, updateSlider = false)
            }

            override fun onStopTrackingTouch(seekBar: SeekBar) {}
        })
    }

    private val priceRow =
        KeyValueRowView(context, LocaleController.getString(priceTitle), markPrice.toPriceString())
    private val liquidationRow = KeyValueRowView(
        context,
        LocaleController.getString("Liquidation Price"),
        EMPTY_VALUE
    ).apply {
        useSkeletonIndicatorWithWidth = LIQUIDATION_SKELETON_WIDTH.dp
    }
    private val detailsView = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(priceRow)
        addView(liquidationRow.apply { setLast(true) })
    }

    private val descriptionLabel = WLabel(context).apply {
        id = View.generateViewId()
        setStyle(13f)
        text = LocaleController.getString("\$perps_leverage_disclaimer")
    }

    private val doneButton = WButton(context).apply {
        id = View.generateViewId()
        text = LocaleController.getString("Done")
        setOnClickListener {
            if (!isValid) return@setOnClickListener
            onDone(this@FuturesLeverageVC.leverage)
            window?.dismissLastNav()
        }
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        setNavTitle(LocaleController.getString("Leverage"))
        navigationBar?.addCloseButton()

        view.addView(minButton, ConstraintLayout.LayoutParams(64.dp, 44.dp))
        view.addView(valueBox, ConstraintLayout.LayoutParams(WRAP_CONTENT, 60.dp))
        view.addView(maxButton, ConstraintLayout.LayoutParams(64.dp, 44.dp))
        view.addView(slider, ConstraintLayout.LayoutParams(0, 44.dp))
        view.addView(detailsView, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
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
            topToBottom(detailsView, slider, 20f)
            toCenterX(detailsView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            topToBottom(descriptionLabel, detailsView, 16f)
            toCenterX(descriptionLabel, 32f)
            topToBottom(doneButton, descriptionLabel, 18f)
            toCenterX(doneButton, 30f)
            toBottom(doneButton, 28f)
        }
        setLeverage(leverage)
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
        unitLabel.setTextColor(WColor.SecondaryText.color)
        valueInput.setHintTextColor(WColor.SecondaryText.color)
        descriptionLabel.setTextColor(WColor.SecondaryText.color)
        detailsView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            clipToBounds = true
        )
        slider.progressTintList = ColorStateList.valueOf(WColor.Tint.color)
        slider.thumbTintList = ColorStateList.valueOf(WColor.Tint.color)
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
        updateValueState()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun setLeverage(value: Int, updateSlider: Boolean = true, updateText: Boolean = true) {
        leverage = value.coerceIn(1, maxLeverage)
        draft = leverage
        if (updateSlider) slider.progress = leverage - 1
        if (updateText) {
            isUpdatingText = true
            valueInput.setText(leverage.toString())
            isUpdatingText = false
        }
        updateValueState()
        updateEstimate()
    }

    private fun updateValueState() {
        valueInput.setTextColor(if (isValid) WColor.PrimaryText.color else WColor.Error.color)
        doneButton.isEnabled = isValid
    }

    private fun updateEstimate() {
        estimateJob?.cancel()
        val load = loadEstimate ?: return
        val value = leverage
        estimates[value]?.let {
            showEstimate(it)
            return
        }
        liquidationRow.setValue("")
        liquidationRow.isLoading = true
        estimateJob = scope.launch {
            delay(ESTIMATE_DEBOUNCE_MS)
            val estimate = try {
                load(value)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                null
            }
            estimate?.let { estimates[value] = it }
            showEstimate(estimate, fadeIn = true)
        }
    }

    private fun showEstimate(estimate: Estimate?, fadeIn: Boolean = false) {
        liquidationRow.isLoading = false
        liquidationRow.setValue(
            estimate?.liquidation?.toPriceString() ?: EMPTY_VALUE,
            fadeIn = fadeIn
        )
    }

    private fun rangeButton(title: String, onTap: () -> Unit) = WLabel(context).apply {
        id = View.generateViewId()
        setStyle(14f, WFont.Medium)
        text = LocaleController.getString(title)
        gravity = Gravity.CENTER
        setOnClickListener {
            if (valueInput.hasFocus()) valueInput.hideKeyboard()
            Haptics.play(this, HapticType.SELECTION)
            onTap()
        }
    }

    data class Estimate(val liquidation: Double?)

    private companion object {
        const val EMPTY_VALUE = "—"
        const val ESTIMATE_DEBOUNCE_MS = 250L
        const val LIQUIDATION_SKELETON_WIDTH = 80
    }
}
