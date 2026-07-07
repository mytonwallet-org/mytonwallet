package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.graphics.toColorInt
import androidx.core.view.doOnPreDraw
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.sp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.ScrollStateHorizontalScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Positioning
import org.mytonwallet.app_air.walletbasecontext.R
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletcore.tokenSlugToStakingSlug
import androidx.core.view.isVisible
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TabletHeaderActionsView(
    context: Context,
    var tabs: List<Item>,
    var onClick: ((HeaderActionsView.Identifier) -> Unit)?,
) : WCell(context), WThemedView, IHeaderActionsView {

    var onHorizontalScroll: (() -> Unit)? = null

    private var actionViews = HashMap<HeaderActionsView.Identifier, TabletHeaderActionItem>()
    var tabsLocalized = if (LocaleController.isRTL) tabs.asReversed() else tabs

    private var itemViews = ArrayList<TabletHeaderActionItem>()
    private var account: MAccount? = null

    private val itemsContainer = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        clipChildren = false
        clipToPadding = false
    }

    private val scrollView = ScrollStateHorizontalScrollView(context).apply {
        id = generateViewId()
        isHorizontalScrollBarEnabled = false
        clipChildren = false
        clipToPadding = false
        overScrollMode = OVER_SCROLL_NEVER
        addView(itemsContainer, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        onScrollChange = { this@TabletHeaderActionsView.onHorizontalScroll?.invoke() }
    }

    override val isScrolling: Boolean
        get() = scrollView.scrollState != ScrollStateHorizontalScrollView.SCROLL_STATE_IDLE

    override val horizontalScrollOffset: Int
        get() = scrollView.horizontalScrollOffset()

    init {
        layoutParams = LayoutParams(MATCH_PARENT, HEIGHT.dp).apply {
            insetsUpdated()
        }
        layoutDirection = LAYOUT_DIRECTION_LTR
        clipChildren = false
        clipToPadding = false
    }

    override fun setupViews() {
        super.setupViews()

        addView(scrollView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setConstraints {
            allEdges(scrollView)
        }

        configureViews()
    }

    private fun generateItems() {
        actionViews.clear()
        itemViews.clear()

        val arr = ArrayList<TabletHeaderActionItem>()
        for (tab in tabsLocalized) {
            val tabItem = TabletHeaderActionItem(context, tab)
            actionViews[tab.identifier] = tabItem
            arr.add(tabItem)
        }
        itemViews = arr
        updateTextSizes()
    }

    private fun configureViews() {
        itemsContainer.removeAllViews()
        generateItems()
        appliedItemSize = -1
        itemViews.forEachIndexed { index, itemView ->
            itemsContainer.addView(
                itemView,
                LinearLayout.LayoutParams(MAX_ITEM_SIZE.dp, MAX_ITEM_SIZE.dp).apply {
                    if (index != 0) {
                        leftMargin = MAX_ITEM_MARGIN.dp
                    }
                })
            val identifier = tabsLocalized[index].identifier
            itemView.setOnClickListener {
                if (alpha > 0) {
                    onClick?.invoke(identifier)
                }
            }
            if (identifier == HeaderActionsView.Identifier.SEND) {
                itemView.setOnLongClickListener {
                    if (alpha > 0) {
                        Haptics.play(this, HapticType.LIGHT_TAP)
                        presentSendSellMenu(itemView)
                        return@setOnLongClickListener true
                    }
                    return@setOnLongClickListener false
                }
            }
        }
        insetsUpdated()
        updateTheme()
        this.account?.let { account ->
            updateActions(account)
        }
    }

    private var appliedItemSize = -1

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        applyItemSizing(MeasureSpec.getSize(widthMeasureSpec))
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    private fun applyItemSizing(availableWidth: Int) {
        if (availableWidth <= 0)
            return
        val visibleCount = itemViews.count { it.isVisible }
        if (visibleCount == 0)
            return
        val marginsCount = visibleCount - 1
        val minRequiredWidth =
            visibleCount * MIN_ITEM_SIZE.dp + marginsCount * MIN_ITEM_MARGIN.dp
        val growRange = visibleCount * (MAX_ITEM_SIZE - MIN_ITEM_SIZE).dp +
            marginsCount * (MAX_ITEM_MARGIN - MIN_ITEM_MARGIN).dp
        val fraction =
            ((availableWidth - minRequiredWidth).toFloat() / growRange).coerceIn(0f, 1f)
        val itemSize =
            lerp(MIN_ITEM_SIZE.toFloat(), MAX_ITEM_SIZE.toFloat(), fraction).toInt().dp
        if (itemSize == appliedItemSize)
            return
        appliedItemSize = itemSize
        val itemMargin =
            lerp(MIN_ITEM_MARGIN.toFloat(), MAX_ITEM_MARGIN.toFloat(), fraction).toInt().dp
        itemViews.forEachIndexed { index, itemView ->
            (itemView.layoutParams as LinearLayout.LayoutParams).apply {
                width = itemSize
                height = itemSize
                if (index != 0) {
                    leftMargin = itemMargin
                }
            }
            itemView.applySizeFraction(fraction)
        }
        updateTextSizes()
    }

    private fun isSellAllowed(): Boolean {
        return account?.supportsBuyWithCard == true// && ConfigStore.isLimited != true
    }

    private fun presentSendSellMenu(anchorView: View) {
        val items = mutableListOf<WMenuPopup.Item>()
        items.add(
            WMenuPopup.Item(
                R.drawable.ic_header_popup_menu_send_outline,
                LocaleController.getString("Send"),
            ) {
                onClick?.invoke(HeaderActionsView.Identifier.SEND)
            }
        )
        items.add(
            WMenuPopup.Item(
                R.drawable.ic_header_popup_menu_multisend_outline,
                LocaleController.getString("Multisend"),
            ) {
                onClick?.invoke(HeaderActionsView.Identifier.MULTISEND)
            }
        )
        if (isSellAllowed()) {
            items.add(
                WMenuPopup.Item(
                    R.drawable.ic_header_popup_menu_sell_outline,
                    LocaleController.getString("Sell"),
                ) {
                    onClick?.invoke(HeaderActionsView.Identifier.SELL)
                }
            )
        }
        WMenuPopup.present(
            anchorView,
            items,
            positioning = Positioning.BELOW,
            backdropStyle = WMenuPopup.BackdropStyle.Transparent,
            usePillShadow = true
        )
    }

    data class Item(
        val identifier: HeaderActionsView.Identifier,
        val icon: Drawable,
        val title: String
    )

    override fun insetsUpdated() {
    }

    override val isTinted = true
    override fun updateTheme() {
        val iconBackgroundColor =
            if (ThemeManager.isDark) "#1F1F1F".toColorInt() else "#FCFCFD".toColorInt()
        val shadowColor =
            if (ThemeManager.isDark) "#40000000".toColorInt() else "#0F003C5D".toColorInt()
        val accentColor = WColor.Tint.color
        val accentShadowColor = (accentColor and 0x00FFFFFF) or 0x60000000
        val iconColor = WColor.Icon.color

        for (itemView in itemViews) {
            itemView.background =
                ItemShadowDrawable(iconBackgroundColor, shadowColor, accentShadowColor)

            itemView.iconView.setColorFilter(iconColor)
            itemView.label.setTextColor(iconColor)
        }
    }

    private class ItemShadowDrawable(
        private val backgroundColor: Int,
        private val normalShadowColor: Int,
        private val pressedShadowColor: Int
    ) : Drawable() {

        private var isPressed = false

        private val rectPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = backgroundColor
        }

        private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.TRANSPARENT
        }

        override fun draw(canvas: Canvas) {
            val cornerRadius = bounds.height() / 4f

            val shadowColor =
                if (isPressed) pressedShadowColor else normalShadowColor

            shadowPaint.setShadowLayer(
                10f.dp,
                0f,
                3f.dp,
                shadowColor
            )

            val rect = RectF(bounds)

            canvas.drawRoundRect(
                rect,
                cornerRadius,
                cornerRadius,
                shadowPaint
            )

            canvas.drawRoundRect(
                rect,
                cornerRadius,
                cornerRadius,
                rectPaint
            )
        }

        override fun isStateful(): Boolean = true

        override fun onStateChange(state: IntArray): Boolean {
            val pressed = state.contains(android.R.attr.state_pressed)

            if (pressed != isPressed) {
                isPressed = pressed
                invalidateSelf()
                return true
            }

            return false
        }

        override fun setAlpha(alpha: Int) {
            rectPaint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            rectPaint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    fun updateTextSizes() {
        doOnPreDraw {
            val labels = itemViews.map { it.label }
            var finalSize = 14f
            val minSize = 8f
            val step = 1f
            while (finalSize >= minSize) {
                val fitsAll = labels.all { label ->
                    label.paint.textSize = finalSize.sp
                    val textWidth = label.paint.measureText(label.text.toString())
                    label.width == 0 || textWidth <= label.width
                }
                if (fitsAll) break
                finalSize -= step
            }
            labels.forEach { label ->
                label.setTextSize(TypedValue.COMPLEX_UNIT_SP, finalSize)
                label.requestLayout()
            }
        }
    }

    override var fadeInPercent: Float = 1f
        set(value) {
            if (field == value)
                return
            field = value
            val alphaValue = ((value - 0.4f) * 5 / 3).coerceAtLeast(0f)
            alpha = alphaValue
        }

    override fun onDestroy() {
        onClick = null
    }

    override fun updateActions(account: MAccount?, tokenSlug: String?) {
        if (account?.accountId != this.account?.accountId) {
            scrollView.resetScroll()
        }
        this.account = account
        val isMainNet = account?.isMainnet == true
        val isLpToken = TokenStore.getToken(tokenSlug)?.isLpToken == true
        setBuyVisibility(isSellAllowed())
        setSellVisibility(isSellAllowed())
        setReceiveVisibility(account?.supportsReceiveScreen == true)
        setSendVisibility(account?.accountType != MAccount.AccountType.VIEW)
        setEarnVisibility(isMainNet)
        setSwapVisibility(account?.supportsSwap == true && !isLpToken)
        updateEarnTitle(account, tokenSlug)
    }

    private fun updateEarnTitle(account: MAccount?, tokenSlug: String?) {
        val label = actionViews[HeaderActionsView.Identifier.EARN]?.label ?: return
        val hasActiveStaking = account?.let { currentAccount ->
            val stakingTokenSlug = tokenSlug?.let { tokenSlugToStakingSlug(it) ?: it }
            StakingStore.getStakingState(currentAccount.accountId)?.let { stakingData ->
                if (stakingTokenSlug != null) {
                    stakingData.hasActiveStaking(stakingTokenSlug)
                } else {
                    stakingData.hasActiveStaking()
                }
            } ?: false
        } ?: false
        val title = LocaleController.getString(if (hasActiveStaking) "Earning" else "Earn")
        if (label.text == title) {
            return
        }
        label.text = title
        updateTextSizes()
    }

    private fun setBuyVisibility(visible: Boolean) {
        actionViews[HeaderActionsView.Identifier.BUY]?.visibility = if (visible) VISIBLE else GONE
    }

    private fun setSellVisibility(visible: Boolean) {
        actionViews[HeaderActionsView.Identifier.SELL]?.visibility = if (visible) VISIBLE else GONE
    }

    private fun setReceiveVisibility(visible: Boolean) {
        actionViews[HeaderActionsView.Identifier.RECEIVE]?.visibility =
            if (visible) VISIBLE else GONE
    }

    private fun setSendVisibility(visible: Boolean) {
        actionViews[HeaderActionsView.Identifier.SEND]?.visibility = if (visible) VISIBLE else GONE
    }

    private fun setSwapVisibility(visible: Boolean) {
        actionViews[HeaderActionsView.Identifier.SWAP]?.visibility = if (visible) VISIBLE else GONE
    }

    private fun setEarnVisibility(visible: Boolean) {
        actionViews[HeaderActionsView.Identifier.EARN]?.visibility = if (visible) VISIBLE else GONE
    }

    private class TabletHeaderActionItem(
        context: Context,
        item: Item
    ) : WView(context) {
        val iconView: AppCompatImageView = AppCompatImageView(context).apply {
            id = generateViewId()
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageDrawable(item.icon)
        }
        val label: WLabel = WLabel(context).apply {
            setSingleLine()
            setStyle(14f, WFont.Medium)
            text = item.title
        }

        init {
            clipChildren = false
            clipToPadding = false

            addView(
                iconView,
                FrameLayout.LayoutParams(
                    MAX_ICON_INNER_SIZE.dp,
                    MAX_ICON_INNER_SIZE.dp,
                    Gravity.CENTER
                )
            )
            addView(label, LayoutParams(MATCH_PARENT, 20.dp))

            applySizeFraction(1f)
        }

        fun applySizeFraction(fraction: Float) {
            val iconSize =
                lerp(MIN_ICON_INNER_SIZE.toFloat(), MAX_ICON_INNER_SIZE.toFloat(), fraction)
                    .toInt().dp
            iconView.layoutParams = iconView.layoutParams?.apply {
                width = iconSize
                height = iconSize
            } ?: FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER)
            val iconPadding = lerp(8f, 12f, fraction)
            val textMargin = lerp(10.66f, 16f, fraction).dp.roundToInt()
            setConstraints {
                toCenterXPx(label, textMargin)
                toBottom(label, lerp(4f, 12f, fraction))
                toTop(iconView, iconPadding)
                toStart(iconView, iconPadding)
            }
        }
    }

    companion object {
        const val HEIGHT = 116
        private const val MIN_ITEM_SIZE = 64
        private const val MAX_ITEM_SIZE = 96
        private const val MIN_ITEM_MARGIN = 8
        private const val MAX_ITEM_MARGIN = 16
        private const val MIN_ICON_INNER_SIZE = 24
        private const val MAX_ICON_INNER_SIZE = 32

        fun headerTabs(context: Context, showEarn: Boolean): List<Item> {
            return mutableListOf<Item>().apply {
                add(
                    Item(
                        HeaderActionsView.Identifier.BUY,
                        context.requireDrawableCompat(R.drawable.ic_header_buy_outline),
                        LocaleController.getString("Buy")
                    )
                )
                add(
                    Item(
                        HeaderActionsView.Identifier.RECEIVE,
                        context.requireDrawableCompat(R.drawable.ic_header_deposit_outline),
                        LocaleController.getString("Deposit")
                    )
                )
                add(
                    Item(
                        HeaderActionsView.Identifier.SWAP,
                        context.requireDrawableCompat(R.drawable.ic_header_swap_outline),
                        LocaleController.getString("Trade")
                    )
                )
                if (showEarn) {
                    add(
                        Item(
                            HeaderActionsView.Identifier.EARN,
                            context.requireDrawableCompat(R.drawable.ic_header_earn_outline),
                            LocaleController.getString("Earn")
                        )
                    )
                }
                add(
                    Item(
                        HeaderActionsView.Identifier.SELL,
                        context.requireDrawableCompat(R.drawable.ic_header_sell_outline),
                        LocaleController.getString("Sell")
                    )
                )
                add(
                    Item(
                        HeaderActionsView.Identifier.SEND,
                        context.requireDrawableCompat(R.drawable.ic_header_send_outline),
                        LocaleController.getString("Send")
                    )
                )
                add(
                    Item(
                        HeaderActionsView.Identifier.SCAN_QR,
                        context.requireDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_qr_code_scan_18_24),
                        LocaleController.getString("Scan QR")
                    )
                )
            }
        }
    }
}
