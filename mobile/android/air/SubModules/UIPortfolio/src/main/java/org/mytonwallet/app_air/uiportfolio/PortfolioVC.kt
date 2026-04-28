package org.mytonwallet.app_air.uiportfolio

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.text.TextPaint
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.isVisible
import androidx.lifecycle.ViewModelProvider
import com.google.android.material.chip.ChipGroup
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.BaseChartView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartHeaderView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartPickerDelegate
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartStyle
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartValueFormatter
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.FlatCheckBox
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.LegendSignatureView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.PieChartView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearChartData
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearChartView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearViewData
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.TransitionParams
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import java.math.BigInteger
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import kotlin.math.abs
import kotlin.math.pow

@SuppressLint("ViewConstructor")
class PortfolioVC(context: Context) : WViewControllerWithModelStore(context) {
    override val TAG = "Portfolio"

    private val viewModel by lazy {
        ViewModelProvider(this)[PortfolioViewModel::class.java]
    }

    private val scrollView = ScrollView(context).apply {
        id = ViewGroup.generateViewId()
        overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
        isVerticalScrollBarEnabled = false
    }
    private val contentLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(ViewConstants.GAP.dp, 0, ViewConstants.GAP.dp, 0)
    }
    private var chartStyle = ChartStyle.default()
    private val absoluteSection = createAbsoluteSection()
    private val distributionSection = createDistributionSection()

    override val shouldDisplayBottomBar: Boolean
        get() = navigationController?.tabBarController == null

    override fun setupViews() {
        super.setupViews()

        title = LocaleController.getString("Portfolio")
        setupNavBar(true)

        scrollView.addView(contentLayout, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        contentLayout.addView(absoluteSection.container, createChartLayoutParams())
        contentLayout.addView(
            distributionSection.container,
            createChartLayoutParams(topMargin = ViewConstants.GAP.dp)
        )

        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))

        view.setConstraints {
            topToBottom(scrollView, navigationBar!!)
            toCenterX(scrollView)
            bottomToBottom(scrollView, view)
        }

        absoluteSection.chartHeaderView.back.setOnClickListener {
            zoomOut(absoluteSection, animated = true)
        }
        distributionSection.chartHeaderView.back.setOnClickListener {
            zoomOut(distributionSection, animated = true)
        }
        absoluteSection.stackChartView.legendSignatureView.apply {
            isClickable = true
            isFocusable = true
            setOnClickListener { zoomIntoPieFromLegend(absoluteSection) }
        }
        distributionSection.stackChartView.legendSignatureView.apply {
            isClickable = true
            isFocusable = true
            setOnClickListener { zoomIntoPieFromLegend(distributionSection) }
        }

        updateTheme()

        collectFlow(viewModel.stateFlow, ::observeState)
    }

    override fun updateTheme() {
        super.updateTheme()

        chartStyle = ChartStyle.default()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        scrollView.setBackgroundColor(WColor.SecondaryBackground.color)
        applySectionStyle(absoluteSection)
        applySectionStyle(distributionSection)
        updateSectionTheme(absoluteSection)
        updateSectionTheme(distributionSection)
    }

    private fun observeState(state: PortfolioUiState) {
        when (state) {
            PortfolioUiState.Idle -> {
                absoluteSection.lineEnabledById.clear()
                distributionSection.lineEnabledById.clear()
                renderSeriesControls(null)
                showSectionLoading(absoluteSection)
                showSectionLoading(distributionSection)
                syncSeriesControlsPresentation()
            }

            is PortfolioUiState.Loading -> {
                configureChartValueFormatting(state.request.baseCurrency)
                absoluteSection.lineEnabledById.clear()
                distributionSection.lineEnabledById.clear()
                renderSeriesControls(null)
                showSectionLoading(absoluteSection)
                showSectionLoading(distributionSection)
                syncSeriesControlsPresentation()
            }

            is PortfolioUiState.Loaded -> {
                configureChartValueFormatting(state.request.baseCurrency)
                syncLineEnabledState(absoluteSection, state.chartData)
                syncLineEnabledState(distributionSection, state.chartData)
                renderSeriesControls(state.chartData)
                showAbsoluteLoaded(state.chartData)
                showDistributionLoaded(state.chartData)
                applyLineEnabledState(absoluteSection)
                applyLineEnabledState(distributionSection)
                syncSeriesControlsPresentation()
            }

            PortfolioUiState.Error -> Unit
        }
    }

    private fun showAbsoluteLoaded(data: StackLinearChartData?) {
        zoomOut(absoluteSection, animated = false)
        absoluteSection.chartData = data

        if (data == null) {
            showSectionStatus(absoluteSection)
            return
        }

        absoluteSection.stackChartView.setData(data)
        absoluteSection.stackChartView.updateTheme()
        absoluteSection.pieChartView.setData(null)
        absoluteSection.stackChartView.visibility = View.VISIBLE
        absoluteSection.stackChartView.legendSignatureView.visibility = View.GONE
        absoluteSection.pieChartView.visibility = View.GONE
        absoluteSection.pieChartView.legendSignatureView.visibility = View.GONE
        updateChartInteractivity(
            absoluteSection.stackChartView,
            absoluteSection.pieChartView,
            isPieActive = false
        )
        showLoadedSection(absoluteSection)
    }

    private fun showDistributionLoaded(data: StackLinearChartData?) {
        zoomOut(distributionSection, animated = false)
        distributionSection.chartData = data

        if (data == null) {
            showSectionStatus(distributionSection)
            return
        }

        distributionSection.stackChartView.setData(data)
        distributionSection.stackChartView.updateTheme()
        distributionSection.lastStackPickerSpan =
            distributionSection.stackChartView.getPickerWindowSpan()

        val initialPieDate =
            distributionSection.stackChartView.getPickerCenterDate().takeIf { it >= 0 }
                ?: data.x.last()

        distributionSection.pieChartView.setData(data)
        distributionSection.pieChartView.updateTheme()
        syncLineEnabledState(distributionSection.pieChartView, distributionSection.lineEnabledById)
        distributionSection.pieChartView.updatePicker(data, initialPieDate)

        distributionSection.mode = ChartMode.PIE
        distributionSection.stackChartView.visibility = View.GONE
        distributionSection.stackChartView.legendSignatureView.visibility = View.GONE
        distributionSection.pieChartView.visibility = View.VISIBLE
        distributionSection.pieChartView.legendSignatureView.visibility = View.GONE
        distributionSection.chartHeaderView.zoomTo(initialPieDate, false)
        updateChartInteractivity(
            distributionSection.stackChartView,
            distributionSection.pieChartView,
            isPieActive = true
        )
        showLoadedSection(distributionSection)
    }

    private fun showSectionLoading(section: ChartSection) {
        prepareSectionForPlaceholder(section)
        showLoadingSection(section)
    }

    private fun showSectionStatus(section: ChartSection) {
        prepareSectionForPlaceholder(section)
        showStatusSection(section)
        updateSectionTheme(section)
    }

    private fun applySectionStyle(section: ChartSection) {
        section.stackChartView.style = chartStyle
        section.pieChartView.style = chartStyle
        section.checkBoxes.values.forEach { it.style = chartStyle }
        section.chartFrame.setBackgroundColor(WColor.Background.color)
        section.chartHeaderView.setBackgroundColor(WColor.Background.color)
    }

    private fun updateSectionTheme(section: ChartSection) {
        applyCardBackground(section.container)
        section.chartSkeletonPlaceholder.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        section.skeletonView.updateTheme()
        section.chartHeaderView.updateTheme()
        section.stackChartView.updateTheme()
        section.pieChartView.updateTheme()
        section.stackChartView.legendSignatureView.recolor()
        section.pieChartView.legendSignatureView.recolor()
        updateCheckBoxColors(section.stackChartView, section.checkBoxes)
    }

    private fun showLoadingSection(section: ChartSection) {
        resetSectionHeightAnimation(section)
        section.chartHeaderView.alpha = 1f
        section.chartHeaderView.visibility = View.INVISIBLE
        section.chartFrame.alpha = 1f
        section.chartFrame.visibility = View.INVISIBLE
        section.chartSkeletonPlaceholder.visibility = View.VISIBLE
        section.chipGroup.alpha = 1f
        startSectionSkeleton(section)
    }

    private fun showStatusSection(section: ChartSection) {
        resetSectionHeightAnimation(section)
        stopSectionSkeleton(section, animated = false)
        section.chartHeaderView.alpha = 1f
        section.chartHeaderView.visibility = View.VISIBLE
        section.chartFrame.alpha = 1f
        section.chartFrame.visibility = View.VISIBLE
        section.chartSkeletonPlaceholder.visibility = View.GONE
        section.chipGroup.alpha = 1f
    }

    private fun showLoadedSection(section: ChartSection) {
        if (!section.skeletonView.isAnimating) {
            resetSectionHeightAnimation(section)
            stopSectionSkeleton(section, animated = false)
            section.chartHeaderView.alpha = 1f
            section.chartHeaderView.visibility = View.VISIBLE
            section.chartFrame.alpha = 1f
            section.chartFrame.visibility = View.VISIBLE
            section.chartSkeletonPlaceholder.visibility = View.GONE
            section.chipGroup.alpha = 1f
            return
        }

        val reveal = {
            section.chartHeaderView.visibility = View.VISIBLE
            section.chartHeaderView.alpha = 0f
            section.chartFrame.visibility = View.VISIBLE
            section.chartFrame.alpha = 0f
            section.chipGroup.alpha = if (section.chipGroup.isVisible) 0f else 1f
            animateChipGroupReveal(section)

            buildList {
                add(section.chartHeaderView)
                add(section.chartFrame)
            }.fadeIn()

            stopSectionSkeleton(section, animated = true)
        }

        if (section.container.width > 0) {
            reveal()
        } else {
            section.container.post(reveal)
        }
    }

    private fun startSectionSkeleton(section: ChartSection) {
        section.skeletonView.animate().cancel()
        section.skeletonView.alpha = 1f
        val mask = {
            section.skeletonView.applyMask(
                listOf(section.chartSkeletonPlaceholder),
                hashMapOf(0 to ViewConstants.BLOCK_RADIUS.dp)
            )
            section.skeletonView.startAnimating()
        }
        if (section.chartSkeletonPlaceholder.width > 0 && section.chartSkeletonPlaceholder.height > 0) {
            mask()
        } else {
            section.container.post(mask)
        }
    }

    private fun stopSectionSkeleton(section: ChartSection, animated: Boolean) {
        section.skeletonView.animate().cancel()
        if (!section.skeletonView.isAnimating) {
            section.skeletonView.alpha = 1f
            section.skeletonView.visibility = View.GONE
            section.chartSkeletonPlaceholder.visibility = View.GONE
            return
        }

        if (!animated) {
            section.skeletonView.alpha = 1f
            section.skeletonView.stopAnimating()
            section.chartSkeletonPlaceholder.visibility = View.GONE
            return
        }

        section.skeletonView.fadeOut {
            section.skeletonView.alpha = 1f
            section.skeletonView.stopAnimating()
            section.chartSkeletonPlaceholder.visibility = View.GONE
        }
    }

    private fun prepareSectionForPlaceholder(section: ChartSection) {
        zoomOut(section, animated = false)
        section.chartData = null
        clearSectionCharts(section.stackChartView, section.pieChartView)
        updateChartInteractivity(section.stackChartView, section.pieChartView, isPieActive = false)
    }

    private fun clearSectionCharts(chartView: BaseChartView<*, *>, pieChartView: PieChartView) {
        chartView.setData(null)
        pieChartView.setData(null)
        chartView.legendSignatureView.visibility = View.GONE
        pieChartView.legendSignatureView.visibility = View.GONE
    }

    private fun animateChipGroupReveal(section: ChartSection) {
        val chipGroup = section.chipGroup
        if (!chipGroup.isVisible) {
            resetSectionHeightAnimation(section)
            return
        }

        val availableWidth =
            (section.container.width - section.container.paddingLeft - section.container.paddingRight)
                .coerceAtLeast(0)
        chipGroup.measure(
            View.MeasureSpec.makeMeasureSpec(availableWidth, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val targetHeight = chipGroup.measuredHeight
        if (targetHeight <= 0) {
            resetSectionHeightAnimation(section)
            return
        }

        section.heightAnimator?.cancel()
        val layoutParams = chipGroup.layoutParams
        layoutParams.height = 0
        chipGroup.layoutParams = layoutParams
        chipGroup.alpha = 0f

        section.heightAnimator = ValueAnimator.ofInt(0, targetHeight).apply {
            duration = 220L
            addUpdateListener { animation ->
                layoutParams.height = animation.animatedValue as Int
                chipGroup.layoutParams = layoutParams
                chipGroup.alpha = animation.animatedFraction
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    resetSectionHeightAnimation(section)
                }

                override fun onAnimationCancel(animation: Animator) {
                    resetSectionHeightAnimation(section)
                }
            })
            start()
        }
    }

    private fun resetSectionHeightAnimation(section: ChartSection) {
        section.heightAnimator?.removeAllListeners()
        section.heightAnimator?.cancel()
        section.heightAnimator = null
        val layoutParams = section.chipGroup.layoutParams
        layoutParams.height = WRAP_CONTENT
        section.chipGroup.layoutParams = layoutParams
        section.chipGroup.alpha = 1f
    }

    private fun zoomIntoPieFromLegend(section: ChartSection) {
        if (section.mode != ChartMode.STACK) return
        if (!section.stackChartView.legendSignatureView.canGoZoom) return
        val date = section.stackChartView.getPickerCenterDate()
        if (date < 0) return
        zoomIntoPie(section, date)
    }

    private fun zoomIntoPie(section: ChartSection, date: Long) {
        val data = section.chartData ?: return
        if (section.lineEnabledById.values.count { it } <= 1) return

        if (section.mode == ChartMode.PIE) {
            section.pieChartView.updatePicker(data, date)
            return
        }

        section.lastStackPickerSpan = section.stackChartView.getPickerWindowSpan()
        section.transitionAnimator?.cancel()
        section.pieChartView.setData(data)
        section.pieChartView.updateTheme()
        syncLineEnabledState(section.pieChartView, section.lineEnabledById)
        section.pieChartView.updatePicker(data, date)
        section.pieChartView.visibility = View.VISIBLE
        section.pieChartView.legendSignatureView.visibility = View.GONE
        updateChartInteractivity(
            section.stackChartView,
            section.pieChartView,
            isPieActive = true,
            isTransitioning = true
        )

        val params = TransitionParams().apply {
            pickerStartOut = section.stackChartView.pickerDelegate.pickerStart
            pickerEndOut = section.stackChartView.pickerDelegate.pickerEnd
            this.date = date
        }
        section.stackChartView.fillTransitionParams(params)
        section.pieChartView.fillTransitionParams(params)
        section.transitionParams = params

        section.stackChartView.transitionMode = BaseChartView.TRANSITION_MODE_PARENT
        section.pieChartView.transitionMode = BaseChartView.TRANSITION_MODE_CHILD
        section.stackChartView.transitionParams = params
        section.pieChartView.transitionParams = params
        section.chartHeaderView.zoomTo(date, true)

        section.transitionAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 220L
            addUpdateListener { animation ->
                params.progress = animation.animatedValue as Float
                section.stackChartView.invalidate()
                section.pieChartView.invalidate()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    section.mode = ChartMode.PIE
                    section.stackChartView.visibility = View.GONE
                    section.stackChartView.legendSignatureView.visibility = View.GONE
                    updateChartInteractivity(
                        section.stackChartView,
                        section.pieChartView,
                        isPieActive = true
                    )
                    resetSectionTransitions(section)
                }
            })
            start()
        }
    }

    private fun zoomOut(section: ChartSection, animated: Boolean) {
        val data = section.chartData
        section.transitionAnimator?.cancel()

        if (section.mode == ChartMode.STACK || data == null) {
            section.mode = ChartMode.STACK
            section.stackChartView.visibility = View.VISIBLE
            section.pieChartView.visibility = View.GONE
            section.pieChartView.setData(null)
            section.stackChartView.clearSelection()
            section.pieChartView.clearSelection()
            section.chartHeaderView.zoomOut(section.stackChartView, animated)
            updateChartInteractivity(
                section.stackChartView,
                section.pieChartView,
                isPieActive = false
            )
            resetSectionTransitions(section)
            return
        }

        restoreStackPickerRange(
            chartView = section.stackChartView,
            pieChartView = section.pieChartView,
            data = data,
            preferredSpan = section.lastStackPickerSpan,
        )
        val params = section.transitionParams ?: TransitionParams().apply {
            pickerStartOut = section.stackChartView.pickerDelegate.pickerStart
            pickerEndOut = section.stackChartView.pickerDelegate.pickerEnd
            date = section.pieChartView.getPickerCenterDate().takeIf { it >= 0 } ?: data.x.last()
        }
        syncLineEnabledState(section.stackChartView, section.lineEnabledById)
        section.stackChartView.fillTransitionParams(params)
        section.pieChartView.fillTransitionParams(params)
        section.transitionParams = params

        section.stackChartView.visibility = View.VISIBLE
        section.stackChartView.transitionMode = BaseChartView.TRANSITION_MODE_PARENT
        section.pieChartView.transitionMode = BaseChartView.TRANSITION_MODE_CHILD
        section.stackChartView.transitionParams = params
        section.pieChartView.transitionParams = params
        section.chartHeaderView.zoomOut(section.stackChartView, animated)
        updateChartInteractivity(
            section.stackChartView,
            section.pieChartView,
            isPieActive = false,
            isTransitioning = true
        )

        if (!animated) {
            section.mode = ChartMode.STACK
            section.pieChartView.visibility = View.GONE
            section.pieChartView.setData(null)
            section.stackChartView.clearSelection()
            section.pieChartView.clearSelection()
            updateChartInteractivity(
                section.stackChartView,
                section.pieChartView,
                isPieActive = false
            )
            resetSectionTransitions(section)
            return
        }

        section.transitionAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = 220L
            addUpdateListener { animation ->
                params.progress = animation.animatedValue as Float
                section.stackChartView.invalidate()
                section.pieChartView.invalidate()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    section.mode = ChartMode.STACK
                    section.pieChartView.visibility = View.GONE
                    section.pieChartView.setData(null)
                    section.stackChartView.clearSelection()
                    section.pieChartView.clearSelection()
                    updateChartInteractivity(
                        section.stackChartView,
                        section.pieChartView,
                        isPieActive = false
                    )
                    resetSectionTransitions(section)
                }
            })
            start()
        }
    }

    private fun resetSectionTransitions(section: ChartSection) {
        section.transitionParams = null
        resetTransitions(section.stackChartView, section.pieChartView)
    }

    private fun restoreStackPickerRange(
        chartView: BaseChartView<*, *>,
        pieChartView: PieChartView,
        data: StackLinearChartData?,
        preferredSpan: Int,
    ) {
        data ?: return
        if (data.x.isEmpty()) return
        val lastIndex = data.x.lastIndex
        if (lastIndex <= 0) {
            chartView.setPickerByIndices(0, 0)
            return
        }

        val anchorIndex = pieChartView.getPickerCenterIndex()
        val fallbackSpan = chartView.getPickerWindowSpan()
        val safeAnchorIndex = anchorIndex.coerceIn(0, lastIndex)
        val desiredSpan = preferredSpan.takeIf { it > 0 }?.coerceIn(1, lastIndex)
            ?: fallbackSpan.coerceIn(1, lastIndex)
        var startIndex = safeAnchorIndex - desiredSpan / 2
        var endIndex = startIndex + desiredSpan

        if (startIndex < 0) {
            endIndex = (endIndex - startIndex).coerceAtMost(lastIndex)
            startIndex = 0
        }
        if (endIndex > lastIndex) {
            startIndex = (startIndex - (endIndex - lastIndex)).coerceAtLeast(0)
            endIndex = lastIndex
        }

        chartView.setPickerByIndices(startIndex, endIndex)
    }

    private fun syncLineEnabledState(section: ChartSection, data: StackLinearChartData?) {
        val lineEnabledById = section.lineEnabledById
        val previousState = lineEnabledById.toMap()
        lineEnabledById.clear()
        data?.lines?.forEach { line ->
            lineEnabledById[line.id] = previousState[line.id] ?: true
        }
    }

    private fun renderSeriesControls(data: StackLinearChartData?) {
        renderSeriesControls(absoluteSection, data)
        renderSeriesControls(distributionSection, data)
    }

    private fun syncSeriesControlsPresentation() {
        updateCheckBoxColors(absoluteSection.stackChartView, absoluteSection.checkBoxes)
        updateCheckBoxColors(distributionSection.stackChartView, distributionSection.checkBoxes)
        updateLegendZoomAvailability()
    }

    private fun renderSeriesControls(section: ChartSection, data: StackLinearChartData?) {
        section.chipGroup.removeAllViews()
        section.checkBoxes.clear()

        val lines = data?.lines?.takeIf { it.size > 1 } ?: run {
            section.chipGroup.visibility = View.GONE
            return
        }

        lines.forEach { line ->
            val checkBox = FlatCheckBox(context).apply {
                setText(line.name)
                recolor(line.color)
                setChecked(section.lineEnabledById[line.id] != false, false)
                setOnClickListener { toggleDataset(section, line.id) }
            }
            section.checkBoxes[line.id] = checkBox
            section.chipGroup.addView(checkBox, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
        section.chipGroup.visibility = View.VISIBLE
    }

    private fun toggleDataset(section: ChartSection, id: String) {
        val lineEnabledById = section.lineEnabledById
        val currentlyEnabled = lineEnabledById[id] != false
        val enabledCount = lineEnabledById.values.count { it }
        if (currentlyEnabled && enabledCount <= 1) {
            section.checkBoxes[id]?.denied()
            refreshCheckBoxState(section.checkBoxes, lineEnabledById, animate = false)
            return
        }

        lineEnabledById[id] = !currentlyEnabled
        if (section.mode == ChartMode.PIE && lineEnabledById.values.count { it } <= 1) {
            zoomOut(section, animated = true)
        }
        refreshCheckBoxState(section.checkBoxes, lineEnabledById)
        applyLineEnabledState(section)
    }

    private fun refreshCheckBoxState(
        checkBoxes: Map<String, FlatCheckBox>,
        lineEnabledById: Map<String, Boolean>,
        animate: Boolean = true,
    ) {
        checkBoxes.forEach { (id, checkBox) ->
            checkBox.setChecked(lineEnabledById[id] != false, animate)
        }
    }

    private fun applyLineEnabledState(section: ChartSection) {
        val (active, inactive) = if (section.mode == ChartMode.PIE)
            section.pieChartView to section.stackChartView
        else
            section.stackChartView to section.pieChartView
        applyLineEnabledState(active, inactive, section.lineEnabledById)
    }

    private fun applyLineEnabledState(
        activeChartView: BaseChartView<*, *>,
        inactiveChartView: BaseChartView<*, *>,
        lineEnabledById: Map<String, Boolean>,
    ) {
        if (activeChartView.lines.isEmpty()) return
        activeChartView.lines.forEach { lineViewData ->
            lineViewData.enabled = lineEnabledById[lineViewData.line.id] != false
        }
        activeChartView.onCheckChanged()
        syncLineEnabledState(inactiveChartView, lineEnabledById)
    }

    private fun syncLineEnabledState(
        chartView: BaseChartView<*, *>,
        lineEnabledById: Map<String, Boolean>,
    ) {
        if (chartView.lines.isEmpty()) return

        var changed = false
        chartView.lines.forEach { lineViewData ->
            val isEnabled = lineEnabledById[lineViewData.line.id] != false
            if (lineViewData.enabled != isEnabled || lineViewData.alpha != if (isEnabled) 1f else 0f) {
                changed = true
            }
            lineViewData.animatorIn?.cancel()
            lineViewData.animatorOut?.cancel()
            lineViewData.enabled = isEnabled
            lineViewData.alpha = if (isEnabled) 1f else 0f
        }

        if (!changed) return

        chartView.invalidatePickerChart = true
        chartView.onPickerDataChanged(false, true, false)
        chartView.invalidate()
    }

    private fun updateCheckBoxColors(
        chartView: BaseChartView<*, *>,
        checkBoxes: Map<String, FlatCheckBox>,
    ) {
        chartView.lines.forEach { lineViewData ->
            val lineColor =
                if (lineViewData.line.color != 0) lineViewData.line.color else lineViewData.lineColor
            checkBoxes[lineViewData.line.id]?.recolor(lineColor)
        }
    }

    private fun updateLegendZoomAvailability() {
        updateLegendZoomAvailability(absoluteSection)
        updateLegendZoomAvailability(distributionSection)
    }

    private fun updateLegendZoomAvailability(section: ChartSection) {
        val canZoom = section.chartData != null && section.lineEnabledById.values.count { it } > 1
        section.stackChartView.legendSignatureView.zoomEnabled = canZoom
        section.stackChartView.legendSignatureView.isClickable = canZoom
        section.stackChartView.legendSignatureView.isFocusable = canZoom
        if (!canZoom) {
            section.stackChartView.legendSignatureView.showProgress(show = false, force = true)
        }
        section.stackChartView.moveLegend()
    }

    private fun updateChartInteractivity(
        chartView: BaseChartView<*, *>,
        pieChartView: PieChartView,
        isPieActive: Boolean,
        isTransitioning: Boolean = false,
    ) {
        val isChartInteractive = !isTransitioning && !isPieActive
        val isPieInteractive = !isTransitioning && isPieActive

        chartView.isEnabled = isChartInteractive
        chartView.isClickable = isChartInteractive
        chartView.isFocusable = isChartInteractive

        pieChartView.isEnabled = isPieInteractive
        pieChartView.isClickable = isPieInteractive
        pieChartView.isFocusable = isPieInteractive
    }

    private fun resetTransitions(chartView: BaseChartView<*, *>, pieChartView: PieChartView) {
        chartView.transitionMode = BaseChartView.TRANSITION_MODE_NONE
        pieChartView.transitionMode = BaseChartView.TRANSITION_MODE_NONE
        chartView.transitionParams = null
        pieChartView.transitionParams = null
        chartView.invalidate()
        pieChartView.invalidate()
    }

    private fun configureChartValueFormatting(baseCurrency: MBaseCurrency) {
        val absoluteFormatter = createAbsoluteChartValueFormatter(baseCurrency)
        absoluteSection.stackChartView.valueFormatter = absoluteFormatter
        absoluteSection.stackChartView.legendSignatureView.useCompactValueFormatting = false
        absoluteSection.stackChartView.legendSignatureView.footerLabel =
            LocaleController.getString("Total")
        absoluteSection.pieChartView.valueFormatter = absoluteFormatter

        val distributionFormatter = createDistributionChartValueFormatter(baseCurrency)
        distributionSection.stackChartView.valueFormatter = distributionFormatter
        distributionSection.pieChartView.valueFormatter = distributionFormatter
    }

    private fun applyCardBackground(container: View) {
        container.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
    }

    private fun createAbsoluteSection(): ChartSection {
        val headerView = HeaderCell(context).apply {
            id = ViewGroup.generateViewId()
            configure(
                title = LocaleController.getString("Total Value"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.FIRST_ITEM
            )
        }
        val descriptionView = WLabel(context).apply {
            text = LocaleController.getString("Tracked asset value over time.")
            setStyle(14f, WFont.Regular)
            setPadding(0, 6.dp, 0, 6.dp)
            setTextColor(WColor.SecondaryText)
        }
        val chartHeaderView = ChartHeaderView(context).apply {
            id = ViewGroup.generateViewId()
        }
        val stackChartView = StackLinearChartView<StackLinearViewData>(context).apply {
            id = ViewGroup.generateViewId()
            style = chartStyle
            valueMode = StackLinearChartView.ValueMode.ABSOLUTE
            animatePickerDuringLineAnimation = true
            pickerMode = ChartPickerDelegate.PickerMode.RANGE
            setHeader(chartHeaderView)
        }
        val pieChartView = PieChartView(context).apply {
            id = ViewGroup.generateViewId()
            style = chartStyle
            animatePickerDuringLineAnimation = true
            valueMode = StackLinearChartView.ValueMode.ABSOLUTE
            pickerMode = ChartPickerDelegate.PickerMode.SINGLE
            setHeader(chartHeaderView)
            visibility = View.GONE
        }
        val chartFrame = createChartFrame(
            chartView = stackChartView,
            pieChartView = pieChartView,
            legendView = stackChartView.legendSignatureView,
            pieLegendView = pieChartView.legendSignatureView,
        )
        val chartSkeletonPlaceholder = createChartSkeletonPlaceholder()
        val chipGroup = createSeriesChipGroup()
        val skeletonView = createChartSkeletonView()

        return ChartSection(
            container = buildSectionContainer(
                headerView, descriptionView, chartHeaderView,
                chartFrame, chartSkeletonPlaceholder, skeletonView, chipGroup,
            ),
            chartFrame = chartFrame,
            chartSkeletonPlaceholder = chartSkeletonPlaceholder,
            chartHeaderView = chartHeaderView,
            stackChartView = stackChartView,
            pieChartView = pieChartView,
            chipGroup = chipGroup,
            skeletonView = skeletonView,
        )
    }

    private fun createDistributionSection(): ChartSection {
        val headerView = HeaderCell(context).apply {
            id = ViewGroup.generateViewId()
            configure(
                title = LocaleController.getString("Portfolio Share"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.FIRST_ITEM
            )
        }
        val descriptionView = WLabel(context).apply {
            text = LocaleController.getString("Current allocation across tracked assets.")
            setStyle(14f, WFont.Regular)
            setPadding(0, 6.dp, 0, 6.dp)
            setTextColor(WColor.SecondaryText)
        }
        val chartHeaderView = ChartHeaderView(context).apply {
            id = ViewGroup.generateViewId()
        }
        val stackChartView = StackLinearChartView<StackLinearViewData>(context).apply {
            id = ViewGroup.generateViewId()
            style = chartStyle
            valueMode = StackLinearChartView.ValueMode.RELATIVE
            animatePickerDuringLineAnimation = true
            pickerMode = ChartPickerDelegate.PickerMode.RANGE
            setHeader(chartHeaderView)
            legendSignatureView.showPercentage = true
            legendSignatureView.percentageFormatter = { ratio ->
                val percent = 100f * ratio
                if (percent < 10f && percent != 0f) {
                    String.format(Locale.ENGLISH, "%.1f%%", percent)
                } else {
                    "${Math.round(percent)}%"
                }
            }
        }
        val pieChartView = PieChartView(context).apply {
            id = ViewGroup.generateViewId()
            style = chartStyle
            animatePickerDuringLineAnimation = true
            valueMode = StackLinearChartView.ValueMode.RELATIVE
            pickerMode = ChartPickerDelegate.PickerMode.SINGLE
            setHeader(chartHeaderView)
            visibility = View.GONE
        }
        val chartFrame = createChartFrame(
            chartView = stackChartView,
            pieChartView = pieChartView,
            legendView = stackChartView.legendSignatureView,
            pieLegendView = pieChartView.legendSignatureView,
        )
        val chartSkeletonPlaceholder = createChartSkeletonPlaceholder()
        val chipGroup = createSeriesChipGroup()
        val skeletonView = createChartSkeletonView()

        return ChartSection(
            container = buildSectionContainer(
                headerView, descriptionView, chartHeaderView,
                chartFrame, chartSkeletonPlaceholder, skeletonView, chipGroup,
            ),
            chartFrame = chartFrame,
            chartSkeletonPlaceholder = chartSkeletonPlaceholder,
            chartHeaderView = chartHeaderView,
            stackChartView = stackChartView,
            pieChartView = pieChartView,
            chipGroup = chipGroup,
            skeletonView = skeletonView,
        )
    }

    private fun buildSectionContainer(
        headerView: View,
        descriptionView: View,
        chartHeaderView: View,
        chartFrame: View,
        chartSkeletonPlaceholder: View,
        skeletonView: View,
        chipGroup: View,
    ): WView {
        return WView(context).apply {
            addView(headerView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(descriptionView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(chartSkeletonPlaceholder, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 0))
            addView(skeletonView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
            addView(chartHeaderView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(chartFrame, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(chipGroup, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            setConstraints {
                toTop(headerView)
                toCenterX(headerView)
                topToBottom(descriptionView, headerView, 6f)
                toCenterX(descriptionView, 20f)
                topToBottom(chartHeaderView, descriptionView, ViewConstants.GAP.toFloat())
                toCenterX(chartHeaderView)
                topToBottom(chartFrame, chartHeaderView)
                toCenterX(chartFrame)
                topToBottom(chipGroup, chartFrame)
                toCenterX(chipGroup, ViewConstants.GAP.toFloat())
                toBottom(chipGroup, ViewConstants.GAP.toFloat())
                topToTop(chartSkeletonPlaceholder, chartHeaderView)
                toCenterX(chartSkeletonPlaceholder, ViewConstants.GAP.toFloat())
                bottomToBottom(chartSkeletonPlaceholder, chartFrame, ViewConstants.GAP.toFloat())
                topToTop(skeletonView, chartHeaderView)
                toCenterX(skeletonView, ViewConstants.GAP.toFloat())
                bottomToBottom(skeletonView, chartFrame)
            }
        }
    }

    private fun createChartFrame(
        chartView: View,
        pieChartView: View,
        legendView: LegendSignatureView,
        pieLegendView: LegendSignatureView,
    ): FrameLayout {
        return FrameLayout(context).apply {
            id = ViewGroup.generateViewId()
            setPadding(0, ViewConstants.GAP.dp, 0, 0)
            addView(chartView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(pieChartView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(legendView, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                setMargins(0, 8.dp, 0, 0)
            })
            addView(pieLegendView, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                setMargins(0, 8.dp, 0, 0)
            })
        }
    }

    private fun createChartSkeletonView(): SkeletonView {
        return SkeletonView(context).apply {
            id = ViewGroup.generateViewId()
            alpha = 0f
        }
    }

    private fun createChartSkeletonPlaceholder(): WBaseView {
        return WBaseView(context).apply {
            id = ViewGroup.generateViewId()
            visibility = View.GONE
            setBackgroundColor(WColor.SecondaryBackground.color, ViewConstants.BLOCK_RADIUS.dp)
        }
    }

    private fun createSeriesChipGroup(): ChipGroup {
        return ChipGroup(context).apply {
            id = ViewGroup.generateViewId()
            isSingleLine = false
            chipSpacingHorizontal = 8.dp
            chipSpacingVertical = 8.dp
            visibility = View.GONE
        }
    }

    private fun createChartLayoutParams(topMargin: Int = 0): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            this.topMargin = topMargin
        }
    }

    private fun createAbsoluteChartValueFormatter(baseCurrency: MBaseCurrency): ChartValueFormatter {
        return object : ChartValueFormatter {
            override fun formatAxisValue(value: Long, paint: TextPaint): CharSequence =
                formatCurrencyAxisValue(value, baseCurrency)

            override fun formatLegendValue(value: Long, paint: TextPaint): CharSequence =
                formatCurrencyLegendValue(value, baseCurrency)
        }
    }

    private fun createDistributionChartValueFormatter(baseCurrency: MBaseCurrency): ChartValueFormatter {
        return object : ChartValueFormatter {
            override fun formatAxisValue(value: Long, paint: TextPaint): CharSequence = "${value}%"

            override fun formatLegendValue(value: Long, paint: TextPaint): CharSequence =
                formatCurrencyLegendValue(value, baseCurrency)
        }
    }

    private fun formatCurrencyLegendValue(value: Long, baseCurrency: MBaseCurrency): String {
        return BigInteger.valueOf(value).toString(
            decimals = baseCurrency.decimalsCount,
            currency = baseCurrency.sign,
            currencyDecimals = baseCurrency.decimalsCount,
            showPositiveSign = false,
        )
    }

    private fun formatCurrencyAxisValue(value: Long, baseCurrency: MBaseCurrency): String {
        val formattedNumber = compactScaledNumber(
            value = value,
            decimals = baseCurrency.decimalsCount,
            maxFractionDigits = 1,
        )
        return applyCurrencyPosition(formattedNumber, baseCurrency.sign)
    }

    private fun compactScaledNumber(value: Long, decimals: Int, maxFractionDigits: Int): String {
        val suffixes = arrayOf("", "K", "M", "B", "T")
        var scaledValue = abs(value.toDouble()) / 10.0.pow(decimals.toDouble())
        var suffixIndex = 0
        while (scaledValue >= 1_000.0 && suffixIndex < suffixes.lastIndex) {
            scaledValue /= 1_000.0
            suffixIndex++
        }

        val formattedValue = DecimalFormat(
            buildString {
                append("#")
                if (maxFractionDigits > 0) {
                    append('.')
                    repeat(maxFractionDigits) { append('#') }
                }
            },
            DecimalFormatSymbols(Locale.US).apply { decimalSeparator = '.' }
        ).format(scaledValue)

        val sign = if (value < 0) "-" else ""
        return sign + formattedValue + suffixes[suffixIndex]
    }

    private fun applyCurrencyPosition(value: String, currency: String): String {
        return if (currency.length > 1 || currency in MBaseCurrency.forcedToRight) {
            "$value $currency"
        } else {
            "$currency$value"
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        contentLayout.setPadding(
            ViewConstants.GAP.dp, 0, ViewConstants.GAP.dp,
            (navigationController?.bottomInset ?: 0) + 24.dp
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        viewModel.onDestroy()
    }

    private data class ChartSection(
        val container: WView,
        val chartFrame: FrameLayout,
        val chartSkeletonPlaceholder: WBaseView,
        val chartHeaderView: ChartHeaderView,
        val stackChartView: StackLinearChartView<StackLinearViewData>,
        val pieChartView: PieChartView,
        val chipGroup: ChipGroup,
        val skeletonView: SkeletonView,
        val checkBoxes: LinkedHashMap<String, FlatCheckBox> = linkedMapOf(),
        val lineEnabledById: LinkedHashMap<String, Boolean> = linkedMapOf(),
        var chartData: StackLinearChartData? = null,
        var mode: ChartMode = ChartMode.STACK,
        var lastStackPickerSpan: Int = 0,
        var transitionParams: TransitionParams? = null,
        var transitionAnimator: ValueAnimator? = null,
        var heightAnimator: ValueAnimator? = null,
    )

    private enum class ChartMode { STACK, PIE }
}
