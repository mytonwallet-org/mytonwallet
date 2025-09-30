package org.mytonwallet.app_air.uiwidgets.configurations.priceWidget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.Gravity
import android.view.View.generateViewId
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.TokenSelectorVC
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WEditableItemView
import org.mytonwallet.app_air.uicomponents.widgets.WTokenSymbolIconView
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetConfigurationVC
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TRON_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletsdk.methods.SDKApiMethod
import org.mytonwallet.app_air.widgets.priceWidget.PriceWidget
import org.mytonwallet.app_air.widgets.priceWidget.PriceWidget.Config

class PriceWidgetConfigurationVC(
    context: Context,
    override val appWidgetId: Int,
    override val onResult: (ok: Boolean) -> Unit
) :
    WidgetConfigurationVC(context), WalletCore.EventObserver {

    override val shouldDisplayTopBar = false

    var selectedToken = TokenStore.getToken(TONCOIN_SLUG)
    private val tokenView = object : WTokenSymbolIconView(context) {
        override fun updateTheme() {
            super.updateTheme()
            shapeDrawable.paint.color = WColor.TrinaryBackground.color
        }
    }.apply {
        id = generateViewId()
        drawable = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18
        )
        defaultSymbol = LocaleController.getString("Loading...")
        setAsset(selectedToken)
    }
    private val tokenRow =
        KeyValueRowView(
            context,
            LocaleController.getString("Token"),
            "",
            KeyValueRowView.Mode.PRIMARY,
            isLast = true,
        ).apply {
            setValueView(tokenView)
            setOnClickListener {
                openTokenSelector()
            }
        }

    var selectedPeriod = MHistoryTimePeriod.DAY
    private val periodView = WEditableItemView(context).apply {
        id = generateViewId()
        drawable = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18
        )
        setText(selectedPeriod.localizedLong)
    }
    private val periodViewRow =
        KeyValueRowView(
            context,
            LocaleController.getString("Chart Period"),
            "",
            KeyValueRowView.Mode.PRIMARY,
            isLast = true,
        ).apply {
            setValueView(periodView)
            setOnClickListener {
                if (continueButton.isLoading)
                    return@setOnClickListener
                WMenuPopup.present(
                    periodView,
                    MHistoryTimePeriod.allPeriods.map {
                        WMenuPopup.Item(
                            null,
                            it.localizedLong,
                            false
                        ) {
                            selectedPeriod = it
                            periodView.setText(it.localizedLong)
                        }
                    },
                    popupWidth = WRAP_CONTENT,
                    aboveView = false
                )
            }
        }

    val continueButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Continue")
        setOnClickListener {
            lockView()
            isLoading = true
            val config = Config(selectedToken?.toDictionary()?.apply {
                if (selectedToken?.slug == TRON_SLUG)
                    put("color", "#FF3B30")
            }, selectedPeriod)
            val baseCurrency = (WBaseStorage.getBaseCurrency() ?: MBaseCurrency.USD).currencyCode
            SDKApiMethod.Token.PriceChart(
                config.assetId ?: PriceWidget.DEFAULT_TOKEN,
                selectedPeriod.value,
                baseCurrency
            )
                .call(object : SDKApiMethod.ApiCallback<Array<Array<Double>>> {
                    override fun onSuccess(result: Array<Array<Double>>) {
                        config.apply {
                            cachedChart = result.toList()
                            cachedChartDt = System.currentTimeMillis()
                            cachedChartCurrency = baseCurrency
                        }
                        WBaseStorage.setWidgetConfigurations(
                            appWidgetId,
                            config.toJson()
                        )
                        val appWidgetManager = AppWidgetManager.getInstance(context)
                        PriceWidget().onUpdate(
                            context, appWidgetManager, intArrayOf(appWidgetId)
                        )
                        onResult(true)
                    }

                    override fun onError(error: Throwable) {
                        unlockView()
                        isLoading = false
                        showError(MBridgeError.UNKNOWN)
                    }
                })
        }
    }

    override fun setupViews() {
        super.setupViews()

        title = LocaleController.getString("Customize Widget")
        setupNavBar(true)
        navigationBar?.titleLabel?.setStyle(20f, WFont.SemiBold)
        navigationBar?.setTitleGravity(Gravity.CENTER)

        view.apply {
            addView(tokenRow, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            addView(periodViewRow, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            addView(continueButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            setConstraints {
                topToBottom(tokenRow, navigationBar!!, 16f)
                toCenterXPx(tokenRow, ViewConstants.HORIZONTAL_PADDINGS.dp)
                topToBottom(periodViewRow, tokenRow)
                toCenterXPx(periodViewRow, ViewConstants.HORIZONTAL_PADDINGS.dp)
                toCenterX(continueButton, 20f)
                toBottomPx(
                    continueButton,
                    navigationController?.getSystemBars()?.bottom ?: 0
                )
            }
        }

        if (TokenStore.tokens.isEmpty()) {
            WalletCore.registerObserver(this)
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        tokenRow.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BAR_ROUNDS.dp,
            0f
        )
        periodViewRow.setBackgroundColor(WColor.Background.color, 0f, ViewConstants.BIG_RADIUS.dp)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        navigationBar?.setPadding(0, (navigationController?.getSystemBars()?.top) ?: 0, 0, 0)
        view.setConstraints {
            toBottomPx(
                continueButton,
                16.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
    }

    var openSelectorsOnTokenReceive = false
    private fun openTokenSelector() {
        if (continueButton.isLoading || isDisappeared)
            return
        if (TokenStore.tokens.isEmpty()) {
            openSelectorsOnTokenReceive = true
            return
        }
        push(
            TokenSelectorVC(
                context,
                LocaleController.getString("Select Token"),
                TokenStore.tokens.values.toList(),
                showMyAssets = false
            ).apply {
                setOnAssetSelectListener { asset ->
                    selectedToken = TokenStore.getToken(asset.slug)
                    tokenView.setAsset(asset)
                }
            })
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.TokensChanged -> {
                if (openSelectorsOnTokenReceive)
                    openTokenSelector()
                if (selectedToken == null) {
                    selectedToken = TokenStore.getToken(TONCOIN_SLUG)
                    tokenView.setAsset(selectedToken)
                }
            }

            else -> {}
        }
    }
}
