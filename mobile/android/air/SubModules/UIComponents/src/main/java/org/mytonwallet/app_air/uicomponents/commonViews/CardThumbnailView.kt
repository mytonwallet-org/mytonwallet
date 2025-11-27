package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

class CardThumbnailView(context: Context) : FrameLayout(context) {

    private var cardNft: ApiNft? = null

    private val imageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(3f.dp)
    }

    private val primaryPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val secondaryPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        alpha = (255 * 0.6f).toInt()
    }

    private var primaryColor: Int = 0
    private var secondaryColor: Int = 0

    private val rect = RectF()
    private val cornerRadius = 2f.dp

    init {
        id = generateViewId()
        setWillNotDraw(false)
        addView(imageView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    fun configure(account: MAccount?) {
        cardNft =
            account?.accountId?.let { activeAccountId ->
                WGlobalStorage.getCardBackgroundNft(activeAccountId)
                    ?.let { ApiNft.fromJson(it) }
            }
        cardNft?.metadata?.cardImageUrl(true)?.let { url ->
            imageView.set(Content.ofUrl(url))
            val colors = cardNft?.metadata?.mtwCardColors ?: return@let
            updateMiniPlaceholderColors(colors.first, colors.second)
            isGone = false
        } ?: run {
            imageView.clear()
            isGone = true
        }
    }

    fun updateMiniPlaceholderColors(primaryColor: Int, secondaryColor: Int) {
        this.primaryColor = primaryColor
        this.secondaryColor = secondaryColor
        primaryPaint.color = primaryColor
        secondaryPaint.color = secondaryColor
        secondaryPaint.alpha = (255 * 0.6f).toInt()
        invalidate()
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        drawMiniPlaceholders(canvas)
    }

    private fun drawMiniPlaceholders(canvas: Canvas) {
        if (primaryColor == 0 && secondaryColor == 0) return

        val centerX = width / 2f

        val v1Width = 16f.dp
        val v1Height = 1.5f.dp
        val v1Top = 3f.dp
        rect.set(
            centerX - v1Width / 2,
            v1Top,
            centerX + v1Width / 2,
            v1Top + v1Height
        )
        canvas.drawRoundRect(rect, cornerRadius, cornerRadius, primaryPaint)

        val v2Width = 5f.dp
        val v2Height = 1.2f.dp
        val v2Top = 6.7f.dp
        rect.set(
            centerX - v2Width / 2,
            v2Top,
            centerX + v2Width / 2,
            v2Top + v2Height
        )
        canvas.drawRoundRect(rect, cornerRadius, cornerRadius, secondaryPaint)

        val v3Width = 7f.dp
        val v3Height = 1.2f.dp
        val v3Top = 10.8f.dp
        rect.set(
            centerX - v3Width / 2,
            v3Top,
            centerX + v3Width / 2,
            v3Top + v3Height
        )
        canvas.drawRoundRect(rect, cornerRadius, cornerRadius, secondaryPaint)
    }
}
