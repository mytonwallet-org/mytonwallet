package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import java.util.Date
import kotlin.math.abs
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityCell
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.GradientDrawables
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.FuturesChangeArrowDrawable
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.pnlColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.DateUtils
import org.mytonwallet.app_air.walletbasecontext.utils.formatTime
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsActivityType
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFill

@SuppressLint("ViewConstructor")
internal class FuturesActivityRowView(
    context: Context,
    private val onTap: (MApiPerpsFill) -> Unit
) : WView(context),
    WThemedView {

    private companion object {
        const val MASK_MIN_COLS = 4
        const val MASK_COLS_RANGE = 8
        const val ARROW_PLACEHOLDER = "→"
        const val ARROW_GAP = 6
    }

    private var ripple = WRippleDrawable.create(0f)
    private var bottomRadius = 0f
    private val iconSize = ApplicationContextHolder.adaptiveIconSize.dp

    private val iconView = AppCompatImageView(context).apply {
        id = generateViewId()
        setPadding(iconSize / 4)
    }

    private val topLeftLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize(), WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        minHeight = 24.dp
        gravity = Gravity.CENTER_VERTICAL
    }

    private val badgeLabel = WLabel(context).apply {
        setStyle(11f, WFont.Medium)
        setPadding(3.5f.dp.roundToInt(), 0, 3.5f.dp.roundToInt(), 0)
        gravity = Gravity.CENTER_VERTICAL
        setSingleLine()
    }

    private val bottomLeftLabel = WLabel(context).apply {
        setStyle(13f, WFont.Regular)
        setSingleLine()
    }

    private val rightLabel = WSensitiveDataContainer(
        WLabel(context).apply {
            setStyle(adaptiveFontSize())
            setSingleLine()
        },
        WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
    ).apply { id = generateViewId() }

    private var activity: MApiPerpsFill? = null
    private var heightSpringAnimation: SpringAnimation? = null
    var isRemoving = false
        private set

    override fun setupViews() {
        super.setupViews()

        background = ripple
        setOnClickListener { activity?.let(onTap) }
        addView(iconView, LayoutParams(iconSize, iconSize))
        addView(topLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(badgeLabel, LayoutParams(WRAP_CONTENT, 16.dp))
        addView(bottomLeftLabel, LayoutParams(0, WRAP_CONTENT))
        addView(rightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            // Icon View
            toTop(iconView, ApplicationContextHolder.adaptiveIconTopMargin)
            toStart(iconView, 12f)

            // Top Left View
            toStart(topLeftLabel, ApplicationContextHolder.adaptiveContentStart)
            toTop(topLeftLabel, 8f)
            startToEnd(badgeLabel, topLeftLabel, 4f)
            centerYToCenterY(badgeLabel, topLeftLabel)

            // Right View
            toEnd(rightLabel, 16f)
            toCenterY(rightLabel)

            // Bottom View
            startToStart(bottomLeftLabel, topLeftLabel)
            endToStart(bottomLeftLabel, rightLabel, 8f)
            toBottom(bottomLeftLabel, 10f)
        }
    }

    /** Content keeps its full-height layout while the row's own height animates. */
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(
                ActivityCell.MAIN_CONTENT_HEIGHT.dp,
                MeasureSpec.EXACTLY
            )
        )
        setMeasuredDimension(measuredWidth, MeasureSpec.getSize(heightMeasureSpec))
    }

    /** Under a day header only the time is shown, as on the home screen. */
    fun configure(activity: MApiPerpsFill, showsTimeOnly: Boolean) {
        this.activity = activity
        rightLabel.setMaskCols(
            MASK_MIN_COLS + abs(activity.identity.hashCode() % MASK_COLS_RANGE)
        )
        topLeftLabel.text = activity.title
        badgeLabel.text = activity.badgeText
        bottomLeftLabel.text = if (showsTimeOnly) {
            Date(activity.time).formatTime()
        } else {
            DateUtils.formatDateAndTimeDotSeparated(activity.time)
        }
        iconView.setImageDrawable(
            context.getDrawableCompat(
                when (activity.activityType) {
                    MApiPerpsActivityType.OPENED,
                    MApiPerpsActivityType.INCREASED -> IconsR.drawable.ic_act_sent

                    MApiPerpsActivityType.REDUCED,
                    MApiPerpsActivityType.CLOSED -> IconsR.drawable.ic_act_received

                    MApiPerpsActivityType.LIQUIDATED -> IconsR.drawable.ic_act_liquidated
                }
            )
        )
        updateTheme()
    }

    /** Rounds the ripple at the bottom of a card whose background is drawn behind the list. */
    fun setBottomRadius(radius: Float) {
        if (bottomRadius == radius) return
        bottomRadius = radius
        ripple = WRippleDrawable.create(0f, 0f, radius, radius)
        background = ripple
        updateTheme()
    }

    fun startRemoveAnimation(onRemoved: () -> Unit) {
        isRemoving = true
        isEnabled = false
        animateHeight(height.toFloat(), 0f, onRemoved)
    }

    fun startInsertAnimation() {
        applyHeightFraction(0f)
        animateHeight(0f, ActivityCell.MAIN_CONTENT_HEIGHT.dp.toFloat())
    }

    fun cancelHeightAnimation() {
        heightSpringAnimation?.cancel()
    }

    private fun animateHeight(from: Float, to: Float, onEnd: (() -> Unit)? = null) {
        heightSpringAnimation?.cancel()
        heightSpringAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(from)
            spring = SpringForce(to).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                updateLayoutParams { height = value.toInt() }
                applyHeightFraction(value / ActivityCell.MAIN_CONTENT_HEIGHT.dp)
            }
            addEndListener { _, canceled, _, _ ->
                if (!canceled) onEnd?.invoke()
            }
            start()
        }
    }

    /** Content is fully faded once the row is at 70% of its height. */
    fun applyHeightFraction(fraction: Float) {
        alpha = ((fraction - 0.7f) / 0.3f).coerceIn(0f, 1f)
        scaleX = lerp(0.85f, 1f, alpha)
        scaleY = scaleX
    }

    override fun updateTheme() {
        ripple.rippleColor = WColor.BackgroundRipple.color
        val activity = activity ?: return
        iconView.background = if (activity.activityType == MApiPerpsActivityType.LIQUIDATED) {
            GradientDrawables.redDrawable
        } else {
            GradientDrawables.blueDrawable
        }
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        badgeLabel.setTextColor(WColor.SecondaryText.color)
        badgeLabel.setBackgroundColor(
            WColor.SecondaryText.color.colorWithAlpha(26),
            4f.dp
        )
        rightLabel.contentView.setTextColor(WColor.PrimaryText.color)
        rightLabel.contentView.text = amountText(activity)
    }

    private fun amountText(activity: MApiPerpsFill): CharSequence {
        val amount = activity.amount
        return when (activity.activityType) {
            MApiPerpsActivityType.OPENED -> amount.toUsdString()

            MApiPerpsActivityType.INCREASED,
            MApiPerpsActivityType.REDUCED -> {
                val previous = activity.previousAmount?.toUsdString()
                    ?: return amount.toUsdString()
                val arrow = FuturesChangeArrowDrawable().apply {
                    setBounds(0, 0, intrinsicWidth, intrinsicHeight)
                }
                SpannableStringBuilder(previous).apply {
                    setSpan(
                        ForegroundColorSpan(WColor.SecondaryText.color),
                        0,
                        previous.length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    append(
                        ARROW_PLACEHOLDER,
                        VerticalImageSpan(arrow, ARROW_GAP.dp, ARROW_GAP.dp),
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    append(amount.toUsdString())
                }
            }

            MApiPerpsActivityType.CLOSED -> colored(
                amount.toUsdString(showPositiveSign = true),
                pnlColor(amount)
            )

            MApiPerpsActivityType.LIQUIDATED -> colored(
                abs(amount).toUsdString(),
                WColor.Red.color
            )
        }
    }

    private fun colored(text: String, color: Int): CharSequence = SpannableString(text).apply {
        setSpan(
            ForegroundColorSpan(color),
            0,
            text.length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }
}
