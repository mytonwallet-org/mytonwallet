import UIKit
import UIActivityList
import UIComponents
import WalletContext
import WalletCore

@MainActor
public class ActivityDetailsListVC: WViewController, ActivityCell.Delegate {
    
    let activityIds: [String]
    let activitiesById: [String: ApiActivity]
    let context: ActivityDetailsContext
    
    @AccountContext var account: MAccount
    
    enum Section {
        case main
    }
    enum Row: Hashable {
        case activity(String)
    }
    
    var collectionView: ActivitiesCollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!
    
    public init(accountContext: AccountContext, activities: [ApiActivity], context: ActivityDetailsContext) {
        self.activityIds = activities.map(\.id)
        self.activitiesById = activities.dictionaryByKey(\.id)
        self._account = accountContext
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        navigationItem.title = lang("Transfer Info")
        addCloseNavigationItemIfNeeded()
        
        collectionView = ActivitiesCollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        collectionView.showsVerticalScrollIndicator = false
        collectionView.allowsSelection = false
        collectionView.delaysContentTouches = false
        collectionView.backgroundColor = .clear
        
        self.dataSource = makeDataSource()
        dataSource.apply(makeSnapshot(), animatingDifferences: false)

        view.backgroundColor = .air.sheetBackground
    }
    
    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = .clear
            configuration.headerTopPadding = 8
            configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
            configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 12
            if !IOS_26_MODE_ENABLED {
                configuration.separatorConfiguration.color = .air.separator
            }
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Row> {
        let activityCellRegistration = UICollectionView.CellRegistration<ActivityCell, Row> { [unowned self] cell, _, item in
            switch item {
            case .activity(let activityId):
                let activity = self.activitiesById[activityId]!
                cell.configure(
                    with: activity,
                    accountContext: _account,
                    delegate: self,
                    showsRightChevron: true
                )
            }
        }
        let dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .activity:
                return collectionView.dequeueConfiguredReusableCell(using: activityCellRegistration, for: indexPath, item: item)
            }
        }
        return dataSource
    }

    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Row> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.main])
        snapshot.appendItems(activityIds.map(Row.activity))
        return snapshot
    }

    public func onSelect(transaction: ApiActivity) {
        AppActions.showActivityDetails(accountId: account.id, activity: transaction, context: context)
    }
}
