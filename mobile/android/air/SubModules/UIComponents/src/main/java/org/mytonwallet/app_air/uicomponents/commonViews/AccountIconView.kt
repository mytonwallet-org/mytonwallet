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
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.gradientColors
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.stores.AccountStore

@SuppressLint("ViewConstructor")
class AccountIconView(context: Context, val usage: Usage) : View(context) {

    sealed class Usage {

        abstract val textSize: Float

        data class SelectableItem(override val textSize: Float) : Usage()
        data class ViewItem(override val textSize: Float = 14f.dp) : Usage()
    }

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f.dp
    }

    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val textPaint = AccountAvatarRenderer.createTextPaint(usage.textSize)

    private var gradientColors: IntArray? = null
    private var abbreviationText: String = ""
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
            is Usage.SelectableItem -> WColor.Tint.color
            else -> WColor.Background.color
        }
        AccountAvatarRenderer.updatePaintTheme(textPaint)
        invalidate()
    }

    private var accountId: String? = null

    fun config(account: MAccount) {
        config(account.accountId, account.name, account.firstAddress ?: "")
    }

    fun config(savedAddress: MSavedAddress) {
        config(savedAddress.accountId, savedAddress.name, savedAddress.address)
    }

    fun config(accountId: String?, title: CharSequence?, address: String) {
        this.accountId = accountId
        gradientColors = address.gradientColors
        abbreviationText = generateAbbreviation(title?.toString(), address)

        currentPadding = when (usage) {
            is Usage.SelectableItem -> {
                if (accountId == AccountStore.activeAccountId) {
                    3f.dp
                } else {
                    1.5f.dp
                }
            }

            is Usage.ViewItem -> 0f
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
        AccountAvatarRenderer.drawCenteredText(
            canvas,
            abbreviationText,
            width / 2f,
            height / 2f,
            textPaint
        )
    }

    private fun drawBorderIfNeeded(canvas: Canvas) {
        val shouldDrawBorder = when (usage) {
            is Usage.SelectableItem -> accountId == AccountStore.activeAccountId
            is Usage.ViewItem -> false
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
