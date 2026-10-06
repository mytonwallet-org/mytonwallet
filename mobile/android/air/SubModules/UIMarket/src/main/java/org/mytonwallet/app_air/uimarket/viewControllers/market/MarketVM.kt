package org.mytonwallet.app_air.uimarket.viewControllers.market

import java.lang.ref.WeakReference
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MApiMarketAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiMarketAssetsResponse
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class MarketVM(delegate: Delegate) : WalletCore.EventObserver {
    interface Delegate {
        fun marketSectionsUpdated()
    }

    private val delegate = WeakReference(delegate)
    private var marketResponse: MApiMarketAssetsResponse? = TokenStore.cachedMarketAssets()
    private var allSections = marketResponse?.let(::buildSections) ?: emptyList()
    private var query = ""
    private var observingWalletCore = false

    var sections: List<MarketSection> = allSections
        private set

    fun start() {
        if (observingWalletCore) return
        observingWalletCore = true
        WalletCore.registerObserver(this)
        marketResponse = TokenStore.cachedMarketAssets()
        rebuildSections()
        TokenStore.loadMarketAssets()
    }

    fun stop() {
        if (!observingWalletCore) return
        observingWalletCore = false
        WalletCore.unregisterObserver(this)
    }

    fun search(value: String) {
        if (query == value) return
        query = value
        applyFilter()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (walletEvent == WalletEvent.MarketAssetsUpdated) {
            marketResponse = TokenStore.cachedMarketAssets()
            rebuildSections()
            return
        }
        if (walletEvent != WalletEvent.TokensChanged &&
            walletEvent != WalletEvent.BaseCurrencyChanged &&
            walletEvent != WalletEvent.NetworkConnected
        ) {
            return
        }
        TokenStore.loadMarketAssets()
        rebuildSections()
    }

    private fun rebuildSections() {
        allSections = marketResponse?.let(::buildSections) ?: emptyList()
        applyFilter()
    }

    private fun buildSections(response: MApiMarketAssetsResponse): List<MarketSection> =
        response.sections.mapNotNull { section ->
            if (section.layout == null || section.assets.isEmpty()) return@mapNotNull null
            MarketSection(section, section.assets.map(::marketToken))
        }

    private fun marketToken(asset: MApiMarketAsset) =
        MarketToken(TokenStore.getToken(asset.slug) ?: asset, asset)

    private fun applyFilter() {
        val normalized = query.trim()
        sections = if (normalized.isEmpty()) {
            allSections
        } else {
            allSections.mapNotNull { section ->
                val matches = section.tokens.filter { it.matches(normalized) }
                section.copy(tokens = matches, visibleLimit = null).takeIf { matches.isNotEmpty() }
            }
        }
        delegate.get()?.marketSectionsUpdated()
    }
}
