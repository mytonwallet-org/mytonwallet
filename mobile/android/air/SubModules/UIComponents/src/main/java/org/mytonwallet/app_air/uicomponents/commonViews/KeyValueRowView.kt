package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Space
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.doOnLayout
import com.google.android.material.progressindicator.CircularProgressIndicator
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell.Companion.SUBTITLE_SKELETON_RADIUS
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class KeyValueRowView(
    context: Context,
    val key: String,
    private var value: CharSequence,
    val mode: Mode,
    private var isLast: Boolean,
) : WView(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    private val ripple = WRippleDrawable.create(0f)

    enum class Mode {
        PRIMARY,
        SECONDARY,
        LINK
    }

    var isSensitiveData = false
        set(value) {
            field = value
            valueLabel.isSensitiveData = value
        }

    private val minHeightSpace: Space by lazy {
        Space(context).apply {
            id = generateViewId()
        }
    }

    private val keyLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            text = key
        }
    }

    val valueLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context).apply {
            setStyle(16f)
            text = value
            movementMethod = ExtraHitLinkMovementMethod(8.dp, 4.dp)
            highlightColor = Color.TRANSPARENT
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
            if (LocaleController.isRTL)
                gravity = Gravity.LEFT
            setPaddingDp(8, 4, 8, 4)
        }
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(
                6,
                2,
                Gravity.END or Gravity.CENTER_VERTICAL,
                endMargin = 8.dp,
                protectContentLayoutSize = false
            )
        ).apply {
            isSensitiveData = false
        }
    }
    var valView: View? = null

    private var skeletonIndicator: WBaseView? = null
    private var skeletonView: SkeletonView? = null
    var useSkeletonIndicatorWithWidth: Int? = null
        set(value) {
            field = value
            updateLoadingState()
            updateSkeletonLoadingState()
        }

    private var progressIndicator: CircularProgressIndicator? = null
    var isLoading: Boolean = false
        set(value) {
            field = value
            updateLoadingState()
            updateSkeletonLoadingState()
        }

    init {
        background = ripple
        // workaround instead of minimumHeight property to manage cases inside another ConstraintLayout
        addView(minHeightSpace, LayoutParams(WRAP_CONTENT, 50.dp))
        addView(keyLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(valueLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            allEdges(minHeightSpace)
            setHorizontalBias(keyLabel.id, 0f)
            setHorizontalBias(valueLabel.id, 1f)
            constrainedWidth(valueLabel.id, true)
            toTop(keyLabel, 14f)
            toCenterY(valueLabel, 0f)
            toStart(keyLabel, 20f)
            startToEnd(valueLabel, keyLabel, 16f)
            toEnd(valueLabel, 12f)
            if (valView is WLabel) {
                startToEnd(valView!!, keyLabel, 16f)
            }
        }

        updateTheme()
    }

    override val isTinted = mode == Mode.LINK
    override fun updateTheme() {
        keyLabel.setTextColor(
            when (mode) {
                Mode.PRIMARY -> {
                    WColor.PrimaryText.color
                }

                Mode.SECONDARY -> {
                    WColor.SecondaryText.color
                }

                Mode.LINK -> {
                    WColor.Tint.color
                }
            }
        )
        ripple.rippleColor = WColor.SecondaryBackground.color
        valueLabel.contentView.setTextColor(WColor.PrimaryText.color)
        progressIndicator?.setIndicatorColor(WColor.SecondaryText.color)
        skeletonIndicator?.setBackgroundColor(
            WColor.SecondaryBackground.color,
            SUBTITLE_SKELETON_RADIUS
        )
    }

    fun setKey(newValue: String?) {
        keyLabel.text = newValue
    }

    fun setValue(newValue: CharSequence?, fadeIn: Boolean = false) {
        value = newValue ?: ""
        valueLabel.contentView.text = newValue
        if (fadeIn) {
            valueLabel.alpha = 0f
            valueLabel.fadeIn()
        }
    }

    private fun updateLoadingState() {
        if (isLoading && useSkeletonIndicatorWithWidth == null && progressIndicator == null) {
            progressIndicator = CircularProgressIndicator(context).apply {
                id = generateViewId()
                isIndeterminate = true
                setIndicatorColor(WColor.SecondaryText.color)
                indicatorSize = 28.dp
            }
            addView(
                progressIndicator,
                ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
            )
            setConstraints {
                toEnd(progressIndicator!!, 20f)
                toCenterY(progressIndicator!!)
            }
        }
        if (isLoading && useSkeletonIndicatorWithWidth == null) {
            progressIndicator?.visibility = VISIBLE
        } else {
            progressIndicator?.visibility = GONE
        }
    }

    private fun updateSkeletonLoadingState() {
        val shouldShowSkeleton = isLoading && useSkeletonIndicatorWithWidth != null
        if (shouldShowSkeleton && skeletonView == null) {
            val skeletonIndicatorWidth = useSkeletonIndicatorWithWidth!!
            skeletonIndicator = WBaseView(context).apply {
                id = generateViewId()
            }
            skeletonView = SkeletonView(context, false)
            val skeletonIndicator = skeletonIndicator ?: return
            val skeletonView = skeletonView ?: return
            addView(
                skeletonIndicator,
                ViewGroup.LayoutParams(skeletonIndicatorWidth, 16.dp)
            )
            addView(skeletonView, LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
            setConstraints {
                toEnd(skeletonIndicator, 20f)
                toCenterY(skeletonIndicator)
                allEdges(skeletonView)
            }
            skeletonIndicator.setBackgroundColor(
                WColor.SecondaryBackground.color,
                SUBTITLE_SKELETON_RADIUS
            )
            skeletonView.bringToFront()
        }
        if (shouldShowSkeleton) {
            val skeletonView = skeletonView ?: return
            val skeletonIndicator = skeletonIndicator ?: return

            skeletonView.animate().cancel()
            skeletonIndicator.animate().cancel()
            skeletonView.alpha = 1f
            skeletonIndicator.alpha = 1f
            skeletonView.visibility = VISIBLE
            skeletonIndicator.visibility = VISIBLE
            skeletonView.doOnLayout {
                skeletonView.applyMask(
                    listOf(skeletonIndicator),
                    hashMapOf(0 to SUBTITLE_SKELETON_RADIUS)
                )
                skeletonView.startAnimating()
            }
        } else {
            val skeletonView = skeletonView ?: return
            val skeletonIndicator = skeletonIndicator ?: return

            if (!WGlobalStorage.getAreAnimationsActive()) {
                skeletonView.visibility = GONE
                skeletonIndicator.visibility = GONE
                skeletonView.stopAnimating()
                return
            }

            skeletonView.animate().cancel()
            skeletonIndicator.animate().cancel()

            if (skeletonView.visibility != GONE || skeletonIndicator.visibility != GONE) {
                skeletonView.fadeOut {
                    skeletonView.stopAnimating()
                    skeletonView.alpha = 1f
                }
                skeletonIndicator.fadeOut {
                    skeletonIndicator.visibility = GONE
                    skeletonIndicator.alpha = 1f
                }
            } else {
                skeletonView.stopAnimating()
            }
        }
    }

    fun setValueView(valueView: View) {
        this.valView = valueView
        addView(
            valueView,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        var endMarginOffset = 0
        (valueView as? WLabel)?.apply {
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
            endMarginOffset = paddingEnd
        }
        setConstraints {
            constrainedWidth(valueView.id, true)
            setHorizontalBias(valueView.id, 1f)
            toEndPx(valueView, 20.dp - endMarginOffset)
            toCenterY(valueView)
            if (valueView is WLabel) {
                startToEnd(valueView, keyLabel, 16f)
            } else {
                keyLabel.apply {
                    setSingleLine()
                    isHorizontalFadingEdgeEnabled = true
                    ellipsize = TextUtils.TruncateAt.MARQUEE
                    isSelected = true
                }
                constrainedWidth(keyLabel.id, true)
                endToStart(keyLabel, valueView, 4f)
            }
        }
    }

    override fun setBackgroundColor(color: Int) {
        setBackgroundColor(color, topRadius, if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f)
    }

    private var topRadius = 0f
    fun setTopRadius(topRadius: Float) {
        this.topRadius = topRadius
        currentBackgroundColor?.let {
            setBackgroundColor(it)
        }
    }

    fun setLast(isLast: Boolean) {
        this.isLast = isLast
        currentBackgroundColor?.let {
            setBackgroundColor(it)
        }
    }
}
