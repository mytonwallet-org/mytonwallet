package org.mytonwallet.app_air.uiswap.screens.cex

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.method.LinkMovementMethod
import android.text.style.TypefaceSpan
import android.text.style.URLSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WQRCodeView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.span.InAppBrowserUrlSpan
import org.mytonwallet.app_air.uiswap.views.SwapConfirmView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.helpers.SpanHelpers
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import java.math.BigInteger
import kotlin.math.max

@SuppressLint("ViewConstructor")
class SwapSendAddressOutputVC(
    context: Context,
    fromToken: IApiToken,
    toToken: IApiToken,
    fromAmount: BigInteger?,
    toAmount: BigInteger?,
    payinAddress: String,
    transactionId: String
) : WViewControllerWithModelStore(context) {
    override val TAG = "SwapSendAddressOutput"

    override val shouldDisplayTopBar = true
    override val shouldDisplayBottomBar = true

    override var isSwipeBackAllowed: Boolean = false
    override val isBackAllowed: Boolean
        get() = false

    private val primarySpan = WForegroundColorSpan()
    private val separatorDrawable = SeparatorBackgroundDrawable().apply {
        backgroundColor = Color.TRANSPARENT
    }

    private val scrollView = ScrollView(context).apply {
        id = View.generateViewId()
        overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
        isVerticalScrollBarEnabled = false
        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            setOnScrollChangeListener { _, _, scrollY, _, _ ->
                updateBlurViews(scrollView = this, computedOffset = scrollY)
            }
        }
        setPadding(ViewConstants.HORIZONTAL_PADDINGS.dp, 0, ViewConstants.HORIZONTAL_PADDINGS.dp, 0)
    }

    private val linearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
    }

    private val bottomDetails = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
    }

    private val confirmView = SwapConfirmView(context).apply {
        config(fromToken, toToken, fromAmount, toAmount)
    }

    private val gapView = View(context).apply {
        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp)
    }

    private val continueButton = WButton(context).apply {
        id = View.generateViewId()
        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, 50.dp).apply {
            leftMargin = 20.dp
            topMargin = leftMargin
            rightMargin = leftMargin
            bottomMargin = leftMargin
        }
        isEnabled = true
        text = LocaleController.getString("Done")
    }

    private val qrCodeView = WQRCodeView(
        context,
        payinAddress,
        (262 - 24).dp,
        (262 - 24).dp,
        fromToken.mBlockchain?.icon ?: 0,
        64.dp,
        null
    ).apply {
        layoutParams = LinearLayout.LayoutParams(262.dp, 262.dp).apply {
            setPadding(100, 100, 100, 100)
            gravity = Gravity.CENTER
        }
        generateInUi()
    }

    private val addressView = CopyTextView(context).apply {
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 22f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        gravity = Gravity.CENTER
        typeface = WFont.Regular.typeface
        layoutParams = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
            topMargin = (16 - 1).dp
            leftMargin = 20.dp
            rightMargin = 20.dp
            bottomMargin = topMargin
        }
        maxWidth = 288.dp

        includeFontPadding = false
        clipLabel = "Address"
        clipToast = LocaleController.getString("%chain% Address Copied")
            .replace("%chain%", fromToken.mBlockchain?.displayName ?: "")
        text = payinAddress
    }

    private val transactionIdText = CopyTextView(context).apply {
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 22f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
        gravity = Gravity.CENTER
        typeface = WFont.Regular.typeface
        layoutParams = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
            topMargin = (22 - 1).dp
            leftMargin = 20.dp
            rightMargin = 20.dp
            bottomMargin = topMargin
        }
        includeFontPadding = false
        clipLabel = "Transaction ID"
        clipToast = LocaleController.getString("Transaction ID Copied")
        text = transactionId
    }

    @SuppressLint("SetTextI18n")
    private val textView = AppCompatTextView(context).apply {
        setPaddingDp(20, 0, 20, 0)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 20f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        gravity = Gravity.CENTER
        typeface = WFont.Regular.typeface
        movementMethod = LinkMovementMethod.getInstance()
        layoutParams = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
            topMargin = 22.dp
        }

        includeFontPadding = false

        val hint =
            LocaleController.getString("Please note that it may take up to a few hours for tokens to appear in your wallet.")
        val supportText = LocaleController.getSpannableStringWithKeyValues(
            "\$swap_changelly_support", listOf(
                Pair(
                    "%livechat%",
                    SpanHelpers.buildSpannable(
                        LocaleController.getString("Changelly Live Chat"),
                        InAppBrowserUrlSpan("https://support.changelly.com/support/home", null)
                    )
                ),
                Pair(
                    "%email%",
                    SpanHelpers.buildSpannable(
                        "support@changelly.org",
                        URLSpan("mailto:support@changelly.org")
                    )
                )
            )
        ).toProcessedSpannableStringBuilder()

        text = SpannableStringBuilder()
            .append(hint)
            .append("\n\n")
            .append(supportText)
        maxWidth = (332 + 20 + 20).dp
    }

    private val titleView = AppCompatTextView(context).apply {
        setPaddingDp(20, 0, 20, 0)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 22f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        gravity = Gravity.CENTER
        typeface = WFont.Regular.typeface
        layoutParams = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
            topMargin = 24.dp
        }

        val fromAmountString = fromAmount?.let { CoinUtils.toDecimalString(it, fromToken.decimals) }
        val ssb = SpannableStringBuilder(fromAmountString)
        ssb.setSpan(primarySpan, 0, ssb.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        ssb.append(' ')
        ssb.append(fromToken.symbol)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && fromAmountString?.length != null) {
            ssb.setSpan(
                TypefaceSpan(WFont.Medium.typeface),
                0,
                fromAmountString.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }

        includeFontPadding = false
        text = LocaleController.getSpannableStringWithKeyValues(
            "Send %1$@ this address:",
            listOf(Pair("%1\$@", ssb))
        )
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Swap"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(scrollView)

        scrollView.addView(linearLayout)
        linearLayout.addView(confirmView)
        linearLayout.addView(gapView)
        linearLayout.addView(bottomDetails)
        bottomDetails.addView(titleView)
        bottomDetails.addView(addressView)
        bottomDetails.addView(qrCodeView)
        bottomDetails.addView(textView)
        bottomDetails.addView(transactionIdText)
        bottomDetails.addView(continueButton)

        linearLayout.setPadding(
            0,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT_THIN.dp,
            0,
            navigationController?.getSystemBars()?.bottom ?: 0,
        )
        linearLayout.clipToPadding = false

        view.setConstraints {
            toCenterX(scrollView)
            toTop(scrollView)
            toBottom(scrollView)
        }

        continueButton.setOnClickListener {
            navigationController?.window?.dismissLastNav()
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        scrollView.setBackgroundColor(WColor.SecondaryBackground.color)
        confirmView.setBackgroundColor(WColor.Background.color, 0f, ViewConstants.BLOCK_RADIUS.dp)
        bottomDetails.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )
        qrCodeView.setPadding(if (ThemeManager.isDark) 16.dp else 0)
        if (ThemeManager.isDark) {
            qrCodeView.setBackgroundColor(Color.WHITE, 16f.dp)
        } else {
            qrCodeView.background = null
        }
        primarySpan.color = WColor.PrimaryText.color
        gapView.setBackgroundColor(WColor.SecondaryBackground.color)
        textView.setTextColor(WColor.SecondaryText.color)
        textView.setLinkTextColor(WColor.Tint.color)
        textView.highlightColor = WColor.tintRippleColor
        titleView.setTextColor(WColor.SecondaryText.color)
        addressView.setTextColor(WColor.PrimaryText.color)
        transactionIdText.setTextColor(WColor.PrimaryText.color)
        separatorDrawable.invalidateSelf()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setConstraints({
            toBottomPx(
                scrollView, max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            scrollView.setOnScrollChangeListener(null)
        }
    }
}
