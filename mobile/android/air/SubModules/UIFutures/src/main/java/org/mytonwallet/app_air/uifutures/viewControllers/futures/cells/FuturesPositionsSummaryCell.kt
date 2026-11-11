package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.formatPnlChange
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsSnapshot
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

@SuppressLint("ViewConstructor")
class FuturesPositionsSummaryCell(context: Context) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private var snapshot: MApiPerpsSnapshot? = null
    private var status: String? = null
    private var isStatusRetryable = false
    private var isStale = false
    private var isShowingSkeletons = false

    private val titleLabel = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        text = LocaleController.getString("Open Positions")
    }

    private val balanceLabel = WLabel(context).apply {
        setStyle(BALANCE_PRIMARY_SIZE, WFont.Balance)
        setSingleLine()
        setOnClickListener { WGlobalStorage.toggleSensitiveDataHidden() }
    }

    private val changeLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setPadding(8.dp, 2.dp, 8.dp, 2.dp)
        setSingleLine()
    }

    private val statusLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(15f)
        gravity = Gravity.CENTER
        visibility = GONE
        setOnClickListener { if (isStatusRetryable) PerpsStore.refresh() }
    }

    private val balanceView = WSensitiveDataContainer(
        balanceLabel,
        WSensitiveDataContainer.MaskConfig(
            16,
            4,
            Gravity.CENTER,
            protectContentLayoutSize = false,
            hero = WSensitiveDataContainer.HeroConfig(
                196f,
                30f,
                globalReveal = true,
                softwareSnapshot = true
            )
        )
    ).apply {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
    }

    private val changeView = WSensitiveDataContainer(
        changeLabel,
        WSensitiveDataContainer.MaskConfig(
            16,
            3,
            Gravity.CENTER,
            protectContentLayoutSize = false,
            hero = WSensitiveDataContainer.HeroConfig(130f, 26f, softwareSnapshot = true)
        )
    ).apply {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
    }

    private val balanceSkeleton = View(context).apply {
        id = generateViewId()
        visibility = GONE
    }
    private val changeSkeleton = View(context).apply {
        id = generateViewId()
        visibility = GONE
    }
    private val skeletonView = SkeletonView(context, isVertical = false).apply {
        id = generateViewId()
    }

    init {
        clipChildren = false
        clipToPadding = false
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(balanceView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(changeView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(statusLabel, LayoutParams(0, WRAP_CONTENT))
        addView(
            balanceSkeleton,
            LayoutParams(BALANCE_SKELETON_WIDTH.dp, BALANCE_SKELETON_HEIGHT.dp)
        )
        addView(changeSkeleton, LayoutParams(CHANGE_SKELETON_WIDTH.dp, CHANGE_SKELETON_HEIGHT.dp))
        addView(skeletonView, LayoutParams(0, 0))
        setConstraints {
            toTop(titleLabel, 16f)
            toCenterX(titleLabel)
            topToBottom(balanceView, titleLabel, 6f)
            toCenterX(balanceView)
            topToBottom(changeView, balanceView, 5f)
            toCenterX(changeView)
            toBottom(changeView, 28f)
            topToBottom(statusLabel, balanceView, 5f)
            toCenterX(statusLabel, 20f)
            toBottom(statusLabel, 28f)
            centerYToCenterY(balanceSkeleton, balanceView)
            toCenterX(balanceSkeleton)
            centerYToCenterY(changeSkeleton, changeView)
            toCenterX(changeSkeleton)
            allEdges(skeletonView)
        }
        updateTheme()
    }

    fun configure(
        snapshot: MApiPerpsSnapshot?,
        isLoading: Boolean,
        status: String?,
        isStatusRetryable: Boolean,
        isStale: Boolean
    ) {
        this.snapshot = snapshot
        this.status = status
        this.isStatusRetryable = isStatusRetryable
        this.isStale = isStale
        if (isLoading) showSkeletons() else hideSkeletons()
        updateTheme()
    }

    private fun showSkeletons() {
        if (isShowingSkeletons) return
        isShowingSkeletons = true
        balanceView.animate().cancel()
        changeView.animate().cancel()
        balanceView.alpha = 0f
        changeView.alpha = 0f
        balanceSkeleton.visibility = VISIBLE
        balanceSkeleton.alpha = 1f
        changeSkeleton.visibility = VISIBLE
        changeSkeleton.alpha = 1f
        post {
            if (!isShowingSkeletons) return@post
            skeletonView.applyMask(
                listOf(balanceSkeleton, changeSkeleton),
                hashMapOf(0 to 8f.dp, 1 to 8f.dp)
            )
            skeletonView.startAnimating()
        }
    }

    private fun hideSkeletons() {
        if (!isShowingSkeletons) return
        isShowingSkeletons = false
        skeletonView.stopAnimating()
        balanceSkeleton.fadeOut()
        changeSkeleton.fadeOut(onCompletion = {
            if (!isShowingSkeletons) {
                balanceSkeleton.visibility = GONE
                changeSkeleton.visibility = GONE
            }
        })
        balanceView.fadeIn()
        changeView.fadeIn()
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.SecondaryText.color)
        balanceSkeleton.setBackgroundColor(WColor.GroupedBackground.color, 8f.dp)
        changeSkeleton.setBackgroundColor(WColor.GroupedBackground.color, 8f.dp)
        skeletonView.updateTheme()
        balanceLabel.setTextColor(WColor.PrimaryText.color)
        val status = status
        statusLabel.isVisible = status != null
        changeView.isVisible = status == null
        // Labels, as the skeleton fades the containers
        val alpha = if (isStale) STALE_ALPHA else 1f
        balanceLabel.alpha = alpha
        changeLabel.alpha = alpha
        if (status != null) {
            statusLabel.text = if (isStatusRetryable) {
                SpannableStringBuilder(status).append("\n").append(
                    LocaleController.getString("Retry"),
                    ForegroundColorSpan(WColor.Tint.color),
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            } else {
                status
            }
            statusLabel.setTextColor(WColor.SecondaryText.color)
            balanceLabel.text = EMPTY_VALUE
            balanceView.setHeroColors(WColor.PrimaryText.color)
            return
        }
        // Totals that miss a book would understate the account
        val isIncomplete = snapshot?.unavailableDexs?.isNotEmpty() == true
        balanceLabel.text = if (isIncomplete) {
            EMPTY_VALUE
        } else {
            (snapshot?.totalEquityAmount ?: 0.0).toBalanceText()
        }
        val pnl = if (isIncomplete) 0.0 else snapshot?.totalPnlAmount ?: 0.0
        val color = balanceChangeColor(pnl)
        changeLabel.text = if (isIncomplete) {
            EMPTY_VALUE
        } else {
            formatPnlChange(pnl, snapshot?.totalPnlPercent ?: 0.0)
        }
        changeLabel.setTextColor(color)
        changeLabel.setBackgroundColor(color.colorWithAlpha(25), 13f.dp)
        balanceView.setHeroColors(WColor.PrimaryText.color)
        changeView.setHeroColors(color)
    }
}

private const val BALANCE_SKELETON_WIDTH = 134
private const val EMPTY_VALUE = "—"
internal const val STALE_ALPHA = 0.55f
private const val BALANCE_SKELETON_HEIGHT = 56
private const val CHANGE_SKELETON_WIDTH = 80
private const val CHANGE_SKELETON_HEIGHT = 28
private const val BALANCE_CURRENCY_SIZE = 34f
private const val BALANCE_DECIMALS_SIZE = 28f
internal const val BALANCE_PRIMARY_SIZE = 40f

internal fun balanceChangeColor(change: Double): Int = when {
    change > 0 -> WColor.DarkGreen.color
    change < 0 -> WColor.Red.color
    else -> WColor.SecondaryText.color
}

/** Dims and shrinks the currency sign and the fraction, as on the Home balance. */
internal fun Double.toBalanceText(): CharSequence {
    val text = toUsdString()
    val fractionStart = text.indexOf('.').takeIf { it >= 0 } ?: text.length
    return SpannableString(text).apply {
        val secondary = WColor.SecondaryText.color
        setSpan(ForegroundColorSpan(secondary), 0, 1, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        setSpan(
            RelativeSizeSpan(BALANCE_CURRENCY_SIZE / BALANCE_PRIMARY_SIZE),
            0,
            1,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        if (fractionStart < text.length) {
            setSpan(
                ForegroundColorSpan(secondary),
                fractionStart,
                text.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                RelativeSizeSpan(BALANCE_DECIMALS_SIZE / BALANCE_PRIMARY_SIZE),
                fractionStart,
                text.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }
}
