package org.mytonwallet.app_air.uiwidgets.configurations.priceWidget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Handler
import android.os.Looper
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
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetConfigurationVC
import org.mytonwallet.app_air.uiwidgets.configurations.views.WidgetPreviewView
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
import org.mytonwallet.app_air.widgets.utils.ImageUtils

class PriceWidgetConfigurationVC(
    context: Context,
    override val appWidgetId: Int,
    override val onResult: (ok: Boolean) -> Unit
) :
    WidgetConfigurationVC(context), WalletCore.EventObserver {
    override val TAG = "PriceWidgetConfiguration"

    private val periodViewRowRipple = WRippleDrawable.create(0f, 0f, ViewConstants.BLOCK_RADIUS.dp, ViewConstants.BLOCK_RADIUS.dp)

    override val shouldDisplayTopBar = false

    private val previewView = WidgetPreviewView(context)

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
            isLast = false,
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
                            updateWidgetPreview()
                        }
                    },
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.BELOW,
                    windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                        periodView,
                        roundRadius = 16f.dp
                    )
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
            addView(previewView, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            addView(tokenRow, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            addView(periodViewRow, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            addView(continueButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))

            setConstraints {
                topToBottom(previewView, navigationBar!!)
                toCenterX(previewView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                topToBottom(tokenRow, previewView, 16f)
                toCenterX(tokenRow, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                topToBottom(periodViewRow, tokenRow)
                toCenterX(periodViewRow, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
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

        updateWidgetPreview()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        previewView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.TOOLBAR_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp
        )
        tokenRow.setTopRadius(ViewConstants.BLOCK_RADIUS.dp)
        tokenRow.setBackgroundColor(WColor.Background.color)
        periodViewRow.background = periodViewRowRipple
        periodViewRowRipple.backgroundColor = WColor.Background.color
        periodViewRowRipple.rippleColor = WColor.SecondaryBackground.color
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
                showMyAssets = false,
                showChain = false
            ).apply {
                setOnAssetSelectListener { asset ->
                    selectedToken = TokenStore.getToken(asset.slug)
                    tokenView.setAsset(asset)
                    updateWidgetPreview()
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

    private fun updateWidgetPreview() {
        previewView.setWidget(null)
        val token = selectedToken?.slug
        val config = Config(
            selectedToken?.toDictionary()?.apply {
                if (selectedToken?.slug == TRON_SLUG)
                    put("color", "#FF3B30")
            },
            selectedPeriod,
            appWidgetMinWidth = WidgetPreviewView.WIDTH,
            appWidgetMinHeight = WidgetPreviewView.HEIGHT,
            appWidgetMaxWidth = WidgetPreviewView.WIDTH,
            appWidgetMaxHeight = WidgetPreviewView.HEIGHT
        )
        val baseCurrency = (WBaseStorage.getBaseCurrency() ?: MBaseCurrency.USD).currencyCode
        SDKApiMethod.Token.PriceChart(
            config.assetId ?: PriceWidget.DEFAULT_TOKEN,
            selectedPeriod.value,
            baseCurrency
        )
            .call(object : SDKApiMethod.ApiCallback<Array<Array<Double>>> {
                override fun onSuccess(result: Array<Array<Double>>) {
                    ImageUtils.loadBitmapFromUrl(
                        context,
                        config.token?.optString("image", ""),
                        onBitmapReady = { image ->
                            Handler(Looper.getMainLooper()).post {
                                if (config.period != selectedPeriod || token != selectedToken?.slug)
                                    return@post
                                config.apply {
                                    cachedChart = result.toList()
                                    cachedChartDt = System.currentTimeMillis()
                                    cachedChartCurrency = baseCurrency
                                }
                                previewView.setWidget(
                                    PriceWidget().generateRemoteViews(
                                        context,
                                        config,
                                        WidgetPreviewView.WIDTH,
                                        WidgetPreviewView.HEIGHT,
                                        null,
                                        null
                                    )
                                )
                            }
                        })
                }

                override fun onError(error: Throwable) {
                }
            })
    }
}
