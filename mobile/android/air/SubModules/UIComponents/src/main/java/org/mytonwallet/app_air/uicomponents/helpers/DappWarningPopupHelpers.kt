package org.mytonwallet.app_air.uicomponents.helpers

import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.ClickableSpan
import android.view.View
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.ApiDappUrlTrustStatus

object DappWarningPopupHelpers {

    data class WarningContent(
        val title: CharSequence,
        val text: CharSequence,
    )

    fun warningContent(
        trustStatus: ApiDappUrlTrustStatus,
        onExploreClick: () -> Unit,
    ): WarningContent {
        return when (trustStatus) {
            ApiDappUrlTrustStatus.INVALID -> WarningContent(
                title = LocaleController.getString("DappurlTrustStatusInvalidTitle"),
                text = LocaleController.getString("\$DappurlTrustStatusInvalidHelp"),
            )

            ApiDappUrlTrustStatus.DANGEROUS -> WarningContent(
                title = LocaleController.getString("DappurlTrustStatusDangerousTitle"),
                text = LocaleController.getString("\$DappurlTrustStatusDangerousHelp"),
            )

            ApiDappUrlTrustStatus.VERIFIED,
            ApiDappUrlTrustStatus.UNKNOWN -> WarningContent(
                title = LocaleController.getString("Unverified Source"),
                text = reopenInIabWarningText(onExploreClick),
            )
        }
    }

    fun reopenInIabWarningText(onExploreClick: () -> Unit): SpannableStringBuilder {
        val warningText = SpannableStringBuilder()
        val template = LocaleController.getString("\$reopen_in_iab_explore")
        val exploreTabText = LocaleController.getString("Explore")
        val exploreTabPlaceholder = "%exploreTab%"

        val placeholderStart = template.indexOf(exploreTabPlaceholder)
        if (placeholderStart != -1) {
            warningText.append(template.substring(0, placeholderStart))

            val buttonStart = warningText.length
            warningText.append(exploreTabText)
            val buttonEnd = warningText.length

            val clickableSpan = object : ClickableSpan() {
                override fun onClick(widget: View) {
                    onExploreClick()
                }

                override fun updateDrawState(ds: TextPaint) {
                    super.updateDrawState(ds)
                    ds.color = WColor.Tint.color
                    ds.isUnderlineText = false
                }
            }

            warningText.setSpan(
                clickableSpan,
                buttonStart,
                buttonEnd,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )

            warningText.append(template.substring(placeholderStart + exploreTabPlaceholder.length))
        } else {
            warningText.append(
                LocaleController.getStringWithKeyValues(
                    "\$reopen_in_iab_explore",
                    listOf(exploreTabPlaceholder to exploreTabText)
                )
            )
        }

        return warningText
    }
}
