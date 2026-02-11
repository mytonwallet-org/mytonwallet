package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.annotation.SuppressLint
import android.graphics.Color
import android.text.TextUtils
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.view.children
import androidx.core.view.doOnPreDraw
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.SpannableHelpers
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class ActivityCell(
    val parentView: View,
    val withoutTagAndComment: Boolean,
    val isFirstInDay: Boolean?
) :
    WCell(parentView.context, LayoutParams(MATCH_PARENT, 0)), WThemedView {

    companion object {
        const val FIRST_DAY_MAIN_CONTENT_HEIGHT = 100
        const val MAIN_CONTENT_HEIGHT = 60
        const val SPACING_BELOW_TAG_AND_COMMENT = 12
        const val SPACING_BETWEEN_TAG_AND_COMMENT = 8
    }

    private val dateView = ActivityDateLabel(context)
    private val mainContentView = ActivityMainContentView(context)
    private val commentLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(ApplicationContextHolder.adaptiveFontSize)
            setTextColor(Color.WHITE)
            maxLines = 5
            isSingleLine = false
            ellipsize = TextUtils.TruncateAt.END
        }
    }
    private var commentView: FrameLayout? = null
    private var singleTagView: ActivitySingleTagView? = null

    private val recyclerWidth by lazy { parentView.width }
    private val bigRadius get() = ViewConstants.BLOCK_RADIUS.dp

    var onTap: ((MApiTransaction) -> Unit)? = null
    private var transaction: MApiTransaction? = null
    private var transactionAddressName: String? = null
    private var positioning: Positioning? = null
    private var baseCurrency: MBaseCurrency? = null
    private var baseCurrencyRate: Double? = null
    private var heightSpringAnimation: SpringAnimation? = null

    override fun setupViews() {
        super.setupViews()

        addView(dateView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            mainContentView,
            LayoutParams(
                MATCH_PARENT,
                if (withoutTagAndComment) MAIN_CONTENT_HEIGHT.dp else WRAP_CONTENT
            )
        )

        setConstraints {
            toTop(dateView)
            setVerticalBias(mainContentView.id, 0f)
            topToBottom(mainContentView, dateView)
            toBottom(mainContentView)
        }

        if (withoutTagAndComment && isFirstInDay != null) {
            layoutParams.height =
                if (isFirstInDay) FIRST_DAY_MAIN_CONTENT_HEIGHT.dp else MAIN_CONTENT_HEIGHT.dp
        } else {
            layoutParams.height = WRAP_CONTENT
        }

        setOnClickListener { onTap?.let { onTap -> transaction?.let(onTap) } }
    }

    data class Positioning(
        val isFirst: Boolean,
        val isFirstInDay: Boolean,
        val isLastInDay: Boolean,
        val isLast: Boolean,
        val isAdded: Boolean = false,
        val isAddedAsNewDay: Boolean = false,
    ) {
        fun matches(comparing: Positioning): Boolean {
            return this.isFirst == comparing.isFirst &&
                this.isFirstInDay == comparing.isFirstInDay &&
                this.isLast == comparing.isLast &&
                this.isLastInDay == comparing.isLastInDay
        }
    }

    fun configure(
        transaction: MApiTransaction,
        accountId: String,
        isMultichain: Boolean,
        positioning: Positioning
    ) {
        if (this.transaction?.isSame(transaction) == true &&
            this.transaction?.isChanged(transaction) == false &&
            this.transactionAddressName == transaction.addressName() &&
            WalletCore.baseCurrency == baseCurrency &&
            TokenStore.baseCurrencyRate == baseCurrencyRate &&
            this.positioning?.matches(positioning) == true
        ) {
            // Nothing changed, just update theme
            updateTheme()
            if (!withoutTagAndComment) {
                configureComment(transaction)
            }
            return
        }
        this.transaction = transaction
        this.transactionAddressName = transaction.addressName()
        this.baseCurrency = WalletCore.baseCurrency
        this.baseCurrencyRate = TokenStore.baseCurrencyRate
        val firstChanged = this.positioning?.isFirst != positioning.isFirst
        val lastChanged = this.positioning?.isLast != positioning.isLast
        this.positioning = positioning

        dateView.visibility = if (positioning.isFirstInDay) VISIBLE else GONE
        if (positioning.isFirstInDay) dateView.configure(transaction.dt, positioning.isFirst)

        mainContentView.configure(transaction, accountId, isMultichain)

        if (!withoutTagAndComment) {
            configureTags(transaction)
            configureComment(transaction)
        }

        updateTheme(forceUpdate = firstChanged || lastChanged)

        if (positioning.isAdded) {
            val startHeight = if (positioning.isFirstInDay && !positioning.isAddedAsNewDay) {
                (FIRST_DAY_MAIN_CONTENT_HEIGHT - MAIN_CONTENT_HEIGHT).dp
            } else {
                bigRadius.roundToInt()
            }

            updateLayoutParams {
                height = startHeight
            }
            mainContentView.alpha = 0f
            if (positioning.isAddedAsNewDay) {
                dateView.alpha = 0f
            }
            doOnPreDraw {
                requestLayout()
                startInsertAnimation()
            }
        } else if (heightSpringAnimation?.isRunning == true) {
            heightSpringAnimation?.cancel()
            updateLayoutParams {
                height = if (cellHeight > 0) cellHeight else WRAP_CONTENT
            }
        }
    }

    private fun startInsertAnimation() {
        val positioning = positioning ?: return
        val widthSpec = parentView.width.exactly
        val heightSpec = 0.unspecified
        mainContentView.measure(widthSpec, heightSpec)
        var targetHeight = mainContentView.measuredHeight
        if (positioning.isFirstInDay) {
            dateView.measure(widthSpec, heightSpec)
            targetHeight += dateView.measuredHeight
        }
        val mainContentViewBottom = targetHeight
        var tagViewBottom = 0
        if (!withoutTagAndComment) {
            if (singleTagView?.isVisible == true) {
                singleTagView?.measure(widthSpec, heightSpec)
                targetHeight += singleTagView?.measuredHeight ?: 0
            }
            tagViewBottom = targetHeight
            if (singleTagView?.isVisible == true && commentView?.isVisible == true) {
                targetHeight += SPACING_BETWEEN_TAG_AND_COMMENT.dp
            }
            if (commentView?.isVisible == true) {
                commentView?.measure(widthSpec, heightSpec)
                targetHeight += commentView?.measuredHeight ?: 0
            }
            if (singleTagView?.isVisible == true || commentView?.isVisible == true)
                targetHeight += SPACING_BELOW_TAG_AND_COMMENT.dp
        }

        val startHeight = if (positioning.isFirstInDay && !positioning.isAddedAsNewDay) {
            (FIRST_DAY_MAIN_CONTENT_HEIGHT - MAIN_CONTENT_HEIGHT).dp
        } else {
            bigRadius.roundToInt()
        }

        heightSpringAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(startHeight.toFloat())
            spring = SpringForce(targetHeight.toFloat()).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }

            addUpdateListener { _, value, _ ->
                updateLayoutParams {
                    height = value.toInt()
                }
                val appearanceStartHeight = 0.7f * mainContentViewBottom
                val fraction =
                    ((value - appearanceStartHeight) / (targetHeight - appearanceStartHeight)).coerceIn(
                        0f,
                        1f
                    )
                mainContentView.alpha = lerp(0f, 1f, fraction)
                mainContentView.scaleX = lerp(0.95f, 1f, mainContentView.alpha)
                mainContentView.scaleY = mainContentView.scaleX
                if (positioning.isAddedAsNewDay) {
                    dateView.alpha = mainContentView.alpha
                    dateView.scaleX = mainContentView.scaleX
                    dateView.scaleY = mainContentView.scaleY
                }
                if (!withoutTagAndComment) {
                    singleTagView?.let { singleTagView ->
                        val fraction =
                            ((value - mainContentViewBottom) / (targetHeight - mainContentViewBottom)).coerceIn(
                                0.7f,
                                1f
                            )
                        singleTagView.alpha = lerp(0f, 1f, (fraction - 0.7f) * 10 / 3)
                        singleTagView.scaleX = lerp(0.95f, 1f, singleTagView.alpha)
                        singleTagView.scaleY = singleTagView.scaleX
                    }
                    commentView?.let { commentView ->
                        val fraction =
                            ((value - tagViewBottom) / (targetHeight - tagViewBottom)).coerceIn(
                                0.7f,
                                1f
                            )
                        commentView.alpha = lerp(0f, 1f, (fraction - 0.7f) * 10 / 3)
                        commentView.scaleX = lerp(0.95f, 1f, commentView.alpha)
                        commentView.scaleY = commentView.scaleX
                    }
                }
            }

            addEndListener { _, canceled, _, _ ->
                if (canceled) {
                    children.forEach {
                        it.scaleX = 1f
                        it.scaleY = 1f
                        it.alpha = 1f
                    }
                }

                val newHeight = if (cellHeight > 0) cellHeight else WRAP_CONTENT
                if (layoutParams.height != newHeight)
                    updateLayoutParams {
                        height = newHeight
                    }
            }
        }
        heightSpringAnimation?.start()
    }

    private fun configureTags(transaction: MApiTransaction) {
        val txn = transaction as? MApiTransaction.Transaction
        val nft = txn?.nft

        if (txn?.isNft != true || nft == null) {
            singleTagView?.visibility = GONE
            return
        }

        val tagView = singleTagView ?: createTagView().also { singleTagView = it }
        tagView.visibility = VISIBLE
        tagView.configure(nft)
    }

    private fun createTagView(): ActivitySingleTagView {
        val tagView = ActivitySingleTagView(context)
        addView(tagView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        tagView.layoutParams = (tagView.layoutParams as LayoutParams).apply {
            matchConstraintMaxWidth = recyclerWidth - 96.dp - ViewConstants.HORIZONTAL_PADDINGS.dp
        }

        setConstraints {
            constrainedWidth(tagView.id, true)
            setVerticalBias(tagView.id, 0f)
            setHorizontalBias(tagView.id, 0f)
            topToTop(tagView, mainContentView, MAIN_CONTENT_HEIGHT.toFloat())
            toStart(tagView, 76f)
            toEnd(tagView, 10f)
            toBottom(tagView, SPACING_BELOW_TAG_AND_COMMENT.toFloat())
        }

        return tagView
    }

    private fun configureComment(transaction: MApiTransaction) {
        val txn = transaction as? MApiTransaction.Transaction

        if (txn?.hasComment != true) {
            commentView?.visibility = GONE
            return
        }

        val commentContainer = commentView ?: createCommentView().also { commentView = it }
        commentContainer.visibility = VISIBLE

        commentLabel.text = txn.comment?.trim()?.take(300)
            ?: SpannableHelpers.encryptedCommentSpan(context)

        if (txn.isIncoming) {
            commentContainer.background = IncomingCommentDrawable()
            commentLabel.setPaddingDpLocalized(18, 6, 12, 6)
            commentLabel.maxWidth = recyclerWidth - 172.dp
        } else {
            commentContainer.background = OutgoingCommentDrawable().apply {
                if (transaction.status == ApiTransactionStatus.FAILED)
                    setBubbleColor(WColor.Red.color.colorWithAlpha(38))
            }
            commentLabel.setPaddingDpLocalized(12, 6, 18, 6)
            commentLabel.maxWidth = recyclerWidth - 118.dp
        }
        (commentContainer.background as ICommentDrawable).apply {
            if (transaction.status == ApiTransactionStatus.FAILED)
                setBubbleColor(WColor.Red.color.colorWithAlpha(38))
        }
        commentLabel.setTextColor(
            if (transaction.status == ApiTransactionStatus.FAILED) WColor.Red else WColor.White
        )

        updateCommentConstraints(txn.isIncoming)
    }

    private fun createCommentView(): WFrameLayout {
        val container = WFrameLayout(context).apply {
            minimumHeight = 36.dp
            addView(commentLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
        addView(container, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        return container
    }

    private fun updateCommentConstraints(isIncoming: Boolean) {
        val commentContainer = commentView ?: return

        setConstraints {
            toBottom(commentContainer, 12f)

            if (singleTagView?.isVisible == true)
                topToBottom(commentContainer, singleTagView!!, 8f)
            else
                topToTop(commentContainer, mainContentView, 60f)

            if (isIncoming) {
                toStart(commentContainer, 70f)
                toEnd(commentContainer, 108f)
                setHorizontalBias(commentContainer.id, 0f)
            } else {
                toStart(commentContainer, 108f)
                toEnd(commentContainer, 10f)
                setHorizontalBias(commentContainer.id, 1f)
            }
        }
    }

    override fun updateTheme() {
        updateTheme(forceUpdate = false)
    }

    private var _isDarkThemeApplied: Boolean? = null
    private var _lastBigRadius: Float? = null
    private fun updateTheme(forceUpdate: Boolean) {
        dateView.updateTheme()
        if (!forceUpdate) {
            val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
            val radiusChanged = _lastBigRadius != ViewConstants.BLOCK_RADIUS
            if (!darkModeChanged && !radiusChanged)
                return
        }
        _isDarkThemeApplied = ThemeManager.isDark
        _lastBigRadius = ViewConstants.BLOCK_RADIUS
        setBackgroundColor(
            WColor.Background.color,
            if (positioning?.isFirst == true) bigRadius else 0f,
            if (positioning?.isLast == true) bigRadius else 0f
        )
        addRippleEffect(
            WColor.SecondaryBackground.color,
            0f,
            if (positioning?.isLast == true) bigRadius else 0f
        )
        mainContentView.updateTheme()
        if (!withoutTagAndComment) {
            singleTagView?.updateTheme()
        }
    }

    private val cellHeight: Int
    get() {
        return if (withoutTagAndComment) {
            if (dateView.isVisible) FIRST_DAY_MAIN_CONTENT_HEIGHT.dp else MAIN_CONTENT_HEIGHT.dp
        } else {
            0
        }
    }

    // Used in recycler-views not using custom rvAdapter
    class Holder(parentView: View) :
        BaseListHolder<Item.Activity>(
            ActivityCell(parentView, false, null).apply {
                val cellHeight = cellHeight
                layoutParams = ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    if (cellHeight > 0)
                        cellHeight
                    else
                        WRAP_CONTENT
                )
            }) {
        private val view: ActivityCell = itemView as ActivityCell
        override fun onBind(item: Item.Activity) {
            view.configure(
                transaction = item.activity,
                accountId = item.accountId,
                isMultichain = item.isMultichain,
                positioning = Positioning(
                    isFirst = item.isFirst,
                    isFirstInDay = false,
                    isLastInDay = item.isLast,
                    isLast = item.isLast,
                ),
            )
        }
    }
}
