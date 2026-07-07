package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData.cells.WalletConnectPaySignDataEip712Cell
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData.cells.WalletConnectPaySignDataValueCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class WalletConnectPaySignDataInfoVC(
    context: Context,
    private val payload: MSignDataPayload,
) : WViewController(context), WRecyclerViewAdapter.WRecyclerViewDataSource {
    override val TAG = "WalletConnectPaySignDataInfo"

    override val shouldDisplayBottomBar = true

    companion object {
        private val TITLE_CELL = WCell.Type(1)
        private val VALUE_CELL = WCell.Type(2)
        private val EIP712_CELL = WCell.Type(3)
        private val GAP_CELL = WCell.Type(4)
    }

    private sealed class Row {
        data class Title(val text: String) : Row()
        data class Value(val text: String, val copyLabel: String) : Row()
        data class Eip712(
            val obj: Map<String, Any?>,
            val typeName: String,
            val types: Map<String, List<MSignDataPayload.SignDataPayloadEip712.TypeField>>,
        ) : Row()

        object Gap : Row()
    }

    private val rows: List<Row> = buildRows()

    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(TITLE_CELL, VALUE_CELL, EIP712_CELL, GAP_CELL)
    )

    private val recyclerView = WRecyclerView(this).apply {
        adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
        setItemAnimator(null)
        clipToPadding = false
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)
        setNavTitle(LocaleController.getString("Transfer Info"), false)
        navigationBar?.addCloseButton()

        recyclerView.clipToPadding = false
        view.addView(recyclerView, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0))
        view.setConstraints {
            toTop(recyclerView)
            toCenterX(recyclerView)
            toBottom(recyclerView)
        }

        updateTheme()
        insetsUpdated()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.reloadData()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            (navigationBar?.calculatedMinHeight ?: 0),
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            20.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
        )
    }

    private fun buildRows(): List<Row> {
        val list = mutableListOf<Row>()
        when (payload) {
            is MSignDataPayload.SignDataPayloadText -> {
                list += Row.Title(LocaleController.getString("Message"))
                list += Row.Value(payload.text, "Message")
            }

            is MSignDataPayload.SignDataPayloadBinary -> {
                list += Row.Title(LocaleController.getString("Binary Data"))
                list += Row.Value(payload.bytes, "Binary Data")
            }

            is MSignDataPayload.SignDataPayloadCell -> {
                list += Row.Title(LocaleController.getString("Cell Schema"))
                list += Row.Value(payload.schema, "Cell Schema")
                list += Row.Gap
                list += Row.Title(LocaleController.getString("Cell Data"))
                list += Row.Value(payload.cell, "Cell Data")
            }

            is MSignDataPayload.SignDataPayloadEip712 -> {
                list += Row.Title(LocaleController.getString("EIP-712 typed data"))
                list += Row.Value(payload.primaryType, "Primary type")
                list += Row.Gap
                list += Row.Title(LocaleController.getString("EIP-712 domain"))
                list += Row.Eip712(payload.domain, "EIP712Domain", payload.types)
                list += Row.Gap
                list += Row.Title(LocaleController.getString("Message"))
                list += Row.Eip712(payload.message, payload.primaryType, payload.types)
            }
        }
        return list
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView) = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int) = rows.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (rows[indexPath.row]) {
            is Row.Title -> TITLE_CELL
            is Row.Value -> VALUE_CELL
            is Row.Eip712 -> EIP712_CELL
            Row.Gap -> GAP_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            TITLE_CELL -> HeaderCell(context)
            VALUE_CELL -> WalletConnectPaySignDataValueCell(context)
            EIP712_CELL -> WalletConnectPaySignDataEip712Cell(context)
            else -> GapCell(context)
        }
    }

    private fun topRadiusFor(index: Int): Float = when {
        index == 0 -> ViewConstants.TOOLBAR_RADIUS.dp
        rows[index - 1] is Row.Gap -> ViewConstants.BLOCK_RADIUS.dp
        else -> 0f
    }

    private fun bottomRadiusFor(index: Int): Float = when {
        index == rows.size - 1 -> ViewConstants.BLOCK_RADIUS.dp
        rows[index + 1] is Row.Gap -> ViewConstants.BLOCK_RADIUS.dp
        else -> 0f
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val index = indexPath.row
        when (val row = rows[index]) {
            is Row.Title -> {
                (cellHolder.cell as HeaderCell).configure(
                    row.text,
                    titleColor = WColor.Tint,
                    topRounding = if (index == 0) HeaderCell.TopRounding.FIRST_ITEM
                    else HeaderCell.TopRounding.NORMAL
                )
            }

            is Row.Value -> {
                (cellHolder.cell as WalletConnectPaySignDataValueCell).configure(
                    row.text,
                    row.copyLabel,
                    topRadius = topRadiusFor(index),
                    bottomRadius = bottomRadiusFor(index)
                )
            }

            is Row.Eip712 -> {
                (cellHolder.cell as WalletConnectPaySignDataEip712Cell).configure(
                    row.obj,
                    row.typeName,
                    row.types,
                    topRadius = topRadiusFor(index),
                    bottomRadius = bottomRadiusFor(index)
                )
            }

            Row.Gap -> {}
        }
    }

    @SuppressLint("ViewConstructor")
    private class GapCell(context: Context) : WCell(
        context,
        ViewGroup.LayoutParams(LayoutParams.MATCH_PARENT, 12.dp)
    )
}
