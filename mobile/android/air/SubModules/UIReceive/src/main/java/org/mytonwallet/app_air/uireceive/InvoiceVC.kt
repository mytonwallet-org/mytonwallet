package org.mytonwallet.app_air.uireceive

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.text.Editable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.TextWatcher
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ScrollView
import android.widget.Toast
import androidx.appcompat.widget.AppCompatEditText
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.TokenAmountInputView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.TokenSelectorVC
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.AddressHelpers
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.helpers.TokenEquivalent
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigDecimal
import java.math.BigInteger
import kotlin.math.max

class InvoiceVC(context: Context) : WViewController(context) {
    override val TAG = "Invoice"

    override val shouldDisplayBottomBar = true

    private val topGapView = View(context).apply {
        id = View.generateViewId()
    }

    private val amountInputView by lazy {
        TokenAmountInputView(context, isFirstItem = true).apply {
            id = View.generateViewId()
        }
    }

    private val title2 = HeaderCell(context).apply {
        id = View.generateViewId()
        configure(LocaleController.getString("Comment"), titleColor = WColor.Tint, topRounding = HeaderCell.TopRounding.NORMAL)
    }

    private val commentInputView by lazy {
        AppCompatEditText(context).apply {
            id = View.generateViewId()
            background = null
            hint = LocaleController.getString("Optional")
            typeface = WFont.Regular.typeface
            layoutParams =
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setPaddingDp(20, 8, 20, 20)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            }
        }
    }

    private val title3 = HeaderCell(context).apply {
        id = View.generateViewId()
        configure("", titleColor = WColor.Tint, topRounding = HeaderCell.TopRounding.NORMAL)
    }

    private val linkLabel by lazy {
        WLabel(context).apply {
            setPaddingDp(20, 8, 20, 20)
            setStyle(14f)
            movementMethod = LinkMovementMethod.getInstance()
            highlightColor = Color.TRANSPARENT
        }
    }

    private val contentLayout by lazy {
        WView(context).apply {
            addView(
                amountInputView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            addView(title2)
            addView(
                commentInputView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            addView(title3)
            addView(
                linkLabel,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            setConstraints {
                toTop(topGapView)
                topToBottom(amountInputView, topGapView)
                topToBottom(title2, amountInputView, ViewConstants.GAP.toFloat())
                topToBottom(commentInputView, title2)
                topToBottom(title3, commentInputView, ViewConstants.GAP.toFloat())
                topToBottom(linkLabel, title3)
                toBottom(linkLabel)
            }
        }
    }

    private val scrollView by lazy {
        ScrollView(context).apply {
            addView(
                contentLayout,
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            id = View.generateViewId()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setOnScrollChangeListener { _, _, scrollY, _, _ ->
                    updateBlurViews(scrollView = this, computedOffset = scrollY)
                }
            }
            overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
            clipToPadding = false
            isVerticalScrollBarEnabled = false
        }
    }

    private val onCommentChangeListener = object : TextWatcher {
        override fun beforeTextChanged(
            s: CharSequence?,
            start: Int,
            count: Int,
            after: Int
        ) {
        }

        override fun onTextChanged(
            s: CharSequence?,
            start: Int,
            before: Int,
            count: Int
        ) {
        }

        override fun afterTextChanged(s: Editable?) {
            updateLink()
        }

    }

    private val onAmountChangeListener = object : TextWatcher {
        override fun beforeTextChanged(
            s: CharSequence?,
            start: Int,
            count: Int,
            after: Int
        ) {
        }

        override fun onTextChanged(
            s: CharSequence?,
            start: Int,
            before: Int,
            count: Int
        ) {
        }

        override fun afterTextChanged(s: Editable?) {
            updateInputState()
        }

    }

    private var token = TokenStore.getToken(TONCOIN_SLUG)
    private var fiatMode = false
    private var equivalent: TokenEquivalent? = null

    override fun setupViews() {
        super.setupViews()
        setNavTitle(LocaleController.getString("Deposit Link"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        commentInputView.addTextChangedListener(onCommentChangeListener)

        amountInputView.doOnEquivalentButtonClick {
            fiatMode = !fiatMode
            val hasValue =
                (equivalent?.tokenAmount?.amountInteger ?: BigInteger.ZERO) > BigInteger.ZERO
            amountInputView.amountEditText.setText(
                if (hasValue) equivalent?.getRaw(fiatMode) ?: "" else ""
            )
            updateInputState()
        }
        amountInputView.amountEditText.addTextChangedListener(onAmountChangeListener)
        amountInputView.tokenSelectorView.setOnClickListener {
            push(
                TokenSelectorVC(
                    context,
                    LocaleController.getString("Select Token"),
                    TokenStore.tokens.values.filter {
                        it.chain == MBlockchain.ton.name
                    },
                    showMyAssets = true,
                    showChain = false,
                ).apply {
                    setOnAssetSelectListener { asset ->
                        token = TokenStore.getToken(asset.slug)
                        updateInputState()
                    }
                })
        }
        updateInputState()

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        topGapView.setBackgroundColor(WColor.Background.color)
        commentInputView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp
        )
        commentInputView.setTextColor(WColor.PrimaryText.color)
        commentInputView.setHintTextColor(WColor.SecondaryText.color)
        linkLabel.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp
        )
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        contentLayout.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            20.dp + max(
                (navigationController?.getSystemBars()?.bottom ?: 0),
                (window?.imeInsets?.bottom ?: 0)
            )
        )
    }

    override fun onDestroy() {
        super.onDestroy()

        amountInputView.tokenSelectorView.setOnClickListener(null)
        amountInputView.doOnEquivalentButtonClick(null)
        amountInputView.doOnFeeButtonClick(null)
        amountInputView.doOnMaxButtonClick(null)
        amountInputView.amountEditText.removeTextChangedListener(onAmountChangeListener)
        commentInputView.removeTextChangedListener(onCommentChangeListener)
    }

    private fun updateInputState() {
        val inputAmountParsed = CoinUtils.fromDecimal(
            amountInputView.amountEditText.text.toString(),
            (if (fiatMode) WalletCore.baseCurrency.decimalsCount else token?.decimals) ?: 0
        )
        equivalent = TokenEquivalent.from(
            fiatMode,
            token!!.price?.toBigDecimal() ?: BigDecimal.ZERO,
            token!!,
            inputAmountParsed ?: BigInteger.ZERO,
            WalletCore.baseCurrency ?: MBaseCurrency.USD
        )
        token?.let {
            amountInputView.set(
                state = TokenAmountInputView.State(
                    title = LocaleController.getString("Amount"),
                    token = token,
                    balance = null,
                    equivalent = equivalent?.getFmt(!fiatMode),
                    subtitle = null,
                    fiatMode = fiatMode,
                    inputDecimal = token!!.decimals,
                    inputSymbol = if (fiatMode) WalletCore.baseCurrency.sign else null,
                    inputError = false,
                ),
                false
            )
            updateLink()
        }
    }

    private fun updateLink() {
        title3.setTitle(
            LocaleController.getString("Share this URL to receive %token%")
                .replace("%token%", token?.name ?: "")
        )
        val shareLink = AddressHelpers.walletInvoiceUrl(
            AccountStore.activeAccount!!.tonAddress!!,
            commentInputView.text.toString(),
            token?.tokenAddress,
            equivalent?.getTokenAmount()?.let {
                if (it > BigInteger.ZERO) it.toString() else null
            }
        )
        val txt = "$shareLink "
        val ss = SpannableStringBuilder(txt)
        ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14
        )?.let { drawable ->
            drawable.mutate()
            drawable.setTint(WColor.SecondaryText.color)
            drawable.alpha = 204
            val width = 7.dp
            val height = 14.dp
            drawable.setBounds(0, 0, width, height)
            val imageSpan = VerticalImageSpan(drawable)
            ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        val clickableSpan: ClickableSpan = object : ClickableSpan() {
            override fun onClick(textView: View) {
                WMenuPopup.present(
                    linkLabel,
                    listOf(
                        WMenuPopup.Item(
                            null,
                            LocaleController.getString("Copy"),
                            false,
                        ) {
                            val clipboard =
                                context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            val clip = ClipData.newPlainText("", shareLink)
                            clipboard.setPrimaryClip(clip)
                            Haptics.play(context, HapticType.LIGHT_TAP)
                            Toast.makeText(context, "Invoice Link Copied", Toast.LENGTH_SHORT)
                                .show()
                        },
                        WMenuPopup.Item(
                            null,
                            LocaleController.getString("Share"),
                            false,
                        ) {
                            val shareIntent = Intent(Intent.ACTION_SEND)
                            shareIntent.setType("text/plain")
                            shareIntent.putExtra(Intent.EXTRA_TEXT, shareLink)
                            window?.startActivity(
                                Intent.createChooser(
                                    shareIntent,
                                    LocaleController.getString("Share")
                                )
                            )
                        }),
                    xOffset = 20.dp,
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.BELOW,
                    windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                        linkLabel,
                        roundRadius = 16f.dp
                    )
                )
            }

            override fun updateDrawState(ds: TextPaint) {
                super.updateDrawState(ds)
                ds.setColor(WColor.PrimaryText.color);
                ds.isUnderlineText = false
            }
        }
        ss.setSpan(clickableSpan, 0, txt.length + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        linkLabel.text = ss
    }
}
