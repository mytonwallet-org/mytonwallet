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
import android.widget.Toast
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletcontext.R
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class AddressPopupHelpers {
    companion object {
        fun configSpannableAddress(
            context: Context,
            spannedString: SpannableStringBuilder,
            startIndex: Int,
            length: Int,
            addressTokenSlug: String,
            address: String,
            popupXOffset: Int,
            color: Int? = null
        ) {
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
                                context,
                                widget,
                                blockchain,
                                address,
                                popupXOffset
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
            context: Context,
            view: View,
            blockchain: MBlockchain,
            address: String,
            xOffset: Int
        ) {
            WMenuPopup.present(
                view,
                listOf(
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.icons.R.drawable.ic_copy,
                        LocaleController.getString(R.string.TransactionInfo_CopyAddress),
                    ) {
                        val clipboard =
                            context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val clip = ClipData.newPlainText(
                            "",
                            address
                        )
                        clipboard.setPrimaryClip(clip)
                        Toast.makeText(
                            context,
                            LocaleController.getString(R.string.TransactionInfo_AddressCopied),
                            Toast.LENGTH_SHORT
                        ).show()
                    },
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.icons.R.drawable.ic_world,
                        LocaleController.getString(R.string.Token_OpenInExplorer),
                    ) {
                        val event = WalletCore.Event.OpenUrl(blockchain.explorerUrl(address))
                        WalletCore.notifyEvent(event)
                    }),
                popupWidth = 196.dp,
                offset = xOffset,
                aboveView = false
            )
        }
    }
}
