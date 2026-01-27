package org.mytonwallet.app_air.uicomponents.widgets.dialog

import android.animation.ValueAnimator
import android.graphics.Color
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.children
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.atMost
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.min

class WDialog(private val customView: ViewGroup, private val config: Config) : IPopup {

    data class Config(
        val title: String? = null,
        val subtitle: String? = null,
        val actionButton: WDialogButton.Config? = null,
        val secondaryButton: WDialogButton.Config? = null,
    )

    private var isPresented: Boolean = false
    private var fullHeight: Int = 0
    private var isAnimating = true
    private lateinit var parentViewController: WeakReference<WViewController>
    private var onDismissListener: (() -> Unit)? = null

    private val overlayView = View(customView.context).apply {
        id = View.generateViewId()
        alpha = 0f
        z = Float.MAX_VALUE - 2
        setBackgroundColor(Color.BLACK.colorWithAlpha(76))
        setOnClickListener {
            dismiss()
        }
    }

    private val titleLabel: WLabel? =
        if (config.title != null) WLabel(customView.context).apply {
            setStyle(22f, WFont.SemiBold)
            gravity = Gravity.START
            text = config.title
            setTextColor(WColor.PrimaryText)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
            updateTheme()
        } else null

    private val subtitleLabel: WLabel? =
        if (config.subtitle != null) WLabel(customView.context).apply {
            setStyle(15f)
            gravity = Gravity.START
            text = config.subtitle
            setTextColor(WColor.SecondaryText)
            updateTheme()
        } else null

    private val actionButton: WLabel? =
        if (config.actionButton != null) WDialogButton(
            customView.context,
            config.actionButton
        ).apply {
            setOnClickListener {
                config.actionButton.onTap?.invoke()
                dismiss()
            }
        } else null

    private val secondaryButton: WLabel? =
        if (config.secondaryButton != null) WDialogButton(
            customView.context,
            config.secondaryButton
        ).apply {
            setOnClickListener {
                config.secondaryButton.onTap?.invoke()
                dismiss()
            }
        } else null

    private val contentView: WFrameLayout = object : WFrameLayout(customView.context), WThemedView {
        override fun updateTheme() {
            setBackgroundColor(WColor.Background.color, 18f.dp)
        }
    }.apply {
        alpha = 0f
        z = Float.MAX_VALUE - 1
        updateTheme()
        titleLabel?.let { titleLabel ->
            addView(titleLabel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.TOP
                topMargin = 24.dp
                marginStart = 24.dp
                marginEnd = 24.dp
            })
        }
        subtitleLabel?.let { subtitleLabel ->
            addView(subtitleLabel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.TOP
                topMargin = if (config.title != null) 60.dp else 24.dp
                marginStart = 24.dp
                marginEnd = 24.dp
            })
        }
        config.actionButton?.let {
            addView(actionButton, FrameLayout.LayoutParams(WRAP_CONTENT, 40.dp).apply {
                gravity = Gravity.TOP or Gravity.END
                marginEnd = 12.dp
            })
        }
        config.secondaryButton?.let {
            addView(secondaryButton, FrameLayout.LayoutParams(WRAP_CONTENT, 40.dp).apply {
                gravity = Gravity.TOP or Gravity.END
            })
        }
        addView(customView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            gravity = Gravity.TOP
            topMargin = if (config.title != null) 60.dp else 24.dp
            bottomMargin = if (config.actionButton != null) 64.dp else 24.dp
        })
        if (titleLabel != null || subtitleLabel != null)
            customView.post {
                customView.layoutParams =
                    (customView.layoutParams as ViewGroup.MarginLayoutParams).apply {
                        topMargin = max(
                            60.dp,
                            (titleLabel?.top ?: 0) +
                                (titleLabel?.height ?: (-16).dp) +
                                (subtitleLabel?.height ?: (-16).dp) +
                                16.dp
                        )
                    }
            }
        setOnClickListener {}
    }

    fun presentOn(viewController: WViewController) {
        if (isPresented)
            throw Exception("WDialog can't be presented more than once")
        isPresented = true
        viewController.setActiveDialog(this)
        PopupHelpers.popupShown(this)
        parentViewController = WeakReference(viewController)
        val parentView = viewController.navigationController?.parent as WView
        parentView.hideKeyboard()
        parentView.addView(
            overlayView,
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        val contentViewWidth = 500.dp.coerceAtMost(parentView.width - 40.dp)
        parentView.apply {
            addView(
                contentView,
                FrameLayout.LayoutParams(
                    contentViewWidth,
                    WRAP_CONTENT
                )
            )
            setConstraints {
                toCenterX(contentView)
                toCenterY(contentView)
            }
        }
        contentView.post {
            if (customView.height == 0) {
                customView.measure(contentViewWidth.atMost, 0.unspecified)
            }

            val measuredHeight =
                if (customView.height > 0) customView.height else customView.measuredHeight
            val customViewLp = customView.layoutParams.apply {
                height = measuredHeight
            } as? ViewGroup.MarginLayoutParams
            customView.layoutParams = customViewLp
            fullHeight =
                (customViewLp?.topMargin ?: 0) + measuredHeight + (customViewLp?.bottomMargin
                    ?: 0)
            if (actionButton != null)
                actionButton.layoutParams =
                    (actionButton.layoutParams as FrameLayout.LayoutParams).apply {
                        topMargin = fullHeight - 52.dp
                    }
            if (secondaryButton != null)
                secondaryButton.layoutParams =
                    (secondaryButton.layoutParams as FrameLayout.LayoutParams).apply {
                        topMargin = fullHeight - 52.dp
                        rightMargin = actionButton!!.width + 24.dp
                    }
            ValueAnimator.ofInt(0, fullHeight).apply {
                duration = AnimationConstants.DIALOG_PRESENT
                interpolator = WInterpolator.emphasized
                addUpdateListener {
                    renderFrame(animatedValue as Int)
                }
                doOnEnd {
                    isAnimating = false
                }
                start()
            }
        }
    }

    val keyboardTop: Int
        get() {
            val viewController = parentViewController.get() ?: return 0
            return (viewController.navigationController?.bottom ?: 0) -
                (viewController.window?.imeInsets?.bottom ?: 0)
        }

    fun insetsUpdated() {
        parentViewController.get()?.let { viewController ->
            val targetTranslationY =
                if (viewController.isKeyboardOpen)
                    min(0, keyboardTop - 16.dp - contentView.bottom).toFloat()
                else
                    0f

            contentView.animate()
                .translationY(targetTranslationY)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .setInterpolator(DecelerateInterpolator())
                .start()
        }
    }

    override fun onBackPressed() {
        dismiss()
    }

    override fun dismiss() {
        if (isAnimating)
            return
        if (!isPresented)
            throw Exception("WDialog is not presented yet")
        overlayView.lockView()
        contentView.lockView()
        contentView.hideKeyboard()
        isAnimating = true
        ValueAnimator.ofInt(contentView.height, 0).apply {
            duration = AnimationConstants.DIALOG_DISMISS
            interpolator = WInterpolator.emphasizedAccelerate
            addUpdateListener {
                renderFrame(animatedValue as Int)
            }
            doOnEnd {
                parentViewController.get()?.setActiveDialog(null)
                (overlayView.parent as? ViewGroup)?.apply {
                    removeView(overlayView)
                    removeView(contentView)
                }
                onDismissListener?.invoke()
                PopupHelpers.popupDismissed(this@WDialog)
            }
            start()
        }
    }

    fun setActionButtonEnabled(isEnabled: Boolean) {
        actionButton?.isEnabled = isEnabled
        actionButton?.alpha = if (isEnabled) 1f else 0.5f
    }

    fun setOnDismissListener(listener: () -> Unit) {
        onDismissListener = listener
    }

    private fun renderFrame(currentHeight: Int) {
        val heightFraction = currentHeight / fullHeight.toFloat()
        overlayView.alpha = heightFraction
        contentView.alpha = (heightFraction * 4).coerceIn(0f, 1f)
        contentView.layoutParams =
            (contentView.layoutParams as ConstraintLayout.LayoutParams).apply {
                height = currentHeight
                bottomMargin = fullHeight - height
            }
        customView.children.forEach {
            it.apply {
                val t = top + (titleLabel?.height ?: 0)
                alpha =
                    ((currentHeight - t) / (fullHeight - t).toFloat())
                        .coerceIn(0f, 1f)
                translationY = -(1 - alpha) * 10.dp
            }
        }
        arrayOf(titleLabel, subtitleLabel, actionButton, secondaryButton).filterNotNull().forEach {
            it.apply {
                alpha =
                    ((currentHeight - top) / (fullHeight - top).toFloat())
                        .coerceIn(0f, 1f)
                translationY = -(1 - alpha) * 10.dp
            }
        }
    }
}
