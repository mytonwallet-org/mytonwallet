package org.mytonwallet.app_air.uicomponents.helpers

import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.ClickableSpan
import android.view.View
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

object DappWarningPopupHelpers {

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
