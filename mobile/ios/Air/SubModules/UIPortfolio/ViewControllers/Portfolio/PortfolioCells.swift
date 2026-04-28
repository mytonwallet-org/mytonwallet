import GraphKit
import UIComponents
import UIKit
import WalletContext

private let portfolioChartHeight = CGFloat(480)
private let portfolioChartHeaderHorizontalInset = CGFloat(16)
private let portfolioSectionHeaderFont = UIFont.systemFont(ofSize: 22.5, weight: .bold)
private let portfolioSectionHeaderKern = CGFloat(-0.25)

private func makePortfolioChartTheme(for traitCollection: UITraitCollection) -> ChartTheme {
    let baseTheme = ChartTheme.extractedTheme(for: traitCollection.userInterfaceStyle)

    return ChartTheme(
        chartTitleColor: baseTheme.chartTitleColor,
        actionButtonColor: baseTheme.actionButtonColor,
        chartBackgroundColor: .air.background,
        chartLabelsColor: baseTheme.chartLabelsColor,
        chartHelperLinesColor: baseTheme.chartHelperLinesColor,
        chartStrongLinesColor: baseTheme.chartStrongLinesColor,
        barChartStrongLinesColor: baseTheme.barChartStrongLinesColor,
        chartDetailsTextColor: baseTheme.chartDetailsTextColor,
        chartDetailsArrowColor: baseTheme.chartDetailsArrowColor,
        chartDetailsViewColor: .air.sheetBackground,
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
    case portfolioShare

    var chartType: ChartType {
        switch self {
        case .totalValue:
            return .absoluteArea
        case .portfolioShare:
            return .pie
        }
    }

    var keepsFullRangePreviewWhenZoomed: Bool {
        switch self {
        case .totalValue:
            return false
        case .portfolioShare:
            return true
        }
    }
}

struct PortfolioChartTileCellConfiguration {
    enum State {
        case error(String)
        case loading
        case noData
        case chart(presentation: PortfolioGraphKitAdapter.ChartPresentation, kind: PortfolioGraphKind, pieVisible: Bool?)
    }

    let title: String
    let subtitle: String
    let state: State
    let showsUpdatingFooter: Bool
    let isRefreshing: Bool
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
    private var lastMeasuredChartWidth: CGFloat = 0

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let headerContainer = UIView()
    private let headerStack = UIStackView()
    private let rootStack = UIStackView()
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
    private let updatingFooterContainer = UIView()
    private let updatingFooterStack = UIStackView()
    private let updatingFooterIndicator = UIActivityIndicatorView(style: .medium)
    private let updatingFooterLabel = UILabel()
    private let refreshIndicator = UIActivityIndicatorView(style: .medium)
    private let stateHeightConstraint: NSLayoutConstraint

    override init(frame: CGRect) {
        self.stateHeightConstraint = stateContainer.heightAnchor.constraint(equalToConstant: portfolioChartHeight)
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
        chartView.setLimitedRange(fraction: nil, tapAction: nil)
        refreshIndicator.stopAnimating()
        updatingFooterIndicator.stopAnimating()
        loadingIndicator.stopAnimating()
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
        subtitleLabel.text = configuration.subtitle

        if configuration.isRefreshing {
            refreshIndicator.startAnimating()
        } else {
            refreshIndicator.stopAnimating()
        }

        updatingFooterStack.isHidden = !configuration.showsUpdatingFooter
        if configuration.showsUpdatingFooter {
            updatingFooterIndicator.startAnimating()
        } else {
            updatingFooterIndicator.stopAnimating()
        }

        apply(state: configuration.state)
        let availableWidth = stateContainer.bounds.width > 0 ? stateContainer.bounds.width : bounds.width
        return updateChartHeightIfNeeded(for: availableWidth)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let availableWidth = stateContainer.bounds.width > 0 ? stateContainer.bounds.width : bounds.width
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
                .kern: portfolioSectionHeaderKern,
                .font: portfolioSectionHeaderFont,
            ]
        )
    }

    private func setupViews() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = portfolioSectionHeaderFont
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = .air.secondaryLabel
        subtitleLabel.numberOfLines = 0

        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.axis = .vertical
        headerStack.alignment = .fill
        headerStack.spacing = 4
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerStack)

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

        updatingFooterStack.translatesAutoresizingMaskIntoConstraints = false
        updatingFooterStack.axis = .horizontal
        updatingFooterStack.alignment = .center
        updatingFooterStack.spacing = 8
        updatingFooterIndicator.startAnimating()
        updatingFooterIndicator.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        updatingFooterLabel.font = .systemFont(ofSize: 13, weight: .medium)
        updatingFooterLabel.textColor = .air.secondaryLabel
        updatingFooterStack.addArrangedSubview(updatingFooterIndicator)
        updatingFooterStack.addArrangedSubview(updatingFooterLabel)

        updatingFooterContainer.translatesAutoresizingMaskIntoConstraints = false
        updatingFooterContainer.addSubview(updatingFooterStack)

        refreshIndicator.translatesAutoresizingMaskIntoConstraints = false
        refreshIndicator.hidesWhenStopped = true
        tileContentView.addSubview(refreshIndicator)

        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.spacing = 18
        rootStack.addArrangedSubview(headerContainer)
        rootStack.addArrangedSubview(stateContainer)
        rootStack.addArrangedSubview(updatingFooterContainer)
        tileContentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: tileContentView.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: tileContentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: tileContentView.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: tileContentView.bottomAnchor),

            refreshIndicator.topAnchor.constraint(equalTo: tileContentView.topAnchor),
            refreshIndicator.trailingAnchor.constraint(equalTo: tileContentView.trailingAnchor, constant: -portfolioChartHeaderHorizontalInset),

            headerStack.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: portfolioChartHeaderHorizontalInset),
            headerStack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -portfolioChartHeaderHorizontalInset),
            headerStack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),

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

            updatingFooterStack.topAnchor.constraint(equalTo: updatingFooterContainer.topAnchor),
            updatingFooterStack.leadingAnchor.constraint(equalTo: updatingFooterContainer.leadingAnchor, constant: portfolioChartHeaderHorizontalInset),
            updatingFooterStack.trailingAnchor.constraint(lessThanOrEqualTo: updatingFooterContainer.trailingAnchor, constant: -portfolioChartHeaderHorizontalInset),
            updatingFooterStack.bottomAnchor.constraint(equalTo: updatingFooterContainer.bottomAnchor),
        ])

        updateLocalizedStrings()
    }

    private func updateLocalizedStrings() {
        loadingLabel.text = lang("Loading...")
        noDataLabel.text = lang("No price data")
        errorTitleLabel.text = lang("Error")
        updatingFooterLabel.text = lang("Updating")

        var retryConfiguration = retryButton.configuration
        retryConfiguration?.title = lang("Try Again")
        retryButton.configuration = retryConfiguration
    }

    private func apply(state: PortfolioChartTileCellConfiguration.State) {
        chartView.isHidden = true
        loadingStack.isHidden = true
        errorStack.isHidden = true
        noDataLabel.isHidden = true

        switch state {
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
            configureChart(presentation: presentation, kind: kind, pieVisible: pieVisible)
        }
    }

    private func configureChart(presentation: PortfolioGraphKitAdapter.ChartPresentation, kind: PortfolioGraphKind, pieVisible: Bool?) {
        let signature = "\(kind.rawValue):\(presentation.json)"

        if chartSignature != signature,
           let controller = createChartController(presentation.json, type: kind.chartType) {
            let chartStrings = makePortfolioChartStrings()
            if let pieController = controller as? PercentPieChartController {
                pieController.keepsFullRangePreviewWhenZoomed = kind.keepsFullRangePreviewWhenZoomed
            }
            applyDetailsPresentation(presentation, to: controller)

            chartView.apply(
                themeProvider: makePortfolioChartTheme(for:),
                strings: chartStrings,
                animated: false
            )
            chartView.setup(controller: controller)
            chartController = controller
            chartSignature = signature
            chartPieVisible = nil
        }

        if let chartController {
            let chartStrings = makePortfolioChartStrings()
            applyDetailsPresentation(presentation, to: chartController)
            chartView.apply(
                themeProvider: makePortfolioChartTheme(for:),
                strings: chartStrings,
                animated: false
            )
        }

        chartView.setLimitedRange(
            fraction: presentation.limitedHistoryFraction.map { CGFloat($0) },
            tapAction: onLimitedHistoryTap
        )

        if let pieVisible,
           chartPieVisible != pieVisible {
            chartView.setPieVisible(pieVisible, animated: chartPieVisible != nil)
            chartPieVisible = pieVisible
        }
    }

    func resetInteraction() {
        chartView.resetInteraction()
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
        let preferredChartHeight = max(
            portfolioChartHeight,
            chartView.isHidden ? portfolioChartHeight : chartView.preferredHeight(for: resolvedWidth)
        )

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
