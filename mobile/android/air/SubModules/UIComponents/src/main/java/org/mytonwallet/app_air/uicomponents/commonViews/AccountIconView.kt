package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.gradientColors
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.stores.AccountStore

@SuppressLint("ViewConstructor")
class AccountIconView(context: Context, val usage: Usage) : FrameLayout(context) {

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

    private val avatarImageView = WCustomImageView(context).apply {
        defaultPlaceholder = Content.Placeholder.Color(WColor.Transparent)
    }

    private var gradientColors: IntArray? = null
    private var abbreviationText: String = ""
    private var avatarUrl: String? = null
    private var currentPadding: Float = 1.5f.dp
    private val ovalRect = RectF()

    var showText: Boolean = true
        set(value) {
            if (field == value) return
            field = value
            invalidate()
        }

    init {
        id = generateViewId()
        isFocusable = false
        isClickable = false
        setWillNotDraw(false)
        addView(avatarImageView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
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

    fun config(
        account: MAccount,
        useTelegramAvatar: Boolean = ApplicationContextHolder.isGramApp,
    ) {
        val avatarUrl = account.telegramAvatarUrl
            ?.takeIf { useTelegramAvatar && !it.substringBefore('?').endsWith(".svg", ignoreCase = true) }
        config(account.accountId, account.name, account.firstAddress ?: "", avatarUrl)
    }

    fun config(savedAddress: MSavedAddress) {
        config(savedAddress.accountId, savedAddress.name, savedAddress.address)
    }

    fun config(
        accountId: String?,
        title: CharSequence?,
        address: String,
        avatarUrl: String? = null
    ) {
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

        if (this.avatarUrl != avatarUrl) {
            this.avatarUrl = avatarUrl
            avatarImageView.clear()
            if (avatarUrl != null) {
                avatarImageView.set(Content.ofUrl(avatarUrl))
            }
        }

        updateAvatarPadding()
        updateTheme()
    }

    private fun updateAvatarPadding() {
        val pad = currentPadding.toInt()
        if (avatarImageView.paddingLeft != pad) {
            avatarImageView.setPadding(pad, pad, pad, pad)
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        drawGradientBackground(canvas)
        if (showText) drawText(canvas)
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
