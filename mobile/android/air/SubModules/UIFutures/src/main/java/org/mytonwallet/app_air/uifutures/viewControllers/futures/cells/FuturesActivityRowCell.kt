package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.RecyclerView
import java.util.Date
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityDateLabel
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFill

/** One activity of the whole history, under its day's date when it is the first of that day. */
@SuppressLint("ViewConstructor")
class FuturesActivityRowCell(context: Context, onTap: (MApiPerpsFill) -> Unit) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    data class Positioning(
        val isFirst: Boolean,
        val isFirstInDay: Boolean,
        val isLast: Boolean,
        val isAdded: Boolean,
        val isAddedAsNewDay: Boolean
    )

    private val dateView = ActivityDateLabel(context, drawsBackground = false)
    private val rowView = FuturesActivityRowView(context, onTap)
    private val container = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(dateView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            rowView,
            LinearLayout.LayoutParams(MATCH_PARENT, ActivityCell.MAIN_CONTENT_HEIGHT.dp)
        )
    }
    private var revealAnimation: SpringAnimation? = null

    override fun setupViews() {
        super.setupViews()

        addView(container, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            toTop(container)
            toCenterX(container)
        }
    }

    fun configure(activity: MApiPerpsFill, positioning: Positioning) {
        revealAnimation?.cancel()
        resetReveal()
        dateView.isGone = !positioning.isFirstInDay
        if (positioning.isFirstInDay) {
            dateView.configure(Date(activity.time), positioning.isFirst)
        }
        rowView.configure(activity, showsTimeOnly = true)
        rowView.setBottomRadius(if (positioning.isLast) ViewConstants.BLOCK_RADIUS.dp else 0f)
        updateTheme()
        if (positioning.isAdded) startReveal(positioning)
    }

    /** The date of a day already shown stays in place; only a new day's date is revealed. */
    private fun startReveal(positioning: Positioning) {
        val dateHeight = if (positioning.isFirstInDay) DATE_HEIGHT.dp.toFloat() else 0f
        val startHeight = if (positioning.isAddedAsNewDay) 0f else dateHeight
        val targetHeight = dateHeight + ActivityCell.MAIN_CONTENT_HEIGHT.dp
        val range = targetHeight - startHeight
        applyReveal(startHeight, 0f, positioning)
        revealAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(startHeight)
            spring = SpringForce(targetHeight).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                applyReveal(value, (value - startHeight) / range, positioning)
            }
            addEndListener { _, _, _, _ -> resetReveal() }
            start()
        }
    }

    private fun applyReveal(height: Float, fraction: Float, positioning: Positioning) {
        updateLayoutParams { this.height = height.toInt() }
        rowView.applyHeightFraction(fraction)
        if (positioning.isAddedAsNewDay) dateView.alpha = fraction.coerceIn(0f, 1f)
    }

    private fun resetReveal() {
        if (layoutParams.height != WRAP_CONTENT) updateLayoutParams { height = WRAP_CONTENT }
        rowView.applyHeightFraction(1f)
        dateView.alpha = 1f
    }

    override fun onDetachedFromWindow() {
        revealAnimation?.cancel()
        super.onDetachedFromWindow()
    }

    override fun updateTheme() {
        dateView.updateTheme()
        rowView.updateTheme()
    }

    private companion object {
        const val DATE_HEIGHT = 40
    }
}
