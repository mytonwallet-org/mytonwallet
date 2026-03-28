package org.mytonwallet.app_air.uiassets.viewControllers.assets.cells

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageButton
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import androidx.core.view.isInvisible
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.resize
import org.mytonwallet.app_air.uicomponents.extensions.setConstraints
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.image.WNftImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class DomainExpirationBannerCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    companion object {
        const val DAYS_THRESHOLD = 14
        private const val IMAGE_SIZE = 28
        private const val IMAGE_OFFSET = 20
        private const val IMAGE_CORNER_RADIUS = 4.5f
        private const val BORDER_WIDTH = 1f
        private const val MARGIN_H = 4
        private const val MARGIN_BOTTOM = 11

        const val CELL_HEIGHT_DP = 44 + MARGIN_H + MARGIN_BOTTOM
    }

    var onTap: (() -> Unit)? = null
    var onClose: (() -> Unit)? = null

    private val ripple = WRippleDrawable.create(24f.dp).apply {
        backgroundColor = WColor.Red.color
        rippleColor = 0x33FFFFFF
    }

    private val card = android.view.View(context).apply {
        id = generateViewId()
        background = ripple
        setOnClickListener { onTap?.invoke() }
    }

    private val img1 = WNftImageView(context, IMAGE_SIZE.dp, 0, IMAGE_CORNER_RADIUS.dp)
    private val img2 = WNftImageView(context, IMAGE_SIZE.dp, 0, IMAGE_CORNER_RADIUS.dp)
    private val img3 = WNftImageView(context, IMAGE_SIZE.dp, 0, IMAGE_CORNER_RADIUS.dp)
    private val imageViews = setOf(img1, img2, img3)

    private val label = WLabel(context).apply {
        id = generateViewId()
        setStyle(14f)
        setLineHeight(18f)
        setTextColor(WColor.White)
        val arrow = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_16_24
        )?.mutate()?.resize(context, 12.dp, 18.dp, WColor.White.color)
        setCompoundDrawablesRelativeWithIntrinsicBounds(null, null, arrow, null)
        compoundDrawablePadding = (-2).dp
    }

    private val closeButton = AppCompatImageButton(context).apply {
        id = generateViewId()
        setImageDrawable(ContextCompat.getDrawable(context, R.drawable.ic_close_30))
        imageTintList = ColorStateList.valueOf(0x99FFFFFF.toInt())
        background = null
        setOnClickListener { onClose?.invoke() }
    }

    init {
        clipChildren = false

        addView(card, LayoutParams(0, 44.dp))
        addView(img3, LayoutParams(IMAGE_SIZE.dp, IMAGE_SIZE.dp))
        addView(img2, LayoutParams(IMAGE_SIZE.dp, IMAGE_SIZE.dp))
        addView(img1, LayoutParams(IMAGE_SIZE.dp, IMAGE_SIZE.dp))
        addView(label, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(closeButton, LayoutParams(30.dp, 30.dp))
        imageViews.forEach {
            it.clipToOutline = true
            it.setPaddingDp(BORDER_WIDTH)
        }

        setConstraints {
            toStart(card, MARGIN_H.toFloat())
            toEnd(card, MARGIN_H.toFloat())
            toTop(card, MARGIN_H.toFloat())
            toBottom(card, MARGIN_BOTTOM.toFloat())

            topToTop(img1, card, 8f)
            bottomToBottom(img1, card, 8f)
            startToStart(img1, card, 12f)

            topToTop(img2, img1)
            bottomToBottom(img2, img1)
            startToStart(img2, card, (12 + IMAGE_OFFSET).toFloat())

            topToTop(img3, img1)
            bottomToBottom(img3, img1)
            startToStart(img3, card, (12 + IMAGE_OFFSET * 2).toFloat())

            topToTop(closeButton, card)
            bottomToBottom(closeButton, card)
            endToEnd(closeButton, card, 10f)

            topToTop(label, card)
            bottomToBottom(label, card)
            startToEnd(label, img1, 12f)
            endToStart(label, closeButton, 4f)
            constrainedWidth(label.id, true)
            setHorizontalBias(label.id, 0f)
        }
    }

    fun configure(iconNfts: List<ApiNft>, count: Int, minDays: Int) {
        if (count == 0)
            return

        ripple.backgroundColor = WColor.Red.color.colorWithAlpha(204)

        img1.isInvisible = iconNfts.isEmpty()
        img2.isInvisible = iconNfts.size < 2
        img3.isInvisible = iconNfts.size < 3

        if (iconNfts.isNotEmpty()) img1.setNftImage(iconNfts[0].thumbnail)
        if (iconNfts.size >= 2) img2.setNftImage(iconNfts[1].thumbnail)
        if (iconNfts.size >= 3) img3.setNftImage(iconNfts[2].thumbnail)

        val lastImg = when {
            iconNfts.size >= 3 -> img3
            iconNfts.size >= 2 -> img2
            else -> img1
        }
        setConstraints { startToEnd(label, lastImg, 12f) }

        label.text = buildBannerText(iconNfts, count, minDays)

        updateTheme()
    }

    private fun buildBannerText(iconNfts: List<ApiNft>, count: Int, minDays: Int): CharSequence {
        val text = if (minDays < 0) {
            if (count == 1) {
                LocaleController.getString("\$domain_was_expired")
                    .replace("%domain%", iconNfts.firstOrNull()?.name ?: count.toString())
                    .toProcessedSpannableStringBuilder()
            } else {
                LocaleController.getPluralOrFormat("\$domains_was_expired", count)
                    .replace("%domain%", count.toString())
                    .toProcessedSpannableStringBuilder()
            }
        } else {
            val inDays = LocaleController.getPluralOrFormat("\$in_days", minDays)
            if (count == 1) {
                LocaleController.getString("\$domain_expire")
                    .replace("%domain%", iconNfts.firstOrNull()?.name ?: "")
                    .replace("%days%", inDays)
                    .toProcessedSpannableStringBuilder()
            } else {
                LocaleController.getPluralOrFormat("\$domains_expire", count)
                    .replace("%domain%", count.toString())
                    .replace("%days%", inDays)
                    .toProcessedSpannableStringBuilder()
            }
        }
        return text
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged)
            return
        _isDarkThemeApplied = ThemeManager.isDark

        val foregroundBorderDrawable = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = IMAGE_CORNER_RADIUS.dp
            setStroke(
                BORDER_WIDTH.dp.roundToInt(),
                ColorUtils.blendARGB(WColor.Red.color, WColor.Background.color, 0.2f)
            )
        }
        imageViews.forEach { it.background = foregroundBorderDrawable }
    }
}
