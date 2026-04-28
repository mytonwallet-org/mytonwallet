package org.mytonwallet.app_air.uisettings.viewControllers.subwallets

import android.content.Context
import android.graphics.Rect
import android.text.SpannableString
import android.text.Spanned
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.helpers.PositionBasedItemDecoration
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uisettings.viewControllers.subwallets.cells.EmptySubwalletsCell
import org.mytonwallet.app_air.uisettings.viewControllers.subwallets.cells.SubwalletCell
import org.mytonwallet.app_air.uisettings.viewControllers.subwallets.cells.SubwalletDescriptionCell
import org.mytonwallet.app_air.uisettings.viewControllers.subwallets.cells.SubwalletRowData
import org.mytonwallet.app_air.uisettings.viewControllers.subwallets.cells.SubwalletsHeaderCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.MarginImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MAccount.AccountChain
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiGroupedWalletVariant
import org.mytonwallet.app_air.walletcore.moshi.ApiSubWallet
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.roundToInt

class SubWalletsVC(
    context: Context,
    private val password: String,
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource {

    override val TAG = "Subwallets"
    override val isSwipeBackAllowed = false
    override val isEdgeSwipeBackAllowed = true

    companion object {
        private const val SECTION_TOP = 0

        private const val ROW_TOP_DESCRIPTION = 0
        private const val ROW_HEADER = 1
        private const val ROW_CURRENT_WALLET = 2
        private const val ROW_BOTTOM_DESCRIPTION = 3
        private const val ROW_HEADER_SUBWALLETS = 4

        val CURRENT_HEADER_CELL = WCell.Type(1)
        val CURRENT_WALLET_CELL = WCell.Type(2)
        val SUBWALLETS_HEADER_CELL = WCell.Type(3)
        val SUBWALLET_CELL = WCell.Type(4)
        val LABEL_CELL = WCell.Type(5)
        val EMPTY_SUBWALLETS_CELL = WCell.Type(6)

        private const val MAX_EMPTY_RESULTS_IN_ROW = 5
        private const val SEARCH_PAUSE_MS = 5000L
        private val HIDDEN_DERIVATION_LABELS = setOf("default", "phantom")
    }

    private val accountId = AccountStore.activeAccountId ?: ""
    private val account: MAccount?
        get() = AccountStore.activeAccount
    private val network = AccountStore.activeAccount?.network

    private val displayChains: List<MBlockchain> =
        AccountStore.activeAccount?.sortedChains()?.mapNotNull { entry ->
            MBlockchain.supportedChains.firstOrNull { it.name == entry.key }
        } ?: emptyList()

    private val variantChains: List<MBlockchain> =
        displayChains.filter { AccountStore.chainSupportsSubWallets(it) }

    private val valueChains: List<MBlockchain> = displayChains

    private var mnemonic: Array<String> = emptyArray()
    private var groups = mutableListOf<ApiGroupedWalletVariant>()
    private var isLoading = false
    private var fetchJob: Job? = null
    private val seenIndices = mutableSetOf<Int>()
    private var alreadyShownCells = 0
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                CURRENT_HEADER_CELL,
                CURRENT_WALLET_CELL,
                SUBWALLETS_HEADER_CELL,
                SUBWALLET_CELL,
                LABEL_CELL,
                EMPTY_SUBWALLETS_CELL
            )
        )

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManagerAccurateOffset(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv.setItemAnimator(null)
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                updateBlurViews(recyclerView)
            }

            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (newState != RecyclerView.SCROLL_STATE_IDLE) {
                    updateBlurViews(recyclerView)
                }
            }
        })
        rv
    }

    private val createButtonSpannable: SpannableString by lazy {
        val text = LocaleController.getString("Create Subwallet")
        val drawable = context.getDrawableCompat(
            org.mytonwallet.app_air.uisettings.R.drawable.ic_plus
        )?.apply {
            setTint(WColor.TextOnTint.color)
            val size = 20.dp
            setBounds(0, 0, size, size)
        }
        val spannable = SpannableString(" $text")
        drawable?.let {
            val imageSpan = MarginImageSpan(it, -0.5f.dp.roundToInt(), 4.5f.dp.roundToInt())
            spannable.setSpan(imageSpan, 0, 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        spannable
    }

    private val bottomReversedCornerViewUpsideDown by lazy {
        ReversedCornerViewUpsideDown(context, null)
    }

    private val createSubwalletButton by lazy {
        WButton(context).apply {
            setOnClickListener { createSubwallet() }
        }
    }

    private val navigationTitle: String
        get() {
            val single = variantChains.singleOrNull()
                ?: return LocaleController.getString("Subwallets")
            val key = "\$chain_Subwallets"
            val localized = LocaleController.getString(key)
            return if (localized == key) {
                "${single.displayName} ${LocaleController.getString("Subwallets")}"
            } else {
                String.format(localized, single.displayName)
            }
        }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(navigationTitle)
        setupNavBar(true)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_CONSTRAINT)
        )
        view.addView(
            createSubwalletButton,
            ViewGroup.LayoutParams(MATCH_CONSTRAINT, 50.dp)
        )

        recyclerView.setPadding(
            0,
            (navigationController?.getSystemBars()?.top ?: 0) + WNavigationBar.DEFAULT_HEIGHT.dp,
            0,
            (navigationController?.getSystemBars()?.bottom ?: 0) + 82.dp
        )
        recyclerView.clipToPadding = false
        recyclerView.addItemDecoration(
            PositionBasedItemDecoration { _ ->
                Rect(
                    ViewConstants.HORIZONTAL_PADDINGS.dp,
                    0,
                    ViewConstants.HORIZONTAL_PADDINGS.dp,
                    0
                )
            }
        )

        view.setConstraints {
            toTop(recyclerView)
            toCenterX(recyclerView)
            toBottom(recyclerView)

            toCenterX(createSubwalletButton, 20f)
            toBottomPx(
                createSubwalletButton,
                16.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
            topToTop(
                bottomReversedCornerViewUpsideDown,
                createSubwalletButton,
                -(ViewConstants.GAP + ViewConstants.BLOCK_RADIUS)
            )
            toBottom(bottomReversedCornerViewUpsideDown)
        }
        navigationBar?.bringToFront()
        createSubwalletButton.post { createSubwalletButton.setText(createButtonSpannable, false) }

        updateTheme()
        loadMnemonicAndStartSearch()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        bottomReversedCornerViewUpsideDown.updateTheme()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun loadMnemonicAndStartSearch() {
        WalletCore.call(
            ApiMethod.Settings.FetchMnemonic(accountId, password)
        ) { result, error ->
            if (error != null || result == null) {
                showError(error?.parsed)
                return@call
            }
            mnemonic = result
            startFetchingVariants()
        }
    }

    private fun startFetchingVariants() {
        isLoading = true
        seenIndices.clear()
        rvAdapter.reloadData()
        fetchJob?.cancel()
        fetchJob = scope.launch {
            fetchVariantsLoop()
        }
    }

    private suspend fun fetchVariantsLoop() {
        var page = 0
        var emptyResultsInRow = 0

        while (true) {
            val result: Array<ApiGroupedWalletVariant>
            try {
                result = withContext(Dispatchers.Main) {
                    kotlinx.coroutines.suspendCancellableCoroutine { cont ->
                        WalletCore.call(
                            ApiMethod.Settings.GetWalletVariants(
                                accountId, page, mnemonic
                            )
                        ) { variants, error ->
                            if (!cont.isActive) return@call
                            if (error != null) {
                                cont.resumeWith(Result.failure(Exception(error.parsed.toLocalized)))
                            } else {
                                cont.resumeWith(Result.success(variants ?: emptyArray()))
                            }
                        }
                    }
                }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) {
                    isLoading = false
                    rvAdapter.reloadData()
                }
                return
            }

            val hasPositiveBalance = result.any { group ->
                group.byChain.values.any { it.balance > BigInteger.ZERO }
            }

            withContext(Dispatchers.Main) {
                val existing = groups.map { it.index }.toSet()
                val newItems = result.filter { !existing.contains(it.index) }
                if (newItems.isNotEmpty()) {
                    alreadyShownCells = groups.size
                    groups.addAll(newItems)
                }
                rvAdapter.reloadData()
            }

            emptyResultsInRow = if (hasPositiveBalance) 0 else emptyResultsInRow + 1
            page++

            if (emptyResultsInRow >= MAX_EMPTY_RESULTS_IN_ROW) break

            delay(SEARCH_PAUSE_MS)
        }

        withContext(Dispatchers.Main) {
            isLoading = false
            rvAdapter.reloadData()
        }
    }

    private val showEmptyLabel: Boolean
        get() = !isLoading && groups.isEmpty()

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int =
        if (groups.isNotEmpty() || showEmptyLabel) 2 else 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            SECTION_TOP -> 5
            else -> if (groups.isNotEmpty()) groups.size else 1
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        if (indexPath.section == SECTION_TOP) return when (indexPath.row) {
            ROW_TOP_DESCRIPTION -> LABEL_CELL
            ROW_HEADER -> CURRENT_HEADER_CELL
            ROW_CURRENT_WALLET -> CURRENT_WALLET_CELL
            ROW_BOTTOM_DESCRIPTION -> LABEL_CELL
            else -> SUBWALLETS_HEADER_CELL
        }
        return if (groups.isNotEmpty()) SUBWALLET_CELL else EMPTY_SUBWALLETS_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            CURRENT_HEADER_CELL -> HeaderCell(context)
            LABEL_CELL -> SubwalletDescriptionCell(context)
            CURRENT_WALLET_CELL -> SubwalletCell(context)
            SUBWALLETS_HEADER_CELL -> SubwalletsHeaderCell(context)
            SUBWALLET_CELL -> SubwalletCell(context).apply {
                onTap = { id -> handleSubwalletTap(id) }
            }

            EMPTY_SUBWALLETS_CELL -> EmptySubwalletsCell(context)
            else -> HeaderCell(context)
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        if (indexPath.section == SECTION_TOP) {
            when (indexPath.row) {
                ROW_TOP_DESCRIPTION -> (cellHolder.cell as SubwalletDescriptionCell).configure(
                    LocaleController.getString("\$subwallets_hint")
                )

                ROW_HEADER -> (cellHolder.cell as HeaderCell).configure(
                    LocaleController.getString("Current Wallet"),
                    WColor.Tint,
                    topRounding = HeaderCell.TopRounding.FIRST_ITEM
                )

                ROW_CURRENT_WALLET -> {
                    val cell = cellHolder.cell as SubwalletCell
                    cell.configure(currentWalletRowData(), true)
                }

                ROW_BOTTOM_DESCRIPTION -> (cellHolder.cell as SubwalletDescriptionCell).configure(
                    LocaleController.getString("\$subwallets_created_wallets")
                )

                ROW_HEADER_SUBWALLETS -> (cellHolder.cell as SubwalletsHeaderCell).configure(
                    isLoading,
                    groups.size
                )
            }
        } else {
            if (indexPath.row < groups.size) {
                val group = groups[indexPath.row]
                val isNew = seenIndices.add(group.index)
                (cellHolder.cell as SubwalletCell).configure(
                    rowData(group),
                    indexPath.row == groups.size - 1,
                    isAdded = isNew,
                    animationDelay = 40L * (indexPath.row - alreadyShownCells)
                )
            }
        }
    }

    private fun handleSubwalletTap(id: String) {
        val group = groups.firstOrNull { it.index.toString() == id } ?: return

        for (existingAccountId in WGlobalStorage.accountIds()) {
            val accountObj = WGlobalStorage.getAccount(existingAccountId) ?: continue
            val existingAccount = MAccount(existingAccountId, accountObj)
            val matches = group.byChain.isNotEmpty() && group.byChain.all { (chainName, entry) ->
                existingAccount.byChain[chainName]?.address == entry.wallet.address
            }
            if (matches) {
                WalletCore.activateAccount(existingAccountId, notifySDK = true) { res, err ->
                    if (res != null && err == null) {
                        navigationController?.popToRoot()
                        WalletCore.notifyEvent(
                            WalletEvent.AccountChangedInApp(
                                persistedAccountsModified = false
                            )
                        )
                    }
                }
                return
            }
        }

        addSubWallet(group)
    }

    private fun addSubWallet(group: ApiGroupedWalletVariant) {
        view.lockView()
        val byChainPayload: Map<String, ApiSubWallet> =
            group.byChain.mapValues { it.value.wallet }
        WalletCore.call(
            ApiMethod.Settings.AddSubWallet(accountId, byChainPayload)
        ) { result, error ->
            if (error != null || result == null) {
                view.unlockView()
                showError(error?.parsed)
                return@call
            }

            val newAccountId = result.accountId
            val byChain = result.byChain
            val activeAccount = account ?: run {
                view.unlockView()
                return@call
            }

            if (newAccountId != null && byChain != null) {
                Logger.d(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(newAccountId, LogMessage.MessagePartPrivacy.PUBLIC)
                        .append("Subwallet Added", LogMessage.MessagePartPrivacy.PUBLIC)
                        .append(
                            "Address: ${result.address}",
                            LogMessage.MessagePartPrivacy.REDACTED
                        ).build()
                )

                val derivationIndex = group.byChain.values.firstOrNull()?.wallet?.derivation?.index
                WGlobalStorage.addAccount(
                    accountId = newAccountId,
                    accountType = activeAccount.accountType.value,
                    MAccount.byChainToJson(byChain),
                    name = subwalletTitle(activeAccount.name, derivationIndex),
                    importedAt = System.currentTimeMillis()
                )
                AirPushNotifications.subscribe(newAccountId, ignoreIfLimitReached = true)
                WalletCore.activateAccount(
                    accountId = newAccountId,
                    notifySDK = false
                ) { _, activateErr ->
                    view.unlockView()
                    if (activateErr != null) {
                        Logger.e(
                            Logger.LogTag.ACCOUNT,
                            LogMessage.Builder()
                                .append(
                                    "Activation failed in subwallets: $activateErr",
                                    LogMessage.MessagePartPrivacy.PUBLIC
                                ).build()
                        )
                        return@activateAccount
                    }
                    navigationController?.popToRoot()
                    WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
                }
            } else {
                view.unlockView()
            }
        }
    }

    fun createSubwallet() {
        view.lockView()
        WalletCore.call(
            ApiMethod.Settings.CreateSubWallet(accountId, password)
        ) { result, error ->
            if (error != null || result == null) {
                view.unlockView()
                showError(error?.parsed)
                return@call
            }

            val activeAccount = account ?: run {
                view.unlockView()
                return@call
            }

            if (result.isNew) {
                val byChain = result.byChain ?: run {
                    view.unlockView()
                    return@call
                }
                Logger.d(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(result.accountId, LogMessage.MessagePartPrivacy.PUBLIC)
                        .append("Subwallet Created", LogMessage.MessagePartPrivacy.PUBLIC)
                        .append(
                            "Address: ${result.address}",
                            LogMessage.MessagePartPrivacy.REDACTED
                        )
                        .build()
                )
                val derivationIndex = byChain.values.firstOrNull()?.derivation?.index
                WGlobalStorage.addAccount(
                    accountId = result.accountId,
                    accountType = activeAccount.accountType.value,
                    MAccount.byChainToJson(byChain),
                    name = subwalletTitle(activeAccount.name, derivationIndex),
                    importedAt = System.currentTimeMillis()
                )
                AirPushNotifications.subscribe(result.accountId, ignoreIfLimitReached = true)
            }

            WalletCore.activateAccount(
                accountId = result.accountId,
                notifySDK = false
            ) { _, activateErr ->
                view.unlockView()
                if (activateErr != null) {
                    Logger.e(
                        Logger.LogTag.ACCOUNT,
                        LogMessage.Builder()
                            .append(
                                "Activation failed in createSubwallet: $activateErr",
                                LogMessage.MessagePartPrivacy.PUBLIC
                            ).build()
                    )
                    return@activateAccount
                }
                navigationController?.popToRoot()
                WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
            }
        }
    }

    private fun currentWalletRowData(): SubwalletRowData {
        val activeByChain = account?.byChain ?: emptyMap()
        val displayedByChain = valueChains.mapNotNull { chain ->
            val entry = activeByChain[chain.name] ?: return@mapNotNull null
            chain.name to AccountChain(address = entry.address, domain = entry.domain)
        }.toMap()

        return SubwalletRowData(
            identifier = "current",
            title = ".${currentSubwalletIndex() + 1}",
            badge = currentDerivationBadge(),
            network = network ?: MBlockchainNetwork.MAINNET,
            accountId = accountId,
            byChain = displayedByChain,
            nativeAmount = currentNativeBalancesText(),
            totalBalance = currentTotalBalanceText()
        )
    }

    private fun rowData(group: ApiGroupedWalletVariant): SubwalletRowData {
        val byChain = valueChains.mapNotNull { chain ->
            val entry = group.byChain[chain.name] ?: return@mapNotNull null
            chain.name to AccountChain(address = entry.wallet.address)
        }.toMap()

        return SubwalletRowData(
            identifier = group.index.toString(),
            title = ".${group.index + 1}",
            badge = derivationBadge(group),
            network = network ?: MBlockchainNetwork.MAINNET,
            accountId = null,
            byChain = byChain,
            nativeAmount = nativeBalancesText(group),
            totalBalance = totalBalanceText(group)
        )
    }

    private fun currentSubwalletIndex(): Int {
        return displayChains
            .firstNotNullOfOrNull { account?.byChain?.get(it.name)?.derivation?.index }
            ?: 0
    }

    private fun currentDerivationBadge(): String? {
        return displayChains
            .firstNotNullOfOrNull {
                derivationBadgeText(account?.byChain?.get(it.name)?.derivation?.label)
            }
    }

    private fun derivationBadge(group: ApiGroupedWalletVariant): String? {
        return displayChains
            .firstNotNullOfOrNull {
                derivationBadgeText(group.byChain[it.name]?.wallet?.derivation?.label)
            }
    }

    private fun derivationBadgeText(label: String?): String? {
        val nonEmpty = label?.takeIf { it.isNotEmpty() } ?: return null
        if (HIDDEN_DERIVATION_LABELS.contains(nonEmpty.lowercase())) return null
        return nonEmpty.take(1).uppercase() + nonEmpty.drop(1)
    }

    private fun currentNativeBalancesText(): String {
        return valueChains.mapNotNull { chain ->
            val token = TokenStore.getToken(chain.nativeSlug) ?: return@mapNotNull null
            val balance = currentNativeBalance(chain)
            balance.doubleAbsRepresentation(token.decimals).toString(
                token.decimals, token.symbol, 0, true
            )
        }.joinToString(", ")
    }

    private fun currentTotalBalanceText(): String {
        val total = valueChains.fold(0.0) { acc, chain ->
            val token = TokenStore.getToken(chain.nativeSlug) ?: return@fold acc
            val balance = currentNativeBalance(chain)
            acc + balance.doubleAbsRepresentation(token.decimals) * token.priceUsd
        }
        return total.toString(
            WalletCore.baseCurrency.decimalsCount,
            WalletCore.baseCurrency.sign,
            WalletCore.baseCurrency.decimalsCount,
            true
        ) ?: ""
    }

    private fun currentNativeBalance(chain: MBlockchain): BigInteger {
        val balances = BalanceStore.getBalances(accountId) ?: return BigInteger.ZERO
        return balances[chain.nativeSlug] ?: BigInteger.ZERO
    }

    private fun nativeBalancesText(group: ApiGroupedWalletVariant): String {
        return valueChains.mapNotNull { chain ->
            val entry = group.byChain[chain.name] ?: return@mapNotNull null
            val token = TokenStore.getToken(chain.nativeSlug) ?: return@mapNotNull null
            entry.balance.doubleAbsRepresentation(token.decimals).toString(
                token.decimals, token.symbol, 0, true
            )
        }.joinToString(", ")
    }

    private fun totalBalanceText(group: ApiGroupedWalletVariant): String {
        val total = valueChains.fold(0.0) { acc, chain ->
            val entry = group.byChain[chain.name] ?: return@fold acc
            val token = TokenStore.getToken(chain.nativeSlug) ?: return@fold acc
            acc + entry.balance.doubleAbsRepresentation(token.decimals) * token.priceUsd
        }
        return total.toString(
            WalletCore.baseCurrency.decimalsCount,
            WalletCore.baseCurrency.sign,
            WalletCore.baseCurrency.decimalsCount,
            true
        ) ?: ""
    }

    private fun subwalletTitle(parentName: String, derivationIndex: Int?): String {
        val suffixDigits = parentName.takeLastWhile { it.isDigit() }
        val base = if (suffixDigits.isNotEmpty()) {
            val dotIndex = parentName.length - suffixDigits.length - 1
            if (dotIndex >= 0 && parentName[dotIndex] == '.') parentName.substring(0, dotIndex)
            else parentName
        } else {
            "${parentName.trim()} "
        }
        val suffix = derivationIndex?.plus(1) ?: return base
        return "$base.$suffix"
    }

    override fun onDestroy() {
        super.onDestroy()
        fetchJob?.cancel()
        scope.coroutineContext[Job]?.cancel()
    }
}
