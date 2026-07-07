package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.cells.WalletConnectPayHeaderCell
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.cells.WalletConnectPayOptionCell
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData.cells.WalletConnectPaySignDataTransferInfoCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.moshi.WcPayAmount
import org.mytonwallet.app_air.walletcore.moshi.WcPayMerchant
import org.mytonwallet.app_air.walletcore.moshi.WcPayPaymentOption
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WalletConnectPaySignDataVC(
    context: Context,
    private val merchant: WcPayMerchant,
    private val paymentAmount: WcPayAmount?,
    private val paymentOption: WcPayPaymentOption?,
    private val onProceed: () -> Unit,
    private val onCancelled: () -> Unit,
    private val onShowTransferInfo: () -> Unit,
) : WViewController(context), WRecyclerViewAdapter.WRecyclerViewDataSource {
    override val TAG = "WalletConnectPaySignData"

    companion object {
        private val HEADER_CELL = WCell.Type(1)
        private val TOKEN_TITLE_CELL = WCell.Type(2)
        private val TOKEN_CELL = WCell.Type(3)
        private val TRANSFER_INFO_CELL = WCell.Type(4)
        private val GAP_CELL = WCell.Type(5)
    }

    private val hasToken = paymentOption != null

    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(HEADER_CELL, TOKEN_TITLE_CELL, TOKEN_CELL, TRANSFER_INFO_CELL, GAP_CELL)
    )

    private val recyclerView = WRecyclerView(this).apply {
        adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
        setItemAnimator(null)
        clipToPadding = false
    }

    private val bottomBar = ReversedCornerViewUpsideDown(context, recyclerView)

    private val cancelButton = WButton(context, WButton.Type.SECONDARY_WITH_BACKGROUND).apply {
        layoutParams = ViewGroup.LayoutParams(0, WRAP_CONTENT)
        text = LocaleController.getString("Cancel")
        setOnClickListener {
            onCancelled()
            window?.dismissLastNav()
        }
    }

    private var isProceeding = false

    private val signButton = WButton(context, WButton.Type.PRIMARY).apply {
        layoutParams = ViewGroup.LayoutParams(0, WRAP_CONTENT)
        text = LocaleController.getString("Sign")
        setOnClickListener {
            if (isProceeding) return@setOnClickListener
            isProceeding = true
            onProceed()
        }
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)
        setNavTitle(merchant.name, false)
        navigationBar?.addCloseButton {
            onCancelled()
            window?.dismissLastNav()
        }

        recyclerView.clipToPadding = false
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomBar,
            ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_CONSTRAINT)
        )
        view.addView(cancelButton, ConstraintLayout.LayoutParams(0, 50.dp))
        view.addView(signButton, ConstraintLayout.LayoutParams(0, 50.dp))

        view.setConstraints {
            toTop(recyclerView)
            toCenterX(recyclerView)
            toBottom(recyclerView)

            topToTop(bottomBar, cancelButton, -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS)
            toBottom(bottomBar)
            startToEnd(signButton, cancelButton, 6f)
            endToStart(cancelButton, signButton, 6f)
        }

        updateTheme()
        insetsUpdated()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        // Re-arm the Sign button if the user backed out of the pushed
        // passcode/Ledger screen without completing the signing.
        isProceeding = false
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.reloadData()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bottomInset = max(
            navigationController?.getSystemBars()?.bottom ?: 0,
            navigationController?.imeInsetBottom ?: 0
        )
        recyclerView.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            (navigationController?.getSystemBars()?.top ?: 0) + (navigationBar?.calculatedMinHeight
                ?: 0),
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            20.dp + ViewConstants.BLOCK_RADIUS.dp.roundToInt() +
                signButton.buttonHeight + bottomInset
        )
        view.setConstraints {
            toStartPx(cancelButton, 20.dp + systemBarStartInset)
            toEndPx(signButton, 20.dp + systemBarEndInset)
            toBottomPx(cancelButton, 20.dp + bottomInset)
            toBottomPx(signButton, 20.dp + bottomInset)
        }
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView) = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        // header + [token title + token + gap] + transfer info
        return if (hasToken) 5 else 2
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return if (hasToken) when (indexPath.row) {
            0 -> HEADER_CELL
            1 -> TOKEN_TITLE_CELL
            2 -> TOKEN_CELL
            3 -> GAP_CELL
            else -> TRANSFER_INFO_CELL
        } else when (indexPath.row) {
            0 -> HEADER_CELL
            else -> TRANSFER_INFO_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> WalletConnectPayHeaderCell(context)
            TOKEN_TITLE_CELL -> HeaderCell(context)
            TOKEN_CELL -> WalletConnectPayOptionCell(context)
            GAP_CELL -> WCell(
                context,
                ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp)
            )

            else -> WalletConnectPaySignDataTransferInfoCell(context)
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (val cell = cellHolder.cell) {
            is WalletConnectPayHeaderCell -> {
                cell.configure(merchant, paymentAmount)
            }

            is HeaderCell -> {
                cell.configure(
                    LocaleController.getString("Token"),
                    titleColor = WColor.Tint,
                    topRounding = HeaderCell.TopRounding.NORMAL
                )
            }

            is WalletConnectPayOptionCell -> {
                paymentOption?.let {
                    cell.configure(it, isLast = true)
                }
            }

            is WalletConnectPaySignDataTransferInfoCell -> {
                cell.onTap = { onShowTransferInfo() }
            }
        }
    }
}
