package org.mytonwallet.app_air.uicreatewallet.viewControllers.addAccountOptions

import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.widget.NestedScrollView
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.LinedCenteredTitleView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicreatewallet.viewControllers.importViewWallet.ImportViewWalletVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.importWallet.ImportWalletVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.wordDisplay.WordDisplayVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.WalletVersionsVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.coloredSubstring
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class AddAccountOptionsVC(context: Context, val network: MBlockchainNetwork, val isOnIntro: Boolean) :
    WViewController(context) {
    override val TAG = "AddAccountOptions"

    private val showCreateButton = !isOnIntro

    override val shouldDisplayTopBar = false

    private val otherVersionsAvailable =
        AccountStore.walletVersionsData?.versions?.isNotEmpty() == true

    private val createWalletRow: SettingsItemCell by lazy {
        SettingsItemCell(context, 64f, SettingsItemCell.SIMPLE_ROW_HEIGHT).apply {
            configure(
                item = SettingsItem(
                    SettingsItem.Identifier.NONE,
                    org.mytonwallet.app_air.uicreatewallet.R.drawable.ic_add_create,
                    LocaleController.getString("Create New Wallet"),
                    value = null,
                    hasTintColor = false
                ),
                subtitle = null,
                isFirst = true,
                isLast = true,
                onTap = {
                    view.lockView()
                    WalletCore.doOnBridgeReady {
                        WalletCore.call(
                            ApiMethod.Auth.GenerateMnemonic(),
                            callback = { words, err ->
                                if (words != null) {
                                    mnemonicGenerated(words)
                                } else {
                                    view.unlockView()
                                    showError(err?.parsed)
                                }
                            })
                    }
                }
            )
        }
    }

    private val orImportTitleView: LinedCenteredTitleView by lazy {
        LinedCenteredTitleView(context).apply {
            configure(LocaleController.getString("or import from"), 24.dp, 24.dp)
            configureText(WFont.Regular, WColor.SecondaryText)
            lineColor = WColor.SecondaryText
        }
    }

    private val createNewWalletView: WView by lazy {
        WView(context).apply {
            addView(createWalletRow, FrameLayout.LayoutParams(0, WRAP_CONTENT))
            addView(orImportTitleView, FrameLayout.LayoutParams(0, WRAP_CONTENT))
            setConstraints {
                toTop(createWalletRow)
                toCenterX(createWalletRow, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                topToBottom(orImportTitleView, createWalletRow, 2f)
                toCenterX(orImportTitleView)
                toBottom(orImportTitleView)
            }
        }
    }

    private val secretWordsRow = SettingsItemCell(context, 64f, SettingsItemCell.SIMPLE_ROW_HEIGHT).apply {
        configure(
            item = SettingsItem(
                SettingsItem.Identifier.NONE,
                org.mytonwallet.app_air.uicreatewallet.R.drawable.ic_add_secret,
                LocaleController.getPluralOrFormat("%1\$d Secret Words", 12, "12/24"),
                value = null,
                hasTintColor = false
            ),
            subtitle = null,
            isFirst = true,
            isLast = false,
            onTap = {
                if (!WGlobalStorage.isPasscodeSet()) {
                    handlePush(
                        ImportWalletVC(
                            context,
                            network = network,
                            passedPasscode = null
                        )
                    )
                } else {
                    lateinit var passcodeConfirmVC: PasscodeConfirmVC
                    passcodeConfirmVC = PasscodeConfirmVC(
                        context,
                        PasscodeViewState.Default(
                            LocaleController.getString("Enter Passcode"),
                            "",
                            LocaleController.getString("Import Existing Wallet"),
                            showNavigationSeparator = false,
                            startWithBiometrics = true
                        ),
                        task = { passcode ->
                            val vc = ImportWalletVC(context, network, passcode)
                            passcodeConfirmVC.push(
                                vc,
                                onCompletion = {
                                    vc.navigationController?.removePrevViewControllers()
                                })
                        }
                    )
                    handlePush(passcodeConfirmVC)
                }
            }
        )
    }

    private val ledgerRow = SettingsItemCell(context, 64f, SettingsItemCell.SIMPLE_ROW_HEIGHT).apply {
        configure(
            item = SettingsItem(
                SettingsItem.Identifier.NONE,
                org.mytonwallet.app_air.uicreatewallet.R.drawable.ic_add_ledger,
                LocaleController.getString("Ledger"),
                value = null,
                hasTintColor = false
            ),
            subtitle = null,
            isFirst = false,
            isLast = true,
            onTap = {
                handlePush(LedgerConnectVC(context, LedgerConnectVC.Mode.AddAccount(network)))
            }
        )
    }

    private val viewRow = SettingsItemCell(context, 64f, SettingsItemCell.SIMPLE_ROW_HEIGHT).apply {
        configure(
            item = SettingsItem(
                SettingsItem.Identifier.NONE,
                org.mytonwallet.app_air.uicreatewallet.R.drawable.ic_add_view,
                LocaleController.getString("View Any Address"),
                value = null,
                hasTintColor = false
            ),
            subtitle = null,
            isFirst = true,
            isLast = true,
            onTap = {
                push(ImportViewWalletVC(context, network, isOnIntro))
            }
        )
    }

    val switchToOtherWalletVersionsButton = WLabel(view.context).apply {
        gravity = Gravity.CENTER
        setStyle(14f)
        setTextColor(WColor.SecondaryText)
        setPaddingDp(16, 8, 16, 8)
        setOnClickListener {
            handlePush(WalletVersionsVC(context), presentAsModal = false)
        }
    }

    private val scrollingContentView: WView by lazy {
        WView(context).apply {
            if (showCreateButton) {
                addView(createNewWalletView, FrameLayout.LayoutParams(0, WRAP_CONTENT))
            } else {
                // Temporarily removed for now
                // addView(importTitleLabel, FrameLayout.LayoutParams(0, WRAP_CONTENT))
            }
            addView(secretWordsRow, FrameLayout.LayoutParams(0, WRAP_CONTENT))
            addView(ledgerRow, FrameLayout.LayoutParams(0, WRAP_CONTENT))
            addView(viewRow, FrameLayout.LayoutParams(0, WRAP_CONTENT))
            if (otherVersionsAvailable)
                addView(
                    switchToOtherWalletVersionsButton,
                    FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
                )

            setConstraints {
                if (showCreateButton) {
                    toTop(createNewWalletView, 78f)
                    toCenterX(createNewWalletView)
                    topToBottom(secretWordsRow, createNewWalletView, 1f)
                } else {
                    // toTop(importTitleLabel, 84f)
                    // toCenterX(importTitleLabel, 32f)
                    // topToBottom(secretWordsRow, importTitleLabel, 32f)
                    toTop(secretWordsRow, 78f)
                }
                toCenterX(secretWordsRow, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                topToBottom(ledgerRow, secretWordsRow)
                toCenterX(ledgerRow, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                topToBottom(viewRow, ledgerRow, 16f)
                toCenterX(viewRow, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                if (otherVersionsAvailable) {
                    topToBottom(switchToOtherWalletVersionsButton, viewRow, 16f)
                    toCenterX(switchToOtherWalletVersionsButton)
                    toBottomPx(
                        switchToOtherWalletVersionsButton,
                        24.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
                    )
                } else {
                    toBottomPx(
                        viewRow,
                        32.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
                    )
                }
            }
        }
    }

    private val scrollView: NestedScrollView by lazy {
        NestedScrollView(context).apply {
            id = View.generateViewId()
            addView(scrollingContentView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString(if (showCreateButton) "Add Wallet" else "Import Wallet") + network.localizedIdentifier)
        setupNavBar(true)

        navigationBar?.addCloseButton()

        view.addView(
            scrollView,
            ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        view.setConstraints {
            allEdges(scrollView)
        }
        view.post {
            calculatedHeight = view.measuredHeight
        }

        updateTheme()
    }

    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )
        switchToOtherWalletVersionsButton.addRippleEffect(
            WColor.BackgroundRipple.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        updateSwitchWalletVersionText()
    }

    private fun updateSwitchWalletVersionText() {
        val action = LocaleController.getString("\$wallet_switch_version_2")
        val fullText = LocaleController.getStringWithKeyValues(
            "\$wallet_switch_version_1",
            listOf(
                Pair(
                    "%action%",
                    action
                )
            )
        )
        switchToOtherWalletVersionsButton.text =
            fullText.coloredSubstring(action, WColor.Tint.color)
    }

    private var calculatedHeight: Int? = null
    override val isExpandable = false
    override fun getModalHalfExpandedHeight(): Int? {
        return calculatedHeight ?: super.getModalHalfExpandedHeight()
    }

    private fun mnemonicGenerated(words: Array<String>) {
        view.unlockView()
        val isFirstPasscodeProtectedWallet = !WGlobalStorage.isPasscodeSet()
        if (isFirstPasscodeProtectedWallet) {
            handlePush(
                WordDisplayVC(
                    context,
                    network = network,
                    words = words,
                    isFirstWalletToAdd = false,
                    isFirstPasscodeProtectedWallet = true,
                    passedPasscode = null
                )
            )
        } else {
            lateinit var passcodeConfirmVC: PasscodeConfirmVC
            passcodeConfirmVC = PasscodeConfirmVC(
                context,
                PasscodeViewState.Default(
                    LocaleController.getString("Enter Passcode"),
                    "",
                    LocaleController.getString("Create New Wallet"),
                    showNavigationSeparator = false,
                    startWithBiometrics = true
                ),
                task = { passcode ->
                    val vc = WordDisplayVC(
                        context,
                        network = network,
                        words = words,
                        isFirstWalletToAdd = false,
                        isFirstPasscodeProtectedWallet = false,
                        passcode
                    )
                    passcodeConfirmVC.push(
                        vc,
                        onCompletion = {
                            vc.navigationController?.removePrevViewControllers()
                        })
                }
            )
            handlePush(passcodeConfirmVC)
        }
    }

    private fun handlePush(
        viewController: WViewController,
        presentAsModal: Boolean = !isOnIntro,
        onCompletion: (() -> Unit)? = null
    ) {
        window?.dismissLastNav {
            if (presentAsModal) {
                val nav = WNavigationController(window!!)
                nav.setRoot(viewController)
                window?.present(nav, onCompletion = onCompletion)
            } else {
                window?.navigationControllers?.lastOrNull()
                    ?.push(viewController, onCompletion = onCompletion)
            }
        }
    }
}
