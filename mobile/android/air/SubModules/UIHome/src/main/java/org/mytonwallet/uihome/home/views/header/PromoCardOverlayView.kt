package org.mytonwallet.uihome.home.views.header

import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import com.facebook.drawee.drawable.ScalingUtils
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.moshi.ApiPromotion
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.uihome.R

class PromoCardOverlayView(context: Context) : FrameLayout(context) {

    companion object {
        private const val CARD_REF_WIDTH = 345.0
        private const val CARD_REF_HEIGHT = 200.0
    }

    private var currentPromotion: ApiPromotion? = null

    private val bgImageView = AppCompatImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
        setImageResource(R.drawable.promo_card_bg)
    }

    private val mascotView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(0f)
        defaultPlaceholder = Content.Placeholder.Color(WColor.Transparent)
    }

    private val overlayImageView = AppCompatImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
        setImageResource(R.drawable.promo_card_overlay)
    }

    init {
        clipChildren = false
        addView(bgImageView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(mascotView, LayoutParams(0, 0))
        addView(overlayImageView, LayoutParams(MATCH_PARENT, MATCH_PARENT))

        mascotView.setOnClickListener {
            val promo = currentPromotion ?: return@setOnClickListener
            when (promo.cardOverlay.onClickAction) {
                "openPromotionModal" -> {
                    WalletCore.notifyEvent(WalletEvent.ShowPromotion(promo))
                }

                "openMintCardModal" -> {
                    val url = ExplorerHelpers.getMtwCardsUrl(
                        AccountStore.activeAccount?.network ?: MBlockchainNetwork.MAINNET
                    )
                    WalletCore.notifyEvent(WalletEvent.OpenUrl(url))
                }
            }
        }
    }

    fun updatePromotion(accountId: String?) {
        val id = accountId ?: ""
        val promoJson = WGlobalStorage.getActivePromotion(id)
        if (promoJson == null) {
            currentPromotion = null
            visibility = GONE
            return
        }

        val promo = ApiPromotion.fromJson(promoJson)
        if (promo == null || promo.kind != "cardOverlay") {
            currentPromotion = null
            visibility = GONE
            return
        }

        currentPromotion = promo
        visibility = VISIBLE
        updateMascot(promo.cardOverlay.mascotIcon)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        currentPromotion?.cardOverlay?.mascotIcon?.let { updateMascotLayout(it, w, h) }
    }

    private fun updateMascot(mascotIcon: ApiPromotion.CardOverlay.MascotIcon?) {
        if (mascotIcon == null || mascotIcon.url.isBlank()) {
            mascotView.visibility = GONE
            return
        }

        mascotView.visibility = VISIBLE
        mascotView.set(
            Content(
                image = Content.Image.Url(mascotIcon.url),
                scaleType = ScalingUtils.ScaleType.FIT_CENTER,
            )
        )

        mascotView.rotation = mascotIcon.rotation.toFloat()

        if (width > 0 && height > 0) {
            updateMascotLayout(mascotIcon, width, height)
        }
    }

    private fun updateMascotLayout(
        mascotIcon: ApiPromotion.CardOverlay.MascotIcon,
        cardW: Int,
        cardH: Int
    ) {
        val scaledWidth = (cardW * mascotIcon.width / CARD_REF_WIDTH).toInt()
        val scaledHeight = (cardH * mascotIcon.height / CARD_REF_HEIGHT).toInt()
        val rightOffset = (cardW * mascotIcon.right / CARD_REF_WIDTH).toInt()
        val topOffset = (cardH * mascotIcon.top / CARD_REF_HEIGHT).toInt()

        val lp = mascotView.layoutParams as LayoutParams
        lp.width = scaledWidth
        lp.height = scaledHeight
        lp.gravity = Gravity.TOP or Gravity.END
        lp.topMargin = -topOffset
        lp.marginEnd = -rightOffset
        mascotView.layoutParams = lp
    }

    fun fadeIn(duration: Long = AnimationConstants.QUICK_ANIMATION) {
        bgImageView.fadeIn(duration)
        mascotView.fadeIn(duration)
        overlayImageView.fadeIn(duration)
    }

    fun fadeOut(duration: Long = AnimationConstants.QUICK_ANIMATION) {
        bgImageView.fadeOut(duration)
        mascotView.fadeOut(duration)
        overlayImageView.fadeOut(duration)
    }
}
