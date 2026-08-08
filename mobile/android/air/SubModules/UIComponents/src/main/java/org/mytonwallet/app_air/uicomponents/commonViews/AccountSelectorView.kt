package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.view.View
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isVisible
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MAccount

@SuppressLint("ViewConstructor")
class AccountSelectorView(
    context: Context,
    private val accountsProvider: () -> List<MAccount>,
    private val onAccountSelected: (MAccount) -> Unit,
    private val isTransparent: Boolean = false
) : WFrameLayout(context),
    WThemedView {

    private val accountIconView = AccountIconView(context, AccountIconView.Usage.ViewItem()).apply {
        isClickable = false
        isFocusable = false
    }

    private val loadingDrawable = RoundProgressDrawable(18f.dp, 0.75f.dp)
    private val loadingView = object : View(context) {
        val size = 18.dp
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val left = (width - size) / 2
            val top = (height - size) / 2
            loadingDrawable.setBounds(left, top, left + size, top + size)
            loadingDrawable.draw(canvas)
        }

        override fun verifyDrawable(who: Drawable): Boolean {
            if (who == loadingDrawable) return isVisible
            return super.verifyDrawable(who)
        }
    }.apply {
        isVisible = false
        loadingDrawable.callback = this
    }

    private val expandIcon = AppCompatImageView(context)

    private var selectedAccountId: String? = null
    private var isLoading = false

    init {
        addView(
            accountIconView,
            LayoutParams(40.dp, 40.dp, Gravity.START or Gravity.CENTER_VERTICAL).apply {
                marginStart = 4.dp
            }
        )
        addView(
            loadingView,
            LayoutParams(40.dp, 40.dp, Gravity.START or Gravity.CENTER_VERTICAL).apply {
                marginStart = 4.dp
            }
        )
        addView(
            expandIcon,
            LayoutParams(18.dp, 18.dp, Gravity.END or Gravity.CENTER_VERTICAL).apply {
                marginEnd = 14.dp
            }
        )
        setOnClickListener { presentAccountSwitcher() }
        updateTheme()
    }

    fun config(account: MAccount) {
        selectedAccountId = account.accountId
        accountIconView.config(account)
    }

    fun setLoading(isLoading: Boolean) {
        this.isLoading = isLoading
        loadingView.isVisible = isLoading
        accountIconView.showText = !isLoading
    }

    override fun updateTheme() {
        setBackgroundColor(
            if (isTransparent) Color.WHITE.colorWithAlpha(38) else WColor.ThumbBackground.color,
            24f.dp
        )
        loadingDrawable.color = WColor.White.color
        expandIcon.setImageDrawable(
            context.getDrawableCompat(R.drawable.ic_expand)?.apply {
                setTint(
                    if (isTransparent) {
                        Color.WHITE.colorWithAlpha(153)
                    } else {
                        WColor.SecondaryText.color
                    }
                )
            }
        )
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            75.dp.exactly,
            48.dp.exactly
        )
    }

    private fun presentAccountSwitcher() {
        if (isLoading) return
        val accounts = accountsProvider()
        if (accounts.isEmpty()) return

        lateinit var popup: IPopup
        val items = accounts.mapIndexed { i, account ->
            WMenuPopup.Item(
                config = WMenuPopup.Item.Config.CustomView(
                    AccountItemView(
                        context = context,
                        accountData = AccountItemView.AccountData(
                            accountId = account.accountId,
                            title = account.name,
                            network = account.network,
                            byChain = account.byChain,
                            accountType = account.accountType
                        ),
                        showArrow = false,
                        isTrusted = true,
                        hasSeparator = false,
                        onSelect = {
                            popup.dismiss()
                            if (account.accountId != selectedAccountId) {
                                onAccountSelected(account)
                            }
                        }
                    )
                ),
                hasSeparator = i < accounts.size - 1
            )
        }

        popup = WMenuPopup.present(
            view = this,
            items = items,
            yOffset = 3.dp,
            positioning = WMenuPopup.Positioning.BELOW,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout.fromView(
                this,
                roundRadius = 24f.dp
            )
        )
    }
}
