package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells

import android.annotation.SuppressLint
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.view.isGone
import androidx.customview.widget.ViewDragHelper
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.swipeRevealLayout.SwipeRevealLayout
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.math.BigInteger
import kotlin.math.abs

@SuppressLint("ViewConstructor")
class AssetsAndActivitiesTokenCell(
    recyclerView: RecyclerView,
) : WCell(recyclerView.context, LayoutParams(MATCH_PARENT, 64.dp)),
    WThemedView {

    companion object {
        private const val MAIN_VIEW_RADIUS = 18f
    }

    lateinit var token: MToken
        private set
    private val lastItemRadius = (ViewConstants.BIG_RADIUS - 1.5f).dp

    private val redRipple = WRippleDrawable.create(0f).apply {
        backgroundColor = WColor.Red.color
        rippleColor = WColor.BackgroundRipple.color
    }

    private fun getRedRippleForLastItem() = WRippleDrawable.create(
        0f,
        0f,
        ViewConstants.BIG_RADIUS.dp,
        ViewConstants.BIG_RADIUS.dp
    ).apply {
        backgroundColor = WColor.Red.color
        rippleColor = WColor.BackgroundRipple.color
    }

    private val separatorView = WBaseView(context)

    private val imageView: IconView by lazy {
        val img = IconView(context)
        img
    }

    private val tokenNameLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
        }
    }

    private val amountLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(13f)
        lbl.layoutDirection = LAYOUT_DIRECTION_LTR
        WSensitiveDataContainer(lbl, WSensitiveDataContainer.MaskConfig(0, 2, Gravity.START))
    }

    private var skipSwitchChangeListener = false
    private val switchView: WSwitch by lazy {
        val sw = WSwitch(context)
        sw.setOnCheckedChangeListener { _, isChecked ->
            if (skipSwitchChangeListener)
                return@setOnCheckedChangeListener
            setTokenVisibility(isChecked)
        }
        sw
    }

    private val deleteLabel = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(android.util.TypedValue.COMPLEX_UNIT_SP, 24f)
        includeFontPadding = false
        ellipsize = TextUtils.TruncateAt.END
        typeface = WFont.Medium.typeface
        maxLines = 1
        text = LocaleController.getString("Delete")
    }

    val secondaryView = WView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        background = redRipple

        addView(deleteLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toCenterY(deleteLabel)
            toCenterX(deleteLabel, 20f)
        }
    }

    val mainView = WView(context, LayoutParams(MATCH_PARENT, 64.dp))

    val swipeRevealLayout = SwipeRevealLayout(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        dragEdge = SwipeRevealLayout.DRAG_EDGE_RIGHT
        isFullOpenEnabled = true
        setSwipeListener(object : SwipeRevealLayout.SwipeListener {
            override fun onClosed(view: SwipeRevealLayout?) {
                mainView.background = ViewHelpers.roundedShapeDrawable(
                    WColor.Background.color,
                    0f,
                    0f,
                    if (isLast) lastItemRadius else 0f,
                    if (isLast) lastItemRadius else 0f
                )
            }

            override fun onOpened(view: SwipeRevealLayout?) {
                mainView.background = ViewHelpers.roundedShapeDrawable(
                    WColor.Background.color,
                    0f,
                    MAIN_VIEW_RADIUS,
                    if (isLast) maxOf(
                        MAIN_VIEW_RADIUS,
                        lastItemRadius
                    ) else MAIN_VIEW_RADIUS,
                    0f
                )
            }

            override fun onFullyOpened(view: SwipeRevealLayout?) {
                onDeleteToken?.invoke()
            }

            override fun onSlide(view: SwipeRevealLayout?, slideOffset: Float) {
                val multiplier = if (slideOffset < 0.02) 0f else slideOffset * 4f
                val variableRadius =
                    if (multiplier >= 1f) MAIN_VIEW_RADIUS else MAIN_VIEW_RADIUS * multiplier
                val bottomRadius = if (isLast) lastItemRadius else 0f

                mainView.background = ViewHelpers.roundedShapeDrawable(
                    WColor.Background.color,
                    0f,
                    variableRadius,
                    if (isLast) maxOf(variableRadius, bottomRadius) else variableRadius,
                    bottomRadius
                )
            }

        })
        setViewDragHelperStateChangeListener {
            when (it) {
                ViewDragHelper.STATE_DRAGGING -> {
                    parent.requestDisallowInterceptTouchEvent(true)
                }

                ViewDragHelper.STATE_IDLE -> {
                    parent.requestDisallowInterceptTouchEvent(false)
                }
            }
        }

        addView(secondaryView)
        addView(mainView)
        initChildren()
    }

    private var onDeleteToken: (() -> Unit)? = null

    override fun setupViews() {
        super.setupViews()

        mainView.addView(separatorView, LayoutParams(0, ViewConstants.SEPARATOR_HEIGHT))
        mainView.addView(imageView, ViewGroup.LayoutParams(48.dp, 48.dp))
        mainView.addView(tokenNameLabel, LayoutParams(0, LayoutParams.WRAP_CONTENT))
        mainView.addView(amountLabel)
        mainView.addView(switchView)
        mainView.setConstraints {
            toBottom(separatorView)
            toEnd(separatorView, 16f)
            toStart(separatorView, 72f)
            toCenterY(imageView)
            toStart(imageView, 12f)
            toTop(tokenNameLabel, 10f)
            toStart(tokenNameLabel, 72f)
            endToStart(tokenNameLabel, switchView, 8f)
            toBottom(amountLabel, 10f)
            toStart(amountLabel, 72f)
            toCenterY(switchView)
            toEnd(switchView, 20f)
        }

        mainView.setOnClickListener {
            switchView.isChecked = !switchView.isChecked
        }

        addView(swipeRevealLayout)
        setConstraints {
            allEdges(swipeRevealLayout)
        }

        post {
            val secondaryViewLayoutParams = secondaryView.layoutParams
            secondaryViewLayoutParams.height = mainView.height
            secondaryView.layoutParams = secondaryViewLayoutParams
        }

        updateTheme()
    }

    override fun updateTheme() {
        mainView.setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLast) lastItemRadius else 0f
        )
        mainView.addRippleEffect(
            WColor.SecondaryBackground.color,
            0f,
            if (isLast) lastItemRadius else 0f
        )

        if (isLast) {
            val lastItemRedRipple = getRedRippleForLastItem()
            secondaryView.background = lastItemRedRipple
            swipeRevealLayout.setBackgroundColor(
                WColor.Red.color,
                0f,
                ViewConstants.BIG_RADIUS.dp
            )
        } else {
            redRipple.backgroundColor = WColor.Red.color
            redRipple.rippleColor = WColor.BackgroundRipple.color
            secondaryView.background = redRipple
            swipeRevealLayout.setBackgroundColor(WColor.Red.color)
        }

        tokenNameLabel.setTextColor(WColor.PrimaryText.color)
        amountLabel.contentView.setTextColor(WColor.SecondaryText.color)
        separatorView.setBackgroundColor(WColor.Separator.color)
        deleteLabel.setTextColor(WColor.TextOnTint.color)
    }

    private var isLast = false
    fun configure(
        token: MToken,
        balance: BigInteger,
        isLast: Boolean,
        isSwipeEnabled: Boolean = true,
        onDeleteToken: (() -> Unit)? = null
    ) {
        this.token = token
        this.isLast = isLast
        this.onDeleteToken = onDeleteToken ?: {
            setTokenVisibility(false)
        }

        swipeRevealLayout.setLockDrag(!isSwipeEnabled)
        imageView.config(token, AccountStore.activeAccount?.isMultichain == true)
        tokenNameLabel.text = token.name
        amountLabel.setMaskCols(4 + abs(token.slug.hashCode() % 8))
        amountLabel.contentView.setAmount(
            MTokenBalance.fromParameters(token, balance)!!.toBaseCurrency,
            token.decimals,
            WalletCore.baseCurrency.sign,
            WalletCore.baseCurrency.decimalsCount,
            true
        )
        skipSwitchChangeListener = true
        switchView.isChecked = !token.isHidden()
        skipSwitchChangeListener = false

        secondaryView.setOnClickListener {
            this.onDeleteToken?.invoke()
        }
        separatorView.isGone = isLast

        updateTheme()
    }

    fun closeSwipe() {
        swipeRevealLayout.close(true)
    }

    private fun setTokenVisibility(visible: Boolean) {
        val data = AccountStore.assetsAndActivityData
        if (visible) {
            data.hiddenTokens.removeAll { hiddenSlug ->
                hiddenSlug == token.slug
            }
            if (!data.visibleTokens.any { hiddenSlug ->
                    hiddenSlug == token.slug
                }) {
                data.visibleTokens.add(token.slug)
            }
        } else {
            data.visibleTokens.removeAll { hiddenSlug ->
                hiddenSlug == token.slug
            }
            if (!data.hiddenTokens.any { hiddenSlug ->
                    hiddenSlug == token.slug
                }) {
                data.hiddenTokens.add(token.slug)
            }
        }

        AccountStore.updateAssetsAndActivityData(data, notify = true)
    }

}
