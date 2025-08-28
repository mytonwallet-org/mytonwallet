package org.mytonwallet.app_air.uicomponents.widgets.suggestion

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.widget.doOnTextChanged
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.WWordInput
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.constants.PossibleWords
import java.lang.ref.WeakReference


@SuppressLint("ViewConstructor")
class WSuggestionView(
    context: Context,
    val onSuggest: (String) -> Unit
) : WView(context), WRecyclerViewAdapter.WRecyclerViewDataSource, WThemedView {

    companion object {
        val SUGGEST_CELL = WCell.Type(1)
    }

    private val rvAdapter = WRecyclerViewAdapter(WeakReference(this), arrayOf(SUGGEST_CELL))

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(context)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv
    }

    override fun setupViews() {
        super.setupViews()

        addView(recyclerView, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        setConstraints {
            allEdges(recyclerView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        recyclerView.setBackgroundColor(
            WColor.Background.color,
            6f.dp,
            WColor.PrimaryText.color.colorWithAlpha(25),
            1f
        )

    }

    fun attachToWordInput(input: WWordInput?) {
        if (input != null) {
            x = input.x + 36.dp
            y = input.y - 56.dp
            (layoutParams as LayoutParams).matchConstraintMaxWidth =
                input.width - 72.dp
            updateSuggestions(input.textField.text.toString())
            input.textField.doOnTextChanged { _, _, _, _ ->
                updateSuggestions(input.textField.text.toString())
            }
        } else {
            visibility = INVISIBLE
        }
    }

    private fun updateSuggestions(keyword: String) {
        suggestions = PossibleWords.All.filter { it.startsWith(keyword) }
        rvAdapter.reloadData()
        visibility =
            if (keyword.isNotEmpty() && suggestions.isNotEmpty() && (suggestions.size > 1 || keyword != suggestions[0])) VISIBLE else INVISIBLE
    }

    private var suggestions = emptyList<String>()

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return suggestions.size
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return SUGGEST_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        val cell = WSuggestionCell(context)
        cell.onTap = { it ->
            onSuggest(it)
        }
        return cell
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val cell = cellHolder.cell as WSuggestionCell
        cell.configure(suggestions[indexPath.row])
    }

}
