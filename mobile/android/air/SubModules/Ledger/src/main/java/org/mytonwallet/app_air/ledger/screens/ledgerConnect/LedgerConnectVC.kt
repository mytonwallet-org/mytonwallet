package org.mytonwallet.app_air.ledger.screens.ledgerConnect

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import androidx.core.view.isVisible
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.mytonwallet.app_air.ledger.LedgerManager
import org.mytonwallet.app_air.ledger.connectionManagers.LedgerBleManager
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.views.LedgerConnectStepStatusView
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.views.LedgerConnectStepView
import org.mytonwallet.app_air.ledger.screens.ledgerWallets.LedgerWalletsVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.R
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.submitStake
import org.mytonwallet.app_air.walletcore.api.submitUnstake
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.ApiDappTransfer
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.ApiTonConnectProof
import org.mytonwallet.app_air.walletcore.moshi.ApiTransferToSign
import org.mytonwallet.app_air.walletcore.moshi.LocalActivityParams
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.DApp.ConfirmDappRequestConnect
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.DApp.ConfirmDappRequestConnect.Request
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.DApp.ConfirmDappRequestSendTransaction
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.DApp.SignDappProof
import org.mytonwallet.app_air.walletcore.moshi.inject.ApiDappSessionChain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Domains.SubmitDnsChangeWallet
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Domains.SubmitDnsRenewal
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Nft.SubmitNftTransfer
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Staking.SubmitStakingClaimOrUnlock
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Transfer.SignDappTransfers
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Transfer.SignDappTransfers.Options
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.math.BigInteger
import kotlin.math.max

class LedgerConnectVC(
    context: Context,
    private val mode: Mode,
    private val headerView: View? = null,
) : WViewController(context), WThemedView, WalletCore.EventObserver {
    override val TAG = "LedgerConnect"

    sealed class Mode {
        data class AddAccount(val network: MBlockchainNetwork) : Mode()
        data class ConnectToSubmitTransfer(
            val address: String,
            val signData: SignData,
            val onDone: () -> Unit
        ) : Mode()

        val accountId: String?
            get() {
                return when (this) {
                    is AddAccount -> {
                        null
                    }

                    is ConnectToSubmitTransfer -> {
                        signData.accountId
                    }
                }
            }
    }

    sealed class SignData {
        abstract val accountId: String

        data class SignTransfer(
            override val accountId: String,
            val transferOptions: MApiSubmitTransferOptions,
            val slug: String,
            val localActivityParams: LocalActivityParams? = null,
            val payload: JSONObject? = null
        ) : SignData()

        data class SignDappTransfers(
            override val accountId: String,
            val update: ApiUpdate.ApiUpdateDappSendTransactions
        ) : SignData()

        data class SignDappData(
            override val accountId: String,
            val update: ApiUpdate.ApiUpdateDappSignData
        ) : SignData()

        data class SignLedgerProof(
            override val accountId: String,
            val operationChain: String,
            val promiseId: String,
            val proof: ApiTonConnectProof
        ) : SignData()

        data class SignNftTransfer(
            override val accountId: String,
            val nft: ApiNft,
            val toAddress: String,
            val comment: String?,
            val realFee: BigInteger?,
            val isNftBurn: Boolean
        ) : SignData()

        data class Staking(
            val isStaking: Boolean,
            override val accountId: String,
            val amount: BigInteger,
            val stakingState: StakingState,
            val realFee: BigInteger,
        ) : SignData()

        data class ClaimRewards(
            override val accountId: String,
            val stakingState: StakingState,
            val realFee: BigInteger
        ) : SignData()

        data class RenewNfts(
            override val accountId: String,
            val nfts: List<ApiNft>,
            val realFee: BigInteger
        ) : SignData()

        data class LinkNftToWallet(
            override val accountId: String,
            val nft: ApiNft,
            val address: String,
            val realFee: BigInteger
        ) : SignData()
    }

    override val shouldDisplayTopBar = true
    override val shouldDisplayBottomBar = true

    private val ledgerImage = AppCompatImageView(context).apply {
        id = View.generateViewId()
    }

    private val connectLedgerStep = LedgerConnectStepView(
        context, LocaleController.getString("Connect your Ledger")
    ).apply {
        state = LedgerConnectStepStatusView.State.IN_PROGRESS
    }

    private val openTonAppStep = LedgerConnectStepView(
        context, LocaleController.getString("Unlock it and open the TON App")
    )

    private val signOnDeviceStep: LedgerConnectStepView by lazy {
        LedgerConnectStepView(
            context, LocaleController.getString(
                if (mode is Mode.ConnectToSubmitTransfer && mode.signData is SignData.SignLedgerProof)
                    "\$ledger_verify_address_on_device"
                else
                    "Please confirm transfer on your Ledger"
            )
        )
    }

    private val stepsView = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(connectLedgerStep, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(openTonAppStep, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        if (mode is Mode.ConnectToSubmitTransfer)
            addView(signOnDeviceStep, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        gravity = Gravity.START
    }

    private val tryAgainButton = WButton(context, WButton.Type.PRIMARY).apply {
        visibility = View.INVISIBLE
    }

    private val informationView: WView by lazy {
        WView(context).apply {
            addView(
                ledgerImage,
                ViewGroup.LayoutParams(
                    WRAP_CONTENT,
                    if (headerView == null) 300.dp else 150.dp
                )
            )
            ledgerImage.setPaddingDp(16)
            setPadding(0, 0, 0, 16.dp)
            addView(stepsView, ViewGroup.LayoutParams(0, WRAP_CONTENT))
            addView(connectionTypeView, ViewGroup.LayoutParams(0, 48.dp))
            setConstraints {
                toTop(ledgerImage)
                toCenterX(ledgerImage)
                setVerticalBias(stepsView.id, 0f)
                topToBottom(stepsView, ledgerImage)
                toCenterX(stepsView, 48f)
                toCenterX(connectionTypeView, 40f)
                topToBottom(connectionTypeView, stepsView, 16f)
                toBottom(connectionTypeView)
            }
        }
    }

    val connectionTypeLabel = WLabel(context).apply {
        text = LocaleController.getString("Connection Type")
        setStyle(16f, WFont.SemiBold)
    }

    val connectionTypeValue = WLabel(context).apply {
        setStyle(16f, WFont.SemiBold)
    }

    val connectionTypeView: WView by lazy {
        WView(context).apply {
            addView(connectionTypeLabel)
            addView(connectionTypeValue)
            setConstraints {
                toStart(connectionTypeLabel, 16f)
                toCenterY(connectionTypeLabel)
                toEnd(connectionTypeValue, 16f)
                toCenterY(connectionTypeValue)
            }
        }
    }

    private val contentView: WView by lazy {
        WView(context).apply {
            headerView?.let {
                headerView.id = View.generateViewId()
                addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            }
            addView(informationView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            setConstraints {
                headerView?.let {
                    toTop(headerView)
                    topToBottomPx(informationView, headerView, ViewConstants.GAP.dp)
                } ?: run {
                    toTop(informationView)
                }
            }

            connectionTypeValue.setOnClickListener {
                WMenuPopup.present(
                    connectionTypeView,
                    listOf(
                        WMenuPopup.Item(
                            null,
                            LocaleController.getString("Bluetooth"),
                            false,
                        ) {
                            tryAgain(LedgerManager.ConnectionMode.BLE)
                            updateConnectionTypeView()
                        },
                        WMenuPopup.Item(
                            null,
                            LocaleController.getString("USB"),
                            false,
                        ) {
                            tryAgain(LedgerManager.ConnectionMode.USB)
                            updateConnectionTypeView()
                        }
                    ),
                    xOffset = connectionTypeView.width - 116.dp,
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.ALIGNED,
                )
            }
        }
    }

    private val scrollView by lazy {
        ScrollView(context).apply {
            clipToPadding = false
            addView(
                contentView,
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            id = View.generateViewId()
            setOnScrollChangeListener { _, _, scrollY, _, _ ->
                updateBlurViews(scrollView = this, computedOffset = scrollY)
            }
            overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
            isVerticalScrollBarEnabled = false
        }
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            isGone = true
        }

    override fun setupViews() {
        super.setupViews()

        LedgerManager.init(window!!.applicationContext)

        title = when (mode) {
            is Mode.AddAccount -> {
                LocaleController.getString("Add Wallet")
            }

            is Mode.ConnectToSubmitTransfer -> {
                LocaleController.getString("Confirm")
            }
        }
        setupNavBar(true)
        if (navigationController?.viewControllers?.size == 1) {
            navigationBar?.addCloseButton()
        }

        view.addView(scrollView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        view.addView(tryAgainButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            topToTop(
                bottomReversedCornerViewUpsideDown,
                tryAgainButton,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
            toBottom(bottomReversedCornerViewUpsideDown)
            toCenterX(tryAgainButton, 20f)
            toBottomPx(
                tryAgainButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
        bottomReversedCornerViewUpsideDown.pauseBlurring()

        updateTheme()

        initBluetooth()
        tryAgain(LedgerManager.activeMode)

        WalletCore.registerObserver(this)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        headerView?.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp,
        )
        informationView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
        )
        connectionTypeView.setBackgroundColor(WColor.SecondaryBackground.color, 16f.dp)
        connectionTypeLabel.setTextColor(WColor.PrimaryText.color)
        connectionTypeValue.setTextColor(WColor.SecondaryText.color)
        updateConnectionTypeView()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            ViewConstants.GAP.dp + tryAgainButton.buttonHeight + 20.dp + max(
                (navigationController?.getSystemBars()?.bottom ?: 0),
                (window?.imeInsets?.bottom ?: 0)
            )
        )
    }

    private fun updateConnectionTypeView() {
        ledgerImage.setImageResource(
            if (LedgerManager.activeMode == LedgerManager.ConnectionMode.USB)
                if (ThemeManager.isDark) R.drawable.img_ledger_usb_dark else R.drawable.img_ledger_usb_light
            else
                if (ThemeManager.isDark) R.drawable.img_ledger_bluetooth_dark else R.drawable.img_ledger_bluetooth_light
        )

        val txt =
            LocaleController.getString(
                if (
                    (LedgerManager.activeMode
                        ?: LedgerManager.ConnectionMode.BLE) == LedgerManager.ConnectionMode.BLE
                )
                    "Bluetooth"
                else
                    "USB"
            ) + " "
        val ss = SpannableStringBuilder(txt)
        ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_8
        )?.let { drawable ->
            drawable.mutate()
            drawable.setTint(WColor.SecondaryText.color)
            val width = 8.dp
            val height = 4.dp
            drawable.setBounds(0, 0, width, height)
            val imageSpan = VerticalImageSpan(drawable)
            ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        connectionTypeValue.text = ss
    }

    // Bluetooth adapter (turn on bluetooth if required)
    private lateinit var bluetoothAdapter: BluetoothAdapter
    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    when (intent.getIntExtra(
                        BluetoothAdapter.EXTRA_STATE,
                        BluetoothAdapter.ERROR
                    )) {
                        BluetoothAdapter.STATE_ON -> {
                            startBleConnection()
                        }

                        BluetoothAdapter.STATE_OFF -> {
                            onUpdate(
                                LedgerManager.ConnectionState.Error(
                                    step = LedgerManager.ConnectionState.Error.Step.CONNECT,
                                    shortMessage = null
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private fun initBluetooth() {
        val bluetoothManager =
            window!!.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter

        window!!.registerReceiver(
            bluetoothStateReceiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        )
    }

    private var tryAgainButtonToOpenSettings: Boolean? = null
    private fun configureTryAgainButton(toOpenSettings: Boolean) {
        if (this.tryAgainButtonToOpenSettings == toOpenSettings)
            return
        this.tryAgainButtonToOpenSettings = toOpenSettings
        tryAgainButton.setText(
            text = LocaleController.getString(
                if (toOpenSettings) "Open Settings" else "Try Again"
            ),
            isAnimated = true
        )
        tryAgainButton.setOnClickListener {
            if (toOpenSettings) {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                val uri = Uri.fromParts("package", context.applicationContext.packageName, null)
                intent.data = uri
                window?.startActivity(intent)
            } else {
                tryAgain(LedgerManager.activeMode)
            }
        }
    }

    private fun tryAgain(connectionMode: LedgerManager.ConnectionMode?) {
        // TODO:: We can later check if any ledger devices are connected using USB and use USB as default in that case
        val defaultMode = LedgerManager.ConnectionMode.BLE
        LedgerManager.activeMode = connectionMode ?: defaultMode
        when (LedgerManager.activeMode!!) {
            LedgerManager.ConnectionMode.BLE -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (!LedgerBleManager.isPermissionGranted()) {
                        window?.requestPermissions(
                            arrayOf(
                                Manifest.permission.BLUETOOTH_SCAN,
                                Manifest.permission.BLUETOOTH_CONNECT
                            )
                        ) { _, grantResults ->
                            if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) checkAndEnableBluetooth()
                            else {
                                onUpdate(
                                    LedgerManager.ConnectionState.Error(
                                        step = LedgerManager.ConnectionState.Error.Step.CONNECT,
                                        shortMessage = LocaleController.getString("Permission Denied")
                                    )
                                )
                                if (!ActivityCompat.shouldShowRequestPermissionRationale(
                                        window!!,
                                        Manifest.permission.BLUETOOTH_SCAN
                                    )
                                ) {
                                    configureTryAgainButton(toOpenSettings = true)
                                }
                            }
                        }
                    } else checkAndEnableBluetooth()
                } else checkAndEnableBluetooth()
            }

            LedgerManager.ConnectionMode.USB -> {
                startUsbConnection()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun checkAndEnableBluetooth() {
        if (!bluetoothAdapter.isEnabled) {
            val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
            enableBtIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            window!!.startActivity(enableBtIntent)
        } else {
            startBleConnection()
        }
    }

    private fun startBleConnection() {
        LedgerManager.startConnection(LedgerManager.ConnectionMode.BLE, onUpdate = {
            onUpdate(it)
        })
    }

    private fun startUsbConnection() {
        LedgerManager.startConnection(LedgerManager.ConnectionMode.USB, onUpdate = {
            onUpdate(it)
        })
    }

    private fun finalizeValidation() {
        val mode = mode as Mode.ConnectToSubmitTransfer
        CoroutineScope(Dispatchers.IO).launch {
            when (val signData = mode.signData) {
                is SignData.SignTransfer -> {
                    try {
                        val id = WalletCore.call(
                            ApiMethod.Transfer.SubmitTransfer(
                                MBlockchain.ton,
                                options = signData.transferOptions
                            )
                        ).activityId
                        signedActivityId = ActivityHelpers.getTxIdFromId(id)
                        Handler(Looper.getMainLooper()).post {
                            mode.onDone()
                            receivedLocalActivities?.firstOrNull { it.getTxHash() == signedActivityId }
                                ?.let {
                                    checkReceivedActivity(it)
                                }
                        }
                    } catch (e: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            signFailed(e as? JSWebViewBridge.ApiError)
                        }
                    }
                }

                is SignData.SignDappTransfers -> {
                    try {
                        val account = AccountStore.accountById(signData.update.accountId) ?: return@launch
                        val dappChain = account.dappChain(signData.update.operationChain) ?: return@launch
                        val signedMessages = WalletCore.call(
                            SignDappTransfers(
                                dappChain = dappChain,
                                accountId = signData.update.accountId,
                                transactions = signData.update.transactions,
                                options = Options(
                                    password = null,
                                    validUntil = signData.update.validUntil,
                                    vestingAddress = signData.update.vestingAddress,
                                    isLegacyOutput = signData.update.isLegacyOutput
                                )
                            )
                        )
                        WalletCore.call(
                            ConfirmDappRequestSendTransaction(
                                signData.update.promiseId,
                                signedMessages
                            )
                        )
                        Handler(Looper.getMainLooper()).post {
                            mode.onDone()
                        }
                    } catch (e: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            signFailed(e as? JSWebViewBridge.ApiError)
                        }
                    }
                }

                is SignData.SignLedgerProof -> {
                    try {
                        Handler(Looper.getMainLooper()).post {
                            view.unlockView()
                        }
                        val account = AccountStore.accountById(signData.accountId) ?: return@launch
                        val dappChain = account.dappChain(signData.operationChain) ?: return@launch
                        val dappChains = listOf(dappChain)
                        val signResult = WalletCore.call(
                            SignDappProof(
                                dappChains,
                                account.accountId,
                                signData.proof,
                                ""
                            )
                        )
                        WalletCore.call(
                            ConfirmDappRequestConnect(
                                signData.promiseId,
                                Request(
                                    accountId = account.accountId,
                                    proofSignatures = signResult.signatures
                                )
                            )
                        )
                        Handler(Looper.getMainLooper()).post {
                            mode.onDone()
                        }
                    } catch (e: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            signFailed(e as? JSWebViewBridge.ApiError)
                        }
                    }
                }

                is SignData.SignNftTransfer -> {
                    try {
                        val result = WalletCore.call(
                            SubmitNftTransfer(
                                chain = signData.nft.chain ?: MBlockchain.ton,
                                accountId = signData.accountId,
                                passcode = "",
                                nft = signData.nft,
                                address = signData.toAddress,
                                comment = signData.comment,
                                fee = signData.realFee ?: BigInteger.ZERO,
                                isNftBurn = signData.isNftBurn
                            )
                        )
                        signedActivityId =
                            MBlockchain.ton.idToTxHash(result.activityIds.lastOrNull())
                        Handler(Looper.getMainLooper()).post {
                            mode.onDone()
                            receivedLocalActivities?.firstOrNull { it.getTxHash() == signedActivityId }
                                ?.let {
                                    checkReceivedActivity(it)
                                }
                        }
                    } catch (e: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            signFailed(e as? JSWebViewBridge.ApiError)
                        }
                    }
                }

                is SignData.Staking -> {
                    try {
                        val result = if (signData.isStaking)
                            WalletCore.submitStake(
                                accountId = signData.accountId,
                                passcode = "",
                                amount = signData.amount,
                                stakingState = signData.stakingState,
                                realFee = signData.realFee,
                            )
                        else
                            WalletCore.submitUnstake(
                                accountId = signData.accountId,
                                passcode = "",
                                amount = signData.amount,
                                stakingState = signData.stakingState,
                                realFee = signData.realFee,
                            )
                        signedActivityId = ActivityHelpers.getTxIdFromId(result.activityId)
                        Handler(Looper.getMainLooper()).post {
                            mode.onDone()
                            receivedLocalActivities?.firstOrNull { it.getTxHash() == signedActivityId }
                                ?.let {
                                    checkReceivedActivity(it)
                                }
                        }
                    } catch (e: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            signFailed(e as? JSWebViewBridge.ApiError)
                        }
                    }
                }

                is SignData.ClaimRewards -> {
                    try {
                        WalletCore.call(
                            SubmitStakingClaimOrUnlock(
                                accountId = signData.accountId,
                                password = "",
                                state = signData.stakingState,
                                realFee = signData.realFee
                            )
                        )
                        Handler(Looper.getMainLooper()).post {
                            mode.onDone()
                        }
                    } catch (e: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            signFailed(e as? JSWebViewBridge.ApiError)
                        }
                    }
                }

                is SignData.RenewNfts -> {
                    try {
                        WalletCore.call(
                            SubmitDnsRenewal(
                                accountId = signData.accountId,
                                password = "",
                                nfts = signData.nfts,
                                realFee = signData.realFee
                            )
                        )
                        Handler(Looper.getMainLooper()).post {
                            mode.onDone()
                        }
                    } catch (e: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            signFailed(e as? JSWebViewBridge.ApiError)
                        }
                    }
                }

                is SignData.LinkNftToWallet -> {
                    try {
                        WalletCore.call(
                            SubmitDnsChangeWallet(
                                accountId = signData.accountId,
                                password = "",
                                nft = signData.nft,
                                address = signData.address,
                                realFee = signData.realFee
                            )
                        )
                        Handler(Looper.getMainLooper()).post {
                            mode.onDone()
                        }
                    } catch (e: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            signFailed(e as? JSWebViewBridge.ApiError)
                        }
                    }
                }

                is SignData.SignDappData -> {
                    try {
                        val account = AccountStore.accountById(signData.update.accountId) ?: return@launch
                        val dappChain = account.dappChain(signData.update.operationChain) ?: return@launch
                        val signedData = WalletCore.call(
                            ApiMethod.Transfer.SignDappData(
                                dappChain = dappChain,
                                accountId = signData.update.accountId,
                                dappUrl = signData.update.dapp.url!!,
                                payloadToSign = signData.update.payloadToSign,
                                password = ""
                            )
                        )
                        WalletCore.call(
                            ApiMethod.DApp.ConfirmDappRequestSignData(
                                signData.update.promiseId,
                                signedData
                            )
                        )
                        Handler(Looper.getMainLooper()).post {
                            mode.onDone()
                        }
                    } catch (e: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            signFailed(e as? JSWebViewBridge.ApiError)
                        }
                    }
                }
            }
        }
    }

    private fun onUpdate(state: LedgerManager.ConnectionState) {
        tryAgainButton.visibility =
            if (state is LedgerManager.ConnectionState.Error) View.VISIBLE else View.INVISIBLE
        connectionTypeView.visibility =
            if (
                state is LedgerManager.ConnectionState.Connecting ||
                state is LedgerManager.ConnectionState.Error
            ) View.VISIBLE else View.GONE
        bottomReversedCornerViewUpsideDown.visibility = tryAgainButton.visibility
        bottomReversedCornerView?.isGone = bottomReversedCornerViewUpsideDown.isVisible
        if (bottomReversedCornerViewUpsideDown.isVisible)
            bottomReversedCornerViewUpsideDown.resumeBlurring()
        else
            bottomReversedCornerViewUpsideDown.pauseBlurring()
        when (state) {
            LedgerManager.ConnectionState.Connecting -> {
                connectLedgerStep.state =
                    LedgerConnectStepStatusView.State.IN_PROGRESS
                openTonAppStep.state = LedgerConnectStepStatusView.State.WAITING
                signOnDeviceStep.state = LedgerConnectStepStatusView.State.WAITING
            }

            is LedgerManager.ConnectionState.ConnectingToTonApp -> {
                connectLedgerStep.state = LedgerConnectStepStatusView.State.DONE
                openTonAppStep.state = LedgerConnectStepStatusView.State.IN_PROGRESS
                signOnDeviceStep.state = LedgerConnectStepStatusView.State.WAITING
            }

            is LedgerManager.ConnectionState.Done -> {
                connectLedgerStep.state = LedgerConnectStepStatusView.State.DONE

                when (mode) {
                    is Mode.AddAccount -> {
                        openTonAppStep.state =
                            LedgerConnectStepStatusView.State.IN_PROGRESS
                        WalletCore.call(
                            ApiMethod.Auth.GetLedgerWallets(
                                MBlockchain.ton,
                                mode.network,
                                0,
                                5
                            )
                        ) { res, err ->
                            res?.let {
                                shouldDestroyLedgerManager = false
                                push(
                                    LedgerWalletsVC(context, mode.network, res.toList()),
                                    onCompletion = {
                                        navigationController?.removePrevViewControllers()
                                    })
                            } ?: run {
                                finalizeFailed()
                            }
                        }
                    }

                    is Mode.ConnectToSubmitTransfer -> {
                        openTonAppStep.state = LedgerConnectStepStatusView.State.DONE
                        signOnDeviceStep.state =
                            LedgerConnectStepStatusView.State.IN_PROGRESS
                        finalizeValidation()
                    }
                }
            }

            is LedgerManager.ConnectionState.Error -> {
                when (state.step) {
                    LedgerManager.ConnectionState.Error.Step.CONNECT -> {
                        connectLedgerStep.state = LedgerConnectStepStatusView.State.ERROR
                        connectLedgerStep.setError(state.shortMessage)
                        openTonAppStep.state = LedgerConnectStepStatusView.State.WAITING
                        signOnDeviceStep.state = LedgerConnectStepStatusView.State.WAITING
                    }

                    LedgerManager.ConnectionState.Error.Step.TON_APP -> {
                        connectLedgerStep.state = LedgerConnectStepStatusView.State.DONE
                        openTonAppStep.state = LedgerConnectStepStatusView.State.ERROR
                        openTonAppStep.setError(state.shortMessage)
                        signOnDeviceStep.state = LedgerConnectStepStatusView.State.WAITING
                    }

                    LedgerManager.ConnectionState.Error.Step.SIGN -> {
                        connectLedgerStep.state = LedgerConnectStepStatusView.State.DONE
                        openTonAppStep.state = LedgerConnectStepStatusView.State.DONE
                        signOnDeviceStep.state = LedgerConnectStepStatusView.State.ERROR
                        signOnDeviceStep.setError(state.shortMessage)
                    }
                }
                if (state.shortMessage == null)
                    state.bridgeError?.let {
                        if (state.bridgeError == MBridgeError.HARDWARE_BLIND_SIGNING_NOT_ENABLED) {
                            showAlert(
                                LocaleController.getString("Error"),
                                it.toLocalized.replace("%chain%", MBlockchain.ton.displayName)
                            )
                            return@let
                        }
                        showError(it)
                    }
            }

            LedgerManager.ConnectionState.None -> {
                connectLedgerStep.state = LedgerConnectStepStatusView.State.WAITING
                openTonAppStep.state = LedgerConnectStepStatusView.State.WAITING
                signOnDeviceStep.state = LedgerConnectStepStatusView.State.WAITING
            }
        }
    }

    private fun finalizeFailed() {
        Handler(Looper.getMainLooper()).post {
            view.unlockView()
            onUpdate(
                LedgerManager.ConnectionState.Error(
                    step = LedgerManager.ConnectionState.Error.Step.TON_APP,
                    shortMessage = null
                )
            )
        }
    }

    private fun signFailed(error: JSWebViewBridge.ApiError?) {
        view.unlockView()
        onUpdate(
            LedgerManager.ConnectionState.Error(
                step = LedgerManager.ConnectionState.Error.Step.SIGN,
                shortMessage = error?.parsed?.toShortLocalized,
                bridgeError = error?.parsed
            )
        )
    }

    var shouldDestroyLedgerManager = true
    override fun onDestroy() {
        super.onDestroy()
        window!!.unregisterReceiver(
            bluetoothStateReceiver,
        )
        if (shouldDestroyLedgerManager)
            LedgerManager.stopConnection()
        WalletCore.unregisterObserver(this)
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            configureTryAgainButton(
                toOpenSettings = LedgerManager.activeMode == LedgerManager.ConnectionMode.BLE &&
                    !LedgerBleManager.isPermissionGranted() &&
                    !ActivityCompat.shouldShowRequestPermissionRationale(
                        window!!,
                        Manifest.permission.BLUETOOTH_SCAN
                    )
            )
        } else {
            configureTryAgainButton(false)
        }
    }

    private var signedActivityId: String? = null
    private var receivedLocalActivities: ArrayList<MApiTransaction>? = null
    private fun checkReceivedActivity(receivedActivity: MApiTransaction) {
        if (signedActivityId == null) {
            // Transfer in-progress, cached received local activity to process on transfer api callback is called
            if (receivedActivity.isLocal()) {
                if (receivedLocalActivities == null)
                    receivedLocalActivities = ArrayList()
                receivedLocalActivities?.add(receivedActivity)
            }
            return
        }

        val txMatch =
            receivedActivity is MApiTransaction.Transaction && signedActivityId == receivedActivity.getTxHash()
        if (!txMatch) {
            return
        }

        signedActivityId = null
        WalletCore.unregisterObserver(this)
        if (window?.topNavigationController != navigationController) {
            window?.dismissNav(navigationController)
            return
        }
        if ((window?.navigationControllers?.size ?: 0) > 1) {
            window?.dismissLastNav {
                if ((mode as? Mode.ConnectToSubmitTransfer)?.signData is SignData.Staking)
                    return@dismissLastNav
                WalletCore.notifyEvent(WalletEvent.OpenActivity(mode.accountId!!, receivedActivity))
            }
        } else {
            navigationController?.popToRoot {
                if ((mode as? Mode.ConnectToSubmitTransfer)?.signData is SignData.Staking)
                    return@popToRoot
                WalletCore.notifyEvent(WalletEvent.OpenActivity(mode.accountId!!, receivedActivity))
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.NewLocalActivities -> {
                walletEvent.localActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            is WalletEvent.ReceivedPendingActivities -> {
                walletEvent.pendingActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            else -> {}
        }
    }
}
