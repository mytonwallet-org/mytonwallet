package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.view.isGone
import com.facebook.drawee.drawable.ScalingUtils
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

class CardThumbnailView(context: Context) : WFrameLayout(context) {

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
    private val borderPaint: Paint by lazy {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = Color.WHITE
            strokeWidth = 1f.dp
        }
    }

    private var primaryColor: Int = 0
    private var secondaryColor: Int = 0
    var showBorder: Boolean = false
        set(value) {
            field = value
            imageView.layoutParams = (imageView.layoutParams as MarginLayoutParams).apply {
                val borderWidth = borderPaint.strokeWidth.toInt()
                leftMargin = borderWidth
                topMargin = borderWidth
                rightMargin = borderWidth
                bottomMargin = borderWidth
            }
            invalidate()
        }

    private val rect = RectF()
    private val cornerRadius = 2f.dp
    private val borderRadius = 3f.dp

    init {
        setWillNotDraw(false)
        addView(imageView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    fun configure(account: MAccount?, showDefaultCard: Boolean = false) {
        cardNft =
            account?.accountId?.let { activeAccountId ->
                WGlobalStorage.getCardBackgroundNft(activeAccountId)
                    ?.let { ApiNft.fromJson(it) }
            }
        cardNft?.metadata?.cardImageUrl(true)?.let { url ->
            imageView.set(
                Content.ofUrl(url).copy(scaleType = ScalingUtils.ScaleType.FIT_XY)
            )
            val colors = cardNft?.metadata?.mtwCardColors ?: return@let
            updateMiniPlaceholderColors(colors.first, colors.second)
            isGone = false
        } ?: run {
            imageView.clear()
            if (showDefaultCard) {
                imageView.set(
                    Content(
                        Content.Image.Res(org.mytonwallet.app_air.uicomponents.R.drawable.img_card),
                        scaleType = ScalingUtils.ScaleType.FIT_XY
                    ),
                )
                updateMiniPlaceholderColors(Color.WHITE, Color.WHITE)
            } else {
                isGone = true
            }
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
        drawBorder(canvas)
    }

    private fun drawBorder(canvas: Canvas) {
        if (!showBorder) return
        val halfStroke = borderPaint.strokeWidth / 2
        rect.set(halfStroke, halfStroke, width - halfStroke, height - halfStroke)
        canvas.drawRoundRect(rect, borderRadius, borderRadius, borderPaint)
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
