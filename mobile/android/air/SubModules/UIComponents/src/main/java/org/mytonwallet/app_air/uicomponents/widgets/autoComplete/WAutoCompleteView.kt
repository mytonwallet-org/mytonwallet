package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextWatcher
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.commonViews.AddressInputLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class WAutoCompleteView(
    context: Context,
    val onSuggest: (MSavedAddress) -> Unit
) : WView(context), WRecyclerViewAdapter.WRecyclerViewDataSource,
    WThemedView {

    companion object {
        val SUGGEST_CELL = WCell.Type(1)
        private const val MAX_HEIGHT = 280
    }

    var maxYInWindow: Int = Int.MAX_VALUE
        set(value) {
            field = value
            updateLayout()
        }

    private val rvAdapter = WRecyclerViewAdapter(WeakReference(this), arrayOf(SUGGEST_CELL))
    private val coroutineScope = CoroutineScope(Dispatchers.Main)
    private var textWatcher: TextWatcher? = null
    private var attachedInput: WeakReference<AddressInputLayout>? = null
    private var currentFilterJob: Job? = null
    private var autoCompleteConfig: AddressInputLayout.AutoCompleteConfig? = null

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(context)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context, LinearLayoutManager.VERTICAL, false)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv.overScrollMode = OVER_SCROLL_NEVER
        rv
    }

    override fun setupViews() {
        super.setupViews()

        addView(recyclerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setConstraints {
            allEdges(recyclerView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        recyclerView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            WColor.PrimaryText.color.colorWithAlpha(25),
            1f
        )
    }

    fun attachToAddressInput(
        input: AddressInputLayout?,
        config: AddressInputLayout.AutoCompleteConfig
    ) {
        this.autoCompleteConfig = config
        if (attachedInput?.get() === input)
            return
        if (input != null) {
            val w = input.width
            (layoutParams as? LayoutParams)?.apply {
                matchConstraintMaxWidth = w
                matchConstraintMaxHeight = MAX_HEIGHT.dp
            }
            updateSuggestions(input.getKeyword())
            attachedInput?.get()?.removeTextChangedListener(textWatcher)
            attachedInput = WeakReference(input)
            textWatcher = input.addTextChangedListener(onTextChanged = { text, _, _, _ ->
                updateSuggestions(text?.toString().orEmpty())
            })
            recyclerView.post {
                if (rvAdapter.itemCount > 0) recyclerView.scrollToPosition(0)
            }
        } else {
            attachedInput = null
            visibility = INVISIBLE
            currentFilterJob?.cancel()
            suggestions = emptyList()
            rvAdapter.reloadData()
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        currentFilterJob?.cancel()
        currentFilterJob = null
        attachedInput?.get()?.removeTextChangedListener(textWatcher)
        textWatcher = null
        coroutineScope.cancel()
    }

    private var suggestionsVisibility = INVISIBLE
    private fun updateSuggestions(keyword: String) {
        currentFilterJob?.cancel()

        currentFilterJob = coroutineScope.launch {
            val filteredAddresses = withContext(Dispatchers.IO) {
                (
                    (AddressStore.addressData?.savedAddresses ?: emptyList()) +
                        (if (autoCompleteConfig?.accountAddresses == true)
                            (AddressStore.addressData?.otherAccountAddresses ?: emptyList())
                        else
                            emptyList())
                    )
                    .distinctBy { it.address }
                    .filter { savedAddress ->
                        savedAddress.address.contains(keyword) ||
                            savedAddress.name.contains(keyword.lowercase())
                    }
            }

            suggestions = filteredAddresses
            val newVisibility =
                if (suggestions.isNotEmpty() && (suggestions.size > 1 || keyword != suggestions[0].address)) VISIBLE else INVISIBLE
            if (newVisibility == VISIBLE) {
                rvAdapter.reloadData()
                updateLayout()
            }
            if (newVisibility != visibility) {
                suggestionsVisibility = newVisibility
                if (newVisibility == VISIBLE) {
                    visibility = VISIBLE
                    alpha = 0f
                    fadeIn(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
                } else
                    fadeOut(AnimationConstants.VERY_VERY_QUICK_ANIMATION, onCompletion = {
                        visibility = suggestionsVisibility
                    })
            }
        }
    }

    private fun updateLayout() {
        val input = attachedInput?.get() ?: return
        val inputLocationInWindow = input.getLocationInWindow()
        val inputBottomInWindow = inputLocationInWindow.y + input.height + 8f.dp

        val parentLocation = (parent as? ViewGroup)?.getLocationInWindow() ?: vec2i()

        x = (inputLocationInWindow.x - parentLocation.x).toFloat()
        y = inputBottomInWindow - parentLocation.y

        layoutParams = (layoutParams as? LayoutParams)?.apply {
            val allowedHeight =
                (maxYInWindow - inputBottomInWindow.toInt()).coerceIn(0, MAX_HEIGHT.dp)
            matchConstraintMaxHeight = allowedHeight
        }
    }

    private var suggestions = emptyList<MSavedAddress>()

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
        val cell = WAutoCompleteCell(context, onRemove = {
            attachedInput?.get()?.getKeyword()?.let { keyword ->
                updateSuggestions(keyword = keyword)
            }
        })
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
        val cell = cellHolder.cell as WAutoCompleteCell
        cell.configure(
            suggestions[indexPath.row],
            indexPath.row == 0,
            indexPath.row == suggestions.size - 1
        )
    }

}
