package org.mytonwallet.app_air.uicomponents.helpers

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.ClickableSpan
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.widget.addTextChangedListener
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.AccountItemView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialogButton
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Positioning
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

class AddressPopupHelpers {
    companion object {
        fun configSpannableAddress(
            viewController: WeakReference<WViewController>,
            title: CharSequence?,
            spannedString: SpannableStringBuilder,
            startIndex: Int,
            length: Int,
            network: MBlockchainNetwork,
            blockchain: MBlockchain?,
            address: String,
            popupXOffset: Int,
            centerHorizontally: Boolean,
            color: Int? = null,
            showTemporaryViewOption: Boolean,
        ) {
            val context = viewController.get()!!.view.context
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14
            )?.let { drawable ->
                drawable.mutate()
                drawable.setTint(color ?: WColor.SecondaryText.color)
                val left = 4.5f.dp.roundToInt()
                val width = 7.dp
                val height = 14.dp
                drawable.setBounds(left, 0, left + width, height)
                val imageSpan = VerticalImageSpan(drawable)
                spannedString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            spannedString.setSpan(
                object : ClickableSpan() {
                    override fun onClick(widget: View) {
                        blockchain?.let {
                            presentMenu(
                                viewController = viewController,
                                view = widget,
                                title = title,
                                blockchain = blockchain,
                                network = network,
                                address = address,
                                xOffset = popupXOffset,
                                yOffset = 0,
                                centerHorizontally = centerHorizontally,
                                showTemporaryViewOption = showTemporaryViewOption,
                                windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                                    widget,
                                    roundRadius = 16f.dp
                                )
                            )
                        }
                    }

                    override fun updateDrawState(ds: TextPaint) {
                        super.updateDrawState(ds)
                        ds.isUnderlineText = false
                    }
                },
                startIndex,
                startIndex + length + 1,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }

        fun copyAddress(context: Context, address: String, blockchain: MBlockchain) {
            val clipboard =
                context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("", address)
            clipboard.setPrimaryClip(clip)
            Haptics.play(context, HapticType.LIGHT_TAP)
            Toast.makeText(
                context,
                LocaleController.getString("%chain% Address Copied")
                    .replace("%chain%", blockchain.displayName),
                Toast.LENGTH_SHORT
            ).show()
        }

        fun presentMenu(
            viewController: WeakReference<WViewController>,
            view: View,
            title: CharSequence?,
            blockchain: MBlockchain,
            network: MBlockchainNetwork,
            address: String,
            xOffset: Int = 0,
            yOffset: Int = 0,
            positioning: Positioning = Positioning.BELOW,
            centerHorizontally: Boolean,
            showTemporaryViewOption: Boolean,
            windowBackgroundStyle: BackgroundStyle,
            displayProgressListener: ((progress: Float) -> Unit)? = null,
        ) {
            val context = viewController.get()?.view?.context ?: return
            val addressSaved = AddressStore.getSavedAddress(address) != null
            WMenuPopup.present(
                view,
                listOfNotNull(
                    if (showTemporaryViewOption)
                        WMenuPopup.Item(
                            config = WMenuPopup.Item.Config.CustomView(
                                AccountItemView(
                                    context = context,
                                    accountData = AccountItemView.AccountData(
                                        accountId = null,
                                        title = title,
                                        network = network,
                                        byChain = mapOf(
                                            blockchain.name to MAccount.AccountChain(
                                                address = address
                                            )
                                        ),
                                        accountType = null,
                                    ),
                                    showArrow = true,
                                    isTrusted = false,
                                    hasSeparator = true,
                                    onSelect = {
                                        WalletContextManager.delegate?.openASingleWallet(
                                            network,
                                            mapOf(blockchain.name to address),
                                            title?.toString()
                                        )
                                    }
                                )
                            ),
                            hasSeparator = true
                        ) {

                        } else null,
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.icons.R.drawable.ic_copy_30,
                        LocaleController.getString("Copy Address"),
                    ) {
                        copyAddress(context, address, blockchain)
                    },
                    WMenuPopup.Item(
                        if (addressSaved) {
                            org.mytonwallet.app_air.uicomponents.R.drawable.ic_star_cross_30
                        } else {
                            org.mytonwallet.app_air.uicomponents.R.drawable.ic_star_30
                        },
                        LocaleController.getString(
                            if (addressSaved) {
                                "Remove from Saved"
                            } else {
                                "Save Address"
                            }
                        ),
                    ) {
                        if (AddressStore.getSavedAddress(address) == null) {
                            saveAddressPressed(
                                address,
                                blockchain.name,
                                view,
                                viewController
                            )
                        } else {
                            removeAddressPressed(address, viewController)
                        }
                    },
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.icons.R.drawable.ic_world_30,
                        LocaleController.getString("View on Explorer"),
                    ) {
                        val config = ExplorerHelpers.createAddressExplorerConfig(
                            blockchain, network, address
                        ) ?: return@Item
                        WalletCore.notifyEvent(WalletEvent.OpenUrlWithConfig(config))
                    }),
                popupWidth = WRAP_CONTENT,
                xOffset = xOffset,
                yOffset = yOffset,
                positioning = positioning,
                centerHorizontally = centerHorizontally,
                windowBackgroundStyle = windowBackgroundStyle,
                displayProgressListener = displayProgressListener,
            )
        }

        private fun saveAddressPressed(
            address: String,
            chain: String,
            view: View,
            viewController: WeakReference<WViewController>
        ) {
            val viewController = viewController.get()!!
            val context = viewController.context
            val input = object : WEditText(context, null, false) {
                init {
                    setSingleLine()
                    setPadding(8.dp, 8.dp, 8.dp, 8.dp)
                    updateTheme()
                }

                override fun updateTheme() {
                    setBackgroundColor(WColor.SecondaryBackground.color, 10f.dp)
                }
            }.apply {
                hint = LocaleController.getString("Name")
            }
            val container = FrameLayout(context).apply {
                setPadding(24.dp, 0, 24.dp, 0)
                addView(input, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            }

            val dialog = WDialog(
                container,
                WDialog.Config(
                    title = LocaleController.getString("Save Address"),
                    subtitle = LocaleController.getString("You can save this address for quick access while sending."),
                    actionButton = WDialogButton.Config(
                        title = LocaleController.getString("Save"),
                        onTap = {
                            view.hideKeyboard()
                            val addressName = input.text.toString().trim()
                            if (addressName.isNotEmpty()) {
                                AddressStore.addAddress(
                                    MSavedAddress(
                                        address,
                                        addressName,
                                        chain
                                    )
                                )
                                WalletCore.notifyEvent(WalletEvent.AccountSavedAddressesChanged)
                            }
                        }
                    )
                )
            )
            dialog.presentOn(viewController)
            dialog.setActionButtonEnabled(false)
            val textWatcher = input.addTextChangedListener(onTextChanged = { text, _, _, _ ->
                dialog.setActionButtonEnabled(text?.trim()?.isNotEmpty() == true)
            })
            dialog.setOnDismissListener {
                input.removeTextChangedListener(textWatcher)
            }
        }

        private fun removeAddressPressed(
            address: String,
            viewController: WeakReference<WViewController>
        ) {
            viewController.get()?.showAlert(
                LocaleController.getString("Remove from Saved"),
                LocaleController.getString("Are you sure you want to remove this address from your saved ones?"),
                LocaleController.getString("Delete"),
                {
                    AddressStore.removeAddress(address)
                    WalletCore.notifyEvent(WalletEvent.AccountSavedAddressesChanged)
                },
                LocaleController.getString("Cancel"),
                preferPrimary = false,
                primaryIsDanger = true
            )
        }
    }
}
