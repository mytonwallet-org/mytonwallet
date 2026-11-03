import UIKit
import UIComponents
import WalletContext
import WalletCore

public struct PerpsCashFlowDetailsDisplayData {
    public struct Row {
        public var title: String
        public var value: String
        public var copyValue: String? = nil
    }
    public var summary: PerpsHomeActivity
    public var rows: [Row]
}

extension PerpsHomeAdapter {
    public static func cashFlowDetails(_ flow: ApiPerpsCashFlow, asset: ApiPerpsAsset?) -> PerpsCashFlowDetailsDisplayData {
        var rows: [PerpsCashFlowDetailsDisplayData.Row] = [
            .init(title: lang("Amount"), value: PerpsFormatting.cashFlowAmount(flow)),
        ]
        if let source = flow.sourceDex { rows.append(.init(title: lang("From"), value: PerpsFormatting.perpsBook(source))) }
        if let destination = flow.destinationDex { rows.append(.init(title: lang("To"), value: PerpsFormatting.perpsBook(destination))) }
        if let address = flow.sourceAddress {
            rows.append(.init(title: lang("Sender"), value: formatStartEndAddress(address), copyValue: address))
        }
        if let address = flow.destinationAddress {
            rows.append(.init(title: lang("Recipient"), value: formatStartEndAddress(address), copyValue: address))
        }
        for fee in flow.fees {
            rows.append(.init(title: lang("Fee"), value: PerpsFormatting.quantity(fee.amount, symbol: fee.token)))
        }
        if let hash = flow.hash {
            rows.append(.init(title: lang("Transfer ID"), value: formatStartEndAddress(hash), copyValue: hash))
        }
        var summary = cashFlow(flow, asset: asset)
        summary.date = PerpsFormatting.date(flow.time)
        return .init(summary: summary, rows: rows)
    }
}

/// Read-only ledger details reuse the activity cell and the app's standard UIKit list/sheet behavior.
@MainActor public final class PerpsCashFlowDetailsVC: WViewController, UICollectionViewDelegate {
    private let data: PerpsCashFlowDetailsDisplayData
    private var collection: UICollectionView!
    private var source: UICollectionViewDiffableDataSource<Int, Int>!
    private lazy var summaryRegistration = UICollectionView.CellRegistration<PerpsActivityCell, PerpsHomeActivity> { cell, _, data in
        var summary = data
        summary.canSelect = false
        cell.configure(summary)
    }
    private lazy var detailRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, PerpsCashFlowDetailsDisplayData.Row> { cell, _, row in
        var content = UIListContentConfiguration.valueCell()
        content.text = row.title
        content.secondaryText = row.value
        content.applyTextStyle(.body)
        content.textProperties.color = .air.secondaryLabel
        content.secondaryTextProperties.font = WTypography.uiFont(.body, content: .technical)
        content.secondaryTextProperties.color = .label
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = .air.groupedItem
        cell.backgroundConfiguration = background
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = row.title
        cell.accessibilityValue = row.value
        cell.accessibilityHint = row.copyValue == nil ? nil : lang("Copy")
        cell.accessibilityTraits = row.copyValue == nil ? .staticText : .button
    }

    public init(data: PerpsCashFlowDetailsDisplayData) {
        self.data = data
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = data.summary.title
        view.backgroundColor = .air.sheetBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .action, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let text = ([data.summary.title, data.summary.date] + data.rows.map { $0.title + ": " + ($0.copyValue ?? $0.value) }).joined(separator: "\n")
            presentActivityViewController(UIActivityViewController(activityItems: [text], applicationActivities: nil))
        })
        let layout = UICollectionViewCompositionalLayout { section, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = .clear
            configuration.showsSeparators = section != 0
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.delaysContentTouches = false
        collection.showsVerticalScrollIndicator = false
        collection.showsHorizontalScrollIndicator = false
        collection.accessibilityIdentifier = "perps.cashFlow.details"
        collection.contentInsetAdjustmentBehavior = .automatic
        collection.delegate = self
        view.addSubview(collection)
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: view.topAnchor),
            collection.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collection.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])
        _ = summaryRegistration; _ = detailRegistration
        source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collection) { [weak self] collection, index, id in
            guard let self else { return nil }
            if id == -1 { return collection.dequeueConfiguredReusableCell(using: summaryRegistration, for: index, item: data.summary) }
            return collection.dequeueConfiguredReusableCell(using: detailRegistration, for: index, item: data.rows[id])
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0, 1])
        snapshot.appendItems([-1], toSection: 0)
        snapshot.appendItems(Array(data.rows.indices), toSection: 1)
        source.apply(snapshot, animatingDifferences: false)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let presenter = navigationController ?? self
        presenter.preferredContentSize = CGSize(width: 580, height: 600)
        presenter.sheetPresentationController?.detents = [.medium(), .large()]
        presenter.sheetPresentationController?.prefersGrabberVisible = true
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        indexPath.section == 1 && data.rows[indexPath.item].copyValue != nil
    }
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let value = data.rows[indexPath.item].copyValue else { return }
        UIPasteboard.general.string = value
        showToast(.init(message: lang("Copied")))
        Haptics.play(.lightTap)
    }
}
