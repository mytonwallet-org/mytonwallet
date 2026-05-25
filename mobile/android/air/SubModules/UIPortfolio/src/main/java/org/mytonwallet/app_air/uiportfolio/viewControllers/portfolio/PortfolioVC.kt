package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
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
import android.view.Gravity
import com.google.android.material.chip.ChipGroup
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.widgets.PillShadowView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.segmentedControlGroup.WSegmentedControlGroup
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.BarChartView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.BaseChartView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartData
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartHeaderView
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.LinearChartView
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
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioChartKind
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioUiState
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.views.BreakdownSectionView
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.views.OverviewSectionView
import java.lang.ref.WeakReference
import androidx.core.view.isInvisible

@SuppressLint("ViewConstructor")
class PortfolioVC(context: Context) : WViewControllerWithModelStore(context) {
    override val TAG = "Portfolio"

    override val topBarConfiguration: ReversedCornerView.Config
        get() = super.topBarConfiguration.copy(blurRootView = scrollView)

    private val viewModel by lazy {
        ViewModelProvider(this)[PortfolioVM::class.java]
    }

    private val scrollView = WScrollView(WeakReference(this)).apply {
        overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
        isVerticalScrollBarEnabled = false
        onScrollStateChange = {
            updateBlurViews(this)
        }
        setOnScrollChangeListener { _, _, _, _, _ ->
            updateBlurViews(this)
        }
    }
    private val contentLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
    }
    private var chartStyle = ChartStyle.default()
    private val overviewSection = OverviewSectionView(context)
    private val breakdownSection = BreakdownSectionView(context)
    private val absoluteSection = createAbsoluteSection()
    private val distributionSection = createDistributionSection()
    private val totalPnlSection = createSimpleSection(
        LocaleController.getString("Total P&L"),
        LinearChartView(context).apply { allowNegativeValues = true },
        PortfolioChartKind.TOTAL_PNL,
    )
    private val dailyPnlSection = createSimpleSection(
        LocaleController.getString("Daily P&L"),
        BarChartView(context),
        PortfolioChartKind.DAILY_PNL,
    )
    private val sharedSkeletonView = SkeletonView(context).apply {
        id = ViewGroup.generateViewId()
        alpha = 0f
    }
    private val periodSelector = createPeriodSelector()
    private val periodSelectorContainer = WFrameLayout(context).apply {
        id = ViewGroup.generateViewId()
        clipChildren = false
        clipToPadding = false
        setPaddingDp(8, 4, 8, 8)
        addView(periodSelector, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setOnClickListener {}
    }
    private var periodSelectorShadow: PillShadowView? = null

    // While fading placeholders in over the prior content, defer applying the new
    // Loaded state until placeholders are fully opaque so the swap is invisible.
    private var placeholdersReady = true
    private var pendingLoaded: PortfolioUiState.Loaded? = null
    private var lastObservedState: PortfolioUiState = PortfolioUiState.Idle

    override val shouldDisplayBottomBar: Boolean
        get() = navigationController?.tabBarController == null

    override fun setupViews() {
        super.setupViews()

        title = LocaleController.getString("Portfolio")
        setupNavBar(true)

        scrollView.addView(contentLayout, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        contentLayout.addView(overviewSection, createChartLayoutParams())
        contentLayout.addView(
            breakdownSection,
            createChartLayoutParams(topMargin = ViewConstants.GAP.dp, horizontalMargin = 0)
        )
        contentLayout.addView(
            absoluteSection.container,
            createChartLayoutParams(topMargin = ViewConstants.GAP.dp)
        )
        contentLayout.addView(
            distributionSection.container,
            createChartLayoutParams(topMargin = ViewConstants.GAP.dp)
        )
        contentLayout.addView(
            totalPnlSection.container,
            createChartLayoutParams(topMargin = ViewConstants.GAP.dp)
        )
        contentLayout.addView(
            dailyPnlSection.container,
            createChartLayoutParams(topMargin = ViewConstants.GAP.dp)
        )

        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
        view.addView(
            sharedSkeletonView,
            ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
        )
        view.addView(
            periodSelectorContainer,
            ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, PERIOD_SELECTOR_SECTION_HEIGHT.dp)
        )
        periodSelectorShadow = PillShadowView.attachTo(periodSelector, 24f.dp)
        periodSelector.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            periodSelectorShadow?.sync()
        }

        view.setConstraints {
            topToBottom(scrollView, navigationBar!!)
            toCenterX(scrollView)
            bottomToBottom(scrollView, view)
            allEdges(sharedSkeletonView)
            toCenterX(periodSelectorContainer, 8f)
            toBottomPx(
                periodSelectorContainer,
                (navigationController?.getSystemBars()?.bottom ?: 0)
            )
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
        overviewSection.updateTheme()
        breakdownSection.updateTheme()
        sharedSkeletonView.updateTheme()
        applySectionStyle(absoluteSection)
        applySectionStyle(distributionSection)
        updateSectionTheme(absoluteSection)
        updateSectionTheme(distributionSection)
        applySimpleSectionStyle(totalPnlSection)
        applySimpleSectionStyle(dailyPnlSection)
        updateSimpleSectionTheme(totalPnlSection)
        updateSimpleSectionTheme(dailyPnlSection)
        periodSelector.updateTheme()
        periodSelector.setBackgroundColor(WColor.Background.color, 24f.dp)
        periodSelector.setSliderColor(WColor.SecondaryBackground.color)
    }

    private fun startSharedSkeleton(
        animated: Boolean = false,
        onFadeInComplete: (() -> Unit)? = null,
    ) {
        sharedSkeletonView.animate().cancel()
        if (animated) {
            sharedSkeletonView.fadeIn(onCompletion = onFadeInComplete)
        } else {
            sharedSkeletonView.alpha = 1f
            onFadeInComplete?.invoke()
        }
        val apply = {
            val targets = buildList {
                addAll(overviewSection.maskTargets())
                addAll(breakdownSection.maskTargets())
                add(absoluteSection.chartSkeletonPlaceholder to ViewConstants.BLOCK_RADIUS.dp)
                add(distributionSection.chartSkeletonPlaceholder to ViewConstants.BLOCK_RADIUS.dp)
                add(totalPnlSection.chartSkeletonPlaceholder to ViewConstants.BLOCK_RADIUS.dp)
                add(dailyPnlSection.chartSkeletonPlaceholder to ViewConstants.BLOCK_RADIUS.dp)
                add(absoluteSection.chartHeaderView.datesPlaceholder to 4f.dp)
                add(distributionSection.chartHeaderView.datesPlaceholder to 4f.dp)
                add(totalPnlSection.chartHeaderView.datesPlaceholder to 4f.dp)
                add(dailyPnlSection.chartHeaderView.datesPlaceholder to 4f.dp)
            }
            val views = targets.map { it.first }
            val radii = HashMap<Int, Float>().apply {
                targets.forEachIndexed { index, pair -> put(index, pair.second) }
            }
            sharedSkeletonView.applyMask(views, radii)
            sharedSkeletonView.startAnimating()
        }
        if (sharedSkeletonView.width > 0) apply() else sharedSkeletonView.post(apply)
    }

    private fun stopSharedSkeleton() {
        sharedSkeletonView.fadeOut {
            sharedSkeletonView.stopAnimating()
        }
    }

    private fun observeState(state: PortfolioUiState) {
        when (state) {
            PortfolioUiState.Idle -> {
                absoluteSection.lineEnabledById.clear()
                distributionSection.lineEnabledById.clear()
                renderSeriesControls(null)
                showSectionLoading(absoluteSection)
                showSectionLoading(distributionSection)
                showSimpleSectionLoading(totalPnlSection)
                showSimpleSectionLoading(dailyPnlSection)
                overviewSection.showPlaceholders()
                breakdownSection.showPlaceholders()
                startSharedSkeleton(animated = false)
                syncSeriesControlsPresentation()
            }

            is PortfolioUiState.Loading -> {
                pendingLoaded = null
                configureChartValueFormatting(state.request.baseCurrency)
                if (!state.animated) {
                    absoluteSection.lineEnabledById.clear()
                    distributionSection.lineEnabledById.clear()
                    renderSeriesControls(null)
                    placeholdersReady = true
                } else {
                    placeholdersReady = false
                }
                showSectionLoading(absoluteSection, animated = state.animated)
                showSectionLoading(distributionSection, animated = state.animated)
                showSimpleSectionLoading(totalPnlSection, animated = state.animated)
                showSimpleSectionLoading(dailyPnlSection, animated = state.animated)
                overviewSection.showPlaceholders(animated = state.animated)
                breakdownSection.showPlaceholders(animated = state.animated)
                val period = state.request.period
                startSharedSkeleton(animated = state.animated) {
                    if (viewModel.selectedPeriod != period) return@startSharedSkeleton
                    placeholdersReady = true
                    pendingLoaded?.let {
                        pendingLoaded = null
                        applyLoaded(it)
                    }
                }
                syncSeriesControlsPresentation()
            }

            is PortfolioUiState.Loaded -> {
                if (!placeholdersReady) {
                    pendingLoaded = state
                } else if (!state.silent && lastObservedState is PortfolioUiState.Loaded) {
                    crossFadeToLoaded(state)
                } else {
                    applyLoaded(state)
                }
            }
        }
        lastObservedState = state
    }

    private fun ChartSection.crossFadeTargets(): List<View> = listOf(
        chartHeaderView.dates,
        chartHeaderView.datesTmp,
        chartFrame,
        chipGroup,
    )

    private fun crossFadeContentViews(): List<View> = buildList {
        addAll(absoluteSection.crossFadeTargets())
        addAll(distributionSection.crossFadeTargets())
        add(totalPnlSection.chartHeaderView.dates)
        add(totalPnlSection.chartHeaderView.datesTmp)
        add(totalPnlSection.chartFrame)
        add(dailyPnlSection.chartHeaderView.dates)
        add(dailyPnlSection.chartHeaderView.datesTmp)
        add(dailyPnlSection.chartFrame)
        addAll(overviewSection.crossFadeTargets())
        addAll(breakdownSection.crossFadeTargets())
    }

    private fun crossFadeToLoaded(state: PortfolioUiState.Loaded) {
        val views = crossFadeContentViews()
        val halfDuration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
        val period = state.request.period
        views.forEach { it.animate().cancel() }
        val anchor = views.first()
        for (i in 1 until views.size) {
            views[i].animate().alpha(0f).setDuration(halfDuration)
        }
        anchor.animate()
            .alpha(0f)
            .setDuration(halfDuration)
            .withEndAction {
                if (viewModel.selectedPeriod != period) return@withEndAction
                applyLoaded(state)
                views.forEach { it.alpha = 0f }
                views.forEach { it.animate().alpha(1f).setDuration(halfDuration) }
            }
    }

    private fun applyLoaded(state: PortfolioUiState.Loaded) {
        crossFadeContentViews().forEach {
            it.animate().cancel()
            it.alpha = 1f
        }
        configureChartValueFormatting(state.request.baseCurrency)
        listOf(
            absoluteSection.stackChartView,
            absoluteSection.pieChartView,
            distributionSection.stackChartView,
            distributionSection.pieChartView,
        ).forEach { it.clearSelection() }
        stopSharedSkeleton()

        // Net worth is mandatory: on failure the whole screen stays in loading — its sections AND
        // the PnL charts — while the VM auto-retries every 5s. Only once net worth is present do
        // the charts render (PnL then handling their own failures with a Try Again button).
        if (state.netWorthFailed) {
            showSectionLoading(absoluteSection, animated = true)
            showSectionLoading(distributionSection, animated = true)
            overviewSection.showPlaceholders(animated = true)
            breakdownSection.showPlaceholders(animated = true)
            showSimpleSectionLoading(totalPnlSection, animated = true)
            showSimpleSectionLoading(dailyPnlSection, animated = true)
            syncSeriesControlsPresentation()
            return
        }

        syncLineEnabledState(absoluteSection, state.chartData)
        syncLineEnabledState(distributionSection, state.chartData)
        renderSeriesControls(state.chartData)
        showAbsoluteLoaded(state.chartData)
        showDistributionLoaded(state.chartData)
        applyLineEnabledState(absoluteSection)
        applyLineEnabledState(distributionSection)
        overviewSection.render(state.overview, state.request.baseCurrency)
        breakdownSection.render(
            chainSlices = state.chainBreakdown,
            assetSlices = state.assetBreakdown,
        )
        overviewSection.hidePlaceholders()
        breakdownSection.hidePlaceholders()
        absoluteSection.chartHeaderView.hideDatesPlaceholder()
        distributionSection.chartHeaderView.hideDatesPlaceholder()

        showSimpleLoaded(totalPnlSection, state.totalPnlChartData)
        showSimpleLoaded(dailyPnlSection, state.dailyPnlChartData)
        applySectionError(
            totalPnlSection.errorView,
            totalPnlSection.chartView,
            totalPnlSection.chartFrame,
            state.totalPnlFailed,
        )
        applySectionError(
            dailyPnlSection.errorView,
            dailyPnlSection.chartView,
            dailyPnlSection.chartFrame,
            state.dailyPnlFailed,
        )
        totalPnlSection.chartHeaderView.hideDatesPlaceholder()
        dailyPnlSection.chartHeaderView.hideDatesPlaceholder()
        syncSeriesControlsPresentation()
    }

    private fun showAbsoluteLoaded(data: StackLinearChartData?) {
        val shouldUseDefaultMode = absoluteSection.chartData == null
        absoluteSection.chartData = data

        if (data == null) {
            showSectionStatus(absoluteSection)
            return
        }

        val savedSelectedDate =
            if (!shouldUseDefaultMode) absoluteSection.stackChartView.getSelectedDate() else -1L

        absoluteSection.stackChartView.setData(data)
        absoluteSection.stackChartView.updateTheme()
        syncLineEnabledState(absoluteSection.stackChartView, absoluteSection.lineEnabledById)
        absoluteSection.stackChartView.reinitPickerHeight()

        if (!shouldUseDefaultMode && absoluteSection.mode == ChartMode.PIE) {
            val pieDate = resolvePieDate(absoluteSection, data)
            absoluteSection.pieChartView.setData(data)
            absoluteSection.pieChartView.updateTheme()
            syncLineEnabledState(absoluteSection.pieChartView, absoluteSection.lineEnabledById)
            absoluteSection.pieChartView.updatePicker(data, pieDate)
            absoluteSection.mode = ChartMode.PIE
            absoluteSection.stackChartView.visibility = View.GONE
            absoluteSection.stackChartView.legendSignatureView.visibility = View.GONE
            absoluteSection.pieChartView.visibility = View.VISIBLE
            absoluteSection.chartHeaderView.zoomTo(pieDate, false)
            updateChartInteractivity(
                absoluteSection.stackChartView,
                absoluteSection.pieChartView,
                isPieActive = true
            )
            showLoadedSection(absoluteSection)
            return
        }

        absoluteSection.lastStackPickerSpan = absoluteSection.stackChartView.getPickerWindowSpan()

        absoluteSection.mode = ChartMode.STACK
        absoluteSection.pieChartView.setData(null)
        absoluteSection.stackChartView.visibility = View.VISIBLE
        absoluteSection.stackChartView.legendSignatureView.visibility = View.GONE
        absoluteSection.pieChartView.visibility = View.GONE
        absoluteSection.pieChartView.legendSignatureView.visibility = View.GONE
        absoluteSection.chartHeaderView.zoomOut(absoluteSection.stackChartView, false)
        updateChartInteractivity(
            absoluteSection.stackChartView,
            absoluteSection.pieChartView,
            isPieActive = false
        )
        if (savedSelectedDate >= 0) {
            absoluteSection.stackChartView.selectDate(savedSelectedDate)
        }
        showLoadedSection(absoluteSection)
    }

    private fun showDistributionLoaded(data: StackLinearChartData?) {
        val shouldUseDefaultMode = distributionSection.chartData == null
        distributionSection.chartData = data

        if (data == null) {
            showSectionStatus(distributionSection)
            return
        }

        val savedSelectedDate =
            if (!shouldUseDefaultMode) distributionSection.stackChartView.getSelectedDate() else -1L

        distributionSection.stackChartView.setData(data)
        distributionSection.stackChartView.updateTheme()
        syncLineEnabledState(
            distributionSection.stackChartView,
            distributionSection.lineEnabledById
        )
        distributionSection.stackChartView.reinitPickerHeight()

        val targetMode =
            if (shouldUseDefaultMode) ChartMode.PIE else distributionSection.mode

        if (targetMode == ChartMode.PIE) {
            if (shouldUseDefaultMode) {
                distributionSection.lastStackPickerSpan =
                    distributionSection.stackChartView.getPickerWindowSpan()
            }
            val pieDate = resolvePieDate(distributionSection, data)
            distributionSection.pieChartView.setData(data)
            distributionSection.pieChartView.updateTheme()
            syncLineEnabledState(
                distributionSection.pieChartView,
                distributionSection.lineEnabledById
            )
            distributionSection.pieChartView.updatePicker(data, pieDate)
            distributionSection.mode = ChartMode.PIE
            distributionSection.stackChartView.visibility = View.GONE
            distributionSection.stackChartView.legendSignatureView.visibility = View.GONE
            distributionSection.pieChartView.visibility = View.VISIBLE
            if (shouldUseDefaultMode) {
                distributionSection.pieChartView.legendSignatureView.visibility = View.GONE
            }
            distributionSection.chartHeaderView.zoomTo(pieDate, false)
            updateChartInteractivity(
                distributionSection.stackChartView,
                distributionSection.pieChartView,
                isPieActive = true
            )
            showLoadedSection(distributionSection)
            return
        }

        distributionSection.lastStackPickerSpan =
            distributionSection.stackChartView.getPickerWindowSpan()

        distributionSection.mode = ChartMode.STACK
        distributionSection.pieChartView.setData(null)
        distributionSection.stackChartView.visibility = View.VISIBLE
        distributionSection.stackChartView.legendSignatureView.visibility = View.GONE
        distributionSection.pieChartView.visibility = View.GONE
        distributionSection.pieChartView.legendSignatureView.visibility = View.GONE
        distributionSection.chartHeaderView.zoomOut(distributionSection.stackChartView, false)
        updateChartInteractivity(
            distributionSection.stackChartView,
            distributionSection.pieChartView,
            isPieActive = false
        )
        if (savedSelectedDate >= 0) {
            distributionSection.stackChartView.selectDate(savedSelectedDate)
        }
        showLoadedSection(distributionSection)
    }

    private fun showSectionLoading(section: ChartSection, animated: Boolean = false) {
        if (!animated) {
            prepareSectionForPlaceholder(section)
        }
        showLoadingSection(section, animated = animated)
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
        section.chartHeaderView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )
    }

    private fun updateSectionTheme(section: ChartSection) {
        applyCardBackground(section.container)
        section.chartSkeletonPlaceholder.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp
        )
        section.chartCoverView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp
        )
        section.chartHeaderView.updateTheme()
        section.stackChartView.updateTheme()
        section.pieChartView.updateTheme()
        section.stackChartView.legendSignatureView.recolor()
        section.pieChartView.legendSignatureView.recolor()
        updateCheckBoxColors(section.stackChartView, section.checkBoxes)
        updateSectionErrorTheme(section.errorView)
    }

    private fun showLoadingSection(section: ChartSection, animated: Boolean = false) {
        resetSectionHeightAnimation(section)
        section.errorView.container.visibility = View.GONE
        section.chartHeaderView.alpha = 1f
        section.chartHeaderView.visibility = View.VISIBLE
        section.chartFrame.alpha = 1f
        if (!animated) {
            section.chartFrame.visibility = View.INVISIBLE
        }
        section.chartCoverView.visibility = View.VISIBLE
        section.chartSkeletonPlaceholder.visibility = View.VISIBLE
        if (animated) {
            section.chartCoverView.fadeIn()
            section.chartSkeletonPlaceholder.fadeIn()
        } else {
            section.chartCoverView.alpha = 1f
            section.chartSkeletonPlaceholder.alpha = 1f
        }
        section.chartHeaderView.showDatesPlaceholder(animated = animated)
        section.chipGroup.alpha = 1f
    }

    private fun showStatusSection(section: ChartSection) {
        resetSectionHeightAnimation(section)
        section.chartHeaderView.alpha = 1f
        section.chartHeaderView.visibility = View.VISIBLE
        section.chartFrame.alpha = 1f
        section.chartFrame.visibility = View.VISIBLE
        section.chipGroup.alpha = 1f
        if (section.chartCoverView.isVisible) {
            section.chartCoverView.bringToFront()
            section.chartCoverView.fadeOut {
                section.chartCoverView.visibility = View.GONE
            }
        }
        if (section.chartSkeletonPlaceholder.isVisible) {
            section.chartSkeletonPlaceholder.bringToFront()
            section.chartSkeletonPlaceholder.fadeOut {
                section.chartSkeletonPlaceholder.visibility = View.GONE
            }
        }
    }

    private fun showLoadedSection(section: ChartSection) {
        resetSectionHeightAnimation(section)

        section.chartHeaderView.visibility = View.VISIBLE
        section.chartHeaderView.alpha = 1f
        section.chartFrame.visibility = View.VISIBLE
        section.chartFrame.alpha = 1f
        section.chipGroup.alpha = 1f
        animateChipGroupReveal(section)

        if (section.chartCoverView.isVisible) {
            section.chartCoverView.bringToFront()
            section.chartCoverView.fadeOut {
                section.chartCoverView.visibility = View.GONE
            }
        }
        if (section.chartSkeletonPlaceholder.isVisible) {
            section.chartSkeletonPlaceholder.bringToFront()
            section.chartSkeletonPlaceholder.fadeOut {
                section.chartSkeletonPlaceholder.visibility = View.GONE
            }
        }
    }

    private fun prepareSectionForPlaceholder(section: ChartSection) {
        zoomOut(section, animated = false)
        section.chartHeaderView.showTitleOnly()
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

        // Already laid out — do not collapse and re-expand on data refresh
        if (chipGroup.height > 0 && section.heightAnimator == null) {
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
            duration = AnimationConstants.VERY_QUICK_ANIMATION
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
        section.chartHeaderView.zoomTo(date, true)
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

        section.transitionAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
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

        val restoredRange = calculateRestoredStackRange(
            chartView = section.stackChartView,
            pieChartView = section.pieChartView,
            data = data,
            preferredSpan = section.lastStackPickerSpan,
        )
        if (animated && data.x.isNotEmpty()) {
            section.chartHeaderView.zoomOut(
                data.x[restoredRange.startIndex],
                data.x[restoredRange.endIndex],
                true
            )
        }
        section.stackChartView.setPickerByIndices(restoredRange.startIndex, restoredRange.endIndex)
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
        updateChartInteractivity(
            section.stackChartView,
            section.pieChartView,
            isPieActive = false,
            isTransitioning = true
        )

        if (!animated) {
            section.chartHeaderView.zoomOut(section.stackChartView, false)
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
            duration = AnimationConstants.VERY_QUICK_ANIMATION
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
        val range = calculateRestoredStackRange(chartView, pieChartView, data, preferredSpan)
        chartView.setPickerByIndices(range.startIndex, range.endIndex)
    }

    private fun calculateRestoredStackRange(
        chartView: BaseChartView<*, *>,
        pieChartView: PieChartView,
        data: StackLinearChartData?,
        preferredSpan: Int,
    ): RestoredStackRange {
        data ?: return RestoredStackRange(0, 0)
        if (data.x.isEmpty()) return RestoredStackRange(0, 0)
        val lastIndex = data.x.lastIndex
        if (lastIndex <= 0) {
            return RestoredStackRange(0, 0)
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

        return RestoredStackRange(startIndex, endIndex)
    }

    private fun resolvePieDate(section: ChartSection, data: StackLinearChartData): Long {
        return section.pieChartView.getPickerCenterDate().takeIf { it >= 0 }
            ?: section.stackChartView.getSelectedDate().takeIf { it >= 0 }
            ?: section.stackChartView.getPickerCenterDate().takeIf { it >= 0 }
            ?: data.x.last()
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

        val signedFormatter = createSignedChartValueFormatter(baseCurrency)
        totalPnlSection.chartView.valueFormatter = signedFormatter
        dailyPnlSection.chartView.valueFormatter = signedFormatter
    }

    private fun applyCardBackground(container: View) {
        container.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
    }

    private fun createAbsoluteSection(): ChartSection {
        val chartHeaderView = ChartHeaderView(context).apply {
            id = ViewGroup.generateViewId()
            setTitle(LocaleController.getString("Total Value"))
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
        val chartCoverView = createChartCoverView()
        val chipGroup = createSeriesChipGroup()
        val errorView = createSectionErrorView { onRetryChart(PortfolioChartKind.NET_WORTH) }

        return ChartSection(
            container = buildSectionContainer(
                chartHeaderView,
                chartFrame, chartCoverView, chartSkeletonPlaceholder, chipGroup,
                errorView.container,
            ),
            chartFrame = chartFrame,
            chartSkeletonPlaceholder = chartSkeletonPlaceholder,
            chartCoverView = chartCoverView,
            chartHeaderView = chartHeaderView,
            stackChartView = stackChartView,
            pieChartView = pieChartView,
            chipGroup = chipGroup,
            errorView = errorView,
        )
    }

    private fun createDistributionSection(): ChartSection {
        val chartHeaderView = ChartHeaderView(context).apply {
            id = ViewGroup.generateViewId()
            setTitle(LocaleController.getString("Portfolio Share"))
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
        val chartCoverView = createChartCoverView()
        val chipGroup = createSeriesChipGroup()
        val errorView = createSectionErrorView { onRetryChart(PortfolioChartKind.NET_WORTH) }

        return ChartSection(
            container = buildSectionContainer(
                chartHeaderView = chartHeaderView,
                chartFrame = chartFrame,
                chartCoverView = chartCoverView,
                chartSkeletonPlaceholder = chartSkeletonPlaceholder,
                chipGroup = chipGroup,
                errorView = errorView.container,
            ),
            chartFrame = chartFrame,
            chartSkeletonPlaceholder = chartSkeletonPlaceholder,
            chartCoverView = chartCoverView,
            chartHeaderView = chartHeaderView,
            stackChartView = stackChartView,
            pieChartView = pieChartView,
            chipGroup = chipGroup,
            errorView = errorView,
        )
    }

    // Inline error/empty overlay shown in place of a chart when its fetch fails (with a
    // Try Again button) or returns no data. Its visibility is always driven together with
    // the chart/cover/skeleton so it never lingers across loading/loaded transitions.
    private fun createSectionErrorView(onRetry: () -> Unit): SectionErrorView {
        val titleLabel = WLabel(context).apply {
            setStyle(15f)
            gravity = Gravity.CENTER
        }
        val retryButton = WButton(context, WButton.Type.SECONDARY).apply {
            setText(LocaleController.getString("Try Again"))
            setOnClickListener { onRetry() }
        }
        val container = LinearLayout(context).apply {
            id = ViewGroup.generateViewId()
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            addView(titleLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            addView(
                retryButton,
                LinearLayout.LayoutParams(WRAP_CONTENT, 40.dp).apply { topMargin = 12.dp },
            )
        }
        return SectionErrorView(container, titleLabel, retryButton)
    }

    private fun updateSectionErrorTheme(errorView: SectionErrorView) {
        errorView.titleLabel.setTextColor(WColor.SecondaryText.color)
        errorView.retryButton.updateTheme()
    }

    // Show the affected chart(s) in their loading state immediately, then re-fetch. The VM
    // result replaces the loading overlay with data (or the error again on repeat failure).
    private fun onRetryChart(kind: PortfolioChartKind) {
        when (kind) {
            PortfolioChartKind.NET_WORTH -> {
                showSectionLoading(absoluteSection, animated = true)
                showSectionLoading(distributionSection, animated = true)
            }

            PortfolioChartKind.TOTAL_PNL -> showSimpleSectionLoading(
                totalPnlSection,
                animated = true
            )

            PortfolioChartKind.DAILY_PNL -> showSimpleSectionLoading(
                dailyPnlSection,
                animated = true
            )
        }
        viewModel.retry(kind)
    }

    // Drives the error overlay in sync with the chart. `failed` => error title + Try Again;
    // otherwise hidden. Returns whether the overlay is showing so callers keep the chart and
    // overlay mutually exclusive.
    private fun applySectionError(
        errorView: SectionErrorView,
        chartView: View,
        chartFrame: View,
        failed: Boolean,
    ): Boolean {
        if (failed) {
            errorView.titleLabel.text = LocaleController.getString("Error")
            errorView.retryButton.visibility = View.VISIBLE
            errorView.container.visibility = View.VISIBLE
            errorView.container.bringToFront()
            chartView.visibility = View.INVISIBLE
            chartFrame.visibility = View.VISIBLE
        } else {
            errorView.container.visibility = View.GONE
            // Undo the INVISIBLE set by a previous failed state so the chart shows again.
            if (chartView.isInvisible) {
                chartView.visibility = View.VISIBLE
            }
        }
        return failed
    }

    private fun buildSectionContainer(
        chartHeaderView: View,
        chartFrame: View,
        chartCoverView: View,
        chartSkeletonPlaceholder: View,
        chipGroup: View,
        errorView: View,
    ): WView {
        return WView(context).apply {
            addView(
                chartCoverView,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
            )
            addView(
                chartSkeletonPlaceholder,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
            )
            addView(chartHeaderView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(chartFrame, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(chipGroup, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(errorView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
            setConstraints {
                toTop(chartHeaderView)
                toCenterX(chartHeaderView)
                topToBottom(chartFrame, chartHeaderView)
                toCenterX(chartFrame)
                topToBottom(chipGroup, chartFrame)
                toCenterX(chipGroup, ViewConstants.GAP.toFloat())
                toBottom(chipGroup, ViewConstants.GAP.toFloat())
                topToTop(chartSkeletonPlaceholder, chartHeaderView, 48f)
                toCenterX(chartSkeletonPlaceholder, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                bottomToBottom(chartSkeletonPlaceholder, chipGroup, ViewConstants.GAP.toFloat())
                topToTop(chartCoverView, chartSkeletonPlaceholder)
                toCenterX(chartCoverView)
                toBottom(chartCoverView)
                topToTop(errorView, chartFrame)
                toCenterX(errorView)
                bottomToBottom(errorView, chartFrame)
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

    private fun createChartSkeletonPlaceholder(): WBaseView {
        return WBaseView(context).apply {
            id = ViewGroup.generateViewId()
            visibility = View.GONE
            setBackgroundColor(WColor.SecondaryBackground.color, ViewConstants.BLOCK_RADIUS.dp)
        }
    }

    private fun createChartCoverView(): WBaseView {
        return WBaseView(context).apply {
            id = ViewGroup.generateViewId()
            visibility = View.GONE
            setBackgroundColor(WColor.Background.color)
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

    private fun createPeriodSelector(): WSegmentedControlGroup {
        return WSegmentedControlGroup(context).apply {
            setDividerColor(Color.TRANSPARENT)
            MHistoryTimePeriod.allPeriods.forEach { period ->
                addView(
                    WLabel(context).apply {
                        layoutParams = LinearLayout.LayoutParams(0, MATCH_PARENT)
                        setStyle(14f)
                        text = period.localized
                        gravity = Gravity.CENTER
                    }
                )
            }
            setOnSelectedOptionChangeCallback { index ->
                viewModel.selectPeriod(MHistoryTimePeriod.allPeriods[index])
            }
            setSelectedIndex(
                MHistoryTimePeriod.allPeriods.indexOf(viewModel.selectedPeriod)
                    .coerceAtLeast(0)
            )
        }
    }

    private fun createChartLayoutParams(
        topMargin: Int = 0,
        horizontalMargin: Int = ViewConstants.HORIZONTAL_PADDINGS.dp,
    ): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            this.topMargin = topMargin
            marginStart = horizontalMargin
            marginEnd = horizontalMargin
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

    private fun createSignedChartValueFormatter(baseCurrency: MBaseCurrency): ChartValueFormatter {
        return object : ChartValueFormatter {
            override fun formatAxisValue(value: Long, paint: TextPaint): CharSequence =
                applyCurrencyPosition(
                    compactScaledNumber(
                        value,
                        baseCurrency.decimalsCount,
                        1,
                        showPositiveSign = true
                    ),
                    baseCurrency.sign,
                )

            override fun formatLegendValue(value: Long, paint: TextPaint): CharSequence =
                formatCurrencyLegendValue(value, baseCurrency, showPositiveSign = true)
        }
    }

    private fun formatCurrencyLegendValue(
        value: Long,
        baseCurrency: MBaseCurrency,
        showPositiveSign: Boolean = false,
    ): String {
        return BigInteger.valueOf(value).toString(
            decimals = baseCurrency.decimalsCount,
            currency = baseCurrency.sign,
            currencyDecimals = baseCurrency.decimalsCount,
            showPositiveSign = showPositiveSign,
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

    private fun compactScaledNumber(
        value: Long,
        decimals: Int,
        maxFractionDigits: Int,
        showPositiveSign: Boolean = false,
    ): String {
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

        val sign = when {
            value < 0 -> "-"
            showPositiveSign && value > 0 -> "+"
            else -> ""
        }
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
        val bottomInset = navigationController?.getSystemBars()?.bottom ?: 0
        contentLayout.setPadding(
            0, 0, 0,
            bottomInset + PERIOD_SELECTOR_SECTION_HEIGHT.dp + 8.dp
        )
        (periodSelectorContainer.layoutParams as? ConstraintLayout.LayoutParams)?.let { lp ->
            lp.bottomMargin = bottomInset
            periodSelectorContainer.layoutParams = lp
        }
    }

    private companion object {
        private const val PERIOD_SELECTOR_SECTION_HEIGHT = 64
    }

    override fun onDestroy() {
        super.onDestroy()
        viewModel.onDestroy()
    }

    private fun createSimpleSection(
        title: String,
        chartView: BaseChartView<*, *>,
        retryKind: PortfolioChartKind,
    ): SimpleChartSection {
        val chartHeaderView = ChartHeaderView(context).apply {
            id = ViewGroup.generateViewId()
            setTitle(title)
        }
        val errorView = createSectionErrorView { onRetryChart(retryKind) }
        chartView.apply {
            id = ViewGroup.generateViewId()
            style = chartStyle
            pickerMode = ChartPickerDelegate.PickerMode.RANGE
            setHeader(chartHeaderView)
        }
        val chartFrame = FrameLayout(context).apply {
            id = ViewGroup.generateViewId()
            setPadding(0, ViewConstants.GAP.dp, 0, 0)
            addView(chartView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(
                chartView.legendSignatureView,
                FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    setMargins(0, 8.dp, 0, 0)
                },
            )
        }
        val chartSkeletonPlaceholder = createChartSkeletonPlaceholder()
        val chartCoverView = createChartCoverView()
        val container = WView(context).apply {
            addView(
                chartCoverView,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
            )
            addView(
                chartSkeletonPlaceholder,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT),
            )
            addView(chartHeaderView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(chartFrame, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(
                errorView.container,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
            )
            setConstraints {
                toTop(chartHeaderView)
                toCenterX(chartHeaderView)
                topToBottom(chartFrame, chartHeaderView)
                toCenterX(chartFrame)
                toBottom(chartFrame, ViewConstants.GAP.toFloat())
                topToTop(chartSkeletonPlaceholder, chartHeaderView, 48f)
                toCenterX(chartSkeletonPlaceholder, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                bottomToBottom(chartSkeletonPlaceholder, chartFrame, ViewConstants.GAP.toFloat())
                topToTop(chartCoverView, chartSkeletonPlaceholder)
                toCenterX(chartCoverView)
                toBottom(chartCoverView)
                topToTop(errorView.container, chartFrame)
                toCenterX(errorView.container)
                bottomToBottom(errorView.container, chartFrame)
            }
        }
        return SimpleChartSection(
            container = container,
            chartFrame = chartFrame,
            chartSkeletonPlaceholder = chartSkeletonPlaceholder,
            chartCoverView = chartCoverView,
            chartHeaderView = chartHeaderView,
            chartView = chartView,
            errorView = errorView,
        )
    }

    private fun applySimpleSectionStyle(section: SimpleChartSection) {
        section.chartView.style = chartStyle
        section.chartFrame.setBackgroundColor(WColor.Background.color)
        section.chartHeaderView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f,
        )
    }

    private fun updateSimpleSectionTheme(section: SimpleChartSection) {
        applyCardBackground(section.container)
        section.chartSkeletonPlaceholder.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp,
        )
        section.chartCoverView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp,
        )
        section.chartHeaderView.updateTheme()
        section.chartView.updateTheme()
        section.chartView.legendSignatureView.recolor()
        updateSectionErrorTheme(section.errorView)
    }

    private fun showSimpleSectionLoading(section: SimpleChartSection, animated: Boolean = false) {
        section.errorView.container.visibility = View.GONE
        if (!animated) {
            section.chartHeaderView.showTitleOnly()
            section.chartView.setData(null)
        }
        section.chartHeaderView.alpha = 1f
        section.chartHeaderView.visibility = View.VISIBLE
        section.chartFrame.alpha = 1f
        if (!animated) {
            section.chartFrame.visibility = View.INVISIBLE
        }
        section.chartCoverView.visibility = View.VISIBLE
        section.chartSkeletonPlaceholder.visibility = View.VISIBLE
        if (animated) {
            section.chartCoverView.fadeIn()
            section.chartSkeletonPlaceholder.fadeIn()
        } else {
            section.chartCoverView.alpha = 1f
            section.chartSkeletonPlaceholder.alpha = 1f
        }
        section.chartHeaderView.showDatesPlaceholder(animated = animated)
    }

    private fun showSimpleSectionStatus(section: SimpleChartSection) {
        section.chartHeaderView.showTitleOnly()
        section.chartData = null
        section.chartView.setData(null)
        section.chartHeaderView.alpha = 1f
        section.chartHeaderView.visibility = View.VISIBLE
        section.chartFrame.alpha = 1f
        section.chartFrame.visibility = View.VISIBLE
        fadeOutSimpleOverlays(section)
        updateSimpleSectionTheme(section)
    }

    private fun showSimpleLoaded(section: SimpleChartSection, data: ChartData?) {
        section.chartData = data
        if (data == null) {
            showSimpleSectionStatus(section)
            return
        }
        @Suppress("UNCHECKED_CAST")
        (section.chartView as BaseChartView<ChartData, *>).setData(data)
        section.chartView.updateTheme()
        section.chartView.visibility = View.VISIBLE
        section.chartHeaderView.alpha = 1f
        section.chartHeaderView.visibility = View.VISIBLE
        section.chartFrame.alpha = 1f
        section.chartFrame.visibility = View.VISIBLE
        fadeOutSimpleOverlays(section)
    }

    private fun fadeOutSimpleOverlays(section: SimpleChartSection) {
        if (section.chartCoverView.isVisible) {
            section.chartCoverView.bringToFront()
            section.chartCoverView.fadeOut {
                section.chartCoverView.visibility = View.GONE
            }
        }
        if (section.chartSkeletonPlaceholder.isVisible) {
            section.chartSkeletonPlaceholder.bringToFront()
            section.chartSkeletonPlaceholder.fadeOut {
                section.chartSkeletonPlaceholder.visibility = View.GONE
            }
        }
    }

    private data class SimpleChartSection(
        val container: WView,
        val chartFrame: FrameLayout,
        val chartSkeletonPlaceholder: WBaseView,
        val chartCoverView: WBaseView,
        val chartHeaderView: ChartHeaderView,
        val chartView: BaseChartView<*, *>,
        val errorView: SectionErrorView,
        var chartData: ChartData? = null,
    )

    private class SectionErrorView(
        val container: LinearLayout,
        val titleLabel: WLabel,
        val retryButton: WButton,
    )

    private data class ChartSection(
        val container: WView,
        val chartFrame: FrameLayout,
        val chartSkeletonPlaceholder: WBaseView,
        val chartCoverView: WBaseView,
        val chartHeaderView: ChartHeaderView,
        val stackChartView: StackLinearChartView<StackLinearViewData>,
        val pieChartView: PieChartView,
        val chipGroup: ChipGroup,
        val errorView: SectionErrorView,
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

    private data class RestoredStackRange(
        val startIndex: Int,
        val endIndex: Int,
    )
}
