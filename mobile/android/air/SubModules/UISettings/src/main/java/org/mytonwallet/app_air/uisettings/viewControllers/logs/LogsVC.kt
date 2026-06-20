package org.mytonwallet.app_air.uisettings.viewControllers.logs

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Typeface
import android.view.View.generateViewId
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.TextView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.recyclerview.widget.LinearLayoutManager
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.drawable.TabletEdgeFadeDrawable
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class LogsVC(context: Context) : WViewController(context) {
    override val TAG = "Logs"

    override val shouldDisplayBottomBar = true
    override val ignoreSideGuttering = true

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val adapter = LogLinesAdapter()

    private val recyclerView: RecyclerView by lazy {
        RecyclerView(context).apply {
            id = generateViewId()
            layoutManager = LinearLayoutManager(context)
            this.adapter = this@LogsVC.adapter
            setHasFixedSize(false)
            clipToPadding = false
            overScrollMode = RecyclerView.OVER_SCROLL_ALWAYS
        }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle("Logs")
        setupNavBar(true)

        view.addView(recyclerView, ConstraintLayout.LayoutParams(0, 0))
        view.setConstraints {
            allEdges(recyclerView)
        }
        navigationBar?.bringToFront()

        loadLogs()
        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPaddingLocalized(
            12.dp + additionalTabletPadding + systemBarStartInset,
            WNavigationBar.DEFAULT_HEIGHT.dp +
                (navigationController?.getSystemBars()?.top ?: 0),
            12.dp + systemBarEndInset,
            12.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
        )
    }

    private fun loadLogs() {
        scope.launch {
            val lines = withContext(Dispatchers.IO) {
                Logger.readLogText().split('\n')
            }
            adapter.submit(lines)
            if (lines.isNotEmpty()) {
                recyclerView.scrollToPosition(lines.size - 1)
            }
        }
    }

    @SuppressLint("NotifyDataSetChanged")
    override fun updateTheme() {
        super.updateTheme()
        if (isSplitDetailPanel)
            view.background =
                TabletEdgeFadeDrawable(WColor.Background.color, dimWhenWide = false)
        else
            view.setBackgroundColor(WColor.Background.color)
        adapter.notifyDataSetChanged()
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.coroutineContext[Job]?.cancel()
    }

    private class LineViewHolder(val textView: TextView) : RecyclerView.ViewHolder(textView)

    private class LogLinesAdapter : RecyclerView.Adapter<LineViewHolder>() {
        private var lines: List<String> = emptyList()

        @SuppressLint("NotifyDataSetChanged")
        fun submit(newLines: List<String>) {
            lines = newLines
            notifyDataSetChanged()
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LineViewHolder {
            val tv = TextView(parent.context).apply {
                typeface = Typeface.MONOSPACE
                textSize = 11f
                setTextColor(WColor.PrimaryText.color)
                layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            }
            return LineViewHolder(tv)
        }

        override fun onBindViewHolder(holder: LineViewHolder, position: Int) {
            holder.textView.text = lines[position]
            holder.textView.setTextColor(WColor.PrimaryText.color)
        }

        override fun getItemCount(): Int = lines.size
    }
}
