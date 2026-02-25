package org.mytonwallet.app_air.uicomponents.widgets.suggestion

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextWatcher
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.widget.addTextChangedListener
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.WWordInput
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.constants.PossibleWords
import java.lang.ref.WeakReference
import kotlin.math.ceil

@SuppressLint("ViewConstructor")
class WSuggestionView(
    context: Context,
    val onSuggest: (String) -> Unit
) : WView(context), WRecyclerViewAdapter.WRecyclerViewDataSource, WThemedView {

    companion object {
        val SUGGEST_CELL = WCell.Type(1)
    }

    private val rvAdapter = WRecyclerViewAdapter(WeakReference(this), arrayOf(SUGGEST_CELL))
    private val coroutineScope = CoroutineScope(Dispatchers.Main)
    private var textWatcher: TextWatcher? = null
    private var attachedInput: WeakReference<WWordInput>? = null
    private var currentFilterJob: Job? = null

    private val measureLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(15f)
            maxLines = 1
        }
    }
    private val cardView: WView by lazy {
        WView(context).apply {
            elevation = 4f.dp
        }
    }

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

        addView(cardView, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        cardView.addView(recyclerView, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        setConstraints { allEdges(cardView) }
        cardView.setConstraints { allEdges(recyclerView) }

        updateTheme()
    }

    override fun updateTheme() {
        cardView.setBackgroundColor(
            WColor.Background.color,
            20f.dp,
            true
        )

        recyclerView.background = null
    }

    fun attachToWordInput(input: WWordInput?) {
        attachedInput?.get()?.textField?.removeTextChangedListener(textWatcher)

        textWatcher = null
        attachedInput = null

        if (input == null) {
            visibility = INVISIBLE
            currentFilterJob?.cancel()
            suggestions = emptyList()
            rvAdapter.reloadData()
            return
        }

        attachedInput = WeakReference(input)
        updateSuggestions(input.textField.text.toString())

        textWatcher = input.textField.addTextChangedListener(onTextChanged = { text, _, _, _ ->
            updateSuggestions(text?.toString().orEmpty())
        })
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        currentFilterJob?.cancel()
        currentFilterJob = null
        attachedInput?.get()?.textField?.removeTextChangedListener(textWatcher)
        attachedInput = null
        textWatcher = null
    }

    private fun updateSuggestions(keyword: String) {
        currentFilterJob?.cancel()

        if (keyword.isEmpty()) {
            suggestions = emptyList()
            rvAdapter.reloadData()
            visibility = INVISIBLE
            return
        }

        currentFilterJob = coroutineScope.launch {
            val filteredSuggestions = withContext(Dispatchers.IO) {
                PossibleWords.All.filter { it.startsWith(keyword) }
            }

            suggestions = filteredSuggestions
            rvAdapter.reloadData()

            val shouldShow =
                suggestions.isNotEmpty() && (suggestions.size > 1 || keyword != suggestions[0])
            visibility = if (shouldShow) VISIBLE else INVISIBLE

            if (shouldShow) {
                recyclerView.post {
                    if (rvAdapter.itemCount > 0) recyclerView.scrollToPosition(0)
                }
                applyGeometry()
            }
        }
    }

    private fun applyGeometry() {
        val input = attachedInput?.get() ?: return
        val parentView = parent as? View ?: return

        val parentWidth = parentView.width
        val inputWidth = input.width

        if (parentWidth <= 0 || inputWidth <= 0) {
            post { applyGeometry() }
            return
        }

        val horizontalMargin = 16.dp

        val desiredWidth = measureContentWidth(suggestions).coerceAtLeast(0)
        val lp = layoutParams
        if (lp != null && lp.width != desiredWidth) {
            lp.width = desiredWidth
            layoutParams = lp
        }

        val rightLimit = (parentWidth - horizontalMargin).toFloat()
        val leftLimit = horizontalMargin.toFloat()
        val maxX = (rightLimit - desiredWidth).coerceAtLeast(leftLimit)

        val textStartX = input.x + input.textField.x
        val isLeftField = (input.x + inputWidth / 2f) <= parentWidth / 2f

        val newX = if (isLeftField) {
            textStartX.coerceIn(leftLimit, maxX)
        } else {
            val fits = textStartX + desiredWidth <= rightLimit
            val candidate = if (fits) textStartX else (rightLimit - desiredWidth)
            candidate.coerceIn(leftLimit, maxX)
        }

        x = newX
        y = input.y - (48.dp + 8.dp)
    }

    private fun measureContentWidth(items: List<String>): Int {
        if (items.isEmpty()) return 0

        val maxWidth = 260.dp
        var total = 0

        for ((index, word) in items.withIndex()) {
            val textWidth = ceil(measureLabel.paint.measureText(word)).toInt()
            val side = if (index == 0) 24.dp else 12.dp
            total += textWidth + side
            if (total >= maxWidth) return maxWidth
        }

        return total
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
        cell.configure(suggestions[indexPath.row], indexPath.row == 0, suggestions.size)
    }

}
