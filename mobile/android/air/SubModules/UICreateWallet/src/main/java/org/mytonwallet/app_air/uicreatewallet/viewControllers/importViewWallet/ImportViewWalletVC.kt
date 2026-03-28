package org.mytonwallet.app_air.uicreatewallet.viewControllers.importViewWallet

import android.animation.ValueAnimator
import android.content.Context
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.AddressInputLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicreatewallet.viewControllers.walletAdded.WalletAddedVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.utils.jsonObject
import java.lang.ref.WeakReference

class ImportViewWalletVC(
    context: Context,
    private val network: MBlockchainNetwork,
    private val isOnIntro: Boolean
) :
    WViewController(context) {
    override val TAG = "ImportViewWallet"

    override val shouldDisplayTopBar = false

    private var prevHeight = 0
    private var heightAnimator: ValueAnimator? = null
    private var isAnimationViewVisible = true
    private var cachedContentBaseHeight = 0
    private var cachedContentWidth = 0

    val animationView = WAnimationView(context).apply {
        play(
            org.mytonwallet.app_air.uicomponents.R.raw.animation_bill, true,
            onStart = {
                fadeIn()
            })
    }

    val titleLabel = WLabel(context).apply {
        setStyle(28f, WFont.SemiBold)
        text = LocaleController.getString("View Mode") + network.localizedIdentifier
        gravity = Gravity.CENTER
        setTextColor(WColor.PrimaryText)
    }

    val subtitleLabel = WLabel(context).apply {
        setStyle(17f, WFont.Regular)
        text = LocaleController.getString("\$import_view_account_note")
            .toProcessedSpannableStringBuilder()
        gravity = Gravity.CENTER
        setTextColor(WColor.PrimaryText)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 26f)
    }

    private var address = ""
    private val addressInputView by lazy {
        AddressInputLayout(
            WeakReference(this),
            autoCompleteConfig = AddressInputLayout.AutoCompleteConfig(accountAddresses = false),
            onTextEntered = {
                view.hideKeyboard()
            }).apply {
            id = View.generateViewId()
            setMaxLines(2)
            setHint(LocaleController.getString("Address or Domain"))
            setPadding(0, 10.dp, 0, 0)
        }
    }

    private val continueButton = WButton(context).apply {
        text =
            LocaleController.getString("Continue")
        isEnabled = false
        setOnClickListener {
            importPressed()
        }
    }

    private val contentView = WView(context)

    private val onInputTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            address = s.toString()
            continueButton.isEnabled = address.isNotEmpty()
            continueButton.text = LocaleController.getString("Continue")
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(contentView, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            toBottom(contentView)
            toCenterX(contentView)
        }
        val bottomPadding = navigationController?.getSystemBars()?.bottom ?: 0
        contentView.setPadding(0, 0, 0, bottomPadding)

        contentView.addView(animationView, ViewGroup.LayoutParams(104.dp, 104.dp))
        contentView.addView(titleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        contentView.addView(subtitleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        contentView.addView(addressInputView, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        contentView.addView(continueButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        contentView.setConstraints {
            toCenterX(animationView)
            toCenterX(titleLabel, 32f)
            toCenterX(subtitleLabel, 32f)
            toCenterX(addressInputView, 10f)
            toCenterX(continueButton, 20f)
            toBottom(continueButton, 16f)
            topToTopPx(addressInputView, continueButton, -(32 + 84).dp)
            bottomToTop(subtitleLabel, addressInputView, 32f)
            bottomToTop(titleLabel, subtitleLabel, 20f)
            bottomToTop(animationView, titleLabel, 24f)
            toTop(animationView, 22f)
        }

        addressInputView.addTextChangedListener(onInputTextWatcher)

        updateTheme()
    }

    override val isExpandable = false
    override fun getModalHalfExpandedHeight(): Int? {
        val width = maxOf(
            view.width,
            navigationController?.width ?: 0,
            context.resources.displayMetrics.widthPixels
        )
        val paddingBottom = contentView.paddingBottom
        if (cachedContentBaseHeight == 0 || cachedContentWidth != width) {
            contentView.measure(
                View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            )
            val measured = contentView.measuredHeight.takeIf { it > 0 } ?: return null
            cachedContentBaseHeight = measured - paddingBottom
            cachedContentWidth = width
        }
        val measured = cachedContentBaseHeight + paddingBottom
        val windowHeight = window?.windowView?.height?.takeIf { it > 0 } ?: return measured
        return minOf(measured, windowHeight)
    }

    override fun updateTheme() {
        super.updateTheme()

        updateBackgroundRadius()
        addressInputView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
    }

    private fun updateBackgroundRadius() {
        val screenTop = (navigationController?.y ?: 0f).toInt() + view.top
        val radius = minOf(screenTop.toFloat(), ViewConstants.BLOCK_RADIUS.dp)
        view.setBackgroundColor(WColor.SecondaryBackground.color, radius, 0f)
    }

    private fun updateContentProperties() {
        updateBackgroundRadius()
        val screenTop = (navigationController?.y ?: 0f).toInt() + view.top
        val systemTop = window?.systemBars?.top ?: 0
        navigationBar?.translationY = maxOf(0f, (systemTop - screenTop).toFloat())
    }

    override fun onDestroy() {
        super.onDestroy()

        addressInputView.removeTextChangedListener(onInputTextWatcher)
    }

    private fun importPressed() {
        val address = addressInputView.getAddress()
        val addressByChain = mutableMapOf<MBlockchain, String>()
        for (chain in MBlockchain.supportedChains) {
            if (chain.isValidAddress(address) || chain.isValidDNS(address)) {
                addressByChain[chain] = address
            }
        }
        view.lockView()
        continueButton.isLoading = true
        WalletCore.call(
            ApiMethod.Auth.ImportViewAccount(network, addressByChain),
            callback = { result, error ->
                if (result == null || error != null) {
                    view.unlockView()
                    continueButton.isLoading = false
                    continueButton.isEnabled = false
                    error?.parsed?.toShortLocalized?.let { it ->
                        continueButton.text = error.parsed.toShortLocalized
                    } ?: run {
                        continueButton.text = LocaleController.getString("Continue")
                        error?.parsed?.toLocalized?.let { it ->
                            showAlert(
                                title = LocaleController.getString("Error"),
                                text = it
                            )
                        }
                    }
                    return@call
                }
                Logger.d(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(
                            result.accountId,
                            LogMessage.MessagePartPrivacy.PUBLIC
                        )
                        .append(
                            "Imported, View",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        )
                        .append(
                            "Address: ${result.byChain}",
                            LogMessage.MessagePartPrivacy.REDACTED
                        ).build()
                )
                val importedName = result.title?.trim()?.takeIf { it.isNotEmpty() }
                WGlobalStorage.addAccount(
                    accountId = result.accountId,
                    accountType = MAccount.AccountType.VIEW.value,
                    byChain = result.byChain.jsonObject,
                    name = importedName,
                    importedAt = null
                )
                AirPushNotifications.subscribe(
                    result.accountId,
                    ignoreIfLimitReached = true
                )
                WalletCore.activateAccount(
                    accountId = result.accountId,
                    notifySDK = false
                ) { _, err ->
                    if (err != null) {
                        return@activateAccount
                    }
                    if (isOnIntro) {
                        handlePush(WalletAddedVC(context, false), {
                            navigationController?.removePrevViewControllers()
                        })
                    } else {
                        WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
                        window!!.dismissLastNav()
                    }
                }
            })
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val navController = navigationController ?: return
        val keyboardHeight = window?.imeInsets?.bottom ?: 0
        val systemBarBottom = navController.getSystemBars().bottom
        val targetHeight = maxOf(systemBarBottom, keyboardHeight)
        if (prevHeight == targetHeight) {
            return
        }

        heightAnimator?.cancel()
        val startInset = contentView.paddingBottom
        prevHeight = targetHeight

        val width = maxOf(view.width, navController.width, ApplicationContextHolder.screenWidth)
        contentView.setPadding(0, 0, 0, targetHeight)
        contentView.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val shouldHideAnimationView = contentView.measuredHeight > (window?.windowView?.height ?: 0)
        contentView.setPadding(0, 0, 0, startInset)

        if (shouldHideAnimationView && isAnimationViewVisible) {
            isAnimationViewVisible = false
            animationView.fadeOut(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
        } else if (!shouldHideAnimationView && !isAnimationViewVisible) {
            isAnimationViewVisible = true
            animationView.fadeIn()
        }

        val onUpdate = { inset: Int ->
            contentView.setPadding(0, 0, 0, inset)
            navController.onBottomSheetHeightChanged()
            updateContentProperties()
        }

        if (!WGlobalStorage.getAreAnimationsActive()) {
            onUpdate(targetHeight)
            return
        }

        heightAnimator = ValueAnimator.ofInt(startInset, targetHeight).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = WInterpolator.emphasized
            addUpdateListener {
                onUpdate(it.animatedValue as Int)
            }
            start()
        }
    }

    override fun onModalSlide(expandOffset: Int, expandProgress: Float) {
        super.onModalSlide(expandOffset, expandProgress)
        updateContentProperties()
    }

    private fun handlePush(viewController: WViewController, onCompletion: (() -> Unit)? = null) {
        window?.dismissLastNav {
            window?.navigationControllers?.lastOrNull()
                ?.push(viewController, onCompletion = onCompletion)
        }
    }
}
