import SwiftUI
import UIKit
import UIComponents
import UIPasscode
import WalletCore
import WalletContext

private let permissionsLog = Log("PermissionsListVC")

final class PermissionsListVC: SettingsBaseVC, WSegmentedControllerContent, UICollectionViewDelegate {
    private enum Section: Hashable {
        case main
    }

    private enum Item: Hashable {
        case permission(ApiWalletPermission)
        case plugin(ApiTonPlugin)
    }

    private enum ContentState {
        case loading
        case permissions([ApiWalletPermission])
        case plugins([ApiTonPlugin])
        case empty
    }

    @AccountContext private var account: MAccount

    private let chain: ApiChain
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var loadTask: Task<Void, Never>?
    private var state: ContentState = .loading
    private var placeholderView: UIView?

    init(accountContext: AccountContext, chain: ApiChain) {
        self._account = accountContext
        self.chain = chain
        super.init(nibName: nil, bundle: nil)
        title = lang("Permissions")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        configureDataSource()
        loadData()
    }

    private func setupViews() {
        view.backgroundColor = .air.groupedBackground

        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        configuration.backgroundColor = .air.groupedBackground

        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .air.groupedBackground
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset = UIEdgeInsets(top: 72, left: 0, bottom: 16, right: 0)
        collectionView.scrollIndicatorInsets = collectionView.contentInset
        collectionView.contentInsetAdjustmentBehavior = .never
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureDataSource() {
        let permissionRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ApiWalletPermission> { cell, _, permission in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    PermissionCellContent(permission: permission)
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.horizontal, 16)
                .margins(.vertical, 8)
            }
        }

        let pluginRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ApiTonPlugin> { cell, _, plugin in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    PluginCellContent(plugin: plugin)
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.horizontal, 16)
                .margins(.vertical, 8)
            }
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] cell, _, _ in
            var content = UIListContentConfiguration.groupedHeader()
            content.text = self?.sectionHeaderTitle
            cell.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .permission(let permission):
                collectionView.dequeueConfiguredReusableCell(using: permissionRegistration, for: indexPath, item: permission)
            case .plugin(let plugin):
                collectionView.dequeueConfiguredReusableCell(using: pluginRegistration, for: indexPath, item: plugin)
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
            guard elementKind == UICollectionView.elementKindSectionHeader else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func loadData(animated: Bool = false) {
        loadTask?.cancel()
        state = .loading
        applySnapshot(animated: animated)

        let accountId = account.id
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if chain == .ton {
                    let plugins = try await Api.fetchWalletPlugins(accountId: accountId)
                    guard !Task.isCancelled, self.account.id == accountId else { return }
                    state = plugins.isEmpty ? .empty : .plugins(plugins)
                } else if chain.isEvm {
                    let permissions = try await Api.fetchWalletPermissions(accountId: accountId, chain: chain)
                    guard !Task.isCancelled, self.account.id == accountId else { return }
                    state = permissions.isEmpty ? .empty : .permissions(permissions)
                } else {
                    state = .empty
                }
                applySnapshot(animated: animated)
            } catch {
                guard !Task.isCancelled else { return }
                permissionsLog.error("failed to load \(chain.rawValue, .public) permissions: \(error, .public)")
                state = .empty
                applySnapshot(animated: animated)
                showAlert(error: error)
            }
        }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        let items: [Item] = switch state {
        case .loading, .empty:
            []
        case .permissions(let permissions):
            permissions.map(Item.permission)
        case .plugins(let plugins):
            plugins.map(Item.plugin)
        }

        if !items.isEmpty {
            snapshot.appendSections([.main])
            snapshot.appendItems(items, toSection: .main)
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
        updatePlaceholder()
    }

    private func updatePlaceholder() {
        placeholderView?.removeFromSuperview()
        placeholderView = nil

        switch state {
        case .loading:
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.startAnimating()
            view.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            placeholderView = spinner
        case .empty:
            let emptyView = HeaderView(
                animationName: "NoResults",
                animationPlaybackMode: .loop,
                title: lang("No Permissions"),
                description: nil,
                compactMode: true
            )
            emptyView.lblTitle.font = .systemFont(ofSize: 17, weight: .medium)
            view.addSubview(emptyView)
            NSLayoutConstraint.activate([
                emptyView.widthAnchor.constraint(equalToConstant: 220),
                emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            placeholderView = emptyView
        case .permissions, .plugins:
            break
        }
    }

    private func showPermissionActions(_ permission: ApiWalletPermission) {
        guard !(presentedViewController is UIAlertController), !(topViewController() is UIAlertController) else { return }

        let alert = UIAlertController(
            title: permission.alertTitle,
            message: permission.alertMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: lang("Revoke"), style: .destructive) { [weak self] _ in
            Task { @MainActor in
                await self?.revoke(permission)
            }
        })
        alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func revoke(_ permission: ApiWalletPermission) async {
        guard account.id == AccountStore.accountId else { return }
        guard let password = await UnlockVC.presentAuthAsync(on: self, title: lang("Confirm Revoking")) else { return }

        do {
            let options = ApiRevokeWalletPermissionOptions(
                accountId: account.id,
                password: password,
                permission: permission
            )
            let result = try await Api.revokeWalletPermission(chain: permission.chain, options: options)
            if let error = result.error {
                showAlert(error: SdkError.apiReturnedError(error: error.rawValue, context: result))
                return
            }
            remove(permission)
        } catch {
            showAlert(error: error)
        }
    }

    private func remove(_ permission: ApiWalletPermission) {
        guard case .permissions(let currentPermissions) = state else { return }
        let updated = currentPermissions.filter { !$0.hasSameRevokeTarget(as: permission) }
        state = updated.isEmpty ? .empty : .permissions(updated)
        applySnapshot(animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .permission(let permission):
            showPermissionActions(permission)
        case .plugin:
            break
        }
    }

    override func scrollToTop(animated: Bool) {
        collectionView?.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }

    var onScroll: ((CGFloat) -> Void)?
    var scrollingView: UIScrollView? { collectionView }
    func calculateHeight(isHosted: Bool) -> CGFloat { 0 }

    private var sectionHeaderTitle: String {
        chain == .ton ? lang("Plugins") : lang("Approvals & Delegations")
    }
}

private extension ApiWalletPermission {
    var alertTitle: String {
        switch self {
        case .approval:
            lang("Revoke Approval")
        case .delegation:
            lang("Revoke Delegation")
        }
    }

    var alertMessage: String {
        switch self {
        case .approval(let approval):
            lang("Are you sure you want to revoke approval for %token%?", arg1: approval.tokenName)
        case .delegation(let delegation):
            lang("Are you sure you want to revoke delegation for %name%?", arg1: delegation.delegateLabel)
        }
    }
}

private struct PermissionCellContent: View {
    let permission: ApiWalletPermission

    var body: some View {
        switch permission {
        case .approval(let approval):
            ApprovalCellContent(approval: approval)
        case .delegation(let delegation):
            DelegationCellContent(delegation: delegation)
        }
    }
}

private struct ApprovalCellContent: View {
    let approval: ApiTokenApproval

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                DappIcon(iconUrl: approval.tokenImage)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let spenderIcon = approval.spenderIcon {
                    DappIcon(iconUrl: spenderIcon)
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.air.groupedItem, lineWidth: 1))
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(approval.tokenName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                Text(lang("Approved to %name%", arg1: approval.spenderLabel))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(amountText)
                .font(.system(size: 14))
                .foregroundStyle(Color.air.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var amountText: String {
        if approval.isUnlimited {
            return lang("Unlimited")
        }
        return TokenAmount(approval.allowanceValue, approval.token).formatted(.defaultAdaptive, roundHalfUp: false)
    }
}

private struct DelegationCellContent: View {
    let delegation: ApiEvmDelegation

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DappIcon(iconUrl: delegation.delegateIcon)
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(delegation.delegateLabel)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                Text(lang("Wallet Delegation"))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PluginCellContent: View {
    let plugin: ApiTonPlugin

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.air.secondaryLabel)
                .frame(width: 40, height: 40)
                .background(Color.air.secondaryFill)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name?.nilIfEmpty ?? lang("Unknown Plugin"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                Text(formatStartEndAddress(plugin.address))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
