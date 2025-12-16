package org.mytonwallet.app_air.uipasscode.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.R
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class PasscodeNumberView(
    context: Context,
    val row: Int,
    val column: Int,
    val light: Boolean
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

    @SuppressLint("SetTextI18n")
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

    override fun updateTheme() {
        val color = if (light) Color.WHITE else Color.BLACK
        // Always set background first to avoid nested RippleDrawables on repeated calls
        setBackgroundColor(
            color.colorWithAlpha(if (light && num != null) 38 else 0),
            40f.dp
        )
        if (num == null) {
            if (column == 1) {
                // Biometric button
                val biometricDrawable =
                    ContextCompat.getDrawable(
                        context,
                        R.drawable.ic_biometric
                    )?.apply {
                        setTint(color)
                    }
                imageView.setImageDrawable(biometricDrawable)
            } else {
                // Backspace button
                val backspaceDrawable =
                    ContextCompat.getDrawable(
                        context,
                        R.drawable.ic_backspace
                    )?.apply {
                        setTint(color)
                    }
                imageView.setImageDrawable(backspaceDrawable)
            }
        }
        addRippleEffect(color.colorWithAlpha(if (light) 128 else 20), 40f.dp)
        titleLabel.setTextColor(color)
        subtitleLabel.setTextColor(color.colorWithAlpha(169))
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
