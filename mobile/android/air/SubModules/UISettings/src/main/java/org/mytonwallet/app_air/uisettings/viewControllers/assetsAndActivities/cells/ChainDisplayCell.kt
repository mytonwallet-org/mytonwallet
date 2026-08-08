package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.MotionEvent
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat.AccessibilityActionCompat
import androidx.core.view.accessibility.AccessibilityViewCommand
import androidx.core.view.isInvisible
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

@SuppressLint("ViewConstructor")
class ChainDisplayCell(
    context: Context,
    private val onVisibilityChanged: (MBlockchain, Boolean) -> Unit,
    private val onReorderStarted: (ChainDisplayCell) -> Unit,
    private val onMoveRequested: (MBlockchain, Int) -> Boolean
) : WCell(context, LayoutParams(MATCH_PARENT, 56.dp)),
    WThemedView {

    companion object {
        private const val REORDERING_OFFSET = 32f
    }

    private var chain: MBlockchain? = null
    private var isFirst = false
    private var isLast = false
    private var usesAutomaticAppearance = true
    private var showsReorderControl = false
    private var appearanceAnimator: ValueAnimator? = null
    private var reorderAnimator: ValueAnimator? = null

    private val directionSign: Float
        get() = if (LocaleController.isRTL) -1f else 1f

    private val reorderView = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageDrawable(
            context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_handle)
        )
        contentDescription = null
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        @SuppressLint("ClickableViewAccessibility")
        setOnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_DOWN && !usesAutomaticAppearance) {
                onReorderStarted(this@ChainDisplayCell)
            }
            false
        }
    }

    private val iconView = AppCompatImageView(context).apply {
        id = generateViewId()
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize())
        setSingleLine()
    }

    private val switchView = WSwitch(context).apply {
        setOnCheckedChangeListener { _, isChecked ->
            chain?.let { onVisibilityChanged(it, isChecked) }
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(reorderView, LayoutParams(28.dp, 28.dp))
        addView(iconView, LayoutParams(28.dp, 28.dp))
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(switchView)
        setConstraints {
            toStart(reorderView, 14f)
            toCenterY(reorderView)

            startToEnd(iconView, reorderView, 8f)
            toCenterY(iconView)

            startToEnd(titleLabel, iconView, 14f)
            endToStart(titleLabel, switchView, 4f)
            toCenterY(titleLabel)

            toEnd(switchView, 20f)
            toCenterY(switchView)
        }

        setOnClickListener {
            if (switchView.isEnabled) switchView.isChecked = !switchView.isChecked
        }
        updateTheme()
    }

    fun configure(
        chain: MBlockchain,
        isVisible: Boolean,
        isSwitchEnabled: Boolean,
        showsReorderControl: Boolean,
        usesAutomaticAppearance: Boolean,
        isFirst: Boolean,
        isLast: Boolean
    ) {
        val animateAppearanceChange = configured &&
            this.usesAutomaticAppearance != usesAutomaticAppearance &&
            isAttachedToWindow
        this.chain = chain
        this.isFirst = isFirst
        this.isLast = isLast
        this.usesAutomaticAppearance = usesAutomaticAppearance

        iconView.setImageDrawable(context.getDrawableCompat(chain.icon))
        titleLabel.text = chain.displayName
        switchView.setOnCheckedChangeListener(null)
        switchView.isChecked = isVisible
        switchView.isEnabled = isSwitchEnabled
        switchView.setOnCheckedChangeListener { _, checked ->
            this.chain?.let { onVisibilityChanged(it, checked) }
        }

        updateTheme(animateAppearance = animateAppearanceChange)
        setShowsReorderControl(
            showsReorderControl,
            animated =
                configured && this.showsReorderControl != showsReorderControl && isAttachedToWindow
        )
        updateAccessibilityActions()
    }

    private fun updateAccessibilityActions() {
        setAccessibilityMoveAction(
            AccessibilityActionCompat.ACTION_SCROLL_BACKWARD,
            offset = -1,
            label = "Move Up",
            isAvailable = showsReorderControl && !isFirst
        )
        setAccessibilityMoveAction(
            AccessibilityActionCompat.ACTION_SCROLL_FORWARD,
            offset = 1,
            label = "Move Down",
            isAvailable = showsReorderControl && !isLast
        )
    }

    private fun setAccessibilityMoveAction(
        action: AccessibilityActionCompat,
        offset: Int,
        label: String,
        isAvailable: Boolean
    ) {
        ViewCompat.replaceAccessibilityAction(
            this,
            action,
            LocaleController.getString(label).takeIf { isAvailable },
            if (isAvailable) {
                AccessibilityViewCommand { _, _ ->
                    chain?.let { onMoveRequested(it, offset) } ?: false
                }
            } else {
                null
            }
        )
    }

    private fun setShowsReorderControl(showsReorderControl: Boolean, animated: Boolean) {
        this.showsReorderControl = showsReorderControl
        reorderAnimator?.cancel()

        if (showsReorderControl) reorderView.isInvisible = false

        val handleStartTranslation = reorderView.translationX
        val handleStartAlpha = reorderView.alpha
        val contentStartTranslation = iconView.translationX
        val handleTargetTranslation = if (showsReorderControl) {
            0f
        } else {
            -REORDERING_OFFSET.dp * directionSign
        }
        val contentTargetTranslation = handleTargetTranslation

        fun render(fraction: Float) {
            reorderView.translationX = lerp(
                handleStartTranslation,
                handleTargetTranslation,
                fraction
            )
            reorderView.alpha = lerp(
                handleStartAlpha,
                if (showsReorderControl) 1f else 0f,
                fraction
            )
            val contentTranslation = lerp(
                contentStartTranslation,
                contentTargetTranslation,
                fraction
            )
            iconView.translationX = contentTranslation
            titleLabel.translationX = contentTranslation

            if (fraction == 1f && !showsReorderControl) reorderView.isInvisible = true
        }

        if (!animated) {
            render(1f)
            return
        }

        reorderAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { render(it.animatedFraction) }
            start()
        }
    }

    override fun updateTheme() {
        appearanceAnimator?.cancel()
        appearanceAnimator = null
        updateTheme(animateAppearance = false)
    }

    private fun updateTheme(animateAppearance: Boolean) {
        val topRadius = if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f
        val bottomRadius = if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        background = WRippleDrawable.create(
            topRadius,
            topRadius,
            bottomRadius,
            bottomRadius
        ).apply {
            backgroundColor = Color.TRANSPARENT
            rippleColor = WColor.SecondaryBackground.color
        }
        val titleColor = if (usesAutomaticAppearance) {
            WColor.SecondaryText.color
        } else {
            WColor.PrimaryText.color
        }
        val iconAlpha = if (usesAutomaticAppearance) 0.5f else 1f
        if (animateAppearance) {
            val startTitleColor = titleLabel.currentTextColor
            val startIconAlpha = iconView.alpha
            appearanceAnimator?.cancel()
            appearanceAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener { animator ->
                    val progress = animator.animatedValue as Float
                    titleLabel.setTextColor(
                        ColorUtils.blendARGB(startTitleColor, titleColor, progress)
                    )
                    iconView.alpha = lerp(startIconAlpha, iconAlpha, progress)
                }
                start()
            }
        } else if (appearanceAnimator?.isRunning != true) {
            titleLabel.setTextColor(titleColor)
            iconView.alpha = iconAlpha
        }
        switchView.updateTheme()
    }
}
