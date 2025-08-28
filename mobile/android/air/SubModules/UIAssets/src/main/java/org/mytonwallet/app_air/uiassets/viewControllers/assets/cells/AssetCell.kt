package org.mytonwallet.app_air.uiassets.viewControllers.assets.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.R
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

@SuppressLint("ViewConstructor")
class AssetCell(
    context: Context,
    val mode: AssetsVC.Mode
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    var onTap: ((transaction: ApiNft) -> Unit)? = null

    private val imageView: WImageView by lazy {
        val img = WImageView(context, 16.dp)
        img
    }

    private val animationView: WAnimationView by lazy {
        val v = WAnimationView(context)
        v.setBackgroundColor(Color.TRANSPARENT, 16f.dp, true)
        v.visibility = GONE
        v
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
        }
    }

    init {
        setPadding((if (mode == AssetsVC.Mode.COMPLETE) 8 else 4).dp)

        addView(imageView, LayoutParams(0, 0))
        if (mode == AssetsVC.Mode.COMPLETE) {
            addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(subtitleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }

        addView(animationView, LayoutParams(0, 0))

        setConstraints {
            toTop(imageView)
            toCenterX(imageView)
            setDimensionRatio(imageView.id, "1:1")
            edgeToEdge(animationView, imageView)
            if (mode == AssetsVC.Mode.COMPLETE) {
                topToBottom(titleLabel, imageView, 8f)
                toCenterX(titleLabel)
                topToBottom(subtitleLabel, titleLabel)
                toCenterX(subtitleLabel)
                toBottom(subtitleLabel)
            } else {
                toBottom(imageView)
            }
        }

        setOnClickListener {
            nft?.let {
                onTap?.invoke(it)
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        addRippleEffect(WColor.SecondaryBackground.color, 16f.dp)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var nft: ApiNft? = null
    fun configure(
        nft: ApiNft,
    ) {
        this.nft = nft
        imageView.loadUrl(nft.thumbnail ?: "")
        if (mode == AssetsVC.Mode.COMPLETE) {
            nft.name?.let {
                titleLabel.text = it
            } ?: run {
                titleLabel.text =
                    SpannableStringBuilder(nft.address.formatStartEndAddress()).apply {
                        updateDotsTypeface()
                    }
            }
            subtitleLabel.text =
                nft.collectionName ?: LocaleController.getString("Standalone NFT")
        }
        if (mode == AssetsVC.Mode.COMPLETE || DevicePerformanceClassifier.isHighClass) {
            animationView.visibility = GONE
            if (nft.metadata?.lottie?.isNotBlank() == true) {
                animationView.visibility = VISIBLE
                animationView.playFromUrl(nft.metadata!!.lottie!!, onStart = {})
            }
        }
        updateTheme()
    }

    fun pauseAnimation() {
        animationView.pauseAnimation()
    }

    fun resumeAnimation() {
        animationView.resumeAnimation()
    }

}
