package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.firstGrapheme
import org.mytonwallet.app_air.walletbasecontext.utils.gradientColors
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.AccountStore

@SuppressLint("ViewConstructor")
class AccountIconView(context: Context, val usage: Usage) : View(context) {

    enum class Usage {
        SELECTABLE_ITEM,
        THUMB
    }

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f.dp
    }

    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = when (usage) {
            Usage.SELECTABLE_ITEM -> 18f.dp
            else -> 11f.dp
        }
        typeface = WFont.Bold.typeface
        color = WColor.White.color
        textAlign = Paint.Align.CENTER
    }

    private var gradientColors: IntArray? = null
    private var titleText: String = ""
    private var currentPadding: Float = 1.5f.dp
    private val ovalRect = RectF()

    init {
        id = generateViewId()
        isFocusable = false
        isClickable = false
        updateTheme()
    }

    fun updateTheme() {
        borderPaint.color = when (usage) {
            Usage.SELECTABLE_ITEM -> WColor.Tint.color
            else -> WColor.Background.color
        }
        textPaint.color = WColor.White.color
        invalidate()
    }

    private var account: MAccount? = null
    fun config(account: MAccount) {
        this.account = account
        val address = account.firstAddress ?: ""
        gradientColors = address.gradientColors

        titleText = account.name
            .trim()
            .split("\\s+".toRegex())
            .filter { it.isNotEmpty() }
            .take(2)
            .joinToString("") { part -> part.firstGrapheme().uppercase() }

        currentPadding = when (usage) {
            Usage.SELECTABLE_ITEM -> {
                if (account.accountId == AccountStore.activeAccountId) {
                    3f.dp
                } else {
                    1.5f.dp
                }
            }

            else -> 1.5f.dp
        }

        updateTheme()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        drawGradientBackground(canvas)
        drawText(canvas)
        drawBorderIfNeeded(canvas)
    }

    private fun drawGradientBackground(canvas: Canvas) {
        val colors = gradientColors ?: return

        ovalRect.set(
            currentPadding,
            currentPadding,
            width - currentPadding,
            height - currentPadding
        )

        backgroundPaint.shader = LinearGradient(
            0f,
            0f,
            0f,
            height.toFloat(),
            colors,
            null,
            Shader.TileMode.CLAMP
        )

        canvas.drawOval(ovalRect, backgroundPaint)
    }

    private fun drawText(canvas: Canvas) {
        if (titleText.isEmpty()) return

        val centerX = width / 2f
        val centerY = height / 2f - (textPaint.descent() + textPaint.ascent()) / 2f
        canvas.drawText(titleText, centerX, centerY, textPaint)
    }

    private fun drawBorderIfNeeded(canvas: Canvas) {
        val shouldDrawBorder = when (usage) {
            Usage.SELECTABLE_ITEM -> account?.accountId == AccountStore.activeAccountId
            else -> true
        }

        if (shouldDrawBorder) {
            drawSelectedBorder(canvas)
        }
    }

    private fun drawSelectedBorder(canvas: Canvas) {
        val halfStroke = borderPaint.strokeWidth / 2
        val left = halfStroke
        val top = halfStroke
        val right = width - halfStroke
        val bottom = height - halfStroke

        val cornerRadius = 25.5f.dp
        canvas.drawRoundRect(
            left,
            top,
            right,
            bottom,
            cornerRadius,
            cornerRadius,
            borderPaint
        )
    }
}
