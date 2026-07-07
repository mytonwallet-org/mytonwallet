package org.mytonwallet.app_air.uisettings.viewControllers.permissions

import android.content.Context
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconTitleSubtitleView
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class PermissionsVC(context: Context) : WViewController(context) {
    override val TAG = "Permissions"

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = true
    override val isSwipeBackAllowed = false
    override val isEdgeSwipeBackAllowed = true

    companion object {
        private val EXCLUDED_CHAINS = setOf("solana", "tron")
    }

    private val accountId = AccountStore.activeAccountId

    private val chains: List<MBlockchain> =
        AccountStore.activeAccount?.sortedChains().orEmpty()
            .mapNotNull { entry -> MBlockchain.supportedChains.find { it.name == entry.key } }
            .filter { !EXCLUDED_CHAINS.contains(it.name) }

    private val isSingleChain = chains.size <= 1

    // Single-chain: a plain screen with a normal navigation bar.
    // Null when there are no eligible chains — don't fall back to TON.
    private val singleChainVC: PermissionsListVC? by lazy {
        val chain = chains.firstOrNull()
        if (isSingleChain && chain != null)
            PermissionsListVC(
                context,
                accountId,
                chain,
                standalone = true
            )
        else null
    }

    // Multi-chain: one tab per chain in a segmented controller.
    private val segmentedController: WSegmentedController? by lazy {
        if (isSingleChain) null
        else {
            val items = chains.map { chain ->
                WSegmentedControllerItem(
                    PermissionsListVC(context, accountId, chain),
                    identifier = chain.name,
                    color = chain.displayColor
                )
            }.toMutableList()
            WSegmentedController(
                navigationController!!,
                items,
                applySideGutters = false,
                pilledTabs = true
            ).apply { addBackButton() }
        }
    }

    // Shown only when the account has no eligible chains.
    private val emptyView: WEmptyIconTitleSubtitleView? by lazy {
        if (singleChainVC == null && segmentedController == null)
            WEmptyIconTitleSubtitleView(
                context,
                animation = R.raw.animation_empty,
                title = LocaleController.getString("No Permissions"),
                subtitle = LocaleController.getString("Nothing to revoke on this chain")
            )
        else null
    }

    override fun setupViews() {
        super.setupViews()

        singleChainVC?.let { listVC ->
            listVC.navigationController = navigationController
            view.addView(
                listVC.view,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
            )
            view.setConstraints { allEdges(listVC.view) }
        }
        segmentedController?.let { controller ->
            view.addView(
                controller,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
            )
            view.setConstraints { allEdges(controller) }
        }
        emptyView?.let { empty ->
            setNavTitle(LocaleController.getString("Permissions"))
            setupNavBar(true)
            view.addView(
                empty,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT)
            )
            view.setConstraints {
                toCenterY(empty)
                toStart(empty, 48f)
                toEnd(empty, 48f)
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        segmentedController?.insetsUpdated()
        singleChainVC?.insetsUpdated()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        segmentedController?.scrollToTop()
        singleChainVC?.scrollToTop()
    }

    override fun onDestroy() {
        super.onDestroy()
        segmentedController?.onDestroy()
        singleChainVC?.onDestroy()
    }
}
