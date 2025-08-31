package org.mytonwallet.app_air.uicomponents.viewControllers.selector

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import androidx.core.widget.doOnTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListAdapter
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.SwapSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletcontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.math.BigInteger
import kotlin.math.max

@SuppressLint("ViewConstructor")
class TokenSelectorVC(
    context: Context,
    private val titleToShow: String,
    private val assets: List<IApiToken>,
    private val showMyAssets: Boolean = true
) : WViewController(context), WThemedView, CustomListAdapter.ItemClickListener {
    private var uiItems = emptyList<BaseListItem>()

    override val shouldDisplayBottomBar = true

    private val rvTokenSelectorAdapter = TokenSelectorAdapter()

    private val recyclerView: RecyclerView by lazy {
        val rv = RecyclerView(context)
        rv.adapter = rvTokenSelectorAdapter
        rv.id = View.generateViewId()
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv.clipToPadding = false
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE)
                    updateBlurViews(recyclerView)
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0)
                    return
                updateBlurViews(recyclerView)
            }
        })
        rv
    }

    private val searchContainer = FrameLayout(context).apply {
        id = View.generateViewId()
    }

    private val searchEditText = SwapSearchEditText(context)
    private var query: String? = null

    override fun setupViews() {
        super.setupViews()

        rvTokenSelectorAdapter.setOnItemClickListener(this)

        buildUiItems()

        setNavTitle(titleToShow)
        setupNavBar(true)

        searchContainer.addView(searchEditText, ViewGroup.LayoutParams(MATCH_PARENT, 48.dp))
        searchContainer.setPaddingDp(20, 0, 20, 8)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        navigationBar?.addBottomView(searchContainer, 56.dp)

        searchEditText.doOnTextChanged { text, _, _, _ ->
            query = text?.toString()
            buildUiItems()
        }

        view.setConstraints {
            topToBottom(searchContainer, navigationBar!!)
            toCenterX(searchContainer)

            toCenterX(recyclerView)
            toTop(recyclerView)
            toBottom(recyclerView)
        }

        updateTheme()
        insetsUpdated()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        val ime = (window?.imeInsets?.bottom ?: 0)
        val nav = (navigationController?.getSystemBars()?.bottom ?: 0)

        view.setConstraints {
            toCenterX(recyclerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toBottomPx(recyclerView, ime)
        }

        recyclerView.setPadding(
            0,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp +
                56.dp,
            0,
            max(0, nav - ime)
        )
    }

    private fun buildUiItems() {
        val balances =
            AccountStore.assetsAndActivityData.getAllTokens(ignorePriorities = true)

        val search = if (query?.isNotEmpty() == true) query?.lowercase() else null
        val assets = this.assets.filter { token ->
            search?.lowercase()?.let {
                token.name?.lowercase()?.contains(search) == true ||
                    token.symbol?.lowercase()?.contains(search) == true ||
                    token.tokenAddress?.lowercase()?.contains(search) == true
            } != false
        }
        val assetsMap = assets.associateBy { it.slug }

        val used = mutableSetOf<String>()
        val uiItems = mutableListOf<BaseListItem>()
        val tmpAssets = mutableListOf<Item.IconDualLine>()

        if (showMyAssets) {
            for (balance in balances) {
                if (!assetsMap.containsKey(balance.token)) continue
                if (balance.amountValue == BigInteger.ZERO) continue
                val asset = assetsMap[balance.token] ?: continue
                if (!used.add(asset.slug)) continue
                tmpAssets.add(
                    asset(
                        asset = asset,
                        balance = balance.amountValue,
                        separator = true
                    )
                )
            }
            if (tmpAssets.isNotEmpty()) {
                tmpAssets[tmpAssets.size - 1] =
                    tmpAssets[tmpAssets.size - 1].copy(allowSeparator = false)
                uiItems.add(TokenItem.Title(LocaleController.getString("MY")))
                uiItems.addAll(tmpAssets)
            }
            tmpAssets.clear()
        }

        val popularAssets = assets.filter { it.isPopular == true }
        for (asset in popularAssets) {
            if (!used.add(asset.slug)) continue
            tmpAssets.add(asset(asset = asset, balance = null, separator = true))
        }
        if (tmpAssets.isNotEmpty()) {
            tmpAssets[tmpAssets.size - 1] =
                tmpAssets[tmpAssets.size - 1].copy(allowSeparator = false)
            uiItems.add(TokenItem.Title(LocaleController.getString("POPULAR")))
            uiItems.addAll(tmpAssets)
        }
        tmpAssets.clear()


        for (asset in assets) {
            if (!used.add(asset.slug)) continue
            tmpAssets.add(asset(asset = asset, balance = null, separator = true))
        }
        if (tmpAssets.isNotEmpty()) {
            tmpAssets[tmpAssets.size - 1] =
                tmpAssets[tmpAssets.size - 1].copy(allowSeparator = false)
            if (uiItems.isNotEmpty()) {
                uiItems.add(TokenItem.Title(LocaleController.getString("Other")))
            }
            uiItems.addAll(tmpAssets)
        }
        tmpAssets.clear()

        this.uiItems = uiItems
        this.rvTokenSelectorAdapter.submitList(uiItems)
    }

    private var onAssetSelectListener: ((IApiToken) -> Unit)? = null

    fun setOnAssetSelectListener(listener: ((IApiToken) -> Unit)) {
        onAssetSelectListener = listener
    }

    override fun onItemClickToken(
        view: View,
        position: Int,
        item: BaseListItem,
        token: IApiToken
    ) {
        onAssetSelectListener?.invoke(token)
        pop()
    }

    private fun asset(asset: IApiToken, balance: BigInteger?, separator: Boolean) =
        Item.IconDualLine(
            image = Content.of(asset),
            title = asset.name ?: asset.symbol,
            subtitle =
                if (balance != null) {
                    if (balance > BigInteger.ZERO) {
                        balance.toString(
                            decimals = asset.decimals,
                            currency = asset.symbol ?: "",
                            currencyDecimals = balance.smartDecimalsCount(asset.decimals),
                            showPositiveSign = false,
                            roundUp = false
                        )
                    } else {
                        asset.symbol
                    }
                } else {
                    asset.symbol
                },
            allowSeparator = separator,
            id = asset.slug,
            clickable = Item.Clickable.Token(asset),
            isSensitiveData = (balance ?: BigInteger.ZERO) > BigInteger.ZERO
        )

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }
}
