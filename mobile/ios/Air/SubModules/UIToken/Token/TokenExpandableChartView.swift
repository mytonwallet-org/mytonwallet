//
//  TokenExpandableChartView.swift
//
//  Created by Sina on 11/11/24.
//

import UIKit
import GraphKit
import UIComponents
import WalletCore
import WalletContext

fileprivate let chartAxisDateFormatter = DateFormatter()

private let rangeViewTintColor = UIColor {
    $0.userInterfaceStyle != .dark
        ? UIColor(red: 239 / 255, green: 239 / 255, blue: 244 / 255, alpha: 0.5)
        : UIColor(red: 24 / 255, green: 34 / 255, blue: 45 / 255, alpha: 0.5)
}

@MainActor
final class TokenExpandableChartView: UIView {

    private struct ChartAnimationGeometry {
        let width: CGFloat
        let height: CGFloat
        let top: CGFloat
        let trailing: CGFloat
    }

    static let collapsedHeight = CGFloat(60)
    private static let expandedChartMaxHeight = CGFloat(200)
    private static let expandedChartTrailingOffset = CGFloat(-12)
    private static var expandedChartHeight: CGFloat {
        let height = 0.36 * (screenWidth - 32 - 6)
        return min(height, expandedChartMaxHeight)
    }
    static var expandedHeight: CGFloat {
        30 + 16 + 76 + expandedChartHeight
    }

    private let parentProcessorQueue = DispatchQueue(label: "TokenExpandableChartView")
    private let locker = DispatchSemaphore(value: 1)
    private let onHeightChange: () -> Void

    public init(onHeightChange: @escaping () -> Void) {
        self.onHeightChange = onHeightChange
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var token: ApiToken? = nil
    private var displayedPeriod: ApiPriceHistoryPeriod? = nil
    private var historyData: [[Double]]? = nil
    private let graph = CompactLineChart()
    private var onPeriodChange: ((ApiPriceHistoryPeriod) -> Void)? = nil

    private var selectedRange: ClosedRange<CGFloat> = 0...1
    private weak var toggleChartRecognizer: UITapGestureRecognizer?

    override func tintColorDidChange() {
        super.tintColorDidChange()
        refreshChartTint()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            refreshChartTint()
        }
    }

    func configure(token: ApiToken, historyData: [[Double]]?, onPeriodChange: @escaping (ApiPriceHistoryPeriod) -> Void) {
        self.token = token
        self.historyData = historyData
        self.onPeriodChange = onPeriodChange

        fillLabels()

        drawChart(period: nil, historyData: historyData, range: selectedRange)
    }

    func rangeChanged(_ range: ClosedRange<CGFloat>) {
        selectedRange = range
        lastSelection = nil
        fillLabels()
    }

    private var heightConstraint: NSLayoutConstraint!
    private var arrowTrailingConstraint: NSLayoutConstraint!

    private var chartAnimationViewTopAnchor: NSLayoutConstraint!
    private var chartAnimationViewTrailingAnchor: NSLayoutConstraint!
    private var chartAnimationViewWidthAnchor: NSLayoutConstraint!
    private var chartAnimationViewHeightAnchor: NSLayoutConstraint!
    private var lastSelection: CompactLineChartSelection?

    var height: CGFloat { heightConstraint.constant }
    var rangeInteractionBlockingGestureRecognizer: UIGestureRecognizer {
        rangeChart.horizontalInteractionBlockingGestureRecognizer
    }
    private var isExpanded = false
    private var isTogglingChart = false
    // MARK: - Views

    private let priceTitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.applyTextStyle(.supporting)
        lbl.text = lang("Price")
        return lbl
    }()

    private let priceValueLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let priceChangeLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let smallChartImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let largeChartImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.alpha = 0
        return iv
    }()

    private lazy var lineChartAnimationView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.alpha = 0
        v.isUserInteractionEnabled = false
        v.addSubview(smallChartImageView)
        v.addSubview(largeChartImageView)
        NSLayoutConstraint.activate([
            smallChartImageView.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            smallChartImageView.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            smallChartImageView.topAnchor.constraint(equalTo: v.topAnchor),
            smallChartImageView.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            largeChartImageView.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            largeChartImageView.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            largeChartImageView.topAnchor.constraint(equalTo: v.topAnchor),
            largeChartImageView.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }()

    private lazy var collapsedChart = {
        let lineChartView = graph.previewView
        lineChartView.translatesAutoresizingMaskIntoConstraints = false
        lineChartView.alpha = 0
        lineChartView.isUserInteractionEnabled = false
        return lineChartView
    }()

    private lazy var expandedChart = {
        let lineChartView = graph.mainView
        lineChartView.translatesAutoresizingMaskIntoConstraints = false
        lineChartView.alpha = 0
        lineChartView.isHidden = true
        return lineChartView
    }()

    private lazy var loadingIndicator = {
        let indicator = WActivityIndicator()
        indicator.presentationDelay = 1
        return indicator
    }()

    private lazy var noPriceDataLabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = lang("No price data")
        label.textColor = UIColor.air.secondaryLabel
        label.applyTextStyle(.footnote)
        label.isHidden = true
        return label
    }()

    private let arrowImageView: UIImageView = {
        let arrowImageView = UIImageView(image: UIImage(systemName: "chevron.down",
                                                        withConfiguration: UIImage.SymbolConfiguration(
                                                            font: WTypography.uiFont(.badgeBold, content: .technical)
                                                        ))!
            .withRenderingMode(.alwaysTemplate))
        arrowImageView.tintColor = UIColor.label.withAlphaComponent(0.3)
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        arrowImageView.contentMode = .center
        return arrowImageView
    }()

    private lazy var rangeChart: CompactLineChartRangeView = {
        let v = graph.rangeView
        v.translatesAutoresizingMaskIntoConstraints = false
        v.alpha = 0
        return v
    }()

    private let timePeriods: [ApiPriceHistoryPeriod] = ApiPriceHistoryPeriod.allCases.reversed()

    private lazy var timeFrameSwitcherView = {
        let switcherView = WChartSegmentedControl(items: timePeriods.map { $0.localized })
        switcherView.translatesAutoresizingMaskIntoConstraints = false
        switcherView.alpha = 0
        return switcherView
    }()

    private lazy var topBarView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = S.homeInsetSectionCornerRadius
        layer.masksToBounds = true
        addSubview(collapsedChart)
        addSubview(expandedChart)
        addSubview(rangeChart)
        addSubview(lineChartAnimationView)
        addSubview(arrowImageView)
        addSubview(timeFrameSwitcherView)
        addSubview(topBarView)
        addSubview(loadingIndicator)
        addSubview(noPriceDataLabel)
        timeFrameSwitcherView.addTarget(self, action: #selector(handlePeriodChange), for: .valueChanged)
        timeFrameSwitcherView.selectedSegmentIndex = timePeriods.firstIndex(where: { it in
            it.rawValue == AppStorageHelper.selectedCurrentTokenPeriod()
        }) ?? 0
        heightConstraint = heightAnchor.constraint(equalToConstant: AppStorageHelper.isTokenChartExpanded ? TokenExpandableChartView.expandedHeight : TokenExpandableChartView.collapsedHeight)
        arrowTrailingConstraint = arrowImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18)
        chartAnimationViewTrailingAnchor = lineChartAnimationView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -33)
        chartAnimationViewTopAnchor = lineChartAnimationView.topAnchor.constraint(equalTo: topAnchor, constant: 11.33)
        chartAnimationViewWidthAnchor = lineChartAnimationView.widthAnchor.constraint(equalToConstant: 82)
        chartAnimationViewHeightAnchor = lineChartAnimationView.heightAnchor.constraint(equalToConstant: 40)

        let loadingIndicatorXConstraint = loadingIndicator.centerXAnchor.constraint(equalTo: lineChartAnimationView.centerXAnchor)
        loadingIndicatorXConstraint.priority = .init(999)

        let noPriceDataLabelXConstraint = noPriceDataLabel.centerXAnchor.constraint(equalTo: loadingIndicator.centerXAnchor)
        noPriceDataLabelXConstraint.priority = .defaultHigh

        graph.rangeDidChange = { [weak self] range in
            self?.rangeChanged(range)
        }
        graph.selectionDidChange = { [weak self] selection in
            self?.lastSelection = selection
            self?.fillLabels()
        }
        
        let priceContainer = UIView()
        do {
            priceContainer.addSubview(priceTitleLabel)
            priceContainer.addSubview(priceValueLabel)
            priceContainer.addSubview(priceChangeLabel)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            priceContainer.addGestureRecognizer(longPress)

            let priceTap = UITapGestureRecognizer(target: self, action: #selector(toggleChart))
            priceContainer.addGestureRecognizer(priceTap)
            priceTap.require(toFail: longPress)
        }
        
        priceContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(priceContainer)

        NSLayoutConstraint.activate([
            topBarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBarView.topAnchor.constraint(equalTo: topAnchor),
            topBarView.heightAnchor.constraint(equalToConstant: 60),
            
            priceContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            priceContainer.topAnchor.constraint(equalTo: topAnchor),

            priceTitleLabel.leadingAnchor.constraint(equalTo: priceContainer.leadingAnchor, constant: 16),
            priceTitleLabel.topAnchor.constraint(equalTo: priceContainer.topAnchor, constant: 10),

            priceValueLabel.leadingAnchor.constraint(equalTo: priceContainer.leadingAnchor, constant: 16),
            priceValueLabel.topAnchor.constraint(equalTo: priceTitleLabel.bottomAnchor, constant: 1),
            priceValueLabel.bottomAnchor.constraint(equalTo: priceContainer.bottomAnchor, constant: -10),

            priceChangeLabel.firstBaselineAnchor.constraint(equalTo: priceValueLabel.firstBaselineAnchor),
            priceChangeLabel.leadingAnchor.constraint(equalTo: priceValueLabel.trailingAnchor, constant: 6),

            priceContainer.trailingAnchor.constraint(greaterThanOrEqualTo: priceTitleLabel.trailingAnchor, constant: 16),
            priceContainer.trailingAnchor.constraint(greaterThanOrEqualTo: priceChangeLabel.trailingAnchor, constant: 16),
            priceContainer.trailingAnchor.constraint(equalTo: priceTitleLabel.trailingAnchor, constant: 16).withPriority(.defaultHigh),
            priceContainer.trailingAnchor.constraint(equalTo: priceChangeLabel.trailingAnchor, constant: 16).withPriority(.defaultHigh),

            collapsedChart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -33),
            collapsedChart.topAnchor.constraint(equalTo: topAnchor, constant: 11.33),
            collapsedChart.widthAnchor.constraint(equalToConstant: 82),
            collapsedChart.heightAnchor.constraint(equalToConstant: 40),

            expandedChart.leadingAnchor.constraint(equalTo: leadingAnchor),
            expandedChart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: Self.expandedChartTrailingOffset),
            expandedChart.topAnchor.constraint(equalTo: topAnchor, constant: 35),
            expandedChart.heightAnchor.constraint(equalToConstant: TokenExpandableChartView.expandedChartHeight),

            loadingIndicatorXConstraint,
            loadingIndicator.centerXAnchor.constraint(greaterThanOrEqualTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: lineChartAnimationView.centerYAnchor),

            noPriceDataLabelXConstraint,
            noPriceDataLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -46),
            noPriceDataLabel.centerYAnchor.constraint(equalTo: loadingIndicator.centerYAnchor),

            chartAnimationViewTrailingAnchor,
            chartAnimationViewTopAnchor,
            chartAnimationViewWidthAnchor,
            chartAnimationViewHeightAnchor,

            arrowTrailingConstraint,
            arrowImageView.topAnchor.constraint(equalTo: topAnchor, constant: 25),

            rangeChart.leadingAnchor.constraint(equalTo: leadingAnchor),
            rangeChart.trailingAnchor.constraint(equalTo: trailingAnchor),
            rangeChart.bottomAnchor.constraint(equalTo: timeFrameSwitcherView.topAnchor, constant: -12),
            rangeChart.heightAnchor.constraint(equalToConstant: 30),

            timeFrameSwitcherView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            timeFrameSwitcherView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            timeFrameSwitcherView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            timeFrameSwitcherView.heightAnchor.constraint(equalToConstant: 28),

            heightConstraint
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChart))
        toggleChartRecognizer = tap
        topBarView.addGestureRecognizer(tap)
        
        updateTheme()

        loadingIndicator.startAnimating(animated: true)

        if AppStorageHelper.isTokenChartExpanded {
            DispatchQueue.main.async {
                self.toggleChart(instant: true)
            }
        }
    }
    
    private func updateTheme() {
        backgroundColor = UIColor.air.groupedItem
        priceTitleLabel.textColor = UIColor.air.secondaryLabel
        loadingIndicator.tintColor = .tintColor
        refreshChartTint()
    }

    private func refreshChartTint() {
        graph.apply(style: CompactLineChartStyle(
            lineColor: tintColor,
            backgroundColor: UIColor.air.background,
            rangeTintColor: rangeViewTintColor,
            rangeCropImage: .airBundle("ChartRangeSelectionFrame"),
            fillOpacity: 0.33
        ))
    }

    // MARK: - Data mehods

    private func fillLabels() {
        guard let token, let tokenPrice = token.price else {
            // TODO: No price available message
            priceValueLabel.text = nil
            return
        }
        if let lastSelection {
            let priceAmount = BaseCurrencyAmount.fromDouble(lastSelection.point.value, TokenStore.baseCurrency)
            let priceString = priceAmount.formatted(.baseCurrencyHighPrecision, roundHalfUp: true)
            let attr = NSAttributedString(string: priceString, attributes: [
                .font: WTypography.uiFont(.calloutEmphasized, content: .technical),
                .foregroundColor: UIColor.label
            ])
            priceValueLabel.attributedText = attr

            let percent = NSAttributedString(string: chartAxisDateFormatter.string(
                from: Date(timeIntervalSince1970: lastSelection.point.timestamp)
            ), attributes: [
                .font: WTypography.uiFont(.supporting, content: .technical),
                .foregroundColor: UIColor.air.secondaryLabel
            ])
            priceChangeLabel.attributedText = percent

        } else {
            let lastPrice = latestTokenChartPrice(
                historyData: historyData,
                range: selectedRange,
                fallbackPrice: tokenPrice
            )
            let percentChange = tokenChartPercentChange(
                historyData: historyData,
                range: selectedRange,
                tokenPercentChange24h: token.percentChange24h,
                shouldUseTokenPercentChange: timePeriods[timeFrameSwitcherView.selectedSegmentIndex] == .day,
                fallbackPrice: tokenPrice
            )
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(lastPrice, TokenStore.baseCurrency)
            let priceString = baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundHalfUp: true)
            let attr = NSAttributedString(string: priceString, attributes: [
                .font: WTypography.uiFont(.calloutEmphasized, content: .technical),
                .foregroundColor: UIColor.label
            ])
            priceValueLabel.attributedText = attr

            if let percentChange {
                let percent = NSAttributedString(string: formatPercent(percentChange), attributes: [
                    .font: WTypography.uiFont(.supporting, content: .technical),
                    .foregroundColor: percentChange > 0 ? UIColor.air.positiveAmount : (percentChange == 0 ? UIColor.air.secondaryLabel : UIColor.air.negativeAmount)
                ])
                priceChangeLabel.attributedText = percent
            } else {
                priceChangeLabel.attributedText = nil
            }

        }
        UIView.animate(withDuration: 0.2) {
            self.priceChangeLabel.alpha = self.priceChangeLabel.attributedText?.string.nilIfEmpty == nil ? 0 : 1
        }
    }

    private func drawChart(period: ApiPriceHistoryPeriod?,
                           historyData data: [[Double]]?,
                           range: ClosedRange<CGFloat>,
                           completion: (@MainActor () -> Void)? = nil) {
        let historyData = reduceNumberOfPoints(data, to: 200)
        let expandedHistoryData = data

        if let period, period != self.displayedPeriod {
            lastSelection = nil
            self.displayedPeriod = period
        }

        // Pending history (nil) and an empty response are distinct presentation states.
        let isLoading = data == nil
        let hasData = data?.isEmpty == false
        noPriceDataLabel.isHidden = data?.isEmpty != true
        if isLoading {
            loadingIndicator.startAnimating(animated: true)
        } else {
            loadingIndicator.stopAnimating(animated: false)
        }
        UIView.animate(withDuration: 0.2) { [self] in
            collapsedChart.alpha = hasData ? 1 : 0
            expandedChart.alpha = hasData ? 1 : 0
            rangeChart.alpha = isExpanded && hasData ? 1 : 0
        }
        let dateFormat: String
        switch timePeriods[timeFrameSwitcherView.selectedSegmentIndex] {
        case .year, .all:
            dateFormat = "MMM d, yyyy"
            break
        default:
            dateFormat = "MMM d, HH:mm"
            break
        }
        chartAxisDateFormatter.dateFormat = dateFormat

        graph.setData(
            (expandedHistoryData ?? []).map {
                CompactLineChartPoint(timestamp: $0[0], value: $0[1])
            },
            previewPoints: (historyData ?? []).map {
                CompactLineChartPoint(timestamp: $0[0], value: $0[1])
            }
        )
        graph.setRange(range, animated: false)
        refreshChartTint()
        if expandedHistoryData?.isEmpty != false {
            lastSelection = nil
        }
        completion?()
    }

    @objc private func handlePeriodChange() {
        let period = timePeriods[timeFrameSwitcherView.selectedSegmentIndex]
        historyData = nil
        lastSelection = nil
        selectedRange = 0...1
        drawChart(period: period, historyData: nil, range: selectedRange)
        fillLabels()
        onPeriodChange?(period)
    }

    @objc private func toggleChart(instant: Bool) {
        if isTogglingChart {
            return
        }
        isTogglingChart = true
        isExpanded = !isExpanded
        expandedChart.isUserInteractionEnabled = isExpanded

        parentProcessorQueue.async {
            self.locker.wait()

            DispatchQueue.main.async {
                self._toggleChartImpl(instant: instant)
            }
        }
    }
    
    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let price = priceValueLabel.text, !price.isEmpty else { return }
        
        UIPasteboard.general.string = price
        AppActions.showToast(icon: .animatedCopy, message: lang("Price Copied"))
        Haptics.play(.lightTap)
    }

    private func _toggleChartImpl(instant: Bool) {
        let targetHeight = isExpanded ? TokenExpandableChartView.expandedHeight : TokenExpandableChartView.collapsedHeight

        let collapsedSnapshotFrame = collapsedChart.snapshotFrame()
        let collapsedGeometry = ChartAnimationGeometry(
            width: max(1, collapsedSnapshotFrame.width),
            height: max(1, collapsedSnapshotFrame.height),
            top: 11.33 + collapsedSnapshotFrame.minY,
            trailing: -33 + collapsedSnapshotFrame.maxX - collapsedChart.bounds.width
        )

        let expandedSnapshotFrame = expandedChart.snapshotFrame(padding: 4)
        let expandedGeometry = ChartAnimationGeometry(
            width: max(1, expandedSnapshotFrame.width),
            height: max(1, expandedSnapshotFrame.height),
            top: 35 + expandedSnapshotFrame.minY,
            trailing: Self.expandedChartTrailingOffset + expandedSnapshotFrame.maxX - expandedChart.bounds.width
        )

        let startGeometry = isExpanded ? collapsedGeometry : expandedGeometry
        let endGeometry = isExpanded ? expandedGeometry : collapsedGeometry

        let updateBlock: (CGFloat, CGFloat) -> () = { [self] progress, value in
            heightConstraint.constant = value

            // Animate line charts
            let currentWidth = startGeometry.width + (endGeometry.width - startGeometry.width) * CGFloat(progress)
            let currentHeight = startGeometry.height + (endGeometry.height - startGeometry.height) * CGFloat(progress)
            let currentTop = startGeometry.top + (endGeometry.top - startGeometry.top) * CGFloat(progress)
            let currentTrailing = startGeometry.trailing + (endGeometry.trailing - startGeometry.trailing) * CGFloat(progress)

            chartAnimationViewWidthAnchor.constant = max(1, currentWidth)
            chartAnimationViewHeightAnchor.constant = max(1, currentHeight)
            chartAnimationViewTopAnchor.constant = currentTop
            chartAnimationViewTrailingAnchor.constant = currentTrailing

            if isExpanded {
                largeChartImageView.alpha = progress
                smallChartImageView.alpha = 1 - progress
                rangeChart.alpha = historyData?.isEmpty ?? true ? 0 : max(0, 2 * (progress - 0.5))
                timeFrameSwitcherView.alpha = max(0, 2 * (progress - 0.5))
            } else {
                smallChartImageView.alpha = progress
                largeChartImageView.alpha = 1 - progress
                rangeChart.alpha = historyData?.isEmpty ?? true ? 0 : max(0, 1 - 2 * progress)
                timeFrameSwitcherView.alpha = max(0, 1 - 2 * progress)
            }

            layoutIfNeeded()
            onHeightChange()
        }

        if instant {
            updateBlock(1, targetHeight)
            arrowImageView.transform = arrowImageView.transform.rotated(by: .pi)
            isTogglingChart = false
            expandedChart.isHidden = isExpanded ? false : true
            collapsedChart.isHidden = isExpanded ? true : false
            loadingIndicator.transform = isExpanded ? .identity.scaledBy(x: 1.2, y: 1.2) : .identity
            locker.signal()
        } else {
            smallChartImageView.image = collapsedChart.snapshotImage()
            largeChartImageView.image = expandedChart.snapshotImage(padding: 4)
            collapsedChart.isHidden = true
            expandedChart.isHidden = true
            lineChartAnimationView.alpha = 1

            UIView.performWithoutAnimation {
                chartAnimationViewWidthAnchor.constant = max(1, startGeometry.width)
                chartAnimationViewHeightAnchor.constant = max(1, startGeometry.height)
                chartAnimationViewTopAnchor.constant = startGeometry.top
                chartAnimationViewTrailingAnchor.constant = startGeometry.trailing
                layoutIfNeeded()
            }

            updateBlock(0, heightConstraint.constant)
            let heightAnimator = ValueAnimator(
                startValue: heightConstraint.constant,
                endValue: targetHeight,
                duration: 0.55,
                dampingRatio: 0.93
            )
            heightAnimator.addUpdateBlock { progress, value in
                updateBlock(progress, value)
            }
            heightAnimator.addCompletionBlock { [weak self] in
                guard let self else { return }
                onHeightChange()
                AppStorageHelper.isTokenChartExpanded = isExpanded
                drawChart(period: displayedPeriod, historyData: historyData, range: selectedRange) { [weak self] in
                    guard let self else { return }
                    expandedChart.isHidden = isExpanded ? false : true
                    collapsedChart.isHidden = isExpanded ? true : false
                    lineChartAnimationView.alpha = 0
                    isTogglingChart = false
                    locker.signal()
                }
            }
            heightAnimator.start()
            UIView.animate(
                withDuration: 0.55,
                delay: 0,
                usingSpringWithDamping: 0.93,
                initialSpringVelocity: 0,
                options: []
            ) { [self] in
                arrowImageView.transform = arrowImageView.transform.rotated(by: .pi)
                loadingIndicator.transform = isExpanded ? .identity.scaledBy(x: 1.2, y: 1.2) : .identity
            }
        }
    }
}

// MARK: - Helper functions

/// Halves the number of points until it's less than **to**
func reduceNumberOfPoints(_ data: [[Double]]?, to: Int) -> [[Double]]? {
    guard var data else {
        return nil
    }
    while data.count > to {
        var filtered: [[Double]] = []
        for (idx, element) in data.enumerated() {
            if idx % 2 == 0 {
                filtered.append(element)
            }
        }
        data = filtered
    }
    return data
}

/// Removes points outside of **range** segment (0 = start of data, 1 = end)
func scope(data: [[Double]]?, range: ClosedRange<CGFloat>) -> [[Double]]? {
    guard let data else {
        return nil
    }
    let count = data.count
    if count <= 2 || range == 0...1 { return data }
    let segmentsCount: CGFloat = CGFloat(count - 1)
    let lo = floor(range.lowerBound * segmentsCount)
    let hi = ceil(range.upperBound * segmentsCount)
    let scoped = Array(data[Int(lo)...Int(hi)])
    return reduceNumberOfPoints(scoped, to: 1000)
}

func latestTokenChartPrice(
    historyData data: [[Double]]?,
    range: ClosedRange<CGFloat>,
    fallbackPrice: Double
) -> Double {
    let chartData = range == 0...1 ? data : scope(data: data, range: range)
    return chartData?.last(where: { $0[1] != 0 })?[1] ?? fallbackPrice
}

func tokenChartPercentChange(
    historyData data: [[Double]]?,
    range: ClosedRange<CGFloat>,
    tokenPercentChange24h: Double?,
    shouldUseTokenPercentChange: Bool,
    fallbackPrice: Double
) -> Double? {
    if shouldUseTokenPercentChange, range == 0...1, let tokenPercentChange24h {
        return tokenPercentChange24h / 100
    }

    let chartData = range == 0...1 ? data : scope(data: data, range: range)
    guard let firstPrice = chartData?.first(where: { $0[1] != 0 })?[1] else {
        return nil
    }

    let lastPrice = chartData?.last(where: { $0[1] != 0 })?[1] ?? fallbackPrice
    return (lastPrice - firstPrice) / firstPrice
}
