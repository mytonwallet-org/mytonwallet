import UIKit
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
    
    var tableView: UITableView!
    private var dataSource: UITableViewDiffableDataSource<Section, Row>!
    
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
        
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        tableView.showsVerticalScrollIndicator = false
        tableView.register(ActivityCell.self, forCellReuseIdentifier: "Transaction")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.allowsSelection = false
        tableView.delaysContentTouches = false
        tableView.contentInset.top = IOS_26_MODE_ENABLED ? -20 : 0
        if IOS_26_MODE_ENABLED {
            tableView.separatorInset = UIEdgeInsets(top: 0, left: 62, bottom: 0, right: 12)
        } else {
            tableView.separatorColor = WTheme.separator
            tableView.separatorInset.left = 62
        }
        
        self.dataSource = makeDataSource()
        dataSource.apply(makeSnapshot(), animatingDifferences: false)

        tableView.backgroundColor = .clear
        view.backgroundColor = WTheme.sheetBackground
    }
    
    private func makeDataSource() -> UITableViewDiffableDataSource<Section, Row> {
        let dataSource = UITableViewDiffableDataSource<Section, Row>(tableView: tableView) { [unowned self] tableView, indexPath, item in
            switch item {
            case .activity(let activityId):
                let cell = tableView.dequeueReusableCell(withIdentifier: "Transaction", for: indexPath) as! ActivityCell
                let activity = self.activitiesById[activityId]!
                cell.configure(
                    with: activity,
                    accountContext: _account,
                    delegate: self,
                    shouldFadeOutSkeleton: false,
                    showsRightChevron: true
                )
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
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
