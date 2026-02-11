package org.mytonwallet.app_air.uiassets.viewControllers.hiddenNFTs.cells

import android.annotation.SuppressLint
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.NftStore

@SuppressLint("ViewConstructor")
class HiddenNFTsItemCell(
    recyclerView: RecyclerView,
    private val onSelect: ((nft: ApiNft) -> Unit)
) : WCell(recyclerView.context, LayoutParams(MATCH_PARENT, 60.dp)),
    WThemedView {

    private lateinit var nft: ApiNft

    private val imageView: WCustomImageView by lazy {
        val img = WCustomImageView(context)
        img
    }

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl.setSingleLine()
        lbl.ellipsize = TextUtils.TruncateAt.END
        lbl
    }

    private val subtitleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(14f)
        lbl.setSingleLine()
        lbl.ellipsize = TextUtils.TruncateAt.END
        lbl
    }

    private val switchView: WSwitch by lazy {
        val sw = WSwitch(context)
        sw.setOnCheckedChangeListener { _, isChecked ->
            setNftVisibility(isChecked)
        }
        sw
    }
    private val hideButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.SECONDARY)
        btn.setOnClickListener {
            setNftVisibility(NftStore.nftData?.blacklistedNftAddresses?.contains(nft.address) == true)
            updateHideButtonText()
        }
        btn
    }
    private val rightView = WFrameLayout(context)

    override fun setupViews() {
        super.setupViews()

        addView(imageView, ViewGroup.LayoutParams(48.dp, 48.dp))
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(rightView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toCenterY(imageView)
            toStart(imageView, 16f)
            toCenterY(rightView)
            toEnd(rightView, 20f)
            toTop(titleLabel, 8f)
            toStart(titleLabel, 76f)
            endToStart(titleLabel, rightView, 8f)
            toBottom(subtitleLabel, 8f)
            toStart(subtitleLabel, 76f)
            endToStart(subtitleLabel, rightView, 8f)
        }

        setOnClickListener {
            onSelect(nft)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        if (nft.isHidden == true) {
            addRippleEffect(
                WColor.SecondaryBackground.color,
                0f,
                if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
            )
        }
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var isLast = false
    fun configure(
        nft: ApiNft,
        isLast: Boolean,
        showSeparator: Boolean,
    ) {
        this.nft = nft
        this.isLast = isLast
        nft.thumbnail?.let {
            imageView.set(Content.ofUrl(it))
        } ?: run {
            imageView.setImageDrawable(null)
        }
        nft.name?.let {
            titleLabel.text = it
        } ?: run {
            titleLabel.text =
                SpannableStringBuilder(nft.address.formatStartEndAddress()).apply {
                    styleDots()
                }
        }
        subtitleLabel.text =
            if (nft.isStandalone()) LocaleController.getString("Standalone NFT") else nft.collectionName
        if (nft.isHidden == true) {
            if (switchView.parent == null) {
                rightView.removeView(hideButton)
                rightView.addView(switchView)
            }
            switchView.isChecked = !nft.shouldHide()
        } else {
            if (hideButton.parent == null) {
                rightView.removeView(switchView)
                rightView.addView(hideButton, LayoutParams(60.dp, WRAP_CONTENT))
            }
            updateHideButtonText()
        }

        updateTheme()
    }

    private fun setNftVisibility(visible: Boolean) {
        if (visible) {
            NftStore.showNft(nft)
        } else {
            NftStore.hideNft(nft)
        }
    }

    private fun updateHideButtonText() {
        hideButton.setText(
            LocaleController.getString(
                if (NftStore.nftData?.blacklistedNftAddresses?.contains(nft.address) == true)
                    "Show"
                else
                    "Hide"
            )
        )
    }
}
