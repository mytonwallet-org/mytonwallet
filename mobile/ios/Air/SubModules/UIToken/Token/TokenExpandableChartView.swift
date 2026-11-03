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

    static let collapsedHeight = CGFloat(64)
    private static let expandedChartMaxHeight = CGFloat(200)
    private static let expandedChartTrailingOffset = CGFloat(-12)
    private static let analyzeButtonSpacing = CGFloat(20)
    private static var expandedChartHeight: CGFloat {
        let height = 0.36 * (screenWidth - 32 - 6)
        return min(height, expandedChartMaxHeight)
    }
    private var analyzeButtonInset: CGFloat {
        onAnalyze == nil ? 0 : Self.analyzeButtonSpacing + AgentSuggestionButton.height
    }
    private var expandedHeight: CGFloat {
        60 + 12 + Self.expandedChartHeight + 12 + 36 + 16 + analyzeButtonInset
    }
    private var expandedLoadingIndicatorOffset: CGFloat {
        // Center in the plot area, excluding the time axis and controls below it.
        60 + Self.expandedChartHeight / 2 - expandedHeight / 2
    }

    private let parentProcessorQueue = DispatchQueue(label: "TokenExpandableChartView")
    private let locker = DispatchSemaphore(value: 1)
    private let onHeightChange: () -> Void
    private let usesStoredPresentation: Bool

    public init(usesStoredPresentation: Bool = true, onHeightChange: @escaping () -> Void) {
        self.usesStoredPresentation = usesStoredPresentation
        self.onHeightChange = onHeightChange
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var token: ApiToken? = nil
    private var price: Double?
    private var percentChange24h: Double?
    private var baseCurrency: MBaseCurrency = .USD
    private var displayedPeriod: ApiPriceHistoryPeriod? = nil
    private var historyData: [[Double]]? = nil
    private var isHistoryRestored = false
    private var historyLoadingState: TokenHistoryLoadingState = .loading
    private struct Configuration: Equatable {
        var tokenSlug: String
        var price: Double?
        var percentChange24h: Double?
        var baseCurrency: MBaseCurrency
        var historyData: [[Double]]?
        var isHistoryRestored: Bool
        var historyLoadingState: TokenHistoryLoadingState
        var isHistoryStale: Bool
        var isValueStale: Bool
        var showsAnalyze: Bool
        var showsTokenIcon: Bool
        var priceTitle: String?
    }
    private var configuration: Configuration?
    private let graph = CompactLineChart()
    private var onPeriodChange: ((ApiPriceHistoryPeriod) -> Void)? = nil
    private var onAnalyze: (() -> Void)?

    private var selectedRange: ClosedRange<CGFloat> = 0...1
    private var chartExpansionProgress: CGFloat = 0
    private weak var toggleChartRecognizer: UITapGestureRecognizer?

    override func tintColorDidChange() {
        super.tintColorDidChange()
        refreshChartTint()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.layoutDirection != previousTraitCollection?.layoutDirection {
            setNeedsUpdateConstraints()
        }
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            refreshChartTint()
        }
    }

    override var semanticContentAttribute: UISemanticContentAttribute {
        didSet { setNeedsUpdateConstraints() }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        setNeedsUpdateConstraints()
    }

    override func updateConstraints() {
        let direction = effectiveUserInterfaceLayoutDirection
        if loadingIndicatorLayoutDirection != direction {
            loadingIndicatorCenterBoundary?.isActive = false
            // Keep the indicator in the trailing half in both layout directions.
            loadingIndicatorCenterBoundary = direction == .rightToLeft
                ? loadingIndicator.centerXAnchor.constraint(lessThanOrEqualTo: centerXAnchor)
                : loadingIndicator.centerXAnchor.constraint(greaterThanOrEqualTo: centerXAnchor)
            loadingIndicatorCenterBoundary?.isActive = true
            loadingIndicatorLayoutDirection = direction
        }
        super.updateConstraints()
    }

    func configure(token: ApiToken,
                   showsTokenIcon: Bool = false,
                   historyData: [[Double]]?,
                   isHistoryRestored: Bool,
                   historyLoadingState: TokenHistoryLoadingState? = nil,
                   onPeriodChange: @escaping (ApiPriceHistoryPeriod) -> Void,
                   onAnalyze: (() -> Void)?) {
        configure(token: token, price: token.price, percentChange24h: token.percentChange24h,
                  baseCurrency: TokenStore.baseCurrency, showsTokenIcon: showsTokenIcon,
                  historyData: historyData, isHistoryRestored: isHistoryRestored,
                  historyLoadingState: historyLoadingState,
                  onPeriodChange: onPeriodChange, onAnalyze: onAnalyze)
    }

    func configure(token: ApiToken,
                   price: Double?,
                   percentChange24h: Double?,
                   baseCurrency: MBaseCurrency,
                   period: ApiPriceHistoryPeriod? = nil,
                   showsTokenIcon: Bool = true,
                   priceTitle: String? = nil,
                   historyData: [[Double]]?,
                   isHistoryRestored: Bool = false,
                   historyLoadingState: TokenHistoryLoadingState? = nil,
                   isHistoryStale: Bool = false,
                   isValueStale: Bool = false,
                   onPeriodChange: @escaping (ApiPriceHistoryPeriod) -> Void,
                   onAnalyze: (() -> Void)? = nil) {
        self.onPeriodChange = onPeriodChange
        self.onAnalyze = onAnalyze
        if let period, let index = timePeriods.firstIndex(of: period),
           timeFrameSwitcherView.selectedSegmentIndex != index {
            timeFrameSwitcherView.selectedSegmentIndex = index
            selectedRange = 0...1
            lastSelection = nil
            self.configuration = nil
        }
        let configuration = Configuration(
            tokenSlug: token.slug,
            price: price,
            percentChange24h: percentChange24h,
            baseCurrency: baseCurrency,
            historyData: historyData,
            isHistoryRestored: isHistoryRestored,
            historyLoadingState: historyLoadingState ?? (historyData == nil ? .loading : .loaded),
            isHistoryStale: isHistoryStale,
            isValueStale: isValueStale,
            showsAnalyze: onAnalyze != nil,
            showsTokenIcon: showsTokenIcon,
            priceTitle: priceTitle
        )
        guard configuration != self.configuration else { return }
        let isFirstConfiguration = self.configuration == nil && self.token == nil
        self.configuration = configuration
        self.token = token
        self.price = price
        self.percentChange24h = percentChange24h
        self.baseCurrency = baseCurrency
        self.historyData = historyData
        self.isHistoryRestored = isHistoryRestored
        self.historyLoadingState = configuration.historyLoadingState
        [collapsedChartShine, expandedChartShine, chartAnimationShine].forEach {
            $0.setActive(isHistoryStale && historyData?.isEmpty == false, animated: !isFirstConfiguration)
        }
        priceShine.setActive(isValueStale && price != nil, animated: !isFirstConfiguration)
        tokenIconView.config(with: token, isStaking: false, isWalletView: false, shouldShowChain: false)
        tokenIconView.alpha = showsTokenIcon ? 1 : 0
        priceTitleLabel.text = priceTitle ?? lang("Price")
        priceLeadingConstraint.constant = showsTokenIcon ? 66 : 16
        if isHistoryRestored {
            lastSelection = nil
        }
        expandedChart.isUserInteractionEnabled = isExpanded && !isHistoryRestored
        analyzeButton.configure(title: lang("Analyze it"), showsArrow: true)
        analyzeButton.isHidden = onAnalyze == nil
        analyzeButton.isUserInteractionEnabled = isExpanded && onAnalyze != nil
        timeFrameBottomConstraint.constant = -16 - analyzeButtonInset
        if isExpanded && !isTogglingChart {
            heightConstraint.constant = expandedHeight
            loadingIndicatorCenterYConstraint.constant = expandedLoadingIndicatorOffset
        }

        fillLabels()

        drawChart(period: nil, historyData: historyData, range: selectedRange)
        if isFirstConfiguration, showsTokenIcon, !isExpanded, !isTogglingChart {
            toggleChart(instant: true)
        }
    }

    func rangeChanged(_ range: ClosedRange<CGFloat>) {
        selectedRange = range
        lastSelection = nil
        fillLabels()
    }

    private var heightConstraint: NSLayoutConstraint!
    private var priceLeadingConstraint: NSLayoutConstraint!
    private var timeFrameBottomConstraint: NSLayoutConstraint!
    private var arrowTrailingConstraint: NSLayoutConstraint!
    private var loadingIndicatorCenterYConstraint: NSLayoutConstraint!
    private var loadingIndicatorCenterBoundary: NSLayoutConstraint?
    private var loadingIndicatorLayoutDirection: UIUserInterfaceLayoutDirection?

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

    private let tokenIconView = IconView(size: 40)

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
        lbl.accessibilityIdentifier = "token_price_value"
        return lbl
    }()

    private let priceChangeLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.accessibilityIdentifier = "token_price_change"
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
        indicator.accessibilityIdentifier = "Token.Chart.Loading"
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

    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("\(lang("Error"))\n\(lang("Retry"))", for: .normal)
        button.titleLabel?.font = WTypography.uiFont(.footnote)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.accessibilityIdentifier = "Token.Chart.Retry"
        button.isHidden = true
        button.addTarget(self, action: #selector(handlePeriodChange), for: .touchUpInside)
        return button
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

    private let timeAxisLabels: [UILabel] = (0..<4).map { index in
        let label = UILabel()
        label.applyTextStyle(.footnote, content: .technical)
        label.textColor = .air.secondaryLabel
        label.textAlignment = index == 0 ? .left : index == 3 ? .right : .center
        return label
    }

    private lazy var timeAxisView: UIStackView = {
        let view = UIStackView(arrangedSubviews: timeAxisLabels)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.distribution = .equalSpacing
        view.alpha = 0
        return view
    }()

    private let timePeriods: [ApiPriceHistoryPeriod] = ApiPriceHistoryPeriod.allCases.reversed()

    private lazy var timeFrameSwitcherView = {
        let switcherView = WChartSegmentedControl(items: timePeriods.map { $0.localized })
        switcherView.translatesAutoresizingMaskIntoConstraints = false
        switcherView.alpha = 0
        return switcherView
    }()

    private lazy var analyzeButton: AgentSuggestionButton = {
        let button = AgentSuggestionButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.alpha = 0
        button.isUserInteractionEnabled = false
        button.accessibilityIdentifier = "Token.Analyze"
        button.addAction(UIAction { [weak self] _ in
            self?.onAnalyze?()
        }, for: .touchUpInside)
        return button
    }()

    private lazy var topBarView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()

    private let priceContainer = UIView()
    private lazy var priceShine = makeShine(content: priceContainer, identifier: "Token.Chart.QuoteShine")
    private lazy var collapsedChartShine = makeShine(content: collapsedChart, identifier: "Token.Chart.PreviewShine")
    private lazy var expandedChartShine = makeShine(content: expandedChart, identifier: "Token.Chart.PlotShine")
    private lazy var chartAnimationShine = makeShine(content: lineChartAnimationView, identifier: "Token.Chart.AnimationShine")

    private func makeShine(content: UIView, identifier: String) -> TradeShineView {
        let shine = TradeShineView(content: content, usesAutoLayout: true)
        shine.translatesAutoresizingMaskIntoConstraints = false
        shine.isUserInteractionEnabled = content.isUserInteractionEnabled
        shine.accessibilityIdentifier = identifier
        return shine
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = S.homeInsetSectionCornerRadius
        layer.masksToBounds = true
        addSubview(collapsedChartShine)
        addSubview(expandedChartShine)
        addSubview(rangeChart)
        rangeChart.isHidden = true
        rangeChart.isUserInteractionEnabled = false
        rangeChart.horizontalInteractionBlockingGestureRecognizer.isEnabled = false
        addSubview(timeAxisView)
        addSubview(chartAnimationShine)
        addSubview(arrowImageView)
        addSubview(timeFrameSwitcherView)
        addSubview(analyzeButton)
        addSubview(topBarView)
        addSubview(loadingIndicator)
        addSubview(noPriceDataLabel)
        addSubview(retryButton)
        timeFrameSwitcherView.addTarget(self, action: #selector(handlePeriodChange), for: .valueChanged)
        timeFrameSwitcherView.selectedSegmentIndex = timePeriods.firstIndex(where: { it in
            it.rawValue == (usesStoredPresentation ? AppStorageHelper.selectedCurrentTokenPeriod() : ApiPriceHistoryPeriod.day.rawValue)
        }) ?? 0
        heightConstraint = heightAnchor.constraint(equalToConstant: (!usesStoredPresentation || AppStorageHelper.isTokenChartExpanded) ? expandedHeight : Self.collapsedHeight)
        timeFrameBottomConstraint = timeFrameSwitcherView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16 - analyzeButtonInset)
        arrowTrailingConstraint = arrowImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18)
        chartAnimationViewTrailingAnchor = chartAnimationShine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -33)
        chartAnimationViewTopAnchor = chartAnimationShine.topAnchor.constraint(equalTo: topAnchor, constant: 11.33)
        chartAnimationViewWidthAnchor = chartAnimationShine.widthAnchor.constraint(equalToConstant: 82)
        chartAnimationViewHeightAnchor = chartAnimationShine.heightAnchor.constraint(equalToConstant: 40)
        loadingIndicatorCenterYConstraint = loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)

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
        
        do {
            priceContainer.addSubview(priceTitleLabel)
            priceContainer.addSubview(priceValueLabel)
            priceContainer.addSubview(priceChangeLabel)
            priceContainer.addSubview(tokenIconView)
            tokenIconView.translatesAutoresizingMaskIntoConstraints = false
            tokenIconView.alpha = 0

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            priceContainer.addGestureRecognizer(longPress)

            let priceTap = UITapGestureRecognizer(target: self, action: #selector(handleToggleTap))
            priceContainer.addGestureRecognizer(priceTap)
            priceTap.require(toFail: longPress)
        }
        
        addSubview(priceShine)
        priceLeadingConstraint = priceTitleLabel.leadingAnchor.constraint(equalTo: priceContainer.leadingAnchor, constant: 16)

        NSLayoutConstraint.activate([
            topBarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBarView.topAnchor.constraint(equalTo: topAnchor),
            topBarView.heightAnchor.constraint(equalToConstant: Self.collapsedHeight),
            
            priceShine.leadingAnchor.constraint(equalTo: leadingAnchor),
            priceShine.topAnchor.constraint(equalTo: topAnchor),

            tokenIconView.leadingAnchor.constraint(equalTo: priceContainer.leadingAnchor, constant: 16),
            tokenIconView.topAnchor.constraint(equalTo: priceContainer.topAnchor, constant: 12),
            tokenIconView.widthAnchor.constraint(equalToConstant: 40),
            tokenIconView.heightAnchor.constraint(equalToConstant: 40),
            priceLeadingConstraint,
            priceTitleLabel.topAnchor.constraint(equalTo: priceContainer.topAnchor, constant: 10),

            priceValueLabel.leadingAnchor.constraint(equalTo: priceTitleLabel.leadingAnchor),
            priceValueLabel.topAnchor.constraint(equalTo: priceTitleLabel.bottomAnchor, constant: 1),
            priceValueLabel.bottomAnchor.constraint(equalTo: priceContainer.bottomAnchor, constant: -10),

            priceChangeLabel.firstBaselineAnchor.constraint(equalTo: priceValueLabel.firstBaselineAnchor),
            priceChangeLabel.leadingAnchor.constraint(equalTo: priceValueLabel.trailingAnchor, constant: 6),

            priceContainer.trailingAnchor.constraint(greaterThanOrEqualTo: priceTitleLabel.trailingAnchor, constant: 16),
            priceContainer.trailingAnchor.constraint(greaterThanOrEqualTo: priceChangeLabel.trailingAnchor, constant: 16),
            priceContainer.trailingAnchor.constraint(equalTo: priceTitleLabel.trailingAnchor, constant: 16).withPriority(.defaultHigh),
            priceContainer.trailingAnchor.constraint(equalTo: priceChangeLabel.trailingAnchor, constant: 16).withPriority(.defaultHigh),

            collapsedChartShine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -33),
            collapsedChartShine.topAnchor.constraint(equalTo: topAnchor, constant: 11.33),
            collapsedChartShine.widthAnchor.constraint(equalToConstant: 82),
            collapsedChartShine.heightAnchor.constraint(equalToConstant: 40),

            expandedChartShine.leadingAnchor.constraint(equalTo: leadingAnchor),
            expandedChartShine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: Self.expandedChartTrailingOffset),
            expandedChartShine.topAnchor.constraint(equalTo: topAnchor, constant: 60),
            expandedChartShine.heightAnchor.constraint(equalToConstant: TokenExpandableChartView.expandedChartHeight),

            timeAxisView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            timeAxisView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            timeAxisView.bottomAnchor.constraint(equalTo: timeFrameSwitcherView.topAnchor, constant: -6),
            timeAxisView.heightAnchor.constraint(equalToConstant: 18),

            loadingIndicatorXConstraint,
            loadingIndicatorCenterYConstraint,

            noPriceDataLabelXConstraint,
            noPriceDataLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -46),
            noPriceDataLabel.centerYAnchor.constraint(equalTo: loadingIndicator.centerYAnchor),

            retryButton.centerXAnchor.constraint(equalTo: noPriceDataLabel.centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: loadingIndicator.centerYAnchor),
            retryButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -46),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

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

            timeFrameBottomConstraint,
            timeFrameSwitcherView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            timeFrameSwitcherView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            timeFrameSwitcherView.heightAnchor.constraint(equalToConstant: 36),

            analyzeButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            analyzeButton.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
            analyzeButton.heightAnchor.constraint(equalToConstant: AgentSuggestionButton.height),
            analyzeButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            heightConstraint
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleToggleTap))
        toggleChartRecognizer = tap
        topBarView.addGestureRecognizer(tap)
        
        updateTheme()

        loadingIndicator.startAnimating(animated: false)

        if !usesStoredPresentation || AppStorageHelper.isTokenChartExpanded {
            DispatchQueue.main.async {
                if !self.isExpanded && !self.isTogglingChart {
                    self.toggleChart(instant: true)
                }
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
        guard let tokenPrice = price else {
            // TODO: No price available message
            priceValueLabel.text = nil
            priceChangeLabel.attributedText = nil
            return
        }
        if let lastSelection, !isHistoryRestored {
            let priceAmount = BaseCurrencyAmount.fromDouble(lastSelection.point.value, baseCurrency)
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
                historyData: isHistoryRestored ? nil : historyData,
                range: selectedRange,
                fallbackPrice: tokenPrice
            )
            let percentChange = tokenChartPercentChange(
                historyData: isHistoryRestored ? nil : historyData,
                range: selectedRange,
                tokenPercentChange24h: percentChange24h,
                shouldUseTokenPercentChange: timePeriods[timeFrameSwitcherView.selectedSegmentIndex] == .day,
                fallbackPrice: tokenPrice
            )
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(lastPrice, baseCurrency)
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
        updateTimeAxis(data)

        if let period, period != self.displayedPeriod {
            lastSelection = nil
            self.displayedPeriod = period
        }

        let hasData = data?.isEmpty == false
        let isLoading = historyLoadingState == .loading && !hasData
        noPriceDataLabel.isHidden = hasData || historyLoadingState != .loaded
        retryButton.isHidden = hasData || historyLoadingState != .failed
        if isLoading {
            loadingIndicator.startAnimating(animated: false)
        } else {
            loadingIndicator.stopAnimating(animated: false)
        }
        UIView.animate(withDuration: 0.2) { [self] in
            let chartAlpha: CGFloat = hasData ? (configuration?.isHistoryStale == true ? 0.55 : 1) : 0
            collapsedChart.alpha = chartAlpha
            expandedChart.alpha = chartAlpha
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
        chartAxisDateFormatter.locale = LocalizationSupport.shared.locale
        chartAxisDateFormatter.calendar = LocalizationSupport.shared.calendar
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
        configuration = nil
        historyData = nil
        historyLoadingState = .loading
        lastSelection = nil
        selectedRange = 0...1
        drawChart(period: period, historyData: nil, range: selectedRange)
        fillLabels()
        onPeriodChange?(period)
    }

    /// A tap toggles with the animation, which also saves the owned token preference. A gesture recognizer's action
    /// receives the recognizer, so it must not target `toggleChart(instant:)` directly.
    @objc private func handleToggleTap() {
        toggleChart(instant: false)
    }

    private func toggleChart(instant: Bool) {
        if isTogglingChart {
            return
        }
        isTogglingChart = true
        isExpanded = !isExpanded
        expandedChart.isUserInteractionEnabled = isExpanded && !isHistoryRestored
        analyzeButton.isUserInteractionEnabled = isExpanded && onAnalyze != nil

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
        let targetHeight = isExpanded ? expandedHeight : Self.collapsedHeight

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
            top: 60 + expandedSnapshotFrame.minY,
            trailing: Self.expandedChartTrailingOffset + expandedSnapshotFrame.maxX - expandedChart.bounds.width
        )

        let startGeometry = isExpanded ? collapsedGeometry : expandedGeometry
        let endGeometry = isExpanded ? expandedGeometry : collapsedGeometry

        let updateBlock: (CGFloat, CGFloat) -> () = { [self] progress, value in
            heightConstraint.constant = value
            chartExpansionProgress = isExpanded ? progress : 1 - progress
            loadingIndicatorCenterYConstraint.constant = expandedLoadingIndicatorOffset * (isExpanded ? progress : 1 - progress)

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
            analyzeButton.alpha = timeFrameSwitcherView.alpha
            updateTimeAxisVisibility()

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
                if usesStoredPresentation {
                    AppStorageHelper.isTokenChartExpanded = isExpanded
                }
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

    private func updateTimeAxis(_ data: [[Double]]?) {
        let timestamps = data?.compactMap { $0.first }.filter(\.isFinite) ?? []
        guard let first = timestamps.min(), let last = timestamps.max() else {
            timeAxisView.alpha = 0
            return
        }
        let formatter = DateFormatter()
        formatter.locale = LocalizationSupport.shared.locale
        let period = timePeriods[timeFrameSwitcherView.selectedSegmentIndex]
        formatter.setLocalizedDateFormatFromTemplate(period == .day ? "jmm" : period == .all ? "MMMyyyy" : "MMMd")
        for (index, label) in timeAxisLabels.enumerated() {
            let timestamp = first + (last - first) * Double(index) / Double(timeAxisLabels.count - 1)
            label.text = formatter.string(from: Date(timeIntervalSince1970: timestamp))
        }
        updateTimeAxisVisibility()
    }

    private func updateTimeAxisVisibility() {
        let alpha = min(1, max(0, (chartExpansionProgress - 0.85) / 0.15))
        timeAxisView.alpha = historyData?.isEmpty == false ? alpha : 0
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
