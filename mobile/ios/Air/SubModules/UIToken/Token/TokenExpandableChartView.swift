//
//  TokenExpandableChartView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/11/24.
//

import UIKit
import UIComponents
import DGCharts
import WalletCore
import WalletContext

fileprivate let dateFormatter = DateFormatter()

@MainActor
final class TokenExpandableChartView: UIView, WThemedView {

    static let collapsedHeight = CGFloat(60)
    private static let expandedChartMaxHeight = CGFloat(200)
    private static var expandedChartHeight: CGFloat {
        let height = 0.36 * (screenWidth - 32 - 6)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return min(height, expandedChartMaxHeight)
        }
        return height
    }
    static var expandedHeight: CGFloat {
        30 + 16 + 76 + expandedChartHeight
    }

    private let parentProcessorQueue: DispatchQueue
    private let locker = DispatchSemaphore(value: 1)
    private let onHeightChange: () -> Void

    public init(parentProcessorQueue: DispatchQueue, onHeightChange: @escaping () -> Void) {
        self.parentProcessorQueue = parentProcessorQueue
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

    private var collapsedChartData: LineChartData? = nil
    private var expandedChartData: LineChartData? = nil
    private var rangeChartData: LineChartData? = nil

    private let processorQueue = DispatchQueue(label: "org.mytonwallet.app.token_chart_background_processor", attributes: .concurrent)
    private var onPeriodChange: ((ApiPriceHistoryPeriod) -> Void)? = nil

    private var selectedRange: ClosedRange<CGFloat> = 0...1

    func configure(token: ApiToken, historyData: [[Double]]?, onPeriodChange: @escaping (ApiPriceHistoryPeriod) -> Void) {
        self.token = token
        self.historyData = historyData
        self.onPeriodChange = onPeriodChange

        fillLabels()

        drawChart(period: nil, historyData: historyData, range: self.selectedRange, rangeOnly: false)
    }

    func rangeChanged(_ range: ClosedRange<CGFloat>) {
        self.selectedRange  = range
        drawChart(period: self.displayedPeriod, historyData: historyData, range: range, rangeOnly: true)
        fillLabels()
    }

    private var heightConstraint: NSLayoutConstraint!
    private var arrowRightConstraint: NSLayoutConstraint!

    private var chartAnimationViewTopAnchor: NSLayoutConstraint!
    private var chartAnimationViewRightAnchor: NSLayoutConstraint!
    private var chartAnimationViewWidthAnchor: NSLayoutConstraint!
    private var chartAnimationViewHeightAnchor: NSLayoutConstraint!
    private var expandedChartRightConstraint: NSLayoutConstraint!
    private var expandedChartWidthConstraint: NSLayoutConstraint!

    private var lastHighlight: Highlight?

    var height: CGFloat { heightConstraint.constant }
    private var isExpanded = false
    private var isTogglingChart = false

    // MARK: - Views

    private let priceTitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 14)
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
            smallChartImageView.leftAnchor.constraint(equalTo: v.leftAnchor),
            smallChartImageView.rightAnchor.constraint(equalTo: v.rightAnchor),
            smallChartImageView.topAnchor.constraint(equalTo: v.topAnchor),
            smallChartImageView.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            largeChartImageView.leftAnchor.constraint(equalTo: v.leftAnchor),
            largeChartImageView.rightAnchor.constraint(equalTo: v.rightAnchor),
            largeChartImageView.topAnchor.constraint(equalTo: v.topAnchor),
            largeChartImageView.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }()

    private lazy var collapsedChart = {
        let lineChartView = WLineChartView()
        lineChartView.alpha = 0
        lineChartView.isUserInteractionEnabled = false
        return lineChartView
    }()

    private lazy var expandedChart = {
        let lineChartView = WLineChartView(popupDateFormatter: { date in
            let dateObj = Date(timeIntervalSince1970: date)
            dateFormatter.dateFormat = dateObj.isInSameYear(as: Date()) ? "MMM d, HH:mm" : "MMM d, yyyy HH:mm"
            return dateFormatter.string(from: dateObj)
        }, popupValueFormatter: { newLabel in
            guard let amount = Double(newLabel) else {
                return ""
            }
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(amount, TokenStore.baseCurrency)
            return baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundUp: true)
        }, onHighlightChange: { [weak self] highlight in
            self?.lastHighlight = highlight
            self?.fillLabels()
        })
        lineChartView.alpha = 0
        lineChartView.isHidden = true
        lineChartView.xAxis.valueFormatter = ChartTimeFormatter()
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
        label.textColor = WTheme.secondaryLabel
        label.font = .systemFont(ofSize: 13)
        label.alpha = 0
        return label
    }()

    private let arrowImageView: UIImageView = {
        let arrowImageView = UIImageView(image: UIImage(systemName: "chevron.down",
                                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 10,
                                                                                                       weight: .bold))!
            .withRenderingMode(.alwaysTemplate))
        arrowImageView.tintColor = WTheme.primaryLabel.withAlphaComponent(0.3)
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        arrowImageView.contentMode = .center
        return arrowImageView
    }()

    private lazy var rangeChart: RangeChartView = {
        let v = RangeChartView()
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
        addSubview(priceTitleLabel)
        addSubview(priceValueLabel)
        addSubview(priceChangeLabel)
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
        arrowRightConstraint = arrowImageView.rightAnchor.constraint(equalTo: rightAnchor, constant: -18)
        chartAnimationViewRightAnchor = lineChartAnimationView.rightAnchor.constraint(equalTo: rightAnchor, constant: -33)
        chartAnimationViewTopAnchor = lineChartAnimationView.topAnchor.constraint(equalTo: topAnchor, constant: 11.33)
        chartAnimationViewWidthAnchor = lineChartAnimationView.widthAnchor.constraint(equalToConstant: 82)
        chartAnimationViewHeightAnchor = lineChartAnimationView.heightAnchor.constraint(equalToConstant: 40)

        expandedChartRightConstraint = expandedChart.rightAnchor.constraint(equalTo: rightAnchor, constant: -16)
        expandedChartWidthConstraint = expandedChart.widthAnchor.constraint(equalTo: widthAnchor, constant: -6)

        let loadingIndicatorXConstraint = loadingIndicator.centerXAnchor.constraint(equalTo: lineChartAnimationView.centerXAnchor)
        loadingIndicatorXConstraint.priority = .init(999)

        let noPriceDataLabelXConstraint = noPriceDataLabel.centerXAnchor.constraint(equalTo: loadingIndicator.centerXAnchor)
        noPriceDataLabelXConstraint.priority = .defaultHigh

        rangeChart.rangeDidChangeClosure = { [weak self] range in
            self?.rangeChanged(range)
        }

        NSLayoutConstraint.activate([
            topBarView.leftAnchor.constraint(equalTo: leftAnchor),
            topBarView.rightAnchor.constraint(equalTo: rightAnchor),
            topBarView.topAnchor.constraint(equalTo: topAnchor),
            topBarView.heightAnchor.constraint(equalToConstant: 60),

            priceTitleLabel.leftAnchor.constraint(equalTo: leftAnchor, constant: 16),
            priceTitleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            priceValueLabel.leftAnchor.constraint(equalTo: leftAnchor, constant: 16),
            priceValueLabel.topAnchor.constraint(equalTo: priceTitleLabel.bottomAnchor, constant: 1),

            priceChangeLabel.firstBaselineAnchor.constraint(equalTo: priceValueLabel.firstBaselineAnchor),
            priceChangeLabel.leadingAnchor.constraint(equalTo: priceValueLabel.trailingAnchor, constant: 6),

            collapsedChart.rightAnchor.constraint(equalTo: rightAnchor, constant: -33),
            collapsedChart.topAnchor.constraint(equalTo: topAnchor, constant: 11.33),
            collapsedChart.widthAnchor.constraint(equalToConstant: 82),
            collapsedChart.heightAnchor.constraint(equalToConstant: 40),

            expandedChartRightConstraint,
            expandedChart.topAnchor.constraint(equalTo: topAnchor, constant: 35),
            expandedChartWidthConstraint,
            expandedChart.heightAnchor.constraint(equalToConstant: TokenExpandableChartView.expandedChartHeight),

            loadingIndicatorXConstraint,
            loadingIndicator.centerXAnchor.constraint(greaterThanOrEqualTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: lineChartAnimationView.centerYAnchor),

            noPriceDataLabelXConstraint,
            noPriceDataLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -46),
            noPriceDataLabel.centerYAnchor.constraint(equalTo: loadingIndicator.centerYAnchor),

            chartAnimationViewRightAnchor,
            chartAnimationViewTopAnchor,
            chartAnimationViewWidthAnchor,
            chartAnimationViewHeightAnchor,

            arrowRightConstraint,
            arrowImageView.topAnchor.constraint(equalTo: topAnchor, constant: 25),

            rangeChart.leadingAnchor.constraint(equalTo: leadingAnchor),
            rangeChart.trailingAnchor.constraint(equalTo: trailingAnchor),
            rangeChart.bottomAnchor.constraint(equalTo: timeFrameSwitcherView.topAnchor, constant: -12),
            rangeChart.heightAnchor.constraint(equalToConstant: 30),

            timeFrameSwitcherView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            timeFrameSwitcherView.leftAnchor.constraint(equalTo: leftAnchor, constant: 16),
            timeFrameSwitcherView.rightAnchor.constraint(equalTo: rightAnchor, constant: -16),
            timeFrameSwitcherView.heightAnchor.constraint(equalToConstant: 28),

            heightConstraint
        ])

        topBarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleChart)))

        updateTheme()

        loadingIndicator.startAnimating(animated: true)

        if AppStorageHelper.isTokenChartExpanded {
            DispatchQueue.main.async {
                self.toggleChart(instant: true)
            }
        }
    }

    func updateTheme() {
        backgroundColor = WTheme.groupedItem
        priceTitleLabel.textColor = WTheme.secondaryLabel
        loadingIndicator.tintColor = WTheme.tint
    }

    // MARK: - Data mehods

    private func fillLabels() {
        guard let token, let tokenPrice = token.price else {
            // TODO: No price available message
            priceValueLabel.text = nil
            return
        }
        if let lastHighlight {
            let priceAmount = BaseCurrencyAmount.fromDouble(lastHighlight.y, TokenStore.baseCurrency)
            let priceString = priceAmount.formatted(.baseCurrencyHighPrecision, roundUp: true)
            let attr = NSAttributedString(string: priceString, attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: WTheme.primaryLabel
            ])
            priceValueLabel.attributedText = attr

            let percent = NSAttributedString(string: "\(expandedChart.xAxis.valueFormatter?.stringForValue(lastHighlight.x, axis: collapsedChart.xAxis) ?? "")", attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: WTheme.secondaryLabel
            ])
            priceChangeLabel.attributedText = percent

        } else if selectedRange != 0...1 {
            let historyData = scope(data: self.historyData, range: selectedRange)
            let firstPriceInChart = historyData?.first(where: { val in val[1] != 0 })?[1]
            let lastPrice: Double = historyData?.last(where: { val in val[1] != 0 })?[1] ?? tokenPrice
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(lastPrice, TokenStore.baseCurrency)
            let priceString = baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundUp: true)
            let attr = NSAttributedString(string: priceString, attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: WTheme.primaryLabel
            ])
            priceValueLabel.attributedText = attr
            var percentChange: Double?
            if let firstPriceInChart {
                percentChange = (lastPrice - firstPriceInChart) / firstPriceInChart
            }
            if let percentChange {
                let percent = NSAttributedString(string: formatPercent(percentChange), attributes: [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: percentChange > 0 ? WTheme.positiveAmount : (percentChange == 0 ? WTheme.secondaryLabel : WTheme.negativeAmount)
                ])
                priceChangeLabel.attributedText = percent
            } else {
                priceChangeLabel.attributedText = nil
            }

        } else {
            let lastPrice: Double = historyData?.last(where: { val in val[1] != 0 })?[1] ?? tokenPrice
            var percentChange: Double?
            if let firstPriceInChart = historyData?.first(where: { val in val[1] != 0 })?[1] {
                percentChange = (lastPrice - firstPriceInChart) / firstPriceInChart
            }
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(lastPrice, TokenStore.baseCurrency)
            let priceString = baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundUp: true)
            let attr = NSAttributedString(string: priceString, attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: WTheme.primaryLabel
            ])
            priceValueLabel.attributedText = attr

            if let percentChange {
                let percent = NSAttributedString(string: formatPercent(percentChange), attributes: [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: percentChange > 0 ? WTheme.positiveAmount : (percentChange == 0 ? WTheme.secondaryLabel : WTheme.negativeAmount)
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
                           rangeOnly: Bool,
                           completion: (() -> Void)? = nil) {
        let historyData = reduceNumberOfPoints(data, to: 200)
        let scopedData = scope(data: data ?? [], range: range)
        _ = consume data

        var periodChanged = false
        if let period, period != self.displayedPeriod {
            periodChanged = true
            lastHighlight = nil
            self.displayedPeriod = period
        }

        if let historyData {
            UIView.animate(withDuration: 0.2) { [self] in
                loadingIndicator.stopAnimating(animated: true)
                collapsedChart.alpha = 1
                expandedChart.alpha = 1
                rangeChart.chartView.alpha = 1
                rangeChart.imageView.alpha = 1
                noPriceDataLabel.alpha = historyData.isEmpty ? 1 : 0
                rangeChart.alpha = !isExpanded || historyData.isEmpty ? 0 : 1
            }
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
        dateFormatter.dateFormat = dateFormat

        processorQueue.async(flags: .barrier) { [self] in
            let allDataEntries: [ChartDataEntry] = (historyData ?? []).map { item in ChartDataEntry(x: item[0], y: item[1]) }
            let scopedDataEntries: [ChartDataEntry] = (scopedData ?? []).map { item in ChartDataEntry(x: item[0], y: item[1]) }

            let collapsedDataSet = LineChartDataSet(entries: allDataEntries)
            collapsedDataSet.colors = [WTheme.tint]
            collapsedDataSet.drawCirclesEnabled = false
            collapsedDataSet.drawFilledEnabled = true
            collapsedDataSet.drawValuesEnabled = false
            collapsedDataSet.drawHorizontalHighlightIndicatorEnabled = false
            collapsedDataSet.lineWidth = 1
            collapsedDataSet.highlightColor = WTheme.tint
            collapsedDataSet.mode = .cubicBezier

            let gradientColors = [WTheme.tint.withAlphaComponent(0.2).cgColor, UIColor.clear.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: gradientColors as CFArray,
                                      locations: [0.4, 1.0])!
            collapsedDataSet.fill = LinearGradientFill(gradient: gradient, angle: -90)
            let collapsedChartData = LineChartData(dataSet: collapsedDataSet)

            let expandedDataSet = collapsedDataSet.copy() as! LineChartDataSet
            expandedDataSet.replaceEntries(scopedDataEntries)
            expandedDataSet.lineWidth = 2
            let expandedChartData = LineChartData(dataSet: expandedDataSet)

            let rangeDataSet = collapsedDataSet.copy() as! LineChartDataSet
            rangeDataSet.lineWidth = 2
            let rangeChartData = LineChartData(dataSet: rangeDataSet)

            DispatchQueue.main.sync {
                self.collapsedChartData = collapsedChartData
                self.expandedChartData = expandedChartData
                self.rangeChartData = rangeChartData

                self.expandedChartWidthConstraint.constant = -16 + (self.expandedChart.frame.width - self.expandedChart.viewPortHandler.contentWidth)
                self.expandedChartRightConstraint.constant = -16 + (self.expandedChart.frame.width - self.expandedChart.viewPortHandler.contentRight)

                if !rangeOnly {
                    self.collapsedChart.data = self.collapsedChartData
                }
                self.expandedChart.data = self.expandedChartData
                if !rangeOnly && !isTogglingChart {
                    self.rangeChart.chartView.data = self.collapsedChartData
                    let image = self.rangeChart.chartView.asImage(padding: 0)
                    self.rangeChart.imageView.image = image
                }
                if !scopedDataEntries.isEmpty {
                    let shouldResetHighlight = periodChanged
                        || self.expandedChart.highlighted.isEmpty
                        || self.expandedChart.highlighted.first?.x ?? 0 < scopedDataEntries.first?.x ?? 0
                        || self.expandedChart.highlighted.last?.x ?? 0 < scopedDataEntries.last?.x ?? 0
                        || lastHighlight == nil
                    if shouldResetHighlight {
                        self.expandedChart.highlightValue(x: scopedDataEntries.last?.x ?? 0, dataSetIndex: 0)
                    }
                }
                completion?()
            }
        }
    }

    @objc private func handlePeriodChange() {
        let period = timePeriods[timeFrameSwitcherView.selectedSegmentIndex]
        let hasData = TokenStore.historyData(tokenSlug: token?.slug ?? "")?.data[period] != nil
        loadingIndicator.startAnimating(animated: true)
        UIView.animate(withDuration: 0.2) { [self] in
            rangeChart.setRange(0...1, animated: true)
            collapsedChart.alpha = 0
            expandedChart.alpha = 0
            rangeChart.chartView.alpha = 0
            rangeChart.imageView.alpha = 0
            if !hasData {
                priceChangeLabel.alpha = 0
            }
        } completion: { [self] ok in
            lastHighlight = nil
            if ok, loadingIndicator.isAnimating, loadingIndicator.layer.presentation()?.opacity == 1 {
                UIView.performWithoutAnimation {
                    drawChart(period: period, historyData: [], range: 0...1, rangeOnly: false)
                }
            }
        }
        onPeriodChange?(period)
    }

    @objc private func toggleChart(instant: Bool) {
        if isTogglingChart {
            return
        }
        isTogglingChart = true
        isExpanded = !isExpanded
        collapsedChart.isUserInteractionEnabled = isExpanded

        parentProcessorQueue.async {
            self.locker.wait()

            DispatchQueue.main.async {
                self._toggleChartImpl(instant: instant)
            }
        }
    }

    private func _toggleChartImpl(instant: Bool) {
        let targetHeight = isExpanded ? TokenExpandableChartView.expandedHeight : TokenExpandableChartView.collapsedHeight

        let collapsedPoints: (CGFloat, CGFloat, CGFloat, CGFloat) = {
            let viewPortHandler = collapsedChart.viewPortHandler
            let contentLeft = viewPortHandler.contentLeft
            let contentTop = viewPortHandler.contentTop
            let contentRight = collapsedChart.frame.width - viewPortHandler.contentWidth - viewPortHandler.contentLeft
            let contentBottom = collapsedChart.frame.height - viewPortHandler.contentBottom

            let endWidth = 82 - contentLeft - contentRight
            let endHeight = 40 - contentTop - contentBottom
            let endTop = 11.33 + contentTop
            let endRight = -33 - contentRight

            return (endWidth, endHeight, endTop, endRight)
        }()

        let expandedPoints: (CGFloat, CGFloat, CGFloat, CGFloat) = {
            let viewPortHandler = expandedChart.viewPortHandler
            let contentLeft = viewPortHandler.contentLeft - 4
            let contentTop = viewPortHandler.contentTop - 4
            let contentRight = expandedChart.frame.width - viewPortHandler.contentWidth - viewPortHandler.contentLeft - 4
            let contentBottom = expandedChart.frame.height - viewPortHandler.contentBottom - 4

            let endWidth = expandedChart.frame.width - contentLeft - contentRight
            let endHeight = expandedChart.frame.height - contentTop - contentBottom
            let endTop = 35 + contentTop
            let endRight = expandedChartRightConstraint.constant - contentRight

            if viewPortHandler.contentWidth < 0 {
                return (
                    screenWidth - 60,
                    min(0.36 * (screenWidth - 78), TokenExpandableChartView.expandedChartHeight),
                    41,
                    -22
                )
            }
            return (endWidth, endHeight, endTop, endRight)
        }()

        let (startWidth, startHeight, startTop, startRight) = isExpanded ? collapsedPoints : expandedPoints
        let (endWidth, endHeight, endTop, endRight) = isExpanded ? expandedPoints : collapsedPoints

        let updateBlock: (CGFloat, CGFloat) -> () = { [self] (progress: CGFloat, value: CGFloat) in
            heightConstraint.constant = value

            // Animate line charts
            let currentWidth = startWidth + (endWidth - startWidth) * CGFloat(progress)
            let currentHeight = startHeight + (endHeight - startHeight) * CGFloat(progress)
            let currentTop = startTop + (endTop - startTop) * CGFloat(progress)
            let currentRight = startRight + (endRight - startRight) * CGFloat(progress)

            chartAnimationViewWidthAnchor.constant = currentWidth
            chartAnimationViewHeightAnchor.constant = currentHeight
            chartAnimationViewTopAnchor.constant = currentTop
            chartAnimationViewRightAnchor.constant = currentRight

            if isExpanded {
                largeChartImageView.alpha = progress
                smallChartImageView.alpha = 1 - progress * 2
                rangeChart.alpha = historyData?.isEmpty ?? true ? 0 : 2 * (progress - 0.5)
                timeFrameSwitcherView.alpha = 2 * (progress - 0.5)
            } else {
                smallChartImageView.alpha = (progress - 0.5) * 2
                largeChartImageView.alpha = 1 - progress
                rangeChart.alpha = historyData?.isEmpty ?? true ? 0 : 1 - 2 * progress
                timeFrameSwitcherView.alpha = 1 - 2 * progress
            }

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
            smallChartImageView.image = collapsedChart.asImage(padding: 0)
            largeChartImageView.image = expandedChart.asImage(padding: 4)
            collapsedChart.isHidden = true
            expandedChart.isHidden = true
            lineChartAnimationView.alpha = 1
            drawChart(period: self.displayedPeriod, historyData: nil, range: selectedRange, rangeOnly: false)
            updateBlock(0, heightConstraint.constant)
            let heightAnimator = ValueAnimator(startValue: heightConstraint.constant, endValue: targetHeight, duration: 0.35)
            heightAnimator.addUpdateBlock { progress, value in
                updateBlock(progress, value)
            }
            heightAnimator.addCompletionBlock { [weak self] in
                guard let self else { return }
                AppStorageHelper.isTokenChartExpanded = isExpanded
                drawChart(period: displayedPeriod, historyData: historyData, range: selectedRange, rangeOnly: false) { [weak self] in
                    guard let self else { return }
                    expandedChart.isHidden = isExpanded ? false : true
                    collapsedChart.isHidden = isExpanded ? true : false
                    lineChartAnimationView.alpha = 0
                    isTogglingChart = false
                    locker.signal()
                }
            }
            heightAnimator.start()
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) { [self] in
                arrowImageView.transform = arrowImageView.transform.rotated(by: .pi)
                loadingIndicator.transform = isExpanded ? .identity.scaledBy(x: 1.2, y: 1.2) : .identity
            }
        }
    }
}

// MARK: - Helper functions

/// Halves the number of points until it's less than **to**
private func reduceNumberOfPoints(_ data: [[Double]]?, to: Int) -> [[Double]]? {
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
private func scope(data: [[Double]]?, range:  ClosedRange<CGFloat>) -> [[Double]]? {
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

class ChartTimeFormatter: AxisValueFormatter {

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        return dateFormatter.string(from: Date(timeIntervalSince1970: value))
    }
}
