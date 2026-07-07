import GraphKit
import UIComponents
import UIKit
import WalletContext

private let portfolioChartHeight = CGFloat(400)
private let portfolioChartPanelInset = CGFloat(16)
private let portfolioChartPanelHorizontalInset = CGFloat(0)
private let portfolioSectionHeaderFont = UIFont.systemFont(ofSize: 17, weight: .semibold)

private func makePortfolioChartTheme(for traitCollection: UITraitCollection) -> ChartTheme {
    let baseTheme = ChartTheme.extractedTheme(for: traitCollection.userInterfaceStyle)

    return ChartTheme(
        chartTitleColor: baseTheme.chartTitleColor,
        actionButtonColor: baseTheme.actionButtonColor,
        chartBackgroundColor: .air.groupedItem,
        chartLabelsColor: baseTheme.chartLabelsColor,
        chartHelperLinesColor: baseTheme.chartHelperLinesColor,
        chartStrongLinesColor: baseTheme.chartStrongLinesColor,
        barChartStrongLinesColor: baseTheme.barChartStrongLinesColor,
        chartDetailsTextColor: baseTheme.chartDetailsTextColor,
        chartDetailsArrowColor: baseTheme.chartDetailsArrowColor,
        chartDetailsViewColor: .air.groupedItem,
        rangeViewFrameColor: baseTheme.rangeViewFrameColor,
        rangeViewTintColor: baseTheme.rangeViewTintColor,
        rangeViewMarkerColor: baseTheme.rangeViewMarkerColor,
        rangeCropImage: baseTheme.rangeCropImage
    )
}

private func makePortfolioChartStrings() -> ChartStrings {
    let formatter = MtwChartDateFormatter.portfolioChart

    return ChartStrings(
        zoomOut: lang("Zoom Out"),
        today: lang("Today"),
        total: lang("Total"),
        revenueInTon: ChartStrings.defaultStrings.revenueInTon,
        revenueInStars: ChartStrings.defaultStrings.revenueInStars,
        revenueInUsd: ChartStrings.defaultStrings.revenueInUsd,
        dateTextFormatter: ChartDateTextFormatter(
            rangeTitle: { fromDate, toDate in
                formatter.rangeString(from: fromDate, to: toDate)
            },
            singleDate: { date in
                formatter.singleDateString(from: date, includesTime: false)
            },
            singleDateTime: { date in
                formatter.singleDateString(from: date, includesTime: true)
            },
            axisDate: { date in
                formatter.axisDateString(from: date)
            },
            axisTime: { date in
                formatter.axisTimeString(from: date)
            }
        )
    )
}

enum PortfolioGraphKind: String {
    case totalValue
    case totalPnl
    case dailyPnl
    case portfolioShare

    var chartType: ChartType {
        switch self {
        case .totalValue:
            return .absoluteArea
        case .totalPnl:
            return .lines
        case .dailyPnl:
            return .bars
        case .portfolioShare:
            return .pie
        }
    }

    var keepsFullRangePreviewWhenZoomed: Bool {
        switch self {
        case .totalValue, .totalPnl, .dailyPnl:
            return false
        case .portfolioShare:
            return true
        }
    }

    var yAxisRepresentsBaseCurrency: Bool {
        switch self {
        case .totalValue, .totalPnl, .dailyPnl:
            return true
        case .portfolioShare:
            return false
        }
    }
}

struct PortfolioChartTileCellConfiguration {
    enum State {
        case idle
        case error(String)
        case loading
        case noData
        case chart(presentation: PortfolioGraphKitAdapter.ChartPresentation, kind: PortfolioGraphKind, pieVisible: Bool?)

        var isChart: Bool {
            if case .chart = self {
                return true
            }
            return false
        }
    }

    let title: String
    let state: State
    let isRefreshing: Bool
    let fadesCurrentData: Bool
    let hidesVerticalAxisLabels: Bool
    let onLimitedHistoryTap: (() -> Void)?
}

class PortfolioTileCell: UICollectionViewCell {
    let tileContentView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        tileContentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tileContentView)

        NSLayoutConstraint.activate([
            tileContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tileContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tileContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tileContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}

final class PortfolioChartTileCell: PortfolioTileCell {
    private var onRetry: (() -> Void)?
    private var onLimitedHistoryTap: (() -> Void)?
    private var onPreferredHeightChanged: (() -> Void)?
    private var chartSignature: String?
    private var chartPieVisible: Bool?
    private var chartController: BaseChartController?
    private var pendingRangeReset = false
    private var isShowingChart = false
    private var pendingChartFadeIn = false
    private var lastMeasuredChartWidth: CGFloat = 0
    private var lastKnownChartHeight: CGFloat = portfolioChartHeight

    private let titleLabel = UILabel()
    private let headerContainer = UIView()
    private let rootStack = UIStackView()
    private let panelContainer = UIView()
    private let panelStack = UIStackView()
    private let stateContainer = UIView()
    private let chartView = ChartContainerView()
    private let loadingStack = UIStackView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private let noDataLabel = UILabel()
    private let errorStack = UIStackView()
    private let errorTitleLabel = UILabel()
    private let errorTextLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let refreshIndicator = UIActivityIndicatorView(style: .medium)
    private let stateHeightConstraint: NSLayoutConstraint

    override init(frame: CGRect) {
        self.stateHeightConstraint = stateContainer.heightAnchor.constraint(equalToConstant: portfolioChartHeight)
        self.stateHeightConstraint.priority = UILayoutPriority(999)
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        onRetry = nil
        onLimitedHistoryTap = nil
        onPreferredHeightChanged = nil
        chartSignature = nil
        chartPieVisible = nil
        chartController = nil
        pendingRangeReset = false
        isShowingChart = false
        pendingChartFadeIn = false
        lastKnownChartHeight = portfolioChartHeight
        chartView.setLimitedRange(fraction: nil, tapAction: nil)
        refreshIndicator.stopAnimating()
        loadingIndicator.stopAnimating()
        chartView.alpha = 1
    }

    @discardableResult
    func configure(
        configuration: PortfolioChartTileCellConfiguration,
        onRetry: @escaping () -> Void,
        onPreferredHeightChanged: (() -> Void)? = nil
    ) -> Bool {
        self.onRetry = onRetry
        self.onLimitedHistoryTap = configuration.onLimitedHistoryTap
        self.onPreferredHeightChanged = onPreferredHeightChanged

        updateLocalizedStrings()
        titleLabel.attributedText = makeSectionHeaderTitle(configuration.title)

        if configuration.isRefreshing {
            refreshIndicator.startAnimating()
        } else {
            refreshIndicator.stopAnimating()
        }

        let wasShowingChart = isShowingChart
        isShowingChart = configuration.state.isChart

        apply(
            state: configuration.state,
            hidesVerticalAxisLabels: configuration.hidesVerticalAxisLabels
        )

        if isShowingChart && (!wasShowingChart || pendingChartFadeIn) {
            pendingChartFadeIn = false
            chartView.alpha = 0
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.chartView.alpha = 1
            }
        } else {
            updateChartDataAlpha(isDimmed: configuration.fadesCurrentData && isShowingChart)
        }

        let availableWidth = stateContainer.bounds.width > 0
            ? stateContainer.bounds.width
            : bounds.width
        return updateChartHeightIfNeeded(for: availableWidth)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let availableWidth = stateContainer.bounds.width > 0
            ? stateContainer.bounds.width
            : bounds.width
        notifyIfPreferredHeightChanged(for: availableWidth)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let updatedAttributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        let targetWidth = layoutAttributes.size.width

        updateChartHeightIfNeeded(for: targetWidth)
        setNeedsLayout()
        layoutIfNeeded()

        let fittedSize = contentView.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        updatedAttributes.size = CGSize(
            width: layoutAttributes.size.width,
            height: ceil(fittedSize.height)
        )
        return updatedAttributes
    }

    private func makeSectionHeaderTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: portfolioSectionHeaderFont,
            ]
        )
    }

    private func setupViews() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = portfolioSectionHeaderFont
        titleLabel.textColor = .air.secondaryLabel
        titleLabel.numberOfLines = 0

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(titleLabel)

        panelContainer.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.backgroundColor = .air.groupedItem
        panelContainer.layer.cornerRadius = 26
        panelContainer.layer.cornerCurve = .continuous
        panelContainer.layer.masksToBounds = true
        panelContainer.directionalLayoutMargins = .init(
            top: portfolioChartPanelInset,
            leading: portfolioChartPanelHorizontalInset,
            bottom: 0,
            trailing: portfolioChartPanelHorizontalInset
        )

        panelStack.translatesAutoresizingMaskIntoConstraints = false
        panelStack.axis = .vertical
        panelStack.alignment = .fill
        panelStack.spacing = 0

        stateContainer.translatesAutoresizingMaskIntoConstraints = false
        stateContainer.backgroundColor = .clear
        stateHeightConstraint.isActive = true

        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.apply(
            themeProvider: makePortfolioChartTheme(for:),
            strings: makePortfolioChartStrings(),
            animated: false
        )
        stateContainer.addSubview(chartView)

        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        loadingStack.axis = .vertical
        loadingStack.alignment = .center
        loadingStack.spacing = 10
        loadingLabel.font = .systemFont(ofSize: 14, weight: .medium)
        loadingLabel.textColor = .air.secondaryLabel
        loadingStack.addArrangedSubview(loadingIndicator)
        loadingStack.addArrangedSubview(loadingLabel)
        stateContainer.addSubview(loadingStack)

        noDataLabel.translatesAutoresizingMaskIntoConstraints = false
        noDataLabel.font = .systemFont(ofSize: 14, weight: .medium)
        noDataLabel.textColor = .air.secondaryLabel
        noDataLabel.textAlignment = .center
        stateContainer.addSubview(noDataLabel)

        errorStack.translatesAutoresizingMaskIntoConstraints = false
        errorStack.axis = .vertical
        errorStack.alignment = .center
        errorStack.spacing = 10
        errorTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        errorTitleLabel.textColor = .label
        errorTextLabel.font = .systemFont(ofSize: 14, weight: .medium)
        errorTextLabel.textColor = .air.secondaryLabel
        errorTextLabel.numberOfLines = 0
        errorTextLabel.textAlignment = .center
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        var retryConfiguration = UIButton.Configuration.plain()
        retryConfiguration.contentInsets = .init(top: 10, leading: 14, bottom: 10, trailing: 14)
        retryConfiguration.baseForegroundColor = .tintColor
        retryButton.configuration = retryConfiguration
        retryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        retryButton.layer.cornerRadius = 8
        retryButton.layer.cornerCurve = .continuous
        retryButton.backgroundColor = .air.groupedItem
        retryButton.addTarget(self, action: #selector(retryButtonPressed), for: .touchUpInside)
        errorStack.addArrangedSubview(errorTitleLabel)
        errorStack.addArrangedSubview(errorTextLabel)
        errorStack.addArrangedSubview(retryButton)
        stateContainer.addSubview(errorStack)

        refreshIndicator.translatesAutoresizingMaskIntoConstraints = false
        refreshIndicator.hidesWhenStopped = true
        tileContentView.addSubview(refreshIndicator)

        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.spacing = 0
        rootStack.addArrangedSubview(headerContainer)
        rootStack.addArrangedSubview(panelContainer)
        panelStack.addArrangedSubview(stateContainer)
        panelContainer.addSubview(panelStack)
        tileContentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: tileContentView.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: tileContentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: tileContentView.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: tileContentView.bottomAnchor),

            refreshIndicator.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            refreshIndicator.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -portfolioChartPanelInset),

            headerContainer.heightAnchor.constraint(equalToConstant: 39),
            titleLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: portfolioChartPanelInset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerContainer.trailingAnchor, constant: -portfolioChartPanelInset),
            titleLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -9),

            panelStack.topAnchor.constraint(equalTo: panelContainer.layoutMarginsGuide.topAnchor),
            panelStack.leadingAnchor.constraint(equalTo: panelContainer.layoutMarginsGuide.leadingAnchor),
            panelStack.trailingAnchor.constraint(equalTo: panelContainer.layoutMarginsGuide.trailingAnchor),
            panelStack.bottomAnchor.constraint(equalTo: panelContainer.layoutMarginsGuide.bottomAnchor),

            chartView.topAnchor.constraint(equalTo: stateContainer.topAnchor),
            chartView.leadingAnchor.constraint(equalTo: stateContainer.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: stateContainer.trailingAnchor),
            chartView.bottomAnchor.constraint(equalTo: stateContainer.bottomAnchor),

            loadingStack.centerXAnchor.constraint(equalTo: stateContainer.centerXAnchor),
            loadingStack.centerYAnchor.constraint(equalTo: stateContainer.centerYAnchor),

            noDataLabel.centerXAnchor.constraint(equalTo: stateContainer.centerXAnchor),
            noDataLabel.centerYAnchor.constraint(equalTo: stateContainer.centerYAnchor),
            noDataLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stateContainer.leadingAnchor),
            noDataLabel.trailingAnchor.constraint(lessThanOrEqualTo: stateContainer.trailingAnchor),

            errorStack.centerXAnchor.constraint(equalTo: stateContainer.centerXAnchor),
            errorStack.centerYAnchor.constraint(equalTo: stateContainer.centerYAnchor),
            errorStack.leadingAnchor.constraint(greaterThanOrEqualTo: stateContainer.leadingAnchor),
            errorStack.trailingAnchor.constraint(lessThanOrEqualTo: stateContainer.trailingAnchor),
            errorTextLabel.widthAnchor.constraint(lessThanOrEqualTo: stateContainer.widthAnchor, multiplier: 0.85),
        ])

        updateLocalizedStrings()
    }

    private func updateLocalizedStrings() {
        loadingLabel.text = lang("Loading...")
        noDataLabel.text = lang("No price data")
        errorTitleLabel.text = lang("Error")

        var retryConfiguration = retryButton.configuration
        retryConfiguration?.title = lang("Try Again")
        retryButton.configuration = retryConfiguration
    }

    private func apply(
        state: PortfolioChartTileCellConfiguration.State,
        hidesVerticalAxisLabels: Bool
    ) {
        chartView.isHidden = true
        loadingStack.isHidden = true
        errorStack.isHidden = true
        noDataLabel.isHidden = true

        switch state {
        case .idle:
            break
        case .error(let errorText):
            chartView.setLimitedRange(fraction: nil, tapAction: nil)
            errorTextLabel.text = errorText
            errorStack.isHidden = false
        case .loading:
            chartView.setLimitedRange(fraction: nil, tapAction: nil)
            loadingStack.isHidden = false
            loadingIndicator.startAnimating()
        case .noData:
            chartView.setLimitedRange(fraction: nil, tapAction: nil)
            noDataLabel.isHidden = false
        case .chart(let presentation, let kind, let pieVisible):
            chartView.isHidden = false
            configureChart(
                presentation: presentation,
                kind: kind,
                pieVisible: pieVisible,
                hidesVerticalAxisLabels: hidesVerticalAxisLabels
            )
        }
    }

    private func updateChartDataAlpha(isDimmed: Bool) {
        let targetAlpha: CGFloat = isDimmed ? 0.5 : 1
        guard abs(chartView.alpha - targetAlpha) > 0.01 else {
            return
        }

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.chartView.alpha = targetAlpha
        }
    }

    private func configureChart(
        presentation: PortfolioGraphKitAdapter.ChartPresentation,
        kind: PortfolioGraphKind,
        pieVisible: Bool?,
        hidesVerticalAxisLabels: Bool
    ) {
        let signature = "\(kind.rawValue):\(presentation.json)"
        
        let isNewSignature = chartSignature != signature
        let isRangeSwitch = pendingRangeReset && isNewSignature
        if isNewSignature,
           let controller = createChartController(presentation.json, type: kind.chartType) {
            if isRangeSwitch {
                pendingChartFadeIn = true
            }
            pendingRangeReset = false
            let chartStrings = makePortfolioChartStrings()
            if let pieController = controller as? PercentPieChartController {
                pieController.keepsFullRangePreviewWhenZoomed = kind.keepsFullRangePreviewWhenZoomed
            }
            controller.hidesVerticalAxisLabels = hidesVerticalAxisLabels
            applyDetailsPresentation(presentation, to: controller)

            UIView.performWithoutAnimation {
                chartView.apply(
                    themeProvider: makePortfolioChartTheme(for:),
                    strings: chartStrings,
                    animated: false
                )
                chartView.setup(controller: controller, noInitialZoom: true)
            }
            chartController = controller
            chartSignature = signature
            chartPieVisible = nil
        }

        if let chartController {
            let chartStrings = makePortfolioChartStrings()
            chartController.hidesVerticalAxisLabels = hidesVerticalAxisLabels
            applyDetailsPresentation(presentation, to: chartController)
            chartView.apply(
                themeProvider: makePortfolioChartTheme(for:),
                strings: chartStrings,
                animated: false
            )
        }

        if !pendingRangeReset || isNewSignature {
            UIView.performWithoutAnimation {
                chartView.setLimitedRange(
                    fraction: presentation.limitedHistoryFraction.map { CGFloat($0) },
                    tapAction: onLimitedHistoryTap
                )
                chartView.expandRange()
            }
        }
        pendingRangeReset = false

        if let pieVisible,
           chartPieVisible != pieVisible {
            chartView.setPieVisible(pieVisible, animated: chartPieVisible != nil)
            chartPieVisible = pieVisible
        }
    }

    func resetInteraction() {
        chartView.resetInteraction()
    }

    func resetRange() {
        pendingRangeReset = true
    }

    func blocksBackSwipe(at point: CGPoint, mainChartLeftSafeInset: CGFloat = 30.0) -> Bool {
        guard !chartView.isHidden else {
            return false
        }

        let pointInChartView = convert(point, to: chartView)
        return chartView.blocksBackSwipe(at: pointInChartView, mainChartLeftSafeInset: mainChartLeftSafeInset)
    }

    var horizontalInteractionBlockingGestureRecognizer: UIGestureRecognizer {
        chartView.horizontalInteractionBlockingGestureRecognizer
    }

    @objc
    private func retryButtonPressed() {
        onRetry?()
    }

    private func applyDetailsPresentation(
        _ presentation: PortfolioGraphKitAdapter.ChartPresentation,
        to controller: BaseChartController
    ) {
        controller.detailsValueTextProvider = presentation.detailsValueTextProvider
        controller.detailsRowSortOrder = .descendingValue
        controller.hidesZeroDetailsRows = true
    }

    @discardableResult
    private func updateChartHeightIfNeeded(for availableWidth: CGFloat) -> Bool {
        guard availableWidth > 0 else {
            return false
        }

        let resolvedWidth = floor(availableWidth)
        let preferredChartHeight: CGFloat
        if chartView.isHidden {
            preferredChartHeight = lastKnownChartHeight
        } else {
            preferredChartHeight = chartView.preferredHeight(for: resolvedWidth)
            lastKnownChartHeight = preferredChartHeight
        }

        guard abs(stateHeightConstraint.constant - preferredChartHeight) > 0.5
                || abs(lastMeasuredChartWidth - resolvedWidth) > 0.5 else {
            return false
        }

        lastMeasuredChartWidth = resolvedWidth
        stateHeightConstraint.constant = preferredChartHeight
        return true
    }

    private func notifyIfPreferredHeightChanged(for availableWidth: CGFloat) {
        guard updateChartHeightIfNeeded(for: availableWidth) else {
            return
        }

        onPreferredHeightChanged?()
    }
}
