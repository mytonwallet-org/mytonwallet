package org.mytonwallet.app_air.uisettings.viewControllers.notificationSettings

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LastItemPaddingDecoration
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uisettings.viewControllers.notificationSettings.cells.NotificationSettingsAccountCell
import org.mytonwallet.app_air.uisettings.viewControllers.notificationSettings.cells.NotificationSettingsFooterCell
import org.mytonwallet.app_air.uisettings.viewControllers.notificationSettings.cells.NotificationSettingsHeaderCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference

class NotificationSettingsVC(
    context: Context,
) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource {
    override val TAG = "NotificationSettings"

    val isPermissionGranted: Boolean
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    val accounts = WGlobalStorage.accountIds().mapNotNull { accountId ->
        AccountStore.accountById(accountId)
    }.filter {
        it.tonAddress != null
    }
    var enabledAccounts: MutableList<String>? =
        WGlobalStorage.getPushNotificationsEnabledAccounts()?.toMutableList()
    var pushNotificationsChecked =
        isPermissionGranted && !enabledAccounts.isNullOrEmpty()

    override val shouldDisplayBottomBar = true

    companion object {
        const val SECTION_HEADER = 0
        const val SECTION_ACCOUNTS = 1
        const val SECTION_FOOTER = 2

        val HEADER_CELL = WCell.Type(1)
        val ITEM_CELL = WCell.Type(2)
        val FOOTER_CELL = WCell.Type(3)
    }

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(HEADER_CELL, ITEM_CELL, FOOTER_CELL))

    var isFirstAppearance = true
    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManagerAccurateOffset(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv.addItemDecoration(
            LastItemPaddingDecoration(
                navigationController?.getSystemBars()?.bottom ?: 0
            )
        )
        rv.setItemAnimator(null)
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0)
                    return
                updateBlurViews(recyclerView)
            }

            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE)
                    updateBlurViews(recyclerView)
            }
        })
        rv
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Notifications & Sounds"))
        setupNavBar(true)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationBar?.calculatedMinHeight ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            20.dp +
                (navigationController?.getSystemBars()?.bottom ?: 0)
        )
        recyclerView.clipToPadding = false

        updateTheme()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        val pushNotificationsChecked = isPermissionGranted && !enabledAccounts.isNullOrEmpty()
        if (this.pushNotificationsChecked != pushNotificationsChecked) {
            this.pushNotificationsChecked = pushNotificationsChecked
            rvAdapter.reloadData()
        }
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        isFirstAppearance = false
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationBar?.calculatedMinHeight ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            (navigationController?.getSystemBars()?.bottom ?: 0)
        )
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 3
    }

    override fun recyclerViewNumberOfItems(
        rv: RecyclerView,
        section: Int
    ): Int {
        if (section == SECTION_ACCOUNTS)
            return accounts.size
        return 1
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        return when (indexPath.section) {
            SECTION_HEADER -> HEADER_CELL
            SECTION_FOOTER -> FOOTER_CELL
            else -> ITEM_CELL
        }
    }

    override fun recyclerViewCellView(
        rv: RecyclerView,
        cellType: WCell.Type
    ): WCell {
        return when (cellType) {
            HEADER_CELL -> {
                NotificationSettingsHeaderCell(
                    context,
                    onPushNotificationsCheckChanged = { isChecked ->
                        if (isChecked && !isPermissionGranted) {
                            rvAdapter.notifyItemChanged(
                                rvAdapter.indexPathToPosition(
                                    IndexPath(
                                        SECTION_HEADER,
                                        0
                                    )
                                )
                            )
                            requestNotificationPermission()
                            return@NotificationSettingsHeaderCell
                        }

                        pushNotificationsChecked = isChecked
                        if (isChecked) {
                            val defaultEnabledAccounts = accounts.take(3)
                            enabledAccounts =
                                defaultEnabledAccounts.map { it.accountId }.toMutableList()
                            defaultEnabledAccounts.forEach {
                                AirPushNotifications.subscribe(it, ignoreIfLimitReached = false)
                            }
                        } else {
                            enabledAccounts?.clear()
                            AirPushNotifications.unsubscribeAll()
                        }
                        for (i in accounts.indices) {
                            rvAdapter.notifyItemChanged(
                                rvAdapter.indexPathToPosition(
                                    IndexPath(
                                        SECTION_ACCOUNTS,
                                        i
                                    )
                                )
                            )
                        }
                    })
            }

            FOOTER_CELL -> {
                NotificationSettingsFooterCell(context)
            }

            else -> {
                NotificationSettingsAccountCell(context).apply {
                    onTap = { account, isChecked ->
                        if (isChecked) {
                            AirPushNotifications.subscribe(account, ignoreIfLimitReached = false)
                            if (enabledAccounts == null)
                                enabledAccounts = mutableListOf()
                            if (enabledAccounts?.contains(account.accountId) != true)
                                enabledAccounts?.add(account.accountId)
                        } else {
                            AirPushNotifications.unsubscribe(account)
                            enabledAccounts?.remove(account.accountId)
                        }
                        val currentIndex =
                            accounts.indexOfFirst { it.accountId == account.accountId }
                        for (i in accounts.indices) {
                            if (i != currentIndex) {
                                rvAdapter.notifyItemChanged(
                                    rvAdapter.indexPathToPosition(
                                        IndexPath(
                                            SECTION_ACCOUNTS,
                                            i
                                        )
                                    )
                                )
                            }
                        }
                        if ((pushNotificationsChecked && enabledAccounts.isNullOrEmpty()) ||
                            (!pushNotificationsChecked && !enabledAccounts.isNullOrEmpty())
                        ) {
                            // Update push notifications switch based on selections
                            pushNotificationsChecked = !enabledAccounts.isNullOrEmpty()
                            rvAdapter.notifyItemChanged(
                                rvAdapter.indexPathToPosition(
                                    IndexPath(
                                        SECTION_HEADER,
                                        0
                                    )
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (indexPath.section) {
            SECTION_HEADER -> {
                (cellHolder.cell as NotificationSettingsHeaderCell).configure(
                    pushNotificationsChecked,
                    accounts.isNotEmpty()
                )
            }

            SECTION_ACCOUNTS -> {
                val item = accounts[indexPath.row]
                val isChecked = enabledAccounts?.contains(item.accountId) ?: false
                (cellHolder.cell as NotificationSettingsAccountCell).configure(
                    item,
                    isChecked = isChecked,
                    isLocked = !isPermissionGranted || ((enabledAccounts?.size
                        ?: 0) >= 3 && !isChecked),
                    isLast = indexPath.row == accounts.size - 1,
                    animated = !isFirstAppearance
                )
            }

            SECTION_FOOTER -> {
                (cellHolder.cell as NotificationSettingsFooterCell).configure()
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            window?.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS)
            ) { _, grantResults ->
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    pushNotificationsChecked = true
                    if (enabledAccounts.isNullOrEmpty()) {
                        val defaultEnabledAccounts = accounts.take(3)
                        enabledAccounts =
                            defaultEnabledAccounts.map { it.accountId }.toMutableList()
                        defaultEnabledAccounts.forEach {
                            AirPushNotifications.subscribe(it, ignoreIfLimitReached = false)
                        }
                        rvAdapter.notifyItemChanged(
                            rvAdapter.indexPathToPosition(
                                IndexPath(
                                    SECTION_HEADER,
                                    0
                                )
                            )
                        )
                        for (i in accounts.indices) {
                            rvAdapter.notifyItemChanged(
                                rvAdapter.indexPathToPosition(
                                    IndexPath(SECTION_ACCOUNTS, i)
                                )
                            )
                        }
                    }
                    AirPushNotifications.register(subscribePreviousAccountsIfEmpty = true)
                } else {
                    openNotificationSettings()
                }
            }
        } else {
            // Should not happen
        }
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        val uri = Uri.fromParts("package", context.applicationContext.packageName, null)
        intent.data = uri
        window?.startActivity(intent)
    }
}
