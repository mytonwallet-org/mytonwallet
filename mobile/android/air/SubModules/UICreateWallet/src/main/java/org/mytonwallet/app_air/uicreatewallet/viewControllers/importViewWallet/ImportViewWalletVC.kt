package org.mytonwallet.app_air.uicreatewallet.viewControllers.importViewWallet

import android.content.Context
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.AddressInputLayout
import org.mytonwallet.app_air.uicomponents.extensions.atMost
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicreatewallet.viewControllers.walletAdded.WalletAddedVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
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

    val animationView = WAnimationView(context).apply {
        play(
            org.mytonwallet.app_air.uicomponents.R.raw.animation_bill, true,
            onStart = {
                fadeIn()
            })
    }

    val titleLabel = WLabel(context).apply {
        setStyle(28f, WFont.SemiBold)
        text = LocaleController.getString("View Any Address") + network.localizedIdentifier
        gravity = Gravity.CENTER
        setTextColor(WColor.PrimaryText)
    }

    val subtitleLabel = WLabel(context).apply {
        setStyle(17f, WFont.Regular)
        text = LocaleController.getStringWithKeyValues(
            "\$import_view_account_note", listOf(
                Pair(
                    "%chains%",
                    LocaleController.getFormattedEnumeration(
                        MBlockchain.supportedChains.map { it.displayName },
                        "or"
                    )
                )
            )
        ).toProcessedSpannableStringBuilder()
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
            setHint(LocaleController.getString("Wallet Address or Domain"))
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

        view.addView(animationView, ViewGroup.LayoutParams(104.dp, 104.dp))
        view.addView(titleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.addView(subtitleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.addView(addressInputView, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.addView(continueButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            toTop(animationView, 22f)
            toCenterX(animationView)
            topToBottom(titleLabel, animationView, 24f)
            toCenterX(titleLabel, 32f)
            topToBottom(subtitleLabel, titleLabel, 20f)
            toCenterX(subtitleLabel, 32f)
            topToBottom(addressInputView, subtitleLabel, 32f)
            toCenterX(addressInputView, 10f)
            constrainMaxHeight(addressInputView.id, 80.dp)
            toCenterX(continueButton, 20f)
            topToTop(continueButton, addressInputView, 112f)
            toBottomPx(continueButton, 16.dp + (navigationController?.getSystemBars()?.bottom ?: 0))
        }

        addressInputView.addTextChangedListener(onInputTextWatcher)

        updateTheme()
    }

    private var cachedHeight = 0
    override val isExpandable = false
    override fun getModalHalfExpandedHeight(): Int? {
        if (cachedHeight > 0)
            return cachedHeight
        titleLabel.measure((view.width - 64.dp).atMost, 0.unspecified)
        subtitleLabel.measure((view.width - 64.dp).atMost, 0.unspecified)

        val titleHeight = titleLabel.measuredHeight.coerceAtLeast(1)
        val subtitleHeight = subtitleLabel.measuredHeight.coerceAtLeast(1)

        cachedHeight = 431.dp + // 416: content + 15: continueButton to bottom
            titleHeight +
            subtitleHeight +
            (navigationController?.getSystemBars()?.bottom ?: 0)
        return cachedHeight
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )
        addressInputView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
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

    private fun handlePush(viewController: WViewController, onCompletion: (() -> Unit)? = null) {
        window?.dismissLastNav {
            window?.navigationControllers?.lastOrNull()
                ?.push(viewController, onCompletion = onCompletion)
        }
    }
}
