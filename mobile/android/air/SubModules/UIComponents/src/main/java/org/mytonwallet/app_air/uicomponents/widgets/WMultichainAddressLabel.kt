package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.drawable.Drawable
import android.text.SpannedString
import android.util.Size
import androidx.core.content.ContextCompat
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.measureWidth
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.helpers.spans.WLetterSpacingSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WSpacingSpan
import org.mytonwallet.app_air.uicomponents.helpers.textOffset
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletbasecontext.utils.trimAddress
import org.mytonwallet.app_air.walletbasecontext.utils.trimDomain
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import kotlin.math.min
import kotlin.math.roundToInt

class WMultichainAddressLabel(context: Context) : WRadialGradientLabel(context) {

    private val drawableCache: MutableMap<Int, Drawable> = mutableMapOf()

    private var displayDataList: List<DisplayData> = emptyList()
    private var currentDisplayWidth: Int = 0
    private var currentDisplayData: SpannedString = SpannedString("")

    private var style: Style = walletStyle

    init {
        maxLines = 1
    }

    private fun loadDrawable(resId: Int): Drawable? {
        return drawableCache[resId] ?: let {
            ContextCompat.getDrawable(context, resId)?.mutate()?.let { drawable ->
                drawableCache[resId] = drawable
                drawable
            }
        }
    }

    fun displayAddresses(account: MAccount?, style: Style) {
        if (account?.network == MBlockchainNetwork.TESTNET)
            this.style = style.copy(
                prefixIconResList = listOf(org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_testnet) + style.prefixIconResList
            )
        else
            this.style = style
        val addresses = account?.byChain?.map { (key, value) ->
            Pair(key, value)
        } ?: emptyList()
        val chainStyle = if (addresses.size > 1) {
            style.multipleChainStyle
        } else {
            style.singleChainStyle
        }
        paint.letterSpacing = chainStyle.letterSpacing
        displayDataList = addresses.map {
            val account = it.second
            val domain = account.domain
            val isDomain = !domain.isNullOrBlank()
            val original = domain ?: account.address
            DisplayData(
                chainName = it.first,
                original = original,
                toDisplay = original,
                isDomain = isDomain,
                keepCharCount = original.length,
                canTrim = isDomain
            )
        }
        untrimDisplayDataList()
        requestLayout()
    }

    private fun getDomainTrimAction(): (input: String, keepCount: Int) -> String {
        val chainStyle = if (displayDataList.size > 1) {
            style.multipleChainStyle
        } else {
            style.singleChainStyle
        }
        return if (chainStyle.domainTrimRule == DomainTrimRule.KEEP_TOP_LEVEL_DOMAIN) {
            { input: String, keepCount: Int -> input.trimDomain(keepCount) }
        } else {
            { input: String, keepCount: Int -> input.trimDomain(keepCount, false) }
        }
    }

    private fun untrimDisplayDataList() {
        val chainStyle = if (displayDataList.size > 1) {
            style.multipleChainStyle
        } else {
            style.singleChainStyle
        }
        displayDataList = displayDataList.map {
            if (it.isDomain) {
                val keepCount = min(chainStyle.domainKeepCount, it.original.length)
                it.copy(
                    toDisplay = getDomainTrimAction()(it.original, keepCount),
                    keepCharCount = keepCount,
                    canTrim = true
                )
            } else {
                it.copy(
                    toDisplay = it.original.trimAddress(chainStyle.addressKeepCount),
                    keepCharCount = chainStyle.addressKeepCount
                )
            }
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        if (displayDataList.isEmpty()) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            return
        }
        untrimDisplayDataList()

        val paddingSize = paddingLeft + paddingRight
        val widthSize = MeasureSpec.getSize(widthMeasureSpec).takeIf { it > 0 } ?: Int.MAX_VALUE
        val widthMode = MeasureSpec.getMode(widthMeasureSpec)

        var needRemeasure = true
        var displayData = buildDisplayData(displayDataList)
        var displayWidth = displayData.measureWidth(paint)
        val availableWidth = widthSize - paddingSize
        // trim until fit available width
        while (needRemeasure) {
            if (displayWidth <= availableWidth || !canTrim(displayDataList)) {
                needRemeasure = false
            } else {
                displayDataList = trim(displayDataList)
                displayData = buildDisplayData(displayDataList)
                displayWidth = displayData.measureWidth(paint)
            }
        }
        currentDisplayWidth = displayWidth.ceilToInt() + paddingSize
        if (displayData.toString() != currentDisplayData.toString()) {
            currentDisplayData = displayData
            text = displayData
        }
        if (widthMode == MeasureSpec.EXACTLY) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        } else {
            super.onMeasure(currentDisplayWidth.exactly, heightMeasureSpec)
        }
    }

    private fun buildDisplayData(displayDataList: List<DisplayData>): SpannedString {
        return buildSpannedString {
            // Display prefix icons
            style.prefixIconResList.mapNotNull { loadDrawable(it) }.forEachIndexed { index, it ->
                it.setTint(currentTextColor)
                it.setBounds(
                    0,
                    -FontManager.activeFont.textOffset,
                    style.prefixIconSize,
                    style.prefixIconSize
                )
                inSpans(
                    VerticalImageSpan(
                        it, verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                    )
                ) {
                    append(" ")
                }
                if (index + 1 < style.prefixIconResList.size)
                    append(" ")
            }
            // Margin between last prefix icon and first chain
            if (style.prefixIconResList.isNotEmpty() && style.prefixIconMargin > 0) {
                inSpans(WSpacingSpan(style.prefixIconMargin)) {
                    append(" ")
                }
            }

            // Define chain-specific style
            val chainStyle = if (displayDataList.size > 1) {
                style.multipleChainStyle
            } else {
                style.singleChainStyle
            }

            // Display chains
            displayDataList.forEachIndexed { index, data ->
                if (chainStyle.displayChainIcon) {
                    val drawableRes = style.chainIconResMap[data.chainName]
                    val chainDrawable = drawableRes?.let { loadDrawable(it) }
                    chainDrawable?.setBounds(
                        0,
                        -FontManager.activeFont.textOffset,
                        style.chainIconSize,
                        style.chainIconSize
                    )
                    if (chainDrawable != null) {
                        if (style.tintChainIcon) {
                            chainDrawable.setTint(currentTextColor)
                        }
                        inSpans(
                            VerticalImageSpan(
                                chainDrawable,
                                verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                            )
                        ) {
                            append(data.chainName)
                        }
                        if (chainStyle.iconMargin > 0) {
                            inSpans(WSpacingSpan(chainStyle.iconMargin)) {
                                append(" ")
                            }
                        }
                    }
                }
                // Apply letter spacing style for '···'
                val toDisplay = buildSpannedString {
                    if (data.isDomain && chainStyle.domainLetterSpacing != null) {
                        inSpans(WLetterSpacingSpan(chainStyle.domainLetterSpacing)) {
                            append(data.toDisplay)
                        }
                    } else if (!data.isDomain && chainStyle.addressLetterSpacing != null) {
                        inSpans(WLetterSpacingSpan(chainStyle.addressLetterSpacing)) {
                            append(data.toDisplay)
                        }
                    } else {
                        append(data.toDisplay)
                    }

                    styleDots()
                }
                append(toDisplay)

                // Define delimiter: symbols of specific width
                if (index < displayDataList.size - 1) {
                    if (style.delimiter.isNotEmpty()) {
                        append(style.delimiter)
                    }
                    if (style.delimiterWidth > 0) {
                        inSpans(WSpacingSpan(style.delimiterWidth)) {
                            append(" ")
                        }
                    }
                }
            }
            // Margin between last chain and first postfix icon
            if (style.postfixIconResList.isNotEmpty() && style.postfixIconMargin > 0) {
                inSpans(WSpacingSpan(style.postfixIconMargin)) {
                    append(" ")
                }
            }
            // Display postfix icons
            style.postfixIconResList.mapNotNull { loadDrawable(it) }.forEach {
                it.setTint(currentTextColor)
                it.setBounds(
                    0,
                    -FontManager.activeFont.textOffset,
                    style.postfixIconSize.width,
                    style.postfixIconSize.height
                )
                inSpans(
                    VerticalImageSpan(
                        it, verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                    )
                ) {
                    append(" ")
                }
            }
        }
    }

    private fun trim(displayDataList: List<DisplayData>): List<DisplayData> {
        return displayDataList.map {
            if (it.canTrim) {
                val keepCharCount = it.keepCharCount - 1
                val toDisplay = trimDisplayValue(it.original, keepCharCount, it.isDomain)
                if (it.toDisplay == toDisplay) {
                    it.copy(canTrim = false)
                } else {
                    it.copy(
                        toDisplay = toDisplay,
                        keepCharCount = keepCharCount,
                        canTrim = keepCharCount > 3
                    )
                }
            } else {
                it
            }
        }
    }

    private fun canTrim(displayDataList: List<DisplayData>): Boolean {
        return displayDataList.any { it.canTrim }
    }

    private fun trimDisplayValue(value: String, keepCount: Int, isDomain: Boolean) = if (isDomain) {
        getDomainTrimAction()(value, keepCount)
    } else {
        value.trimAddress(keepCount)
    }

    private data class DisplayData(
        val chainName: String,
        val original: String,
        val toDisplay: String,
        val isDomain: Boolean,
        val keepCharCount: Int,
        val canTrim: Boolean
    )

    data class Style(
        val singleChainStyle: ChainStyle,
        val multipleChainStyle: ChainStyle,
        val chainIconSize: Int,
        val prefixIconSize: Int,
        val prefixIconMargin: Int,
        val postfixIconSize: Size,
        val postfixIconMargin: Int,
        val chainIconResMap: Map<String, Int>,
        val tintChainIcon: Boolean,
        val prefixIconResList: List<Int>,
        val postfixIconResList: List<Int>,
        val delimiter: String,
        val delimiterWidth: Int
    )

    data class ChainStyle(
        val displayChainIcon: Boolean,
        val letterSpacing: Float = 0f,
        val iconMargin: Int,
        val addressKeepCount: Int,
        val domainKeepCount: Int,
        val domainTrimRule: DomainTrimRule,
        val domainLetterSpacing: Float? = null,
        val addressLetterSpacing: Float? = null
    )

    enum class DomainTrimRule {
        KEEP_TOP_LEVEL_DOMAIN, SYMMETRIC
    }

    companion object {
        // Home screen styles
        val walletStyle: Style = Style(
            singleChainStyle = ChainStyle(
                displayChainIcon = true,
                iconMargin = 6.dp,
                addressKeepCount = 12,
                domainKeepCount = 16,
                domainTrimRule = DomainTrimRule.KEEP_TOP_LEVEL_DOMAIN
            ),
            multipleChainStyle = ChainStyle(
                displayChainIcon = true,
                iconMargin = 2.dp,
                addressKeepCount = 6,
                domainKeepCount = 10,
                domainTrimRule = DomainTrimRule.KEEP_TOP_LEVEL_DOMAIN
            ),
            chainIconSize = 16.dp,
            prefixIconSize = 16.dp,
            prefixIconMargin = 0.dp,
            postfixIconSize = Size(16.dp, 16.dp),
            postfixIconMargin = 0.dp,
            chainIconResMap = mapOf(
                MBlockchain.ton.name to R.drawable.ic_blockchain_ton_128,
                MBlockchain.tron.name to R.drawable.ic_blockchain_tron_40
            ),
            tintChainIcon = false,
            prefixIconResList = emptyList(),
            postfixIconResList = emptyList(),
            delimiter = ", ",
            delimiterWidth = 0
        )

        val walletExpandStyle: Style = walletStyle.copy(
            prefixIconMargin = 4.dp,
            postfixIconResList = listOf(R.drawable.ic_arrows_14),
            postfixIconSize = Size(7.dp, 14.dp),
            postfixIconMargin = 4.5f.dp.roundToInt()
        )

        // Customization screen styles
        val walletCustomizationStyle: Style = walletStyle.copy(
            multipleChainStyle = walletStyle.multipleChainStyle.copy(
                addressKeepCount = 4
            ),
            prefixIconMargin = 6.dp,
        )

        val walletCustomizationViewStyle: Style = walletCustomizationStyle.copy(
            prefixIconResList = listOf(org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_eye)
        )

        val walletCustomizationHardwareStyle: Style = walletCustomizationStyle.copy(
            prefixIconResList = listOf(org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_ledger)
        )

        // Select wallet card screen styles
        val miniCardWalletStyle: Style = Style(
            singleChainStyle = ChainStyle(
                displayChainIcon = false,
                iconMargin = 0.dp,
                addressKeepCount = 8,
                domainKeepCount = 12,
                domainTrimRule = DomainTrimRule.KEEP_TOP_LEVEL_DOMAIN
            ),
            multipleChainStyle = ChainStyle(
                displayChainIcon = true,
                iconMargin = 1.dp,
                addressKeepCount = 4,
                domainKeepCount = 5,
                domainTrimRule = DomainTrimRule.SYMMETRIC
            ),
            chainIconSize = 9.dp,
            prefixIconSize = 12.dp,
            prefixIconMargin = 4.dp,
            postfixIconSize = Size(12.dp, 12.dp),
            postfixIconMargin = 0.dp,
            chainIconResMap = mapOf(
                MBlockchain.ton.name to R.drawable.ic_symbol_ton,
                MBlockchain.tron.name to R.drawable.ic_symbol_tron
            ),
            tintChainIcon = true,
            prefixIconResList = emptyList(),
            postfixIconResList = emptyList(),
            delimiter = "",
            delimiterWidth = 2.dp
        )

        val miniCardWalletSelectedStyle: Style = miniCardWalletStyle

        val miniCardWalletViewStyle: Style = miniCardWalletStyle.copy(
            prefixIconResList = listOf(org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_eye)
        )

        val miniCardWalletHardwareStyle: Style = miniCardWalletStyle.copy(
            prefixIconResList = listOf(org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_ledger)
        )

        // Select wallet card row screen styles
        val cardRowWalletStyle: Style = Style(
            singleChainStyle = ChainStyle(
                displayChainIcon = false,
                iconMargin = 0.dp,
                addressKeepCount = 12,
                domainKeepCount = 100,
                domainTrimRule = DomainTrimRule.KEEP_TOP_LEVEL_DOMAIN
            ),
            multipleChainStyle = ChainStyle(
                displayChainIcon = true,
                iconMargin = 2.dp,
                addressKeepCount = 6,
                domainKeepCount = 10,
                domainTrimRule = DomainTrimRule.KEEP_TOP_LEVEL_DOMAIN,
                domainLetterSpacing = -0.002f
            ),
            chainIconSize = 10.dp,
            prefixIconSize = 12.dp,
            prefixIconMargin = 4.dp,
            postfixIconSize = Size(12.dp, 12.dp),
            postfixIconMargin = 0.dp,
            chainIconResMap = mapOf(
                MBlockchain.ton.name to R.drawable.ic_symbol_ton,
                MBlockchain.tron.name to R.drawable.ic_symbol_tron
            ),
            tintChainIcon = true,
            prefixIconResList = emptyList(),
            postfixIconResList = emptyList(),
            delimiter = ",",
            delimiterWidth = 3.dp
        )

        val cardRowWalletViewStyle: Style = cardRowWalletStyle.copy(
            prefixIconResList = listOf(org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_eye)
        )

        val cardRowWalletHardwareStyle: Style = cardRowWalletStyle.copy(
            prefixIconResList = listOf(org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_ledger)
        )

        // Select wallet card row screen styles
        val settingsHeaderWalletStyle: Style = Style(
            singleChainStyle = ChainStyle(
                displayChainIcon = false,
                iconMargin = 0.dp,
                addressKeepCount = 12,
                domainKeepCount = 100,
                domainTrimRule = DomainTrimRule.KEEP_TOP_LEVEL_DOMAIN
            ),
            multipleChainStyle = ChainStyle(
                displayChainIcon = true,
                iconMargin = 1.5f.dp.roundToInt(),
                addressKeepCount = 6,
                domainKeepCount = 12,
                domainTrimRule = DomainTrimRule.KEEP_TOP_LEVEL_DOMAIN,
                domainLetterSpacing = -0.002f
            ),
            chainIconSize = 12.dp,
            prefixIconSize = 16.dp,
            prefixIconMargin = 5.dp,
            postfixIconSize = Size(0, 0),
            postfixIconMargin = 0.dp,
            chainIconResMap = mapOf(
                MBlockchain.ton.name to R.drawable.ic_symbol_ton,
                MBlockchain.tron.name to R.drawable.ic_symbol_tron
            ),
            tintChainIcon = true,
            prefixIconResList = emptyList(),
            postfixIconResList = emptyList(),
            delimiter = ",",
            delimiterWidth = 4.dp
        )

        val settingsHeaderWalletViewStyle: Style = settingsHeaderWalletStyle.copy(
            prefixIconResList = listOf(org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_eye)
        )

        val settingsHeaderWalletHardwareStyle: Style = settingsHeaderWalletStyle.copy(
            prefixIconResList = listOf(org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_ledger)
        )
    }
}
