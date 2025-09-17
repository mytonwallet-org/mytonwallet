package org.mytonwallet.app_air.uiassets.viewControllers

import WNavigationController
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode
import org.mytonwallet.app_air.uiassets.viewControllers.hiddenNFTs.HiddenNFTsVC
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config.Icon
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore

object CollectionsMenuHelpers {

    fun presentPinnedCollectionMenuOn(
        view: View,
        collectionMode: CollectionMode
    ) {
        val collectionAddress = when (collectionMode) {
            is CollectionMode.SingleCollection -> {
                collectionMode.collection.address
            }

            CollectionMode.TelegramGifts -> {
                NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
            }
        }
        val location = IntArray(2)
        view.getLocationInWindow(location)
        WMenuPopup.Companion.present(
            view,
            listOf(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = null,
                        title = LocaleController.getString("Remove Tab"),
                    )
                ) {
                    val homeNftCollections =
                        WGlobalStorage.getHomeNftCollections(AccountStore.activeAccountId!!)
                    homeNftCollections.remove(collectionAddress)
                    WGlobalStorage.setHomeNftCollections(
                        AccountStore.activeAccountId!!,
                        homeNftCollections
                    )
                    WalletCore.notifyEvent(WalletEvent.HomeNftCollectionsUpdated)
                }
            ),
            popupWidth = WRAP_CONTENT,
            aboveView = false,
            centerHorizontally = true
        )
    }

    fun presentCollectionsMenuOn(view: View, navigationController: WNavigationController) {
        val hiddenNFTsExist =
            NftStore.nftData?.cachedNfts?.firstOrNull { it.isHidden == true } != null ||
                NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
        val collections = NftStore.getCollections()
        // Extract telegram gifts
        val telegramGifts = NftStore.nftData?.cachedNfts?.filter {
            it.isTelegramGift == true
        }
        val telegramGiftCollectionAddresses = NftStore.nftData?.telegramGiftCollectionAddresses
        val telegramGiftItem = if ((telegramGifts?.size ?: 0) < 2)
            null
        else
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = null,
                    title = LocaleController.getString("Telegram Gifts"),
                    subItems = telegramGifts!!.map {
                        it.collectionAddress
                    }.distinct().map { giftCollectionAddress ->
                        val nftCollection =
                            collections.find { it.address == giftCollectionAddress }!!
                        WMenuPopup.Item(
                            WMenuPopup.Item.Config.Item(
                                icon = null,
                                title = nftCollection.name,
                                isSubItem = true,
                            )
                        ) {
                            navigationController.push(
                                AssetsVC(
                                    view.context,
                                    AssetsVC.Mode.COMPLETE,
                                    collectionMode = CollectionMode.SingleCollection(
                                        nftCollection
                                    )
                                )
                            )
                        }
                    }.toMutableList().apply {
                        val allTelegramGiftsItem = WMenuPopup.Item(
                            WMenuPopup.Item.Config.Item(
                                icon = Icon(org.mytonwallet.app_air.icons.R.drawable.ic_menu_gifts),
                                title = LocaleController.getString("All Telegram Gifts"),
                            ),
                        ) {
                            navigationController.push(
                                AssetsVC(
                                    view.context,
                                    AssetsVC.Mode.COMPLETE,
                                    collectionMode = AssetsVC.CollectionMode.TelegramGifts,
                                ),
                            )
                        }
                        add(0, allTelegramGiftsItem)
                    },
                ),
                hasSeparator = collections.any {
                    telegramGiftCollectionAddresses?.contains(it.address) != true
                } || hiddenNFTsExist,
            )
        val hiddenNFTsItem = WMenuPopup.Item(
            WMenuPopup.Item.Config.Item(
                icon = null,
                title = LocaleController.getString("Hidden NFTs")
            )
        ) {
            val hiddenNFTsVC = HiddenNFTsVC(view.context)
            (navigationController.tabBarController?.navigationController
                ?: navigationController).push(hiddenNFTsVC)
        }
        val menuItems =
            ArrayList(collections.filter {
                telegramGiftItem == null ||
                    telegramGiftCollectionAddresses?.contains(it.address) != true
            }
                .mapIndexed { i, nftCollection ->
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(
                            icon = null,
                            title = nftCollection.name,
                        )
                    ) {
                        navigationController.push(
                            AssetsVC(
                                view.context,
                                AssetsVC.Mode.COMPLETE,
                                collectionMode = CollectionMode.SingleCollection(
                                    nftCollection
                                )
                            )
                        )
                    }
                })
        if (menuItems.isNotEmpty() && hiddenNFTsExist)
            menuItems[menuItems.size - 1].hasSeparator = true
        if (telegramGiftItem != null)
            menuItems.add(0, telegramGiftItem)
        if (hiddenNFTsExist) menuItems.add(hiddenNFTsItem)
        val location = IntArray(2)
        view.getLocationInWindow(location)
        WMenuPopup.Companion.present(
            view,
            menuItems,
            popupWidth = 256.dp,
            offset = (-location[0] + (navigationController.width / 2) - 128.dp),
            aboveView = false
        )
    }

}
