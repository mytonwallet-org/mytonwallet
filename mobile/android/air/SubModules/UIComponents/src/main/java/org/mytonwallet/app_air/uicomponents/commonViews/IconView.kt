package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import androidx.annotation.DrawableRes
import androidx.core.content.ContextCompat
import androidx.core.graphics.toColorInt
import androidx.core.view.setPadding
import com.facebook.drawee.drawable.ScalingUtils
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.GradientDrawables
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WActivityImageView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.utils.gradientColors
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@Deprecated("use WCustomImageView")
@SuppressLint("ViewConstructor")
class IconView(
    context: Context,
    val viewSize: Int = 48.dp,
    val chainSize: Int = 16.dp,
) : WView(context) {

    private val activityImageView: WActivityImageView by lazy {
        WActivityImageView(context).apply {
            chainSize = this@IconView.chainSize
        }
    }

    private val gradientDrawableCache = mutableMapOf<String, GradientDrawable>()
    private val transactionGradientCache = mutableMapOf<ApiTransactionType?, GradientDrawable>()
    private val swapGradientCache = mutableMapOf<MApiTransaction.UIStatus, GradientDrawable>()
    private var failedTransactionDrawable: GradientDrawable? = null

    init {
        isFocusable = false
        isClickable = false

        addView(activityImageView, LayoutParams(viewSize, viewSize))

        setConstraints {
            toTop(activityImageView)
            toStart(activityImageView)
            toBottom(activityImageView)
        }

        updateTheme()
    }

    fun setSize(size: Int) {
        activityImageView.layoutParams.apply {
            width = size
            height = size
        }

        requestLayout()
    }

    fun updateTheme() {
        clearCache()
    }

    fun config(account: MAccount, padding: Int = 10.dp) {
        val address = account.firstAddress ?: ""
        activityImageView.imageView.background = getCachedGradientDrawable(address.gradientColors)

        activityImageView.imageView.setPadding(padding)
        activityImageView.imageView.setImageDrawable(
            ContextCompat.getDrawable(
                context,
                R.drawable.ic_address
            )
        )
    }

    fun config(transaction: MApiTransaction.Transaction) {
        val iconRes = transaction.type?.getIcon() ?: if (transaction.isIncoming) {
            org.mytonwallet.app_air.walletcontext.R.drawable.ic_act_received
        } else {
            org.mytonwallet.app_air.walletcontext.R.drawable.ic_act_sent
        }

        val subImageAnimation = if (transaction.isLocal() || transaction.isPending()) {
            if (transaction.isIncoming) {
                if (ThemeManager.isDark)
                    R.raw.clock_dark_orange
                else
                    R.raw.clock_light_orange
            } else {
                if (ThemeManager.isDark)
                    R.raw.clock_dark_gray
                else
                    R.raw.clock_light_gray
            }
        } else 0

        activityImageView.set(
            Content(
                image = Content.Image.Res(iconRes),
                subImageRes = if (transaction.status == ApiTransactionStatus.FAILED) {
                    if (ThemeManager.isDark)
                        R.drawable.ic_failed_dark
                    else
                        R.drawable.ic_failed
                } else 0,
                subImageAnimation = subImageAnimation,
                scaleType = ScalingUtils.ScaleType.FIT_X
            )
        )

        activityImageView.imageView.setPadding(viewSize / 4)
        activityImageView.imageView.background = getCachedTransactionGradientDrawable(transaction)
    }

    fun config(swap: MApiTransaction.Swap) {
        val subImageAnimation = if (swap.isInProgress) {
            if (ThemeManager.isDark)
                R.raw.clock_dark_gray
            else
                R.raw.clock_light_gray
        } else 0

        activityImageView.set(
            Content(
                image = Content.Image.Res(
                    org.mytonwallet.app_air.walletcontext.R.drawable.ic_act_swap
                ),
                subImageRes = 0,
                subImageAnimation = subImageAnimation
            )
        )

        activityImageView.imageView.setPadding(viewSize / 4)
        activityImageView.imageView.background = getCachedSwapGradientDrawable(swap)
    }

    fun config(
        walletToken: MTokenBalance,
        alwaysShowChain: Boolean = false,
        showPercentBadge: Boolean = false
    ) {
        activityImageView.imageView.setPadding(0)
        val token = TokenStore.getToken(walletToken.token)

        if (token != null) {
            val correctTokenToShow =
                if (token.slug == STAKE_SLUG)
                    TokenStore.getToken(TONCOIN_SLUG) ?: token else token
            activityImageView.set(Content.of(correctTokenToShow, alwaysShowChain, showPercentBadge))
        } else {
            activityImageView.clear()
        }
    }

    fun config(token: MToken?, alwaysShowChain: Boolean = true) {
        if (token != null) {
            activityImageView.set(Content.of(token, alwaysShowChain))
        } else {
            activityImageView.clear()
        }
    }

    fun config(
        @DrawableRes iconDrawableRes: Int?,
        gradientStartColor: String?,
        gradientEndColor: String?,
    ) {
        activityImageView.imageView.setPadding(17.dp)

        iconDrawableRes?.let { res ->
            activityImageView.imageView.setImageDrawable(ContextCompat.getDrawable(context, res))
        }

        val startColor = gradientStartColor?.toColorInt() ?: 0
        val endColor = gradientEndColor?.toColorInt() ?: 0
        activityImageView.imageView.background =
            getCachedGradientDrawable(intArrayOf(startColor, endColor))
    }

    fun setImageDrawable(drawable: Drawable?, padding: Int = 0) {
        activityImageView.imageView.setPadding(padding)
        activityImageView.imageView.setImageDrawable(drawable)
        activityImageView.imageView.background = null
    }

    private fun getCachedGradientDrawable(colors: IntArray): GradientDrawable {
        val key = colors.contentHashCode().toString()
        return gradientDrawableCache.getOrPut(key) {
            GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, colors).apply {
                shape = GradientDrawable.OVAL
            }
        }
    }

    private fun getCachedTransactionGradientDrawable(transaction: MApiTransaction.Transaction): GradientDrawable {
        if (transaction.status == ApiTransactionStatus.FAILED) {
            if (failedTransactionDrawable == null) {
                failedTransactionDrawable = GradientDrawables.redDrawable
            }
            return failedTransactionDrawable!!
        }
        return transactionGradientCache.getOrPut(transaction.type) {
            getTransactionGradientDrawable(transaction.type, transaction.isIncoming)
        }
    }

    private fun getCachedSwapGradientDrawable(swap: MApiTransaction.Swap): GradientDrawable {
        val uiStatus = swap.cex?.status?.uiStatus ?: swap.status.uiStatus
        return swapGradientCache.getOrPut(uiStatus) {
            getSwapGradientDrawable(uiStatus)
        }
    }

    private fun getTransactionGradientDrawable(
        type: ApiTransactionType?,
        isIncoming: Boolean
    ): GradientDrawable {
        return when (type) {
            ApiTransactionType.STAKE -> GradientDrawables.purpleDrawable

            ApiTransactionType.UNSTAKE,
            ApiTransactionType.LIQUIDITY_WITHDRAW,
            ApiTransactionType.MINT,
            ApiTransactionType.EXCESS,
            ApiTransactionType.BOUNCED -> GradientDrawables.greenDrawable

            ApiTransactionType.CONTRACT_DEPLOY,
            ApiTransactionType.CALL_CONTRACT,
            ApiTransactionType.DNS_CHANGE_ADDRESS,
            ApiTransactionType.DNS_CHANGE_SITE,
            ApiTransactionType.DNS_CHANGE_SUBDOMAINS,
            ApiTransactionType.DNS_CHANGE_STORAGE,
            ApiTransactionType.DNS_DELETE,
            ApiTransactionType.DNS_RENEW -> GradientDrawables.grayDrawable

            ApiTransactionType.BURN -> GradientDrawables.redDrawable

            ApiTransactionType.UNSTAKE_REQUEST,
            ApiTransactionType.LIQUIDITY_DEPOSIT,
            ApiTransactionType.AUCTION_BID,
            ApiTransactionType.NFT_TRADE -> GradientDrawables.blueDrawable

            null -> if (isIncoming) {
                GradientDrawables.greenDrawable
            } else {
                GradientDrawables.blueDrawable
            }
        }
    }

    private fun getSwapGradientDrawable(uiStatus: MApiTransaction.UIStatus): GradientDrawable {
        return when (uiStatus) {
            MApiTransaction.UIStatus.HOLD -> GradientDrawables.grayDrawable
            MApiTransaction.UIStatus.PENDING,
            MApiTransaction.UIStatus.COMPLETED -> GradientDrawables.blueDrawable

            MApiTransaction.UIStatus.EXPIRED,
            MApiTransaction.UIStatus.FAILED -> GradientDrawables.redDrawable
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        clearCache()
    }

    private fun clearCache() {
        gradientDrawableCache.clear()
        transactionGradientCache.clear()
        swapGradientCache.clear()
        failedTransactionDrawable = null
    }
}
