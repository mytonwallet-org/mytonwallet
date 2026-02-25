package org.mytonwallet.app_air.uiassets.viewControllers

import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode
import org.mytonwallet.app_air.uiassets.viewControllers.hiddenNFTs.HiddenNFTsVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config.Icon
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.NftStore

object CollectionsMenuHelpers {
    fun presentPinnedCollectionMenuOn(
        view: View,
        collectionMode: CollectionMode,
        onReorderTapped: (() -> Unit)?,
        onRemoveTapped: ((collectionMode: CollectionMode) -> Unit),
    ) {
        val shouldShowReorder = onReorderTapped != null
        val items = mutableListOf(
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = Icon(
                        org.mytonwallet.app_air.uiassets.R.drawable.ic_collection_unpin_small,
                        WColor.PrimaryLightText
                    ),
                    title = LocaleController.getString("Remove Tab"),
                ),
                hasSeparator = shouldShowReorder
            ) {
                onRemoveTapped(collectionMode)
            }
        )
        if (shouldShowReorder)
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_reorder,
                            WColor.PrimaryLightText
                        ),
                        title = LocaleController.getString("Reorder")
                    ),
                    hasSeparator = false
                ) {
                    onReorderTapped.invoke()
                })
        WMenuPopup.present(
            view,
            items,
            popupWidth = WRAP_CONTENT,
            positioning = WMenuPopup.Positioning.BELOW,
            centerHorizontally = true,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(view, roundRadius = 16f.dp)
        )
    }

    fun presentCollectionsMenuOn(
        showingAccountId: String,
        view: View,
        navigationController: WNavigationController,
        onReorderTapped: (() -> Unit)?
    ) {
        val shouldShowReorder = onReorderTapped != null
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
                                    showingAccountId,
                                    AssetsVC.Mode.COMPLETE,
                                    isShowingSingleCollection = true,
                                    collectionMode = CollectionMode.SingleCollection(nftCollection)
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
                                    showingAccountId,
                                    AssetsVC.Mode.COMPLETE,
                                    collectionMode = CollectionMode.TelegramGifts,
                                    isShowingSingleCollection = true
                                ),
                            )
                        }
                        add(0, allTelegramGiftsItem)
                    },
                ),
                hasSeparator = collections.any {
                    telegramGiftCollectionAddresses?.contains(it.address) != true
                } || hiddenNFTsExist || shouldShowReorder,
            )
        val hiddenNFTsItem = WMenuPopup.Item(
            WMenuPopup.Item.Config.Item(
                icon = Icon(
                    org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_hide,
                    WColor.PrimaryLightText
                ),
                title = LocaleController.getString("Hidden NFTs")
            ),
            hasSeparator = shouldShowReorder
        ) {
            val hiddenNFTsVC =
                HiddenNFTsVC(view.context, showingAccountId)
            (navigationController.tabBarController?.navigationController
                ?: navigationController).push(hiddenNFTsVC)
        }
        val menuItems =
            ArrayList(collections.filter {
                telegramGiftItem == null ||
                    telegramGiftCollectionAddresses?.contains(it.address) != true
            }.mapIndexed { i, nftCollection ->
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = null,
                        title = nftCollection.name,
                    )
                ) {
                    navigationController.push(
                        AssetsVC(
                            view.context,
                            showingAccountId,
                            AssetsVC.Mode.COMPLETE,
                            collectionMode = CollectionMode.SingleCollection(nftCollection),
                            isShowingSingleCollection = true
                        )
                    )
                }
            })
        if (menuItems.isNotEmpty() && (hiddenNFTsExist || shouldShowReorder))
            menuItems[menuItems.size - 1].hasSeparator = true
        if (telegramGiftItem != null)
            menuItems.add(0, telegramGiftItem)
        if (hiddenNFTsExist) menuItems.add(hiddenNFTsItem)
        if (shouldShowReorder) {
            menuItems.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_reorder,
                            WColor.PrimaryLightText
                        ),
                        title = LocaleController.getString("Reorder")
                    ),
                    hasSeparator = false
                ) {
                    onReorderTapped()
                })
        }
        val location = view.getLocationInWindow()
        WMenuPopup.present(
            view,
            menuItems,
            popupWidth = 256.dp,
            xOffset = (-location.x + (navigationController.width / 2) - 128.dp),
            positioning = WMenuPopup.Positioning.BELOW,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(view, roundRadius = 40f.dp)
        )
    }

}
