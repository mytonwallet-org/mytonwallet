package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.util.TypedValue
import android.view.Gravity
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.textOffset
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.isSameDayAs
import org.mytonwallet.app_air.walletcontext.utils.isSameYearAs
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import java.math.BigInteger
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

open class WLabel(context: Context) : AppCompatTextView(context), WThemedView {
    init {
        if (id == NO_ID) {
            id = generateViewId()
        }
        gravity = if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
    }

    private val datePattern by lazy {
        when (WGlobalStorage.getLangCode()) {
            "ru" -> "d MMMM"
            else -> "MMMM d"
        }
    }

    private val fullDatePattern by lazy {
        when (WGlobalStorage.getLangCode()) {
            "ru" -> "d MMMM yyyy"
            else -> "MMMM d, yyyy"
        }
    }

    private val monthAndDayFormat by lazy {
        SimpleDateFormat(datePattern, Locale(WGlobalStorage.getLangCode()))
    }

    private val fullDateFormat by lazy {
        SimpleDateFormat(fullDatePattern, Locale(WGlobalStorage.getLangCode()))
    }

    private var textOffset = 0
    fun setStyle(size: Float, font: WFont? = null) {
        typeface = (font ?: WFont.Regular).typeface
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        textOffset = when (font) {
            WFont.NunitoSemiBold, WFont.NunitoExtraBold -> {
                0
            }

            else -> {
                FontManager.activeFont.textOffset
            }
        }
    }

    fun setLineHeight(size: Float) {
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, size)
    }

    fun setAmount(
        amount: BigInteger,
        decimals: Int,
        currency: String,
        currencyDecimals: Int,
        smartDecimals: Boolean,
        showPositiveSign: Boolean = false,
        forceCurrencyToRight: Boolean = false,
    ) {
        val newText = amount.toString(
            decimals = decimals,
            currency = currency,
            currencyDecimals = if (smartDecimals) amount.smartDecimalsCount(currencyDecimals) else currencyDecimals,
            showPositiveSign = showPositiveSign,
            forceCurrencyToRight = forceCurrencyToRight,
            roundUp = false
        )
        if (text != newText)
            text = newText
    }

    fun setAmount(
        amount: Double?,
        decimals: Int,
        currency: String,
        currencyDecimals: Int,
        smartDecimals: Boolean,
        showPositiveSign: Boolean = false
    ) {
        text = amount?.toString(
            decimals = decimals,
            currency = currency,
            currencyDecimals = currencyDecimals,
            smartDecimals = smartDecimals,
            showPositiveSign = showPositiveSign
        )
    }

    fun setTextIfChanged(newText: String?) {
        if (text == newText)
            return
        text = newText
    }

    fun setUserFriendlyDate(dt: Date) {
        val now = Date()
        if (now.isSameDayAs(dt)) {
            text = LocaleController.getString("Today")
        } else {
            val sameYear = now.isSameYearAs(dt)
            text =
                if (sameYear) monthAndDayFormat.format(dt) else fullDateFormat.format(dt)
        }
    }

    private var themedColor: WColor? = null

    fun setTextColor(color: WColor?) {
        themedColor = color
        updateTheme()
    }

    override fun updateTheme() {
        themedColor?.let {
            setTextColor(it.color)
        }
    }

    fun animateTextColor(endColor: Int, duration: Long) {
        val colorAnimator = ValueAnimator.ofArgb(currentTextColor, endColor)
        colorAnimator.duration = duration
        colorAnimator.addUpdateListener { animator ->
            val animatedColor = animator.animatedValue as Int
            setTextColor(animatedColor)
        }
        colorAnimator.start()
    }

    var applyFontOffsetFix = false
    override fun onDraw(canvas: Canvas) {
        if (applyFontOffsetFix && textOffset != 0) {
            canvas.save()
            canvas.translate(0f, textOffset.toFloat())
            super.onDraw(canvas)
            canvas.restore()
        } else {
            super.onDraw(canvas)
        }
    }
}
