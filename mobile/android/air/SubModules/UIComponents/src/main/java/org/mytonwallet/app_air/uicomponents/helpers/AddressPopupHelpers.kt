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
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.commonViews.TemporaryAccountItemView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialogButton
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference

class AddressPopupHelpers {
    companion object {
        const val POPUP_WIDTH = 196

        fun configSpannableAddress(
            viewController: WeakReference<WViewController>,
            title: CharSequence?,
            spannedString: SpannableStringBuilder,
            startIndex: Int,
            length: Int,
            addressTokenSlug: String,
            address: String,
            popupXOffset: Int,
            color: Int? = null,
            showTemporaryViewOption: Boolean,
        ) {
            val context = viewController.get()!!.view.context
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_24
            )?.let { drawable ->
                drawable.mutate()
                drawable.setTint(color ?: WColor.SecondaryText.color)
                val width = 12.dp
                val height = 12.dp
                drawable.setBounds(0, 0, width, height)
                val imageSpan = VerticalImageSpan(drawable)
                spannedString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            spannedString.setSpan(
                object : ClickableSpan() {
                    override fun onClick(widget: View) {
                        TokenStore.getToken(addressTokenSlug)?.mBlockchain?.let { blockchain ->
                            presentMenu(
                                viewController,
                                widget,
                                title,
                                blockchain,
                                address,
                                popupXOffset,
                                showTemporaryViewOption
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

        fun presentMenu(
            viewController: WeakReference<WViewController>,
            view: View,
            title: CharSequence?,
            blockchain: MBlockchain,
            address: String,
            xOffset: Int,
            showTemporaryViewOption: Boolean,
        ) {
            val context = viewController.get()!!.view.context
            WMenuPopup.present(
                view,
                listOfNotNull(
                    if (showTemporaryViewOption)
                        WMenuPopup.Item(
                            config = WMenuPopup.Item.Config.CustomView(
                                TemporaryAccountItemView(context, title, blockchain, address, true)
                            ),
                            hasSeparator = true
                        ) {

                        } else null,
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.icons.R.drawable.ic_copy,
                        LocaleController.getString("Copy Address"),
                    ) {
                        val clipboard =
                            context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val clip = ClipData.newPlainText(
                            "",
                            address
                        )
                        clipboard.setPrimaryClip(clip)
                        Haptics.play(context, HapticType.LIGHT_TAP)
                        Toast.makeText(
                            context,
                            LocaleController.getString("Address was copied!"),
                            Toast.LENGTH_SHORT
                        ).show()
                    },
                    /*WMenuPopup.Item(
                        org.mytonwallet.app_air.uicomponents.R.drawable.ic_star, // TODO:: Update this icon
                        LocaleController.getString(
                            if (AddressStore.getAddress(address) == null)
                                "Save Address"
                            else
                                "Remove From Saved"
                        ),
                    ) {
                        if (AddressStore.getAddress(address) == null) {
                            saveAddressPressed(
                                address,
                                blockchain.name,
                                view,
                                viewController
                            )
                        } else {
                            removeAddressPressed(address, viewController)
                        }
                    },*/
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.icons.R.drawable.ic_world,
                        LocaleController.getString("View on Explorer"),
                    ) {
                        val walletEvent =
                            WalletEvent.OpenUrl(blockchain.explorerUrl(address))
                        WalletCore.notifyEvent(walletEvent)
                    }),
                popupWidth = WRAP_CONTENT,
                offset = xOffset,
                aboveView = false
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
                LocaleController.getString("Remove From Saved"),
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
