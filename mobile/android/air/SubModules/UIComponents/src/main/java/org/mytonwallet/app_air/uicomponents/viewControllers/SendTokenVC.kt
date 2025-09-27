package org.mytonwallet.app_air.uicomponents.viewControllers

import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListAdapter
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import java.math.BigInteger
import kotlin.math.max

class SendTokenVC(
    context: Context,
    private val selectedChain: MBlockchain? = null
) : WViewController(context),
    CustomListAdapter.ItemClickListener {
    private var uiItems = emptyList<BaseListItem>()

    private val rvSwapTokenSelectorAdapter = CustomListAdapter()

    override val shouldDisplayBottomBar = true

    private val recyclerView = RecyclerView(context).apply {
        adapter = rvSwapTokenSelectorAdapter
        id = View.generateViewId()
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
        clipToPadding = false
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
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
    }

    override fun setupViews() {
        super.setupViews()

        rvSwapTokenSelectorAdapter.setOnItemClickListener(this)

        buildUiItems()
        setNavTitle(LocaleController.getString("Currency"))
        setupNavBar(true)

        view.addView(recyclerView, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0))
        view.setConstraints {
            toCenterX(recyclerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
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

        recyclerView.setPadding(
            0,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.Companion.DEFAULT_HEIGHT.dp,
            0,
            max(0, nav - ime)
        )
    }

    private fun buildUiItems() {
        val balances =
            AccountStore.assetsAndActivityData.getAllTokens(ignorePriorities = true)

        val uiItems =
            mutableListOf<BaseListItem>(Item.ListTitle(LocaleController.getString("Choose Currency to Send")))
        for (balance in balances) {
            if (balance.amountValue == BigInteger.ZERO) continue
            val asset = TokenStore.getToken(balance.token) ?: continue
            if (selectedChain == null || asset.chain == selectedChain.name)
                uiItems.add(
                    asset(
                        asset = MApiSwapAsset.from(asset),
                        balance = balance.amountValue,
                        separator = true
                    )
                )
        }

        this.uiItems = uiItems
        this.rvSwapTokenSelectorAdapter.submitList(uiItems)
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

    private fun asset(
        asset: MApiSwapAsset,
        balance: BigInteger,
        separator: Boolean
    ): Item.IconDualLine {
        return Item.IconDualLine(
            image = Content.Companion.of(asset),
            title = asset.name ?: asset.symbol,
            subtitle = if (balance > BigInteger.ZERO) {
                balance.toString(
                    decimals = asset.decimals,
                    currency = asset.symbol ?: "",
                    currencyDecimals = balance.smartDecimalsCount(asset.decimals),
                    showPositiveSign = false,
                    roundUp = false
                )
            } else {
                asset.symbol
            },
            allowSeparator = separator,
            id = asset.slug,
            isSensitiveData = WGlobalStorage.getIsSensitiveDataProtectionOn(),
            clickable = Item.Clickable.Token(asset)
        )
    }


}
