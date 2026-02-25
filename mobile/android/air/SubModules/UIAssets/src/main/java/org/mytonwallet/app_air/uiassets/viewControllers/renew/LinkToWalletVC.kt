package org.mytonwallet.app_air.uiassets.viewControllers.renew

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.AddressInputLayout
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivitySingleTagView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.roundToInt

class LinkToWalletVC(
    context: Context,
    val nft: ApiNft
) : WViewController(context) {
    override val TAG = "LinkToWallet"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false

    var address: String? = NftStore.nftData?.linkedAddressByAddress?.get(nft.address)
    private var realFee = BigInteger.ZERO

    private val nftTagView = ActivitySingleTagView(context).apply {
        configure(nft)
    }

    private val feeLabel = WLabel(context).apply {
        setStyle(14f, WFont.Regular)
        setTextColor(WColor.SecondaryText)
    }

    private val titleLabel = HeaderCell(context, startMargin = 20f).apply {
        configure(
            LocaleController.getString("Linked Address"),
            WColor.Tint,
            HeaderCell.TopRounding.NORMAL
        )
    }

    private val addressInputView by lazy {
        AddressInputLayout(
            WeakReference(this),
            AddressInputLayout.AutoCompleteConfig(
                type = AddressInputLayout.AutoCompleteConfig.Type.EXTERNAL
            ),
            onTextEntered = {
                view.hideKeyboard()
            }).apply {
            id = View.generateViewId()
            showCloseOnTextEditing = true
            setHint(LocaleController.getString("Enter Address"))
        }
    }

    private val linkedWalletView: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = View.generateViewId()
            orientation = LinearLayout.VERTICAL
            addView(titleLabel)
            addView(
                addressInputView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
        }
    }

    private val linkButton = WButton(context).apply {
        text =
            LocaleController.getString("Link")
        setOnClickListener {
            onRenewPressed()
        }
    }

    private val onInputDestinationTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            address = s.toString()
            if (MBlockchain.ton.isValidAddress(address ?: "")) {
                calculateFee(address!!)
            } else {
                linkButton.isEnabled = false
                linkButton.isLoading = false
                linkButton.text = LocaleController.getString("Enter Address")
            }
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Change Linked Wallet"))
        setupNavBar(true)

        navigationBar?.addCloseButton()

        view.addView(nftTagView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(feeLabel, FrameLayout.LayoutParams(WRAP_CONTENT, 21.dp))
        view.addView(linkedWalletView, FrameLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        view.addView(linkButton, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        view.setConstraints {
            topToBottom(nftTagView, navigationBar!!, 16f)
            toCenterX(nftTagView, 16f)
            topToBottom(linkedWalletView, nftTagView, 16f)
            toCenterX(linkedWalletView, 16f)
            toTop(feeLabel, 287.6f)
            toCenterX(feeLabel)
            topToBottom(linkButton, feeLabel, 16f)
            toCenterX(linkButton, 16f)
            toBottomPx(linkButton, 8.dp)
            constrainMaxHeight(linkedWalletView.id, 118.dp)
            constrainedHeight(linkedWalletView.id, true)
        }

        address?.let { address ->
            addressInputView.setText(address)
            calculateFee(address)
        } ?: run {
            linkButton.isEnabled = false
        }
        addressInputView.addTextChangedListener(onInputDestinationTextWatcher)

        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val systemBarBottom = (navigationController?.getSystemBars()?.bottom ?: 0)
        view.setPadding(
            0,
            0,
            0,
            systemBarBottom
        )
        addressInputView.insetsUpdated()
    }

    override fun keyboardAnimationFrameRendered() {
        super.keyboardAnimationFrameRendered()
        addressInputView.insetsUpdated()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
        nftTagView.setBackgroundColor(
            WColor.Background.color,
            12f.dp
        )
        linkedWalletView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
    }

    @SuppressLint("SetTextI18n")
    private fun calculateFee(address: String) {
        val accountId = displayedAccount.accountId ?: return
        linkButton.isLoading = true
        WalletCore.call(
            ApiMethod.Domains.CheckDnsChangeWalletDraft(
                accountId,
                nft,
                address
            ), callback = { res, err ->
                if (this.address != address || isDestroyed)
                    return@call
                this.realFee = res?.realFee ?: BigInteger.ZERO
                if (err != null || realFee == null) {
                    Handler(Looper.getMainLooper()).postDelayed({
                        calculateFee(address)
                    }, 5000)
                    return@call
                }
                if ((BalanceStore.getBalances(accountId)
                        ?.get(TONCOIN_SLUG) ?: BigInteger.ZERO) >= realFee
                ) {
                    linkButton.isEnabled = true
                    linkButton.isLoading = false
                    val tonToken = TokenStore.getToken(TONCOIN_SLUG) ?: return@call
                    feeLabel.text =
                        "${LocaleController.getString("Fee")}: ${
                            realFee.toString(
                                decimals = tonToken.decimals,
                                currency = tonToken.symbol,
                                currencyDecimals = realFee.smartDecimalsCount(tonToken.decimals),
                                showPositiveSign = false,
                                forceCurrencyToRight = true
                            )
                        }"
                    feeLabel.alpha = 0f
                    feeLabel.fadeIn()
                } else {
                    linkButton.isEnabled = false
                    linkButton.setText(LocaleController.getString("Insufficient Balance"))
                }
            })
    }

    private fun onRenewPressed() {
        if (AccountStore.activeAccount?.isHardware == true) {
            submitDnsChangeWithHardware()
        } else {
            submitDnsChangeWithPassword()
        }
    }

    private val headerView: View
        get() {
            return PasscodeHeaderSendView(
                WeakReference(this),
                (window!!.windowView.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
            ).apply {
                config(
                    Content.ofUrl(nft.image ?: ""),
                    LocaleController.getString("Confirm Linking"),
                    nft.name ?: "",
                    Content.Rounding.Radius(12f.dp)
                )
            }
        }

    private fun submitDnsChangeWithHardware() {
        linkButton.lockView()
        val account = AccountStore.activeAccount!!
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                signData = LedgerConnectVC.SignData.LinkNftToWallet(
                    accountId = account.accountId,
                    nft = nft,
                    address = address!!,
                    realFee = realFee
                ),
                onDone = {
                    window?.dismissLastNav { }
                }),
            headerView = headerView
        )
        val nav = WNavigationController(window!!)
        nav.setRoot(ledgerConnectVC)
        window?.present(nav, onCompletion = {
            linkButton.unlockView()
        })
    }

    private fun submitDnsChangeWithPassword() {
        val passcodeConfirmVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                headerView,
                LocaleController.getString("Confirm Linking")
            ),
            task = { passcode ->
                WalletCore.call(
                    ApiMethod.Domains.SubmitDnsChangeWallet(
                        AccountStore.activeAccountId!!,
                        passcode,
                        nft,
                        address!!,
                        realFee
                    ), callback = { res, err ->
                        if (err != null) {
                            showError(err.parsed)
                            return@call
                        }
                        window?.dismissLastNav {
                            window?.dismissLastNav { }
                        }
                    })
            }
        )
        val nav = WNavigationController(window!!)
        nav.setRoot(passcodeConfirmVC)
        window?.present(nav, onCompletion = {
            linkButton.unlockView()
        })
    }

    override fun onDestroy() {
        super.onDestroy()

        addressInputView.removeTextChangedListener(onInputDestinationTextWatcher)
    }
}
