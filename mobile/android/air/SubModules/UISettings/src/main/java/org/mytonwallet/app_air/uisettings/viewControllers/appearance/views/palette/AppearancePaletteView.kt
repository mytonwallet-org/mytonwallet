package org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.palette

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.helper.widget.Flow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.palette.ImagePaletteHelpers
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.NftAccentColors
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

@SuppressLint("ViewConstructor")
class AppearancePaletteView(
    context: Context,
    private val showUnlockButton: Boolean
) : WView(context), WThemedView {
    var onPaletteSelected:
        ((
            accountId: String,
            nftAccentId: Int?,
            state: AppearancePaletteItemView.State, nft: ApiNft?
        ) -> Unit)? = null

    var overrideTintColor: Int? = null

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.text = LocaleController.getString("Palette")
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    private val smallWidthOffset = 8
    private val horizontalGap = 12.dp
    private val itemWidth = 34.dp
    private val flowHelper = Flow(context).apply {
        id = generateViewId()
        setWrapMode(Flow.WRAP_CHAIN)
        setHorizontalStyle(Flow.CHAIN_PACKED)
        setHorizontalBias(0f)
        setHorizontalGap(horizontalGap)
        setVerticalGap(horizontalGap)
    }

    var paletteItemViews: List<AppearancePaletteItemView>
    private val palettesView = WView(context).apply {
        val viewIds = IntArray(NftAccentColors.light.size + 1)
        var paletteItemViews = mutableListOf<AppearancePaletteItemView>()
        (listOf(null) + (0 until NftAccentColors.light.size).toList()).forEachIndexed { index, nftAccentId ->
            val itemView =
                AppearancePaletteItemView(context, nftAccentId, onTap = { nftAccentId, state ->
                    val accountId = accountId ?: return@AppearancePaletteItemView
                    onPaletteSelected?.invoke(
                        accountId,
                        nftAccentId,
                        state,
                        nftsByColorIndex[nftAccentId]?.firstOrNull()
                    )
                })
            paletteItemViews.add(itemView)
            addView(itemView, LayoutParams(itemWidth, itemWidth))
            viewIds[index] = itemView.id
        }
        this@AppearancePaletteView.paletteItemViews = paletteItemViews
        addView(flowHelper, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        flowHelper.referencedIds = viewIds
    }

    private val separatorView = WBaseView(context)

    private val unlockButton = WLabel(context).apply {
        setPaddingDp(20, 16, 20, 16)
        setStyle(16f)
        text = LocaleController.getString("Unlock New Palettes")
        setOnClickListener {
            WalletCore.notifyEvent(WalletEvent.OpenUrl("https://cards.mytonwallet.io"))
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel)
        addView(palettesView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        if (showUnlockButton) {
            addView(separatorView, LayoutParams(MATCH_PARENT, ViewConstants.SEPARATOR_HEIGHT))
            addView(unlockButton, LayoutParams(MATCH_PARENT, 56.dp))
        }

        setConstraints {
            toTop(titleLabel, 16f)
            toStart(titleLabel, 20f)
            topToBottom(palettesView, titleLabel, 17f)
            toCenterX(palettesView)
            if (showUnlockButton) {
                topToBottom(separatorView, palettesView, 16f)
                toCenterX(separatorView, 20f)
                topToBottom(unlockButton, separatorView)
                toBottom(unlockButton)
            } else {
                toBottom(palettesView, 16f)
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp
        )
        titleLabel.setTextColor(overrideTintColor ?: WColor.Tint.color)
        if (showUnlockButton) {
            unlockButton.setTextColor(overrideTintColor ?: WColor.Tint.color)
            separatorView.setBackgroundColor(WColor.Separator.color)
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        // Align palette items with label and button
        val numberOfItems =
            (width + smallWidthOffset - 40.dp + horizontalGap) / (itemWidth + horizontalGap)
        val additionalSpace =
            width + smallWidthOffset - 40.dp - numberOfItems * (itemWidth + horizontalGap) + horizontalGap
        flowHelper.setMaxElementsWrap(numberOfItems)
        flowHelper.setHorizontalGap(horizontalGap + additionalSpace / numberOfItems)
        palettesView.post {
            palettesView.requestLayout()
        }
    }

    private var accountId: String? = null
    val nftsByColorIndex = mutableMapOf<Int, MutableList<ApiNft>>()
    fun updatePaletteView(accountId: String, mtwNfts: List<ApiNft>?) {
        this.accountId = accountId
        if (mtwNfts == null) {
            paletteItemViews.forEach { item ->
                item.configure(AppearancePaletteItemView.State.LOADING)
            }
            return
        }
        var pendingExtractions = mtwNfts.size

        nftsByColorIndex.clear()

        if (mtwNfts.isEmpty()) {
            reloadViews()
            return
        }

        mtwNfts.forEach { nft ->
            ImagePaletteHelpers.extractPaletteFromNft(nft) { colorIndex ->
                colorIndex?.let {
                    nftsByColorIndex.getOrPut(it) { mutableListOf() }.add(nft)
                }
                pendingExtractions--

                if (pendingExtractions == 0) {
                    reloadViews()
                    reorderPaletteItems()
                }
            }
        }
    }

    private fun reorderPaletteItems() {
        val sortedIds = paletteItemViews.sortedBy { item ->
            when {
                item.nftAccentId == null -> 0
                !nftsByColorIndex[item.nftAccentId].isNullOrEmpty() -> 1
                else -> 2
            }
        }.map { it.id }.toIntArray()

        flowHelper.referencedIds = sortedIds
    }

    fun reloadViews() {
        val accountId = accountId ?: return
        val selectedIndex = WGlobalStorage.getNftAccentColorIndex(accountId)
        if (nftsByColorIndex.isEmpty()) {
            paletteItemViews.forEach { item ->
                val itemIndex = item.nftAccentId
                val isSelected = itemIndex == selectedIndex
                val isLocked = itemIndex != null
                item.configure(if (isLocked) AppearancePaletteItemView.State.LOCKED else if (isSelected) AppearancePaletteItemView.State.SELECTED else AppearancePaletteItemView.State.AVAILABLE)
            }
            return
        }
        paletteItemViews.forEach { item ->
            val itemIndex = item.nftAccentId
            val isSelected = itemIndex == selectedIndex
            val isLocked =
                if (itemIndex == null) false else nftsByColorIndex[itemIndex].isNullOrEmpty()
            item.configure(if (isLocked) AppearancePaletteItemView.State.LOCKED else if (isSelected) AppearancePaletteItemView.State.SELECTED else AppearancePaletteItemView.State.AVAILABLE)
        }
    }
}
