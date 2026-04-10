package org.mytonwallet.app_air.uicomponents.viewControllers.selector

import android.content.Context
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

object TokenSelectorHelper {
    fun buildAddTokenSelector(
        context: Context,
        account: MAccount
    ): TokenSelectorVC {
        val assets = TokenStore.swapAssets2?.filter {
            val chain = it.chain
            chain != null
                && MBlockchain.supportedChainValues.contains(chain)
                && account.isChainSupported(chain)
        } ?: emptyList()
        return TokenSelectorVC(
            context = context,
            titleToShow = LocaleController.getString("Add Token"),
            assets = assets,
            showMyAssets = false,
            showChain = account.isMultichain,
        ).apply {
            setOnAssetSelectListener(::addTokenToAssetsAndActivityData)
        }
    }

    private fun addTokenToAssetsAndActivityData(asset: IApiToken) {
        val assetsAndActivityData = AccountStore.assetsAndActivityData
        assetsAndActivityData.deletedTokens =
            ArrayList(assetsAndActivityData.deletedTokens.filter { it != asset.slug })

        if (assetsAndActivityData.getAllTokens(shouldSort = false).none { it.token == asset.slug }
        ) {
            assetsAndActivityData.addedTokens.add(asset.slug)
        }
        if (assetsAndActivityData.visibleTokens.none { it == asset.slug }) {
            assetsAndActivityData.visibleTokens.add(asset.slug)
        }
        AccountStore.updateAssetsAndActivityData(
            newValue = assetsAndActivityData,
            notify = true,
            saveToStorage = true
        )
    }
}
