package org.mytonwallet.app_air.uisettings.viewControllers.subwallets.cells

import android.content.Context
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isVisible
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WMultichainAddressLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MAccount.AccountChain
import kotlin.math.roundToInt

data class SubwalletRowData(
    val identifier: String,
    val title: String,
    val badge: String?,
    val network: MBlockchainNetwork,
    val accountId: String?,
    val byChain: Map<String, AccountChain>,
    val nativeAmount: String,
    val totalBalance: String
)

class SubwalletCell(
    context: Context,
) : WCell(context), WThemedView {

    var identifier: String = ""
        private set
    var onTap: ((identifier: String) -> Unit)? = null

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize(), WFont.SemiBold)
        lbl
    }

    private val badgeLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(10f, WFont.SemiBold)
        lbl.setPadding(3.dp, 0, 3.dp, 0)
        lbl
    }

    private val addressesLabel: WMultichainAddressLabel by lazy {
        val lbl = WMultichainAddressLabel(context)
        lbl.setStyle(13f, WFont.Regular)
        lbl
    }

    private val totalBalanceLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl
    }

    private val nativeAmountLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(13f)
        lbl.maxLines = 1
        lbl.ellipsize = android.text.TextUtils.TruncateAt.END
        lbl.gravity = android.view.Gravity.END
        lbl
    }

    init {
        layoutParams.apply {
            height = 60.dp
        }
        addView(titleLabel)
        addView(badgeLabel, LayoutParams(WRAP_CONTENT, 14.dp))
        addView(addressesLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(totalBalanceLabel)
        addView(nativeAmountLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toTop(titleLabel, 8f)
            toStart(titleLabel, 16f)
            startToEnd(badgeLabel, titleLabel, 4f)
            centerYToCenterY(badgeLabel, titleLabel)
            toTop(addressesLabel, 32f)
            toStart(addressesLabel, 16f)
            toTop(totalBalanceLabel, 8f)
            toEnd(totalBalanceLabel, 16f)
            toTop(nativeAmountLabel, 32f)
            startToEnd(nativeAmountLabel, addressesLabel, 8f)
            toEnd(nativeAmountLabel, 16f)
        }

        setOnClickListener {
            onTap?.invoke(identifier)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        if (onTap != null)
            addRippleEffect(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        badgeLabel.setTextColor(WColor.SecondaryText.color)
        badgeLabel.setBackgroundColor(WColor.SecondaryBackground.color, 4f.dp)
        addressesLabel.setTextColor(WColor.SecondaryText.color)
        totalBalanceLabel.setTextColor(WColor.PrimaryText.color)
        nativeAmountLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var isLast = false
    private var heightSpringAnimation: SpringAnimation? = null

    fun configure(
        rowData: SubwalletRowData,
        isLast: Boolean,
        isAdded: Boolean = false,
        animationDelay: Long = 0L
    ) {
        this.isLast = isLast
        this.identifier = rowData.identifier
        titleLabel.text = rowData.title

        val badge = rowData.badge?.takeIf { it.isNotEmpty() }
        if (badge != null) {
            badgeLabel.isVisible = true
            badgeLabel.text = badge
        } else {
            badgeLabel.isVisible = false
        }

        addressesLabel.displayAddresses(
            network = rowData.network,
            accountId = rowData.accountId,
            byChain = rowData.byChain,
            style = WMultichainAddressLabel.cardRowWalletStyle
        )

        totalBalanceLabel.text = "≥ ${rowData.totalBalance}"
        nativeAmountLabel.text = rowData.nativeAmount
        updateTheme()

        if (isAdded && WGlobalStorage.getAreAnimationsActive()) {
            heightSpringAnimation?.cancel()
            heightSpringAnimation = null
            val initialHeight = if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f.dp
            layoutParams.height = initialHeight.roundToInt()
            setContentAlpha(0f)
            requestLayout()
            postDelayed({ startInsertAnimation() }, animationDelay)
        } else {
            heightSpringAnimation?.cancel()
            heightSpringAnimation = null
            layoutParams.height = 60.dp
            setContentAlpha(1f)
        }
    }

    private fun setContentAlpha(alpha: Float) {
        titleLabel.alpha = alpha
        badgeLabel.alpha = alpha
        addressesLabel.alpha = alpha
        totalBalanceLabel.alpha = alpha
        nativeAmountLabel.alpha = alpha
    }

    private fun startInsertAnimation() {
        val targetHeight = 60.dp.toFloat()
        val startHeight = if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        layoutParams.height = startHeight.toInt()
        requestLayout()
        heightSpringAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(startHeight)
            spring = SpringForce(targetHeight).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                layoutParams.height = value.toInt()
                requestLayout()
                val fraction =
                    ((value - 0.8f * targetHeight) / (0.2f * targetHeight)).coerceIn(0f, 1f)
                setContentAlpha(fraction)
            }
            addEndListener { _, _, _, _ ->
                layoutParams.height = 60.dp
                setContentAlpha(1f)
                heightSpringAnimation = null
            }
            start()
        }
    }
}
