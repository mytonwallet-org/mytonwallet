package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.content.ContextCompat
import androidx.core.graphics.toColorInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.sp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Positioning
import org.mytonwallet.app_air.walletbasecontext.R
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.tokenSlugToStakingSlug
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class HeaderActionsView(
    context: Context,
    var tabs: List<Item>,
    var onClick: ((Identifier) -> Unit)?,
) : WCell(context), WThemedView {

    private var actionViews = HashMap<Identifier, HeaderActionItem>()
    var tabsLocalized = if (LocaleController.isRTL) tabs.asReversed() else tabs

    private var itemViews = ArrayList<HeaderActionItem>()
    private var account: MAccount? = null

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

        configureViews()
    }

    fun resetTabs(tabs: List<Item>) {
        this.tabs = tabs
        tabsLocalized = if (LocaleController.isRTL) tabs.asReversed() else tabs
        configureViews()
    }

    private fun generateItems() {
        actionViews.clear()
        itemViews.clear()

        val arr = ArrayList<HeaderActionItem>()
        for (tab in tabsLocalized) {
            val tabItem = HeaderActionItem(context, tab)
            actionViews[tab.identifier] = tabItem
            arr.add(tabItem)
        }
        itemViews = arr
        updateTextSizes()
    }

    private fun configureViews() {
        removeAllViews()
        generateItems()
        itemViews.forEachIndexed { index, itemView ->
            addView(
                itemView,
                LayoutParams(if (itemViews.size == 1) MATCH_PARENT else 0, MATCH_PARENT).apply {
                    if (index != 0) {
                        leftMargin = 11.dp
                    }
                })
            val identifier = tabsLocalized[index].identifier
            itemView.setOnClickListener {
                if (alpha > 0) {
                    onClick?.invoke(identifier)
                }
            }
            if (identifier == Identifier.SEND) {
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
        setConstraints {
            itemViews.forEachIndexed { index, itemView ->
                toTop(itemView)
                toBottom(itemView)
                when (index) {
                    0 -> leftToLeft(this@HeaderActionsView, itemView)
                    else -> leftToRight(itemViews[index - 1], itemView)
                }
            }
            rightToRight(this@HeaderActionsView, itemViews.last())
            if (itemViews.size > 1) {
                createHorizontalChain(
                    ConstraintSet.PARENT_ID, ConstraintSet.LEFT,
                    ConstraintSet.PARENT_ID, ConstraintSet.RIGHT,
                    itemViews.map { it.id }.toIntArray(),
                    null,
                    ConstraintSet.CHAIN_SPREAD
                )
            }
        }

        insetsUpdated()
        updateTheme()
        this.account?.let { account ->
            updateActions(account)
        }
    }

    private fun isSellAllowed(): Boolean {
        return account?.supportsBuyWithCard == true && ConfigStore.isLimited != true
    }

    private fun presentSendSellMenu(anchorView: View) {
        val items = mutableListOf<WMenuPopup.Item>()
        items.add(
            WMenuPopup.Item(
                R.drawable.ic_header_popup_menu_send_outline,
                LocaleController.getString("Send"),
            ) {
                onClick?.invoke(Identifier.SEND)
            }
        )
        items.add(
            WMenuPopup.Item(
                R.drawable.ic_header_popup_menu_multisend_outline,
                LocaleController.getString("Multisend"),
            ) {
                onClick?.invoke(Identifier.MULTISEND)
            }
        )
        if (isSellAllowed()) {
            items.add(
                WMenuPopup.Item(
                    R.drawable.ic_header_popup_menu_sell_outline,
                    LocaleController.getString("Sell"),
                ) {
                    onClick?.invoke(Identifier.SELL)
                }
            )
        }
        WMenuPopup.present(
            anchorView,
            items,
            positioning = Positioning.BELOW
        )
    }

    data class Item(
        val identifier: Identifier,
        val icon: Drawable,
        val title: String
    )

    enum class Identifier {
        RECEIVE,
        SEND,
        MULTISEND,
        SELL,
        EARN,
        SWAP,
        LOCK_APP,
        TOGGLE_SENSITIVE_DATA_PROTECTION,
        SCAN_QR,
        SCROLL_TO_TOP,
        DETAILS,
        REPEAT,
        SHARE,
        WALLET_SETTINGS,
        BACK,
    }

    fun insetsUpdated() {
        val extraPadding = when (itemViews.size) {
            2 -> 48f
            3 -> 32f
            4 -> 20f
            else -> 0f
        }
        setPadding(
            (17.5f - ViewConstants.HORIZONTAL_PADDINGS + extraPadding).dp.roundToInt(),
            paddingTop,
            (17.5f - ViewConstants.HORIZONTAL_PADDINGS + extraPadding).dp.roundToInt(),
            paddingBottom
        )
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
            itemView.iconContainer.background =
                CircleShadowDrawable(iconBackgroundColor, shadowColor, accentShadowColor)

            itemView.iconView.setColorFilter(iconColor)
            itemView.label.setTextColor(iconColor)
        }
    }

    private class CircleShadowDrawable(
        private val circleColor: Int,
        private val normalShadowColor: Int,
        private val pressedShadowColor: Int
    ) : Drawable() {
        private var isPressed = false

        private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = circleColor
        }
        private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.TRANSPARENT
        }

        override fun draw(canvas: Canvas) {
            val centerX = bounds.width() / 2f
            val centerY = bounds.height() / 2f
            val radius = minOf(bounds.width(), bounds.height()) / 2f

            val shadowColor = if (isPressed) pressedShadowColor else normalShadowColor
            shadowPaint.setShadowLayer(10f.dp, 0f, 3f.dp, shadowColor)
            canvas.drawCircle(centerX, centerY, radius, shadowPaint)
            canvas.drawCircle(centerX, centerY, radius, circlePaint)
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
            circlePaint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {
            circlePaint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    fun updateTextSizes() {
        post {
            val labels = itemViews.map { it.label }
            var finalSize = 13f
            val minSize = 8f
            val step = 1f
            while (finalSize >= minSize) {
                val fitsAll = labels.all { label ->
                    label.paint.textSize = finalSize.sp
                    val textWidth = label.paint.measureText(label.text.toString())
                    label.width == 0 || textWidth <= label.width - 8.dp
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

    var fadeInPercent: Float = 1f
        set(value) {
            if (field == value)
                return
            field = value
            val alphaValue = ((value - 0.4f) * 5 / 3).coerceAtLeast(0f)
            alpha = alphaValue
            itemViews.forEach {
                it.iconContainer.apply {
                    scaleX = alphaValue
                    scaleY = alphaValue
                }
            }
        }

    fun onDestroy() {
        onClick = null
    }

    fun updateActions(account: MAccount?, tokenSlug: String? = null) {
        this.account = account
        val isMainNet = account?.network == MBlockchainNetwork.MAINNET
        setSendVisibility(account?.accountType != MAccount.AccountType.VIEW)
        setEarnVisibility(isMainNet)
        setSwapVisibility(isMainNet && account.accountType == MAccount.AccountType.MNEMONIC)
        updateEarnTitle(account, tokenSlug)
    }

    private fun updateEarnTitle(account: MAccount?, tokenSlug: String?) {
        val label = actionViews[Identifier.EARN]?.label ?: return
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

    private fun setSendVisibility(visible: Boolean) {
        actionViews[Identifier.SEND]?.visibility = if (visible) VISIBLE else GONE
    }

    private fun setSwapVisibility(visible: Boolean) {
        actionViews[Identifier.SWAP]?.visibility = if (visible) VISIBLE else GONE
    }

    private fun setEarnVisibility(visible: Boolean) {
        actionViews[Identifier.EARN]?.visibility = if (visible) VISIBLE else GONE
    }

    private class HeaderActionItem(
        context: Context,
        item: Item
    ) : WView(context) {
        val iconContainer: WFrameLayout = WFrameLayout(context).apply {
            pivotX = ICON_SIZE.dp / 2f
            pivotY = ICON_SIZE.dp.toFloat()
        }
        val iconView: AppCompatImageView = AppCompatImageView(context).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageDrawable(item.icon)
        }
        val label: WLabel = WLabel(context).apply {
            gravity = Gravity.CENTER
            setSingleLine()
            setStyle(13f, WFont.Regular)
            text = item.title
        }

        init {
            clipChildren = false
            clipToPadding = false

            iconContainer.addView(
                iconView,
                FrameLayout.LayoutParams(ICON_INNER_SIZE.dp, ICON_INNER_SIZE.dp, Gravity.CENTER)
            )
            addView(iconContainer, LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp))
            addView(label, LayoutParams(MATCH_PARENT, 20.dp))

            setConstraints {
                toCenterX(label)
                toBottom(label)
                toTop(iconContainer, 14f)
                toCenterX(iconContainer)
                bottomToTop(iconContainer, label, 12f)
            }
        }
    }

    companion object {
        const val HEIGHT = 94
        private const val ICON_SIZE = 44
        private const val ICON_INNER_SIZE = 30

        fun headerTabs(context: Context, showEarn: Boolean): List<Item> {
            return mutableListOf<Item>().apply {
                add(
                    Item(
                        Identifier.RECEIVE,
                        ContextCompat.getDrawable(
                            context,
                            R.drawable.ic_header_add_outline
                        )!!,
                        LocaleController.getString("Fund")
                    )
                )
                add(
                    Item(
                        Identifier.SEND,
                        ContextCompat.getDrawable(context, R.drawable.ic_header_send_outline)!!,
                        LocaleController.getString("Send")
                    )
                )
                add(
                    Item(
                        Identifier.SWAP,
                        ContextCompat.getDrawable(context, R.drawable.ic_header_swap_outline)!!,
                        LocaleController.getString("Swap")
                    )
                )
                if (showEarn) {
                    add(
                        Item(
                            Identifier.EARN,
                            ContextCompat.getDrawable(context, R.drawable.ic_header_earn_outline)!!,
                            LocaleController.getString("Earn")
                        )
                    )
                }
            }
        }
    }
}
