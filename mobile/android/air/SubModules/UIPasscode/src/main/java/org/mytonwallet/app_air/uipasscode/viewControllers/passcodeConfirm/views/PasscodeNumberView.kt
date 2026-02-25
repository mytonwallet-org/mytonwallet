package org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import androidx.core.animation.doOnCancel
import androidx.core.animation.doOnEnd
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeOutObjectAnimator
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class PasscodeNumberView(
    context: Context,
    val row: Int,
    val column: Int,
    val light: Boolean?,
    val showMotionBackgroundDrawable: Boolean
) : WView(context), WThemedView {

    val num = getNum(row, column)

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(22f)
        lbl
    }

    private val subtitleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(14f, WFont.Medium)
        lbl
    }

    private val imageView: WImageView by lazy {
        val iv = WImageView(context)
        iv
    }

    var customDrawable: Drawable? = null
    var drawableTint: Int? = null

    override fun setupViews() {
        super.setupViews()

        if (num == null) {
            addView(imageView)
        }
        num?.let {
            addView(titleLabel)
            addView(subtitleLabel)
            titleLabel.text = it.toString()
            subtitleLabel.text = subtitle(it)
        }

        setConstraints {
            if (num == null) {
                allEdges(imageView)
            } else {
                toTop(titleLabel, 16f)
                toCenterX(titleLabel)
                toBottom(subtitleLabel, 16f)
                toCenterX(subtitleLabel)
            }
        }

        updateTheme()
    }

    fun updateConstraintsForSize(currentSize: Int) {
        val scaleFactor = currentSize / 80f.dp
        if (scaleFactor >= 1)
            return

        titleLabel.setStyle(22f * scaleFactor)
        subtitleLabel.setStyle(14f * scaleFactor, WFont.Medium)

        if (num == null) {
            imageView.scaleX = scaleFactor
            imageView.scaleY = scaleFactor
        } else {
            if (scaleFactor > 0.5) {
                val scaledSpacing = 16f * scaleFactor
                setConstraints {
                    toTop(titleLabel, scaledSpacing)
                    toCenterX(titleLabel)
                    toBottom(subtitleLabel, scaledSpacing)
                    toCenterX(subtitleLabel)
                }
            } else {
                subtitleLabel.visibility = GONE
                setConstraints {
                    toCenterY(titleLabel)
                }
            }
        }
    }

    override fun updateTheme() {
        val color = if (light ?: ThemeManager.isDark) Color.WHITE else Color.BLACK
        titleLabel.setTextColor(color)
        subtitleLabel.setTextColor(color.colorWithAlpha(169))
        updateBackground()
    }

    fun updateBackground() {
        val color = if (showMotionBackgroundDrawable)
            (if (light ?: ThemeManager.isDark) Color.WHITE else Color.BLACK).colorWithAlpha(20)
        else WColor.BackgroundRipple.color
        val radius = if (measuredWidth == measuredHeight) 40f.dp else 16f.dp
        // Always set background first to avoid nested RippleDrawables on repeated calls
        setBackgroundColor(0, radius)
        if (num == null) {
            updateImage(false)
        }
        addRippleEffect(color, radius)
    }

    fun updateImage(animated: Boolean) {
        isEnabled = customDrawable != null
        if (customDrawable == null) {
            if (isVisible && animated) {
                imageView.fadeOutObjectAnimator()?.apply {
                    fun cleanup() {
                        if (customDrawable != null) return
                        imageView.setImageDrawable(null)
                        visibility = INVISIBLE
                        imageView.alpha = 1f
                    }

                    doOnCancel { cleanup() }
                    doOnEnd { cleanup() }

                    start()
                }
            } else {
                visibility = INVISIBLE
                imageView.setImageDrawable(null)
                imageView.alpha = 1f
            }
            return
        }

        val color = drawableTint ?: if (light ?: ThemeManager.isDark) Color.WHITE else Color.BLACK
        customDrawable!!.setTint(color)

        if (animated) {
            imageView.crossFadeImage(customDrawable!!)
        } else {
            imageView.setImageDrawable(customDrawable)
            imageView.alpha = 1f
        }

        if (isInvisible)
            visibility = VISIBLE
    }

    private fun getNum(row: Int, column: Int): Int? {
        if (row < 4) {
            return (row - 1) * 3 + column
        } else if (column == 2) {
            return 0
        }
        return null
    }

    private fun subtitle(forNum: Int): String {
        return when (forNum) {
            0, 1 -> ""
            7 -> "PQRS"
            8 -> "TUV"
            9 -> "WXYZ"
            else -> {
                var txt = ""
                val startIndex = 'A'.code + forNum * 3 - 6
                for (charIndex in startIndex..startIndex + 2) {
                    val char = charIndex.toChar()
                    txt += char
                }
                return txt.trimEnd()
            }
        }
    }
}
