package org.mytonwallet.app_air.uifutures.viewControllers.futuresActivity

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.ClickableSpan
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.widget.NestedScrollView
import java.util.Date
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.ClipboardHelpers
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.formatFuturesChange
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.formatFuturesDuration
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.pnlColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPriceString
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatDateAndTime
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsActivityType
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFill

@SuppressLint("ViewConstructor")
class FuturesActivityVC(context: Context, private val activity: MApiPerpsFill) :
    WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "FuturesActivity"

    override val isSwipeBackAllowed = false

    private val isLiquidated = activity.activityType == MApiPerpsActivityType.LIQUIDATED

    private val isDetailsExpandedByDefault: Boolean
        get() = navigationController?.isCenteredWindow == true ||
            navigationController?.isShortWideWindow == true

    private val effectiveExpandProgress: Float
        get() = if (isDetailsExpandedByDefault) 1f else (modalExpandProgress ?: 0f)

    private val headerView = FuturesActivityHeaderView(
        context,
        activity.asset,
        activity.resolvedSide,
        activity.badgeText,
        activity.headerAmount,
        previousAmount = activity.previousMargin.takeIf {
            !activity.isResult && activity.headerTradeSize == null
        },
        showsSign = activity.isResult,
        amountColor = WColor.Red.takeIf { isLiquidated },
        isSensitiveData = true
    )

    // Draws the card, so the container's padding insets it as the sheet expands
    private val headerCardView = WFrameLayout(context).apply {
        addView(
            headerView,
            FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = 24.dp
                bottomMargin = 26.dp
            }
        )
    }
    private val headerViewContainer = WFrameLayout(context).apply {
        addView(headerCardView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private fun generateActions(): List<HeaderActionsView.Item> = listOfNotNull(
        if (!isDetailsExpandedByDefault) {
            HeaderActionsView.Item(
                HeaderActionsView.Identifier.DETAILS,
                context.requireDrawableCompat(R.drawable.ic_act_details_outline),
                LocaleController.getString("Details")
            )
        } else {
            null
        },
        HeaderActionsView.Item(
            HeaderActionsView.Identifier.SHARE,
            context.requireDrawableCompat(R.drawable.ic_act_share_outline),
            LocaleController.getString("Share")
        )
    )

    private val actionsView = HeaderActionsView(
        context,
        generateActions(),
        onClick = { identifier ->
            when (identifier) {
                HeaderActionsView.Identifier.DETAILS -> toggleModalState()
                HeaderActionsView.Identifier.SHARE -> sharePressed()
                else -> {}
            }
        }
    )

    private val sectionViews = ArrayList<LinearLayout>()
    private val detailsView = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        if (isLiquidated) {
            addView(
                liquidationNoticeView(),
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    bottomMargin = ViewConstants.GAP.dp
                }
            )
        }
        detailSections().forEachIndexed { index, rows ->
            val section = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                rows.forEach { addView(it, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)) }
            }
            sectionViews.add(section)
            addView(
                section,
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    if (index > 0) topMargin = ViewConstants.GAP.dp
                }
            )
        }
    }

    private val innerContentView: WView by lazy {
        WView(context).apply {
            addView(headerViewContainer, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(
                actionsView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, HeaderActionsView.HEIGHT.dp)
            )
            addView(detailsView, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            setConstraints {
                toTop(headerViewContainer)
                toCenterX(headerViewContainer)
                topToBottom(actionsView, headerViewContainer, ViewConstants.GAP.toFloat())
                topToBottom(detailsView, actionsView, ViewConstants.GAP.toFloat())
                toCenterX(detailsView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                toBottomPx(detailsView, navigationController?.getSystemBars()?.bottom ?: 0)
                setVerticalBias(detailsView.id, 0f)
            }
        }
    }

    private val scrollingContentView: WView by lazy {
        WView(context).apply {
            addView(innerContentView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }.also(::layoutScrollingContent)
    }

    private fun layoutScrollingContent(scrollingContentView: WView) {
        val topInset = (navigationController?.getSystemBars()?.top ?: 0) +
            WNavigationBar.DEFAULT_HEIGHT.dp
        scrollingContentView.setConstraints {
            toTopPx(innerContentView, topInset)
            constrainMinHeight(innerContentView.id, (window?.windowView?.height ?: 0) - topInset)
        }
    }

    private val scrollView: NestedScrollView by lazy {
        NestedScrollView(context).apply {
            id = View.generateViewId()
            addView(scrollingContentView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)
        navigationBar?.setTitleGravity(Gravity.START)
        setNavTitle(activity.detailsTitle, animated = false)
        setNavSubtitle(subtitle(), animated = false)
        navigationBar?.addCloseButton()

        actionsView.setPadding(0, 0, 0, 16.dp)

        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(scrollView)
        }

        updateTheme()
        applyExpandPresentation()
    }

    private var appliedDetailsExpandedByDefault: Boolean? = null
    override fun insetsUpdated() {
        super.insetsUpdated()
        innerContentView.setConstraints {
            toBottomPx(detailsView, navigationController?.getSystemBars()?.bottom ?: 0)
            toStartPx(detailsView, ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset)
            toEndPx(detailsView, ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset)
        }
        layoutScrollingContent(scrollingContentView)
        if (appliedDetailsExpandedByDefault != isDetailsExpandedByDefault) {
            appliedDetailsExpandedByDefault = isDetailsExpandedByDefault
            actionsView.resetTabs(generateActions())
        }
        applyExpandPresentation()
    }

    override fun updateTheme() {
        super.updateTheme()
        updateBackground()
        headerView.updateTheme()
        sectionViews.forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp,
                clipToBounds = true
            )
        }
    }

    private fun updateBackground() {
        val expandProgress = 10f / 3f * ((effectiveExpandProgress - 0.7f).coerceIn(0f, 1f))
        val halfExpandedRadius =
            if (ViewConstants.BLOCK_RADIUS == 0f) 24f.dp else ViewConstants.BLOCK_RADIUS.dp
        val currentRadius = (1 - expandProgress) * halfExpandedRadius
        innerContentView.setBackgroundColor(WColor.SecondaryBackground.color, currentRadius, 0f)
        if (ViewConstants.BLOCK_RADIUS == 0f) {
            headerCardView.setBackgroundColor(WColor.Background.color, currentRadius, 0f)
        } else {
            headerCardView.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp
            )
        }
        if (effectiveExpandProgress == 1f) {
            view.setBackgroundColor(WColor.SecondaryBackground.color)
        } else {
            view.background = null
        }
    }

    override fun getModalHalfExpandedHeight(): Int =
        innerContentView.top + actionsView.bottom + 36.dp

    override fun onModalSlide(expandOffset: Int, expandProgress: Float) {
        super.onModalSlide(expandOffset, expandProgress)
        applyExpandPresentation()
    }

    private fun applyExpandPresentation() {
        val progress = effectiveExpandProgress
        updateBackground()
        detailsView.alpha = progress
        val padding = (ViewConstants.HORIZONTAL_PADDINGS.dp * progress).roundToInt()
        headerViewContainer.setPaddingRelative(
            padding + systemBarStartInset,
            0,
            padding + systemBarEndInset,
            0
        )
        if (isDetailsExpandedByDefault) {
            navigationBar?.expansionValue = 1f
            view.translationY = 0f
            scrollingContentView.translationY = 0f
        }
        topReversedCornerView?.translationZ = navigationBar?.translationZ ?: 0f
    }

    /** The date, and for a closed position how long it was held when its open is known. */
    private fun subtitle(): String {
        val date = Date(activity.time).formatDateAndTime(SUBTITLE_DATE_FORMAT)
        val openedAt = activity.positionOpenedAt?.takeIf { activity.isResult } ?: return date
        val held = LocaleController.getStringWithKeyValues(
            "\$perps_held",
            listOf("%duration%" to heldDuration(activity.time - openedAt))
        )
        return "$date · $held"
    }

    private fun heldDuration(millis: Long): String {
        val minutes = (millis / MINUTE_MS).coerceAtLeast(1)
        val hours = minutes / 60
        val days = hours / 24
        return when {
            days > 0 -> formatFuturesDuration(days = days, hours = hours % 24)
            hours > 0 -> formatFuturesDuration(hours = hours, minutes = minutes % 60)
            else -> formatFuturesDuration(minutes = minutes)
        }
    }

    private fun detailSections(): List<List<KeyValueRowView>> = when {
        activity.isResult -> resultSections()
        activity.activityType == MApiPerpsActivityType.REDUCED -> reducedSections()
        else -> changeSections()
    }

    /** A closed or liquidated position: its result, size and prices, then the fees. */
    private fun resultSections(): List<List<KeyValueRowView>> = listOf(
        listOfNotNull(
            activity.collateralBefore?.toDoubleOrNull()?.let {
                row(
                    "Invested",
                    it.toUsdString(),
                    hintKey = "\$perps_invested_hint",
                    isSensitiveData = true
                )
            },
            if (isLiquidated) {
                activity.closingValue?.let {
                    row(
                        "Closing Value",
                        it.toUsdString(),
                        hintKey = "\$perps_closing_value_hint",
                        isSensitiveData = true
                    )
                }
            } else {
                profitRow()
            }
        ),
        listOfNotNull(positionSizeRow(), priceRow()),
        listOfNotNull(
            activity.payment?.takeIf { it != EMPTY_VALUE }?.let {
                row("You Received", it, isSensitiveData = true)
            },
            activity.feeAmount?.let {
                row("Fees", it.toUsdString(), hintKey = "\$perps_fees_hint", isSensitiveData = true)
            }
        ),
        listOfNotNull(activity.transferId?.let { transferIdRow(it) })
    ).withLastRows()

    /** Shown as unknown on a reduction, hidden on a close when the result is unknown. */
    private fun profitRow(): KeyValueRowView? {
        val pnl = activity.realizedPnl
        if (pnl == null && activity.isResult) return null
        val isLoss = pnl != null && pnl < 0
        return row(
            if (isLoss) "Loss" else "Profit",
            pnl?.let {
                SpannableString(it.toUsdString(showPositiveSign = true)).apply {
                    setSpan(
                        ForegroundColorSpan(
                            if (it == 0.0) WColor.PrimaryText.color else pnlColor(it)
                        ),
                        0,
                        length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            } ?: EMPTY_VALUE,
            hintKey = if (isLoss) "\$perps_loss_hint" else "\$perps_profit_hint",
            isSensitiveData = true
        )
    }

    /** Entry and exit when the open is in the fill history, the fill price otherwise. */
    private fun priceRow(): KeyValueRowView? {
        val exit = activity.price?.toPriceString() ?: EMPTY_VALUE
        val entry = activity.entryPriceAmount ?: return row(
            LocaleController.getStringWithKeyValues(
                "\$perps_asset_price",
                listOf("%asset%" to activity.name)
            ),
            exit
        )
        return row(
            if (isLiquidated) "Entry / Liquidation Price" else "Entry / Exit Price",
            "${entry.toPriceString()} / $exit"
        )
    }

    private fun liquidationNoticeView(): WAlertLabel {
        val title = LocaleController.getString("\$perps_liquidated_title")
        val text = SpannableStringBuilder(title)
            .append("\n")
            .append(LocaleController.getString("\$perps_liquidated_message"))
        text.setSpan(WTypefaceSpan(WFont.Bold), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return WAlertLabel(context, text, WColor.Red.color, coloredText = true)
    }

    /** A reduction: its realized result first, then size, prices and the payout. */
    private fun reducedSections(): List<List<KeyValueRowView>> = listOf(
        listOfNotNull(profitRow()),
        listOfNotNull(positionSizeRow(), priceRow(), liquidationPriceRow()),
        paymentRows(),
        listOfNotNull(activity.transferId?.let { transferIdRow(it) })
    ).withLastRows()

    private fun changeSections(): List<List<KeyValueRowView>> = listOf(
        listOfNotNull(positionSizeRow()),
        listOfNotNull(
            row(
                LocaleController.getStringWithKeyValues(
                    "\$perps_asset_price",
                    listOf("%asset%" to activity.name)
                ),
                activity.price?.toPriceString() ?: EMPTY_VALUE
            ),
            liquidationPriceRow()
        ),
        paymentRows(),
        listOfNotNull(activity.transferId?.let { transferIdRow(it) })
    ).withLastRows()

    /** The position size, or the trade size when the backend omits the position's. */
    private fun positionSizeRow(): KeyValueRowView? {
        activity.positionSize?.let {
            return row(
                "Position Size",
                formatFuturesChange(activity.previousAmount?.toString(), it.toString()),
                hintKey = if (activity.previousAmount == null) {
                    "\$perps_position_size_details_hint"
                } else {
                    "\$perps_position_size_change_hint"
                },
                isSensitiveData = true
            )
        }
        return activity.tradeSize?.let {
            row("Trade Size", it.toUsdString(), isSensitiveData = true)
        }
    }

    /** Trade activities carry no liquidation price. */
    private fun liquidationPriceRow() =
        row("Liquidation Price", EMPTY_VALUE, hintKey = "\$perps_liquidation_price_hint")

    private fun paymentRows() = listOfNotNull(
        activity.activityType.paymentKey?.let { key ->
            row(key, activity.payment ?: EMPTY_VALUE, isSensitiveData = true)
        },
        row(
            "Fees",
            activity.feeAmount?.toUsdString() ?: EMPTY_VALUE,
            hintKey = "\$perps_fees_hint",
            isSensitiveData = true
        )
    )

    private fun List<List<KeyValueRowView>>.withLastRows() = filter { it.isNotEmpty() }
        .onEach { rows ->
            rows.forEachIndexed { index, row -> row.setLast(index == rows.lastIndex) }
        }

    private fun row(
        key: String,
        value: CharSequence,
        hintKey: String? = null,
        isSensitiveData: Boolean = false
    ) = KeyValueRowView(context, LocaleController.getString(key), value).apply {
        this.isSensitiveData = isSensitiveData
        hintKey?.let { setHint { showAlert(this.key, LocaleController.getString(it)) } }
    }

    private fun transferIdRow(transferId: String): KeyValueRowView {
        val value = SpannableStringBuilder(transferId.formatStartEndAddress(6, 6))
        value.styleDots()
        context.getDrawableCompat(R.drawable.ic_arrows_14)?.mutate()?.let { drawable ->
            drawable.setTint(WColor.SecondaryText.color)
            drawable.alpha = 204
            drawable.setBounds(0, 0, 7.dp, 14.dp)
            value.append(
                " ",
                VerticalImageSpan(
                    drawable,
                    startPadding = 3.5f.dp.roundToInt(),
                    verticalOffsetEm = FontManager.inlineIconVerticalOffsetEm,
                    isRTL = false
                ),
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        val row = row("Transfer ID", value)
        value.setSpan(
            object : ClickableSpan() {
                override fun onClick(widget: View) {
                    presentTransferIdMenu(row.valueLabel.contentView, transferId)
                }

                override fun updateDrawState(ds: TextPaint) {
                    super.updateDrawState(ds)
                    ds.color = WColor.PrimaryText.color
                    ds.isUnderlineText = false
                }
            },
            0,
            value.length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        row.setValue(value)
        return row
    }

    private fun presentTransferIdMenu(anchor: View, transferId: String) {
        WMenuPopup.present(
            anchor,
            listOf(
                WMenuPopup.Item(R.drawable.ic_copy_30, LocaleController.getString("Copy")) {
                    if (ClipboardHelpers.copyToClipboard(context, "", transferId)) {
                        Haptics.play(context, HapticType.LIGHT_TAP)
                        Toast.makeText(
                            context,
                            LocaleController.getString("Copied"),
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            ),
            yOffset = 0,
            popupWidth = WRAP_CONTENT,
            positioning = WMenuPopup.Positioning.BELOW,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(anchor, roundRadius = 16f.dp)
        )
    }

    private fun sharePressed() {
        val text = listOf(
            activity.detailsTitle,
            "${activity.title} · ${activity.badgeText}",
            activity.headerAmount.toUsdString()
        ).joinToString("\n")
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        window?.startActivity(
            Intent.createChooser(shareIntent, LocaleController.getString("Share"))
        )
    }

    private companion object {
        const val EMPTY_VALUE = "—"
        const val SUBTITLE_DATE_FORMAT = "MMMM d, HH:mm"
        const val MINUTE_MS = 60_000L
    }
}

internal fun WViewController.presentFuturesActivity(activity: MApiPerpsFill) {
    val window = window ?: return
    val nav = WNavigationController(
        window,
        WNavigationController.PresentationConfig(
            style = WNavigationController.PresentationStyle.BottomSheet
        )
    )
    nav.setRoot(FuturesActivityVC(context, activity))
    window.present(nav)
}
