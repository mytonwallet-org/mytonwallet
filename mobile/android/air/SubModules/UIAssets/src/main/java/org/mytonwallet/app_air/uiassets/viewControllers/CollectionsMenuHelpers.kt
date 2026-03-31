package org.mytonwallet.app_air.uiassets.viewControllers

import android.content.Intent
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode
import org.mytonwallet.app_air.uiassets.viewControllers.hiddenNFTs.HiddenNFTsVC
import org.mytonwallet.app_air.uiassets.viewControllers.renew.LinkToWalletVC
import org.mytonwallet.app_air.uiassets.viewControllers.renew.RenewVC
import org.mytonwallet.app_air.uicomponents.base.WActionBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.getLocationOnScreen
import org.mytonwallet.app_air.uicomponents.helpers.palette.ImagePaletteHelpers
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config.Icon
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopupView
import org.mytonwallet.app_air.uisend.sendNft.SendNftVC
import org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm.ConfirmNftVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MCollectionTabToShow
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore

object CollectionsMenuHelpers {
    fun configureSelectionActionBar(
        actionBar: WActionBar,
        shouldShowTransferActions: Boolean,
        onCloseTapped: () -> Unit,
        onHideTapped: () -> Unit,
        onSelectAllTapped: () -> Unit,
        onSendTapped: (() -> Unit)? = null,
        onBurnTapped: (() -> Unit)? = null
    ) {
        actionBar.setTint(WColor.SecondaryText, animated = false)
        actionBar.clearActions()
        actionBar.addLeadingAction(
            WActionBar.ActionItem(
                iconResId = org.mytonwallet.app_air.uicomponents.R.drawable.ic_close
            ) {
                onCloseTapped()
            }
        )
        if (shouldShowTransferActions) {
            actionBar.addTrailingAction(
                WActionBar.ActionItem(
                    iconResId = org.mytonwallet.app_air.icons.R.drawable.ic_arrow_up_thin_24
                ) {
                    onSendTapped?.invoke()
                }
            )
        }
        actionBar.addTrailingAction(
            WActionBar.ActionItem(
                iconResId = org.mytonwallet.app_air.icons.R.drawable.ic_header_eye_hidden
            ) {
                onHideTapped()
            }
        )
        if (shouldShowTransferActions) {
            actionBar.addTrailingAction(
                WActionBar.ActionItem(
                    iconResId = org.mytonwallet.app_air.icons.R.drawable.ic_trash_24
                ) {
                    onBurnTapped?.invoke()
                }
            )
        }
        actionBar.addTrailingAction(
            WActionBar.ActionItem(
                iconResId = org.mytonwallet.app_air.icons.R.drawable.ic_more
            ) { moreButton ->
                presentSelectionActionBarMenu(moreButton, onSelectAllTapped)
            }
        )
    }

    fun configureReorderActionBar(
        actionBar: WActionBar,
        onSaveTapped: () -> Unit,
        onCancelTapped: () -> Unit
    ) {
        actionBar.setTint(WColor.Tint, animated = false)
        actionBar.clearActions()
        actionBar.addLeadingAction(
            WActionBar.ActionItem(
                title = LocaleController.getString("Cancel")
            ) {
                onCancelTapped()
            }
        )
        actionBar.addTrailingAction(
            WActionBar.ActionItem(
                title = LocaleController.getString("Save")
            ) {
                onSaveTapped()
            }
        )
        actionBar.setTitle("", false)
    }

    private fun presentSelectionActionBarMenu(
        anchorView: View,
        onSelectAllTapped: () -> Unit
    ) {
        val items = mutableListOf<WMenuPopup.Item>()
        items.add(
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = Icon(
                        org.mytonwallet.app_air.icons.R.drawable.ic_tick_30,
                        WColor.PrimaryLightText
                    ),
                    title = LocaleController.getString("Select All")
                )
            ) {
                onSelectAllTapped()
            }
        )

        WMenuPopup.present(
            anchorView,
            items,
            popupWidth = WRAP_CONTENT,
            positioning = WMenuPopup.Positioning.ALIGNED
        )
    }

    fun presentPinnedCollectionMenuOn(
        view: View,
        collectionMode: CollectionMode,
        onReorderTapped: (() -> Unit)?,
        onSelectTapped: (() -> Unit)?,
        onRemoveTapped: ((collectionMode: CollectionMode) -> Unit),
    ) {
        val shouldShowReorder = onReorderTapped != null
        val shouldShowSelect = onSelectTapped != null
        val items = mutableListOf(
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = Icon(
                        org.mytonwallet.app_air.uiassets.R.drawable.ic_collection_unpin_small,
                        WColor.PrimaryLightText
                    ),
                    title = LocaleController.getString("Remove Tab"),
                ),
                hasSeparator = shouldShowReorder || shouldShowSelect
            ) {
                onRemoveTapped(collectionMode)
            }
        )
        if (shouldShowReorder) items.add(makeReorderItem { onReorderTapped.invoke() })
        if (shouldShowSelect) items.add(makeSelectItem { onSelectTapped.invoke() })
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
        onReorderTapped: (() -> Unit)?,
        onSelectTapped: (() -> Unit)?
    ) {
        val shouldShowReorder = onReorderTapped != null
        val shouldShowSelect = onSelectTapped != null
        val currentNftData = NftStore.nftData?.takeIf { it.accountId == showingAccountId }
        val hiddenNFTsExist =
            NftStore.getHasHiddenNft(showingAccountId) ||
                currentNftData?.blacklistedNftAddresses?.isNotEmpty() == true
        val collections = NftStore.getCollections(showingAccountId)
        // Extract telegram gifts
        val telegramGifts = currentNftData?.cachedNfts?.filter {
            it.isTelegramGift == true && !it.shouldHide()
        }
        val telegramGiftCollectionAddresses = currentNftData?.telegramGiftCollectionAddresses
        val telegramGiftItem = if ((telegramGifts?.size ?: 0) < 2)
            null
        else
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = null,
                    title = LocaleController.getString("Telegram Gifts"),
                    subItems = telegramGifts!!
                        .mapNotNull { it.collectionAddress }
                        .distinct()
                        .mapNotNull { giftCollectionAddress ->
                            collections.find { it.address == giftCollectionAddress }
                                ?.let { nftCollection ->
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
                                                AssetsVC.ViewMode.COMPLETE,
                                                isShowingSingleCollection = true,
                                                collectionMode = CollectionMode.SingleCollection(
                                                    nftCollection
                                                )
                                            )
                                        )
                                    }
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
                                        AssetsVC.ViewMode.COMPLETE,
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
                } || hiddenNFTsExist || shouldShowReorder || shouldShowSelect,
            )
        val hiddenNFTsItem = WMenuPopup.Item(
            WMenuPopup.Item.Config.Item(
                icon = Icon(
                    org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_hide,
                    WColor.PrimaryLightText
                ),
                title = LocaleController.getString("Hidden NFTs")
            ),
            hasSeparator = shouldShowReorder || shouldShowSelect
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
                    pushOnTopNavigationController(
                        navigationController,
                        AssetsVC(
                            view.context,
                            showingAccountId,
                            AssetsVC.ViewMode.COMPLETE,
                            collectionMode = CollectionMode.SingleCollection(nftCollection),
                            isShowingSingleCollection = true
                        )
                    )
                }
            })
        if (menuItems.isNotEmpty() && (hiddenNFTsExist || shouldShowReorder || shouldShowSelect))
            menuItems[menuItems.size - 1].hasSeparator = true
        if (telegramGiftItem != null)
            menuItems.add(0, telegramGiftItem)
        if (hiddenNFTsExist) menuItems.add(hiddenNFTsItem)
        if (shouldShowReorder) menuItems.add(
            makeReorderItem { onReorderTapped() }
        )
        if (shouldShowSelect) menuItems.add(makeSelectItem { onSelectTapped.invoke() })
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

    fun presentNftMenuOn(
        showingAccountId: String,
        nft: ApiNft,
        view: View,
        navigationController: WNavigationController,
        shouldShowCollectionItem: Boolean = true,
        roundRadius: Float,
        onReorderTapped: (() -> Unit)? = null,
        onSelectTapped: (() -> Unit)? = null
    ): INavigationPopup? {
        val menuItems = buildNftMenuItems(
            showingAccountId,
            nft,
            navigationController,
            shouldShowCollectionItem = shouldShowCollectionItem,
            onReorderTapped = onReorderTapped,
            onSelectTapped = onSelectTapped
        )
        if (menuItems.isEmpty()) {
            return null
        }
        val popupWidth = WMenuPopupView.measureWidth(view.context, menuItems)
        val viewLocation = view.getLocationOnScreen()
        val viewCenterX = viewLocation.x + view.width / 2
        val xOffset = if (viewCenterX <= view.resources.displayMetrics.widthPixels / 2) {
            view.width + 11.dp
        } else {
            -(popupWidth + 11.dp)
        }

        return WMenuPopup.present(
            view,
            menuItems,
            popupWidth = WRAP_CONTENT,
            xOffset = xOffset,
            yOffset = (-46).dp,
            positioning = WMenuPopup.Positioning.ALIGNED,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(view, roundRadius = roundRadius)
        )
    }

    private fun buildNftMenuItems(
        showingAccountId: String,
        nft: ApiNft,
        navigationController: WNavigationController,
        shouldShowCollectionItem: Boolean,
        onReorderTapped: (() -> Unit)?,
        onSelectTapped: (() -> Unit)?
    ): MutableList<WMenuPopup.Item> {
        val wearItems = buildNftWearItems(showingAccountId, nft)
        val actionItems = buildNftActionItems(nft, navigationController)
        val infoItems = buildNftInfoItems(
            showingAccountId,
            nft,
            navigationController,
            shouldShowCollectionItem
        )
        val modeItems = buildNftModeItems(onReorderTapped, onSelectTapped)

        if (wearItems.isNotEmpty() && (actionItems.isNotEmpty() || infoItems.isNotEmpty())) {
            wearItems.last().hasSeparator = true
        }
        if (actionItems.isNotEmpty() && infoItems.isNotEmpty()) {
            actionItems.last().hasSeparator = true
        }
        if (modeItems.isNotEmpty()) {
            when {
                infoItems.isNotEmpty() -> infoItems.last().hasSeparator = true
                actionItems.isNotEmpty() -> actionItems.last().hasSeparator = true
                wearItems.isNotEmpty() -> wearItems.last().hasSeparator = true
            }
        }

        return mutableListOf<WMenuPopup.Item>().apply {
            addAll(wearItems)
            addAll(actionItems)
            addAll(infoItems)
            addAll(modeItems)
        }
    }

    private fun buildNftWearItems(
        showingAccountId: String,
        nft: ApiNft
    ): MutableList<WMenuPopup.Item> {
        if (!nft.isMtwCard) {
            return mutableListOf()
        }
        return mutableListOf(
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = Icon(
                        org.mytonwallet.app_air.uiassets.R.drawable.ic_card_install,
                        WColor.PrimaryLightText
                    ),
                    title = LocaleController.getString(
                        if (nft.isInstalledMtwCard) "Reset Card" else "Install Card"
                    )
                )
            ) {
                if (nft.isInstalledMtwCard) {
                    WGlobalStorage.setCardBackgroundNft(showingAccountId, null)
                    resetPalette(showingAccountId)
                } else {
                    WGlobalStorage.setCardBackgroundNft(showingAccountId, nft.toDictionary())
                    if (!nft.isInstalledMtwCardPalette) {
                        installPalette(showingAccountId, nft)
                    }
                }
                WalletCore.notifyEvent(WalletEvent.NftCardUpdated)
            },
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = Icon(
                        org.mytonwallet.app_air.uiassets.R.drawable.ic_card_pallete,
                        WColor.PrimaryLightText
                    ),
                    title = LocaleController.getString(
                        if (nft.isInstalledMtwCardPalette) "Reset Palette" else "Install Palette"
                    )
                )
            ) {
                if (nft.isInstalledMtwCardPalette) {
                    resetPalette(showingAccountId)
                } else {
                    installPalette(showingAccountId, nft)
                }
            }
        )
    }

    private fun buildNftActionItems(
        nft: ApiNft,
        navigationController: WNavigationController
    ): MutableList<WMenuPopup.Item> {
        val items = mutableListOf<WMenuPopup.Item>()
        val canTransferNft = canTransferNft(nft)

        if (canTransferNft) {
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.icons.R.drawable.ic_arrow_up_thin_30,
                            WColor.PrimaryLightText
                        ),
                        title = LocaleController.getString("Send")
                    )
                ) {
                    pushOnTopNavigationController(
                        navigationController,
                        SendNftVC(navigationController.context, nft)
                    )
                }
            )
        }
        if (nft.canRenew() && canTransferNft) {
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_renew,
                            WColor.PrimaryLightText
                        ),
                        title = LocaleController.getString("Renew")
                    )
                ) {
                    presentRenewModal(navigationController, nft)
                }
            )
        }
        if (nft.canLinkToAddress() && canTransferNft) {
            val linkedAddress = NftStore.nftData?.linkedAddressByAddress?.get(nft.address)
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_link,
                            WColor.PrimaryLightText
                        ),
                        title = LocaleController.getString(
                            if (linkedAddress.isNullOrBlank()) "Link to Wallet" else "Change Wallet"
                        )
                    )
                ) {
                    presentLinkToWalletModal(navigationController, nft)
                }
            )
        }
        items.add(
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = Icon(
                        if (nft.shouldHide()) {
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_unhide
                        } else {
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_hide
                        },
                        WColor.PrimaryLightText
                    ),
                    title = LocaleController.getString(if (nft.shouldHide()) "Unhide" else "Hide")
                )
            ) {
                toggleNftVisibility(nft)
            }
        )
        if (canTransferNft) {
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.icons.R.drawable.ic_trash_30,
                            WColor.Red
                        ),
                        title = LocaleController.getString("\$burn_action"),
                        titleColor = WColor.Red.color
                    )
                ) {
                    pushBurnNftConfirm(navigationController, nft)
                }
            )
        }
        return items
    }

    private fun buildNftInfoItems(
        showingAccountId: String,
        nft: ApiNft,
        navigationController: WNavigationController,
        shouldShowCollectionItem: Boolean
    ): MutableList<WMenuPopup.Item> {
        val items = mutableListOf<WMenuPopup.Item>()
        if (shouldShowCollectionItem && nft.collectionAddress != null) {
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.icons.R.drawable.ic_collection_30,
                            WColor.PrimaryLightText
                        ),
                        title = LocaleController.getString("Collection")
                    )
                ) {
                    openCollection(showingAccountId, nft, navigationController)
                }
            )
        }
        items.add(
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = Icon(
                        org.mytonwallet.app_air.icons.R.drawable.ic_share,
                        WColor.PrimaryLightText
                    ),
                    title = LocaleController.getString("Share")
                )
            ) {
                shareNft(showingAccountId, nft, navigationController)
            }
        )

        val openInItems = buildNftOpenInItems(showingAccountId, nft)
        if (openInItems.isNotEmpty()) {
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.icons.R.drawable.ic_world_30,
                            WColor.PrimaryLightText
                        ),
                        title = LocaleController.getString("Open In..."),
                        subItems = openInItems
                    )
                )
            )
        }
        return items
    }

    private fun buildNftModeItems(
        onReorderTapped: (() -> Unit)?,
        onSelectTapped: (() -> Unit)?
    ): MutableList<WMenuPopup.Item> {
        val items = mutableListOf<WMenuPopup.Item>()
        if (onReorderTapped != null) items.add(makeReorderItem { onReorderTapped() })
        if (onSelectTapped != null) items.add(makeSelectItem { onSelectTapped() })
        return items
    }

    private fun makeReorderItem(
        onReorder: () -> Unit
    ) = WMenuPopup.Item(
        WMenuPopup.Item.Config.Item(
            icon = Icon(
                org.mytonwallet.app_air.uiassets.R.drawable.ic_reorder,
                WColor.PrimaryLightText
            ),
            title = LocaleController.getString("Reorder")
        )
    ) { onReorder() }

    private fun makeSelectItem(onSelect: () -> Unit) = WMenuPopup.Item(
        WMenuPopup.Item.Config.Item(
            icon = Icon(
                org.mytonwallet.app_air.icons.R.drawable.ic_tick_30,
                WColor.PrimaryLightText
            ),
            title = LocaleController.getString("Select")
        )
    ) { onSelect() }

    fun buildNftOpenInItems(
        showingAccountId: String,
        nft: ApiNft
    ): MutableList<WMenuPopup.Item> {
        val items = mutableListOf<WMenuPopup.Item>()
        if (nft.chain == MBlockchain.ton && nft.collectionAddress != null) {
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_getgems,
                            tintColor = null,
                            iconSize = 28.dp
                        ),
                        title = "Getgems"
                    )
                ) {
                    openLink("https://getgems.io/collection/${nft.collectionAddress}/${nft.address}")
                }
            )

            val tonscanUrl = nft.chain
                ?.nftExplorer()
                ?.nftUrl(MBlockchainNetwork.ofAccountId(showingAccountId), nft.address)
            if (tonscanUrl != null) {
                items.add(
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(
                            icon = Icon(
                                org.mytonwallet.app_air.uiassets.R.drawable.ic_tonscan,
                                tintColor = null,
                                iconSize = 28.dp
                            ),
                            title = "Tonscan"
                        )
                    ) {
                        openLink(tonscanUrl)
                    }
                )
            }
        }
        if (nft.isOnFragment == true && nft.fragmentUrl != null) {
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_fragment,
                            tintColor = null,
                            iconSize = 28.dp
                        ),
                        title = "Fragment"
                    )
                ) {
                    openLink(nft.fragmentUrl!!)
                }
            )
        }
        if (nft.isTonDns) {
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            org.mytonwallet.app_air.uiassets.R.drawable.ic_tondomains,
                            tintColor = null,
                            iconSize = 28.dp
                        ),
                        title = "TON Domains"
                    )
                ) {
                    openLink(nft.tonDnsUrl)
                }
            )
        }
        return items
    }

    fun canTransferNft(nft: ApiNft): Boolean {
        return isOwnNft(nft) && !nft.isOnSale
    }

    fun isOwnNft(nft: ApiNft): Boolean {
        if (AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW) {
            return false
        }
        val ownerAddress = nft.ownerAddress ?: return false
        if (ownerAddress.isEmpty()) {
            return false
        }
        return AccountStore.activeAccount?.addressByChain?.get(
            (nft.chain ?: MBlockchain.ton).name
        ) == ownerAddress
    }

    fun presentRenewModal(
        navigationController: WNavigationController,
        nft: ApiNft
    ) {
        val nav = WNavigationController(
            navigationController.window,
            WNavigationController.PresentationConfig(
                overFullScreen = false,
                isBottomSheet = true
            )
        )
        nav.setRoot(RenewVC(navigationController.context, nft))
        navigationController.window.present(nav)
    }

    fun presentLinkToWalletModal(
        navigationController: WNavigationController,
        nft: ApiNft
    ) {
        val nav = WNavigationController(
            navigationController.window,
            WNavigationController.PresentationConfig(
                overFullScreen = false,
                isBottomSheet = true,
                aboveKeyboard = true
            )
        )
        nav.setRoot(LinkToWalletVC(navigationController.context, nft))
        navigationController.window.present(nav)
    }

    fun openCollection(
        showingAccountId: String,
        nft: ApiNft,
        navigationController: WNavigationController
    ) {
        val collectionAddress = nft.collectionAddress ?: return
        pushOnTopNavigationController(
            navigationController,
            AssetsVC(
                navigationController.context,
                showingAccountId,
                AssetsVC.ViewMode.COMPLETE,
                collectionMode = CollectionMode.SingleCollection(
                    MCollectionTabToShow(
                        chain = (nft.chain ?: MBlockchain.ton).name,
                        address = collectionAddress,
                        name = nft.collectionName ?: ""
                    )
                ),
                isShowingSingleCollection = true
            )
        )
    }

    fun shareNft(
        showingAccountId: String,
        nft: ApiNft,
        navigationController: WNavigationController
    ) {
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(
                Intent.EXTRA_TEXT,
                nft.scanUrl(MBlockchainNetwork.ofAccountId(showingAccountId))
            )
        }
        navigationController.window.startActivity(
            Intent.createChooser(
                shareIntent,
                LocaleController.getString("Share")
            )
        )
    }

    fun openLink(url: String) {
        WalletCore.notifyEvent(WalletEvent.OpenUrl(url))
    }

    fun toggleNftVisibility(nft: ApiNft) {
        if (nft.shouldHide()) {
            NftStore.showNft(nft)
        } else {
            NftStore.hideNft(nft)
        }
    }

    fun pushBurnNftConfirm(
        navigationController: WNavigationController,
        nft: ApiNft
    ) {
        pushOnTopNavigationController(
            navigationController,
            ConfirmNftVC(
                navigationController.context,
                ConfirmNftVC.Mode.Burn(nft.chain ?: MBlockchain.ton),
                nft,
                null
            )
        )
    }

    fun pushSendNfts(
        navigationController: WNavigationController,
        nfts: List<ApiNft>
    ) {
        if (nfts.isEmpty()) return
        pushOnTopNavigationController(
            navigationController,
            SendNftVC(navigationController.context, nfts)
        )
    }

    fun pushBurnNftsConfirm(
        navigationController: WNavigationController,
        nfts: List<ApiNft>
    ) {
        val chain = nfts.firstOrNull()?.chain ?: return
        pushOnTopNavigationController(
            navigationController,
            ConfirmNftVC(navigationController.context, ConfirmNftVC.Mode.Burn(chain), nfts, null)
        )
    }

    private fun pushOnTopNavigationController(
        navigationController: WNavigationController,
        viewController: org.mytonwallet.app_air.uicomponents.base.WViewController
    ) {
        val window = navigationController.window
        val topNavigationController = window?.navigationControllers?.lastOrNull()
            ?.tabBarController?.navigationController
        if (topNavigationController != null) {
            topNavigationController.push(viewController)
        } else {
            (window?.navigationControllers?.lastOrNull() ?: navigationController).push(
                viewController
            )
        }
    }

    private fun installPalette(showingAccountId: String, nft: ApiNft) {
        ImagePaletteHelpers.extractPaletteFromNft(nft) { colorIndex ->
            if (colorIndex != null) {
                WGlobalStorage.setNftAccentColor(
                    showingAccountId,
                    colorIndex,
                    nft.toDictionary()
                )
            }
            WalletContextManager.delegate?.themeChanged()
        }
    }

    private fun resetPalette(showingAccountId: String) {
        WGlobalStorage.setNftAccentColor(
            showingAccountId,
            null,
            null
        )
        WalletContextManager.delegate?.themeChanged()
    }
}
