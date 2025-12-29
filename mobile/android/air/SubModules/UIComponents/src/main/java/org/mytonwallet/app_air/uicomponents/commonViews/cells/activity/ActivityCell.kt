package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.annotation.SuppressLint
import android.graphics.Color
import android.text.TextUtils
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
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
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class ActivityCell(
    val parentView: View,
    val withoutTagAndComment: Boolean,
    val isFirstInDay: Boolean?
) :
    WCell(parentView.context), WThemedView {

    companion object {
        const val FIRST_DAY_MAIN_CONTENT_HEIGHT = 112
        const val MAIN_CONTENT_HEIGHT = 64
    }

    private val dateView = ActivityDateLabel(context)
    private val mainContentView = ActivityMainContentView(context)
    private val commentLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setTextColor(Color.WHITE)
            maxLines = 5
            isSingleLine = false
            ellipsize = TextUtils.TruncateAt.END
        }
    }
    private var commentView: FrameLayout? = null
    private var singleTagView: ActivitySingleTagView? = null
    private val separator = View(context).apply { id = generateViewId() }

    private val recyclerWidth by lazy { parentView.width }
    private val bigRadius by lazy { ViewConstants.BIG_RADIUS.dp }

    var onTap: ((MApiTransaction) -> Unit)? = null
    private var transaction: MApiTransaction? = null
    private var isFirst = false
    private var isLast = false
    private var isLastInDay = false
    private var baseCurrency: MBaseCurrency? = null
    private var baseCurrencyRate: Double? = null

    override fun setupViews() {
        super.setupViews()

        val cellHeight = cellHeight
        layoutParams = layoutParams.apply {
            height = if (cellHeight > 0)
                cellHeight
            else
                WRAP_CONTENT
        }

        addView(dateView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            mainContentView,
            LayoutParams(
                MATCH_PARENT,
                if (withoutTagAndComment) MAIN_CONTENT_HEIGHT.dp else WRAP_CONTENT
            )
        )
        addView(separator, LayoutParams(0, ViewConstants.SEPARATOR_HEIGHT))

        setConstraints {
            toTop(dateView)
            setVerticalBias(mainContentView.id, 0f)
            topToBottom(mainContentView, dateView)
            toBottom(mainContentView)
            toBottom(separator)
            toStart(separator, 72f)
            toEnd(separator, 16f)
        }

        if (withoutTagAndComment && isFirstInDay != null) {
            layoutParams.height =
                if (isFirstInDay) FIRST_DAY_MAIN_CONTENT_HEIGHT.dp else MAIN_CONTENT_HEIGHT.dp
        } else {
            layoutParams.height = WRAP_CONTENT
        }

        setOnClickListener { onTap?.let { onTap -> transaction?.let(onTap) } }
    }

    fun configure(
        transaction: MApiTransaction,
        accountId: String,
        isFirst: Boolean,
        isFirstInDay: Boolean,
        isLastInDay: Boolean,
        isLast: Boolean
    ) {
        if (this.transaction?.isChanged(transaction) == false &&
            WalletCore.baseCurrency == baseCurrency &&
            TokenStore.baseCurrencyRate == baseCurrencyRate &&
            this.isFirst == isFirst &&
            this.isLast == isLast &&
            this.isLastInDay == isLastInDay
        ) {
            // Nothing changed, just update theme
            updateTheme()
            if (!withoutTagAndComment) {
                configureComment(transaction)
            }
            return
        }
        this.transaction = transaction
        this.baseCurrency = WalletCore.baseCurrency
        this.baseCurrencyRate = TokenStore.baseCurrencyRate
        val firstChanged = this.isFirst != isFirst
        val lastChanged = this.isLast != isLast
        this.isFirst = isFirst
        this.isLast = isLast
        this.isLastInDay = isLastInDay

        dateView.visibility = if (isFirstInDay) VISIBLE else GONE
        if (isFirstInDay) dateView.configure(transaction.dt, isFirst)

        mainContentView.configure(transaction, accountId)

        if (!withoutTagAndComment) {
            configureTags(transaction)
            configureComment(transaction)
        }

        separator.visibility = if (isLastInDay) INVISIBLE else VISIBLE
        updateTheme(forceUpdate = firstChanged || lastChanged)
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
            topToTop(tagView, mainContentView, 60f)
            toStart(tagView, 76f)
            toEnd(tagView, 10f)
            toBottom(tagView, 12f)
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
            commentLabel.maxWidth = recyclerWidth - 178.dp
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
    private fun updateTheme(forceUpdate: Boolean) {
        if (!forceUpdate) {
            val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
            if (!darkModeChanged)
                return
        }
        _isDarkThemeApplied = ThemeManager.isDark
        separator.setBackgroundColor(WColor.Separator.color)
        setBackgroundColor(
            WColor.Background.color,
            if (isFirst) bigRadius else 0f,
            if (isLast) bigRadius else 0f
        )
        addRippleEffect(
            WColor.SecondaryBackground.color,
            0f,
            if (isLast) bigRadius else 0f
        )
        dateView.updateTheme()
        mainContentView.updateTheme()
        if (!withoutTagAndComment) {
            singleTagView?.updateTheme()
        }
    }

    private val cellHeight: Int
        get() {
            return if (withoutTagAndComment) {
                val height = if (dateView.isVisible) 112.dp else MAIN_CONTENT_HEIGHT.dp
                height
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
                isFirst = item.isFirst,
                isFirstInDay = false,
                isLastInDay = item.isLast,
                isLast = item.isLast
            )
        }
    }
}
