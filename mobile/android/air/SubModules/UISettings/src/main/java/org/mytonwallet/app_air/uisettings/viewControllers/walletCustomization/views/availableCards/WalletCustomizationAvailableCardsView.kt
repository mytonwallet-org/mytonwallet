package org.mytonwallet.app_air.uisettings.viewControllers.walletCustomization.views.availableCards

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.content.ContextCompat
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt


@SuppressLint("ViewConstructor")
open class WalletCustomizationAvailableCardsView(
    context: Context,
    private val totalWidth: Int,
) : FrameLayout(context), WThemedView, WRecyclerViewAdapter.WRecyclerViewDataSource {

    companion object {
        val AVAILABLE_CARD_CELL = WCell.Type(1)

        private fun calculateNoOfColumns(totalWidth: Int): Int {
            return max(
                2,
                ((totalWidth - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp) - 16.dp) / 100.dp
            )
        }

        private fun cellWidth(totalWidth: Int): Int {
            return ((totalWidth - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp) - 16.dp) /
                calculateNoOfColumns(totalWidth)
        }

        fun calculateHeight(totalWidth: Int, itemsCount: Int): Int {
            return 67.dp +
                (ceil(itemsCount / calculateNoOfColumns(totalWidth).toFloat()) *
                    (cellWidth(totalWidth) / WalletCustomizationAvailableCardCell.RATIO + 4.dp)).roundToInt()
        }

        const val DEFAULT_HEIGHT = 242
    }

    var onCardChanged: ((accountId: String, nft: ApiNft?) -> Unit)? = null
    var tintColor = 0

    private val topDrawable = ContextCompat.getDrawable(
        context,
        org.mytonwallet.app_air.uisettings.R.drawable.ic_arrow_tooltip_top
    )
    private val topImageView = AppCompatImageView(context).apply {
        setImageDrawable(topDrawable)
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(14f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 20f)
        setTextColor(WColor.SecondaryText)
        text = LocaleController.getString("Select the card stored in this wallet:")
    }

    private val rvAdapter = WRecyclerViewAdapter(WeakReference(this), arrayOf(AVAILABLE_CARD_CELL))

    private val recyclerView by lazy {
        WRecyclerView(context).apply {
            adapter = rvAdapter
            val spanSize = totalWidth - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp - 16.dp
            val layoutManager = GridLayoutManager(context, spanSize)
            layoutManager.spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
                override fun getSpanSize(position: Int): Int {
                    return cellWidth()
                }
            }
            layoutManager.isSmoothScrollbarEnabled = true
            setLayoutManager(layoutManager)
            overScrollMode = OVER_SCROLL_NEVER
            itemAnimator = null
            setPadding(8.dp, 0, 8.dp, 0)
        }
    }

    private val roundDrawable by lazy {
        RoundProgressDrawable(13.dp, 1f.dp).apply {
            color = WColor.SecondaryText.color
        }
    }

    private val progressView by lazy {
        AppCompatImageView(context).apply {
            id = generateViewId()
            setImageDrawable(roundDrawable)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            alpha = 0f
            setPaddingDp(5.5f)
        }
    }

    private val animationView: WAnimationView by lazy {
        WAnimationView(context).apply {
            alpha = 0f
        }
    }
    private val emptyView by lazy {
        val emptyTitle = WLabel(context).apply {
            setStyle(14f, WFont.Medium)
            setTextColor(WColor.PrimaryText)
            gravity = Gravity.CENTER
            text = LocaleController.getString("You don’t have any cards to customize yet")
            alpha = 0f
        }
        val emptyDescription = WLabel(context).apply {
            setStyle(14f)
            setTextColor(WColor.SecondaryText)
            gravity = Gravity.CENTER
            text =
                LocaleController.getString("MyTonWallet Cards can be installed for wallets and displayed on the home screen and in the wallet list.")
            alpha = 0f
        }
        WView(context).apply {
            addView(animationView, LayoutParams(110.dp, 110.dp))
            animationView.apply {
                animationView.play(R.raw.animation_empty, true, onStart = {
                    animationView.fadeIn()
                    emptyTitle.fadeIn()
                    emptyDescription.fadeIn()
                })
                Handler(Looper.getMainLooper()).postDelayed({
                    if (emptyTitle.alpha == 0f) {
                        animationView.fadeIn()
                        emptyTitle.fadeIn()
                        emptyDescription.fadeIn()
                    }
                }, 3000)
            }
            addView(emptyTitle, LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(emptyDescription, LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            setConstraints {
                toTop(animationView, 7f)
                toCenterX(animationView)
                topToBottom(emptyTitle, animationView, 15f)
                toCenterX(emptyTitle, 16f)
                topToBottom(emptyDescription, emptyTitle, 16f)
                toCenterX(emptyDescription, 16f)
            }
        }
    }

    private var accountId: String? = null
    private var cards: List<ApiNft?>? = null
    private var selectedCardAddress: String? = null

    private fun calculateNoOfColumns(): Int {
        return calculateNoOfColumns(totalWidth)
    }

    private fun cellWidth(): Int {
        return cellWidth(totalWidth)
    }

    private val contentView: FrameLayout by lazy {
        FrameLayout(context).apply {
            addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                topMargin = 14.dp
            })
            addView(recyclerView, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = 47.dp
            })
            addView(progressView, LayoutParams(24.dp, 24.dp).apply {
                gravity = Gravity.CENTER
            })
            addView(emptyView, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            })
        }
    }

    private val containerView: FrameLayout by lazy {
        FrameLayout(context).apply {
            addView(contentView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    init {
        addView(topImageView, LayoutParams(32.dp, 16.dp).apply {
            topMargin = 3.dp
            gravity = Gravity.CENTER_HORIZONTAL
        })
        addView(containerView, LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
            topMargin = 18.dp
        })
        updateTheme()
    }

    override fun updateTheme() {
        containerView.setBackgroundColor(WColor.Background.color, 16f.dp)
        topDrawable?.setTint(WColor.Background.color)
        roundDrawable.color = WColor.SecondaryText.color
    }

    fun configure(accountId: String, cards: List<ApiNft?>?) {
        val isAccountChanged = accountId != this.accountId
        this.accountId = accountId
        this.cards = cards
        this.selectedCardAddress = WGlobalStorage.getCardBackgroundNftAddress(accountId)
        titleLabel.animate().cancel()
        recyclerView.animate().cancel()
        emptyView.animate().cancel()
        progressView.animate().cancel()
        cards?.let {
            val rows = ceil(cards.size / calculateNoOfColumns().toFloat())
            val itemsHeight =
                (rows * (cellWidth() / WalletCustomizationAvailableCardCell.RATIO + 4.dp)).roundToInt()
            recyclerView.updateLayoutParams {
                height = itemsHeight
            }
            rvAdapter.reloadData()
            if (isAccountChanged) {
                progressView.alpha = 0f
                if (cards.isEmpty()) {
                    titleLabel.alpha = 0f
                    recyclerView.alpha = 0f
                    emptyView.alpha = 1f
                } else {
                    titleLabel.alpha = 1f
                    recyclerView.alpha = 1f
                    emptyView.alpha = 0f
                }
            } else {
                if (cards.isEmpty()) {
                    titleLabel.fadeOut()
                    recyclerView.fadeOut()
                    emptyView.fadeIn()
                } else {
                    titleLabel.fadeIn()
                    recyclerView.fadeIn()
                    emptyView.fadeOut()
                }
                progressView.fadeOut()
            }
        } ?: run {
            progressView.alpha = 1f
            titleLabel.alpha = 0f
            recyclerView.alpha = 0f
            emptyView.alpha = 0f
        }
    }

    fun reload() {
        rvAdapter.reloadData()
    }

    fun setContentAlpha(alpha: Float) {
        contentView.alpha = alpha
    }

    fun reloadSelectedItem() {
        cards?.indexOfFirst { it?.address == selectedCardAddress }?.let {
            if (it > -1)
                rvAdapter.notifyItemChanged(it)
        }
    }

    fun onDestroy() {
        recyclerView.onDestroy()
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return cards?.size ?: 0
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return AVAILABLE_CARD_CELL
    }

    override fun recyclerViewCellView(
        rv: RecyclerView,
        cellType: WCell.Type
    ): WCell {
        return WalletCustomizationAvailableCardCell(context, cellWidth()).apply {
            onTap = { accountId, nft ->
                WGlobalStorage.setCardBackgroundNft(accountId, nft?.toDictionary())
                selectedCardAddress = nft?.address
                rvAdapter.reloadData()
                onCardChanged?.invoke(accountId, nft)
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val card = cards?.getOrNull(indexPath.row)
        (cellHolder.cell as WalletCustomizationAvailableCardCell).apply {
            tintColor = this@WalletCustomizationAvailableCardsView.tintColor
            configure(
                accountId!!,
                card,
                BalanceStore.totalBalanceInBaseCurrency(accountId!!)
                    ?.toBigInteger(WalletCore.baseCurrency.decimalsCount) ?: BigInteger.ZERO,
                selectedCardAddress == card?.address
            )
        }
    }

}
