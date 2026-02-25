package org.mytonwallet.app_air.uireceive

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Shader
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WQRCodeView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.AddressHelpers
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class QRCodeVC(
    context: Context,
    val chain: MBlockchain,
) : WViewController(context) {
    override val TAG = "QRCode"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false

    override var title: String?
        get() = chain.displayName
        set(_) {}

    val walletAddress: String
        get() = AccountStore.activeAccount?.addressByChain?.get(chain.name) ?: ""

    companion object {
        const val HEIGHT = 307
    }

    private val qrCodeSize = 252.dp
    internal val qrCodeView: WQRCodeView by lazy {
        val qrContent = if (chain == MBlockchain.ton)
            AddressHelpers.walletInvoiceUrl(walletAddress)
        else
            walletAddress
        val v = WQRCodeView(
            context,
            qrContent,
            qrCodeSize,
            qrCodeSize,
            chain.icon,
            56.dp,
            chain.qrGradientColors?.let {
                LinearGradient(
                    0f, 0f, qrCodeSize.toFloat(), qrCodeSize.toFloat(),
                    it,
                    null,
                    Shader.TileMode.CLAMP
                )
            }
        ).apply {
            setPadding(1, 1, 1, 1)
            generate {
                view.fadeIn()
            }
        }
        v
    }

    val ornamentView = AppCompatImageView(context).apply {
        id = View.generateViewId()
        alpha = 0.5f
    }

    init {
        view.alpha = 0f
    }

    private val addressLabel = CopyTextView(context).apply {
        id = View.generateViewId()

        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 22f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        gravity = Gravity.LEFT
        typeface = WFont.Regular.typeface
        layoutParams = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)

        includeFontPadding = false
        clipLabel = "Address"
        clipToast =
            LocaleController.getString("%chain% Address Copied")
                .replace("%chain%", chain.displayName)
        setText(walletAddress, walletAddress)
    }

    private val titleLabel = HeaderCell(context, startMargin = 24f).apply {
        configure(
            title = LocaleController.getString("Your %blockchain% Address")
                .replace("%blockchain%", title.toString()),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private val warningLabel = WLabel(context).apply {
        setStyle(14f, WFont.Regular)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 20f)
        text = if (chain == MBlockchain.ton)
            LocaleController.getString("\$send_only_ton")
        else
            LocaleController.getStringWithKeyValues(
                "\$send_only_chain", listOf(
                    Pair("%chain%", chain.name.replaceFirstChar { it.uppercaseChar() }),
                    Pair(
                        "%symbol%",
                        TokenStore.getToken(chain.nativeSlug)?.symbol ?: ""
                    ),
                )
            )
    }

    val addressView = WView(context).apply {
        setPadding(20.dp, 6.dp, 20.dp, 14.dp)

        addView(
            addressLabel,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT)
        )
        addView(
            warningLabel,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT)
        )

        setConstraints {
            toTop(addressLabel)
            toCenterX(addressLabel)
            topToBottom(warningLabel, addressLabel, 11f)
            toCenterX(warningLabel, 4f)
        }
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(
            ornamentView,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, LayoutParams.MATCH_CONSTRAINT)
        )
        view.addView(
            qrCodeView,
            LayoutParams(qrCodeSize, qrCodeSize)
        )
        view.addView(
            titleLabel,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT)
        )
        view.addView(
            addressView,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT)
        )

        view.setConstraints {
            toCenterX(qrCodeView)
            centerYToCenterY(ornamentView, qrCodeView, 16f.dp)
            toCenterX(ornamentView)
            topToBottom(titleLabel, qrCodeView, 39f)
            toCenterX(titleLabel)
            topToBottom(addressView, titleLabel)
            toCenterX(addressView)
        }

        addressView.measure(0.unspecified, 0.unspecified)
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(Color.TRANSPARENT)
        view.setConstraints {
            toTopPx(
                qrCodeView, (navigationController?.getSystemBars()?.top ?: 0) +
                    WNavigationBar.DEFAULT_HEIGHT.dp + 16.dp
            )
        }
        addressLabel.setTextColor(WColor.PrimaryText.color)
        titleLabel.updateTheme()
        warningLabel.setTextColor(WColor.SecondaryText.color)
        addressView.setBackgroundColor(WColor.Background.color)

        val ornamentRes = chain.receiveOrnamentImage
        if (ornamentRes != null) {
            ornamentView.setImageDrawable(ContextCompat.getDrawable(context, ornamentRes))
            ornamentView.scaleType = ImageView.ScaleType.CENTER_INSIDE
            ornamentView.visibility = View.VISIBLE
        } else {
            ornamentView.setImageDrawable(null)
            ornamentView.visibility = View.INVISIBLE
        }
    }

    fun getHeight(): Int {
        return (addressView.y + addressView.height).toInt()
    }

    fun getTransparentHeight(): Int {
        return HEIGHT.dp
    }

}
