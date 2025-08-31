package org.mytonwallet.app_air.uicomponents.widgets.dialog

import android.animation.ValueAnimator
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.children
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import java.lang.ref.WeakReference
import kotlin.math.max

class WDialog(private val customView: ViewGroup, private val config: Config) {

    data class Config(
        val title: String? = null,
        val actionButton: WDialogButton.Config? = null,
        val secondaryButton: WDialogButton.Config? = null,
    )

    private var isPresented: Boolean = false
    private var fullHeight: Int = 0
    private var isAnimating = true
    private lateinit var parentViewController: WeakReference<WViewController>

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
        if (config.title != null) object : WLabel(customView.context), WThemedView {
            override fun updateTheme() {
                super.updateTheme()
                setTextColor(WColor.PrimaryText.color)
            }
        }.apply {
            setStyle(22f, WFont.Medium)
            gravity = Gravity.START
            text = config.title
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

    private val contentView: FrameLayout = object : FrameLayout(customView.context), WThemedView {
        override fun updateTheme() {
            setBackgroundColor(WColor.Background.color, 18f.dp)
        }
    }.apply {
        id = View.generateViewId()
        alpha = 0f
        z = Float.MAX_VALUE - 1
        updateTheme()
        titleLabel?.let { titleLabel ->
            addView(titleLabel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.TOP
                topMargin = 24.dp
                marginStart = 24.dp
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
        if (config.title != null)
            titleLabel?.post {
                customView.layoutParams =
                    (customView.layoutParams as ViewGroup.MarginLayoutParams).apply {
                        topMargin = max(60.dp, titleLabel.height + 16.dp)
                    }
            }
        setOnClickListener {}
    }

    fun presentOn(viewController: WViewController) {
        if (isPresented)
            throw Exception("WDialog can't be presented more than once")
        isPresented = true
        viewController.setActiveDialog(this)
        parentViewController = WeakReference(viewController)
        val parentView =
            (viewController.navigationController?.tabBarController?.navigationController?.viewControllers?.last()
                ?: viewController).view
        parentView.hideKeyboard()
        parentView.addView(
            overlayView,
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        parentView.apply {
            addView(
                contentView,
                FrameLayout.LayoutParams(
                    500.dp.coerceAtMost(parentView.width - 40.dp),
                    WRAP_CONTENT
                )
            )
            setConstraints {
                toCenterX(contentView)
                toCenterY(contentView)
            }
        }
        contentView.post {
            customView.layoutParams = customView.layoutParams.apply {
                height = customView.height
            }
            fullHeight = contentView.height
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

    fun dismiss() {
        if (isAnimating)
            return
        if (!isPresented)
            throw Exception("WDialog is not presented yet")
        overlayView.lockView()
        contentView.lockView()
        isAnimating = true
        ValueAnimator.ofInt(contentView.height, 0).apply {
            duration = AnimationConstants.DIALOG_DISMISS
            interpolator = WInterpolator.emphasizedAccelerate
            addUpdateListener {
                renderFrame(animatedValue as Int)
            }
            doOnEnd {
                parentViewController.get()?.setActiveDialog(null)
                (overlayView.parent as? WViewController.ContainerView)?.apply {
                    removeView(overlayView)
                    removeView(contentView)
                }
            }
            start()
        }
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
        arrayOf(titleLabel, actionButton, secondaryButton).filterNotNull().forEach {
            it.apply {
                alpha =
                    ((currentHeight - top) / (fullHeight - top).toFloat())
                        .coerceIn(0f, 1f)
                translationY = -(1 - alpha) * 10.dp
            }
        }
    }
}
