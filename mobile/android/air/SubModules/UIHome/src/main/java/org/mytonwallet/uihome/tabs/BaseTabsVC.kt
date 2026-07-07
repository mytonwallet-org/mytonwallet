package org.mytonwallet.uihome.tabs

import android.content.Context
import android.content.Intent
import android.view.ViewGroup
import androidx.core.net.toUri
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode
import org.mytonwallet.app_air.uiassets.viewControllers.token.TokenVC
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVC
import org.mytonwallet.app_air.uicomponents.base.ITabsVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WNavigationController.PresentationConfig
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uireceive.ReceiveBackgroundCache
import org.mytonwallet.app_air.uisettings.viewControllers.settings.SettingsVC
import org.mytonwallet.app_air.uitransaction.viewControllers.transaction.TransactionVC
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.utils.toUriOrNull
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.SubprojectHelpers
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.uihome.home.HomeVC
import org.mytonwallet.uihome.home.promotion.PromotionVC
import org.mytonwallet.uihome.tabs.views.IBottomNavigationView

/**
 * Shared base for the two tab containers (phone [TabsVC] and tablet TabletTabsVC). Owns the four
 * per-tab navigation stacks (Home/Agent/Explore/Settings) and the shared [WalletEvent] routing, and
 * supports transferring the live stacks between containers on a layout swap so each tab's back stack
 * survives. Container-specific chrome (bottom bar, minimize, blur, search, mounting) is left to the
 * subclasses via the [ITabsVC] members they implement.
 */
abstract class BaseTabsVC(context: Context) :
    WViewController(context), ITabsVC {

    override val shouldDisplayBottomBar: Boolean
        get() {
            return !WGlobalStorage.isGradientNavigationBarActive()
        }

    // Per-tab navigation stacks ///////////////////////////////////////////////////////////////////
    protected val stackNavigationControllers = HashMap<Int, WNavigationController>()
    protected var cachedExploreVC: ExploreVC? = null
    private var ownsStacks = true

    /** The currently selected tab id (backed differently per container). */
    protected abstract var currentTabId: Int

    /** Hook so a subclass can wire up the Explore VC (search field) once it's created. */
    protected open fun onExploreCreated(exploreVC: ExploreVC) {}

    /** Detach the live stacks from this container's view tree (called before a transfer). */
    protected abstract fun detachMountedStacks()

    protected fun getNavigationStack(id: Int): WNavigationController {
        stackNavigationControllers[id]?.let { return it }
        val nav = WNavigationController(window!!)
        nav.tabBarController = this
        nav.setRoot(
            when (id) {
                IBottomNavigationView.ID_HOME -> HomeVC(context, MScreenMode.Default)
                IBottomNavigationView.ID_AGENT -> AgentVC(context)
                IBottomNavigationView.ID_EXPLORE -> ExploreVC(context).also {
                    cachedExploreVC = it
                    onExploreCreated(it)
                }

                IBottomNavigationView.ID_SETTINGS -> SettingsVC(context)
                else -> throw Error()
            }
        )
        stackNavigationControllers[id] = nav
        return nav
    }

    protected fun navForOrNull(id: Int): WNavigationController? = stackNavigationControllers[id]

    protected val navStacks: Collection<WNavigationController> get() = stackNavigationControllers.values

    // Layout swap transfer ////////////////////////////////////////////////////////////////////////
    class TabStacksTransfer(
        val stacks: HashMap<Int, WNavigationController>,
        val exploreVC: ExploreVC?,
        val selectedItemId: Int,
        // Full-screen VCs pushed over the main navigation controller (above the tab container),
        // detached but not destroyed so they survive the container swap.
        val pushedOverMain: List<WViewController>,
        // Current Explore search query, so it survives a phone <-> tablet swap.
        val searchText: String,
    )

    protected open fun exportSearchText(): String = ""

    protected open fun restoreSearchText(text: String) {}

    /**
     * The full-screen VCs currently pushed over this container's main navigation controller, above
     * the tab content. Detached (not destroyed) so the new container can re-host them. Each container
     * resolves its own main nav (phone: the window root nav; tablet: the content-panel nav).
     */
    protected open fun exportPushedOverMain(): List<WViewController> = emptyList()

    /** Re-host VCs returned by [exportPushedOverMain] onto this container's main nav after setup. */
    protected open fun adoptPushedOverMain(pushed: List<WViewController>) {}

    private var pendingPushedOverMain: List<WViewController> = emptyList()

    /** Detach the stacks from this container and hand them to the other one (resize swap). */
    fun exportStacks(): TabStacksTransfer {
        val selected = currentTabId
        val pushedOverMain = exportPushedOverMain()
        detachMountedStacks()
        for (nav in stackNavigationControllers.values) {
            (nav.parent as? ViewGroup)?.removeView(nav)
            nav.tabBarController = null
        }
        val searchText = exportSearchText()
        ownsStacks = false
        return TabStacksTransfer(
            HashMap(stackNavigationControllers),
            cachedExploreVC,
            selected,
            pushedOverMain,
            searchText
        )
    }

    /** Adopt stacks built by the other container before this VC's views are set up (resize swap). */
    fun adoptStacksBeforeSetup(transfer: TabStacksTransfer) {
        destroyStacks()
        stackNavigationControllers.putAll(transfer.stacks)
        cachedExploreVC = transfer.exploreVC
        cachedExploreVC?.let { onExploreCreated(it) }
        for (nav in stackNavigationControllers.values) {
            nav.tabBarController = this
        }
        ownsStacks = true
        currentTabId = transfer.selectedItemId
        pendingPushedOverMain = transfer.pushedOverMain
        pendingSearchText = transfer.searchText
    }

    private var pendingSearchText: String = ""

    protected fun adoptPendingSearchText() {
        val text = pendingSearchText
        pendingSearchText = ""
        restoreSearchText(text)
    }

    /** Re-host the pushed-over-main VCs once this container's views/main nav exist. */
    protected fun adoptPendingPushedOverMain() {
        if (pendingPushedOverMain.isEmpty())
            return
        val pushed = pendingPushedOverMain
        pendingPushedOverMain = emptyList()
        adoptPushedOverMain(pushed)
    }

    protected fun destroyStacks() {
        stackNavigationControllers.values.forEach {
            it.tabBarController = null
            it.onDestroy()
        }
        stackNavigationControllers.clear()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (ownsStacks)
            destroyStacks()
        cachedExploreVC = null
    }

    // Shared receive-background precache //////////////////////////////////////////////////////////
    protected fun precacheReceiveBackground() {
        WalletCore.doOnBridgeReady {
            val prioritized = AccountStore.activeAccount?.sortedChains()?.mapNotNull { entry ->
                MBlockchain.supportedChains.find { it.name == entry.key }
            } ?: emptyList()
            ReceiveBackgroundCache.precache(window?.systemBars?.top ?: 0, prioritized)
        }
    }

    // Shared WalletEvent routing //////////////////////////////////////////////////////////////////
    private fun openUrl(config: InAppBrowserConfig) {
        val window = window ?: return
        val browserVC = InAppBrowserVC(context, this, config)
        val nav = WNavigationController(window)
        nav.setRoot(browserVC)
        window.present(nav)
    }

    private fun canOpenExternally(url: String): Boolean {
        val scheme = url.toUriOrNull()?.scheme?.lowercase() ?: return false
        return scheme in setOf("geo", "mailto", "market", "tg")
    }

    /** Routes the events common to both containers. Returns true if handled. */
    protected fun routeWalletEvent(walletEvent: WalletEvent): Boolean {
        val window = window ?: return false
        when (walletEvent) {
            is WalletEvent.OpenUrl -> {
                val url = walletEvent.url
                if (walletEvent.isExternal) {
                    context.startActivityCatching(Intent(Intent.ACTION_VIEW, url.toUri()))
                } else if (WalletContextManager.delegate?.get()?.handleDeeplink(
                        url,
                        DeeplinkOpenSource.INTERNAL_UI
                    ) != true) {
                    if (canOpenExternally(url)) {
                        context.startActivityCatching(Intent(Intent.ACTION_VIEW, url.toUri()))
                    } else if (url.lowercase().startsWith("https://")) {
                        val resolved = if (SubprojectHelpers.isSubproject(url))
                            SubprojectHelpers.appendSubprojectContext(url)
                        else url
                        openUrl(InAppBrowserConfig(resolved, injectDappConnect = true))
                    } else {
                        Logger.w(Logger.LogTag.AIR_APPLICATION, "OpenUrl: unsupported link = $url")
                    }
                }
                return true
            }

            is WalletEvent.OpenUrlWithConfig -> {
                walletEvent.config?.let { openUrl(it) }
                return true
            }

            is WalletEvent.ShowPromotion -> {
                val nav = WNavigationController(
                    window,
                    PresentationConfig(style = WNavigationController.PresentationStyle.BottomSheet)
                )
                nav.setRoot(PromotionVC(context, walletEvent.promotion))
                window.present(nav)
                return true
            }

            is WalletEvent.OpenActivity -> {
                walletEvent.activity.let { activity ->
                    val nav = WNavigationController(
                        window,
                        PresentationConfig(style = WNavigationController.PresentationStyle.BottomSheet)
                    )
                    nav.setRoot(TransactionVC(context, walletEvent.accountId, activity))
                    window.present(nav)
                }
                return true
            }

            is WalletEvent.OpenToken -> {
                val account = AccountStore.activeAccount ?: return true
                val token = TokenStore.getToken(walletEvent.slug) ?: return true
                getNavigationStack(IBottomNavigationView.ID_HOME).push(
                    TokenVC(
                        context,
                        account,
                        token
                    )
                )
                return true
            }

            is WalletEvent.OpenNftList -> {
                if (walletEvent.nfts.isEmpty()) return true
                val assetsVC = AssetsVC(
                    context,
                    walletEvent.accountId,
                    AssetsVC.ViewMode.COMPLETE,
                    collectionMode = CollectionMode.ReadOnly(walletEvent.name, walletEvent.nfts),
                    isShowingSingleCollection = true
                )
                (window.navigationControllers.lastOrNull()
                    ?: getNavigationStack(IBottomNavigationView.ID_HOME)).push(assetsVC)
                return true
            }

            else -> return false
        }
    }
}
